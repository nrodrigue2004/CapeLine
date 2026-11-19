# vpreview.py: vehicles.py's preview renders with the baked texture sets, the way the game shows them (the colour
# map's alpha over the part colour, as SurfaceAppearance AlphaMode Overlay does; tinted glass; Neon lights): one
# render a look with a hero for scale (art/preview/vehicle_<Look>.png), a Downtown street where the game parks the
# hub's vehicles (from art/export/vehicles/layout.json), and a contact sheet (art/preview/vehicles.png).
import math
import os

import kit
import bpy
import numpy as np
from mathutils import Vector

from studs import rb
from vkit import lin

PREV = os.path.join(kit.ROOT, "preview")
SHOWN = []


def _cull(m):
    """Roblox culls back faces; so does the preview (a liner seen from outside, a shell from inside)."""
    nt = m.node_tree
    out = nt.nodes["Material Output"]
    src = out.inputs["Surface"].links[0].from_socket
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mx = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(geo.outputs["Backfacing"], mx.inputs["Fac"])
    nt.links.new(src, mx.inputs[1])
    nt.links.new(tr.outputs["BSDF"], mx.inputs[2])
    nt.links.new(mx.outputs["Shader"], out.inputs["Surface"])
    return m


def _mat_textured(look, maps):
    m = bpy.data.materials.new("prev_" + look)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = maps["Color"][0]
    info = nt.nodes.new("ShaderNodeObjectInfo")
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(tc.outputs["Alpha"], mix.inputs["Factor"])
    nt.links.new(info.outputs["Color"], mix.inputs[6])
    nt.links.new(tc.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], p.inputs["Base Color"])
    for key, sock in (("Roughness", "Roughness"), ("Metalness", "Metallic")):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = maps[key][0]
        t.image.colorspace_settings.name = "Non-Color"
        nt.links.new(t.outputs["Color"], p.inputs[sock])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = maps["Normal"][0]
    tn.image.colorspace_settings.name = "Non-Color"
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    return _cull(m)


_FLAT = {}


def _mat_flat(rgb, kind, alpha):
    key = (rgb, kind, alpha)
    if key in _FLAT:
        return _FLAT[key]
    m = bpy.data.materials.new("flat%d" % len(_FLAT))
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    col = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1)
    p.inputs["Base Color"].default_value = col
    p.inputs["Roughness"].default_value = 0.05 if kind == "Glass" else 0.45
    if kind == "Neon":
        p.inputs["Emission Color"].default_value = col
        p.inputs["Emission Strength"].default_value = 1.1
    if alpha > 0:
        p.inputs["Alpha"].default_value = 1 - alpha
        p.inputs["Specular IOR Level"].default_value = 0.8
    _FLAT[key] = _cull(m)
    return m


def _scene(fast, res):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 12 if fast else 48
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    w = bpy.data.worlds.new("Sky")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.72, 0.95, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.85
    sc.world = w
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.4
    sun.data.angle = math.radians(6)
    sun.rotation_euler = (math.radians(40), math.radians(10), math.radians(35))
    sc.collection.objects.link(sun)
    return sc


def _keep(o):
    o.hide_render = False
    SHOWN.append(o)
    return o


def _clear():
    for o in SHOWN:
        bpy.data.objects.remove(o, do_unlink=True)
    SHOWN.clear()


def _ground(size, rgb=(112, 114, 120), at=(0, 0, 0)):
    g = _keep(kit.box("ground", size, size, 0.4, at=(at[0], -at[2], at[1] - 0.2)))
    g.data.materials.append(_mat_flat(rgb, "SmoothPlastic", 0))
    return g


def _hero(x, y, z, yaw=0):
    """A blocky hero (5 studs tall) for scale."""
    parts = [((2, 2, 1), (0, 3.0, 0), (60, 90, 200)), ((1.2, 1.2, 1.2), (0, 4.6, 0), (240, 196, 150)),
             ((0.9, 2, 0.9), (-0.5, 1.0, 0), (40, 46, 90)), ((0.9, 2, 0.9), (0.5, 1.0, 0), (40, 46, 90)),
             ((0.8, 2, 0.8), (-1.4, 3.0, 0), (240, 196, 150)), ((0.8, 2, 0.8), (1.4, 3.0, 0), (240, 196, 150))]
    a = math.radians(yaw)
    for (s_, c, rgb) in parts:
        cx = c[0] * math.cos(a) + c[2] * math.sin(a)
        cz = -c[0] * math.sin(a) + c[2] * math.cos(a)
        o = _keep(kit.box("hero", s_[0], s_[2], s_[1], at=rb(x + cx, y + c[1], z + cz)))
        o.rotation_euler = (0, 0, a)
        o.data.materials.append(_mat_flat(rgb, "SmoothPlastic", 0))


def _place(lk, mats, at=(0, 0, 0), ry=0.0, tint=None, steer=0.0):
    """A copy of a look's meshes with its foot at `at`, turned ry degrees (Roblox) about up; steer turns the front
    wheels (their own meshes, 2026-11-19) that many degrees about their own centre, a check they are separate."""
    for mname, ob in lk.meshes.items():
        cp = ob.copy()
        bpy.context.scene.collection.objects.link(cp)
        cp.data = ob.data.copy()
        sp = lk.spin.get(mname)
        if steer and sp and sp["steer"]:
            vs = [v.co.copy() for v in cp.data.vertices]
            lo = [min(v[i] for v in vs) for i in range(3)]
            hi = [max(v[i] for v in vs) for i in range(3)]
            c = [(lo[i] + hi[i]) / 2 for i in range(3)]
            a = math.radians(steer)
            for v in cp.data.vertices:
                dx, dy = v.co.x - c[0], v.co.y - c[1]
                v.co.x = c[0] + dx * math.cos(a) - dy * math.sin(a)
                v.co.y = c[1] + dx * math.sin(a) + dy * math.cos(a)
        cp.data.materials.clear()
        if ob in lk.textured():
            cp.data.materials.append(mats[lk.name])
            c = tint if (tint and mname.endswith("Body") and lk.tint) else (lk.body_rgb if mname.endswith("Body") else lk.detail_rgb)
            cp.color = (lin(c[0]), lin(c[1]), lin(c[2]), 1)
        else:
            rgb, kind, alpha = lk.extra[mname]
            cp.data.materials.append(_mat_flat(rgb, kind, alpha))
        cp.location = rb(*at)
        cp.rotation_euler = (0, 0, math.radians(ry))
        _keep(cp)


def _camera(frm, to, lens=40):
    return _keep(kit.camera(rb(*frm), rb(*to), lens=lens))


def _size(lk):
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for ob in lk.meshes.values():
        for v in ob.data.vertices:
            r = (v.co.x, v.co.z, -v.co.y)
            for i in range(3):
                lo[i] = min(lo[i], r[i])
                hi[i] = max(hi[i], r[i])
    return lo, hi


PAINTS = [(226, 64, 52), (52, 128, 220), (250, 196, 44), (80, 184, 96), (244, 244, 240), (40, 180, 190)]


def run(LOOKS, MAPS, fast=False, only=None):
    res = (640, 400) if fast else (960, 600)
    _scene(fast, res)
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.hide_render = True
    mats = {name: _mat_textured(name, MAPS[name]) for name in LOOKS}
    shots = []
    order = ["CarSedan", "CarHatch", "CarTaxi", "CarBubble", "Tram", "DockTruck", "FieldTripBus", "IceCreamTruck",
             "FerryVan", "NewsVan", "ShowVan", "PartsTruck"]
    street_only = os.environ.get("VPREVIEW_STREET")  # just the street shot (a check)
    for name in [] if street_only else [n for n in order if n in LOOKS] + [n for n in LOOKS if n not in order]:
        lk = LOOKS[name]
        lo, hi = _size(lk)
        L = hi[2] - lo[2]
        Hh = hi[1]
        _ground(400)
        _place(lk, mats, tint=PAINTS[1] if lk.tint else None, steer=22)
        _hero(hi[0] + 2.4, 0, lo[2] + L * 0.62, yaw=-20)
        d = max(L, Hh * 2.0) * 1.55
        _camera((-d * 0.7, Hh * 0.55 + d * 0.2, -d * 0.62), (0, Hh * 0.42, 0), lens=45)
        out = os.path.join(PREV, "vehicle_%s.png" % name)
        kit.render(out)
        shots.append((name, out))
        _clear()
        # the back three quarters, smaller
        _ground(400)
        _place(lk, mats, tint=PAINTS[0] if lk.tint else None)
        _camera((d * 0.7, Hh * 0.55 + d * 0.22, d * 0.66), (0, Hh * 0.42, 0), lens=45)
        out = os.path.join(PREV, "vehicle_%s_back.png" % name)
        kit.render(out)
        _clear()
        if os.environ.get("VPREVIEW_FRONT"):  # a straight-on look at the nose (a check; not in the sheet)
            _ground(400)
            _place(lk, mats, tint=PAINTS[1] if lk.tint else None)
            _camera((-L * 0.25, Hh * 0.75, lo[2] - L * 0.9), (0, Hh * 0.5, 0), lens=45)
            kit.render(os.path.join(PREV, "vehicle_%s_front.png" % name))
            _clear()
    if only is None or street_only:
        street(LOOKS, mats)
        sheet(shots)


def street(LOOKS, mats):
    """A staged Downtown street: the hub's cars in a few paints along both kerbs, a tram down the middle and the
    escorts queued behind it (a look check; the real hub layout spreads its 40 vehicles too thin for one shot)."""
    _ground(600, (96, 98, 104))
    for x in (-13.0, 13.0):  # the pavements
        k = _keep(kit.box("kerb", 6, 220, 0.6, at=(x * 1.4, 0, 0.3)))
        k.data.materials.append(_mat_flat((176, 172, 164), "SmoothPlastic", 0))
    cars = ["CarSedan", "CarHatch", "CarTaxi", "CarBubble", "CarSedan", "CarHatch", "CarBubble", "CarTaxi"]
    for i, name in enumerate(cars):
        if name not in LOOKS:
            continue
        for side in (-1, 1):
            k = i * 2 + (side > 0)
            _place(LOOKS[name], mats, at=(side * 11.5, 0, -40 + i * 13 + (side > 0) * 6), ry=180 if side < 0 else 0,
                   tint=PAINTS[k % len(PAINTS)] if LOOKS[name].tint else None)
    if "Tram" in LOOKS:
        _place(LOOKS["Tram"], mats, at=(-4.5, 0, 6), ry=0, tint=(250, 196, 44))
    z = 34
    for name in ("DockTruck", "FieldTripBus", "IceCreamTruck", "NewsVan"):
        if name in LOOKS:
            _place(LOOKS[name], mats, at=(4.8, 0, z), ry=0, tint=PAINTS[1] if LOOKS[name].tint else None)
            z += 22 if name == "DockTruck" else 16
    _hero(7.5, 0, -14, yaw=30)
    _camera((30, 18, -52), (0, 2, 4), lens=32)
    kit.render(os.path.join(PREV, "vehicles_street.png"))
    _clear()


def sheet(shots):
    imgs = []
    for name, path in shots + [("street", os.path.join(PREV, "vehicles_street.png"))]:
        if os.path.exists(path):
            im = bpy.data.images.load(path)
            a = np.empty(im.size[0] * im.size[1] * 4, dtype=np.float32)
            im.pixels.foreach_get(a)
            imgs.append(a.reshape(im.size[1], im.size[0], 4))
    if not imgs:
        return
    h, w = imgs[0].shape[:2]
    cols = 4
    rows = (len(imgs) + cols - 1) // cols
    out = np.ones((rows * h, cols * w, 4), dtype=np.float32) * 0.1
    for i, a in enumerate(imgs):
        r, c = i // cols, i % cols
        if a.shape[:2] != (h, w):
            continue
        out[(rows - 1 - r) * h:(rows - r) * h, c * w:(c + 1) * w] = a
    im = bpy.data.images.new("sheet", cols * w, rows * h, alpha=True)
    im.pixels.foreach_set(out.reshape(-1))
    im.filepath_raw = os.path.join(PREV, "vehicles.png")
    im.file_format = "PNG"
    im.save()
