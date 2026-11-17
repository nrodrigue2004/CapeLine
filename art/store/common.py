# art/store/common.py: the shared kit for the store art (notes/Store Page.md: the experience icons and the
# thumbnails nate A/B tests at launch). Everything is the game's own art, posed for a poster:
#   * heroes: the blocky R15 body with Roblox's classic Shirt and Pants mapping (art/blender/clothed.py's body,
#     faces from art/clothes/faces.py, clothes from art/clothes/heroes.py tinted the way the game tints them), or
#     painted in suit colours (Shared.LookKit's SUIT_COLORS), with the creator's gear: capes, masks, gloves,
#     boots, emblems, hair (Spiky, Swept), auras;
#   * robots: the remade Spark Trooper (art/export/Trooper.fbx + art/export/trooper/*.png, coloured as
#     EnemyRenderer colours it, human eyes or turned glowing ones, a broken shell showing the endoskeleton);
#   * the city: the kit's tiling building fronts (art/export/city, art/city/materials.py) on box towers;
#   * effects: the effects library's textures (art/export/fx) on camera-facing cards, plus 3D bolts and chunks.
# Blender axes as the other art scripts: x across, +y the figure's front, z up; 1 unit = 1 stud.
# Run nothing here directly: art/store/icons.py and art/store/thumbs.py import it.
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ART, "blender"))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

OUT = os.path.join(ART, "export", "store")  # finished PNGs (nate uploads them himself)
RAW = os.path.join(OUT, "raw")  # the renders before post.py adds speed lines, grading and captions
FX = os.path.join(ART, "export", "fx")
# the city kit and the bosses come from the art pipeline's exports; STORE_ASSETS points at another checkout's
# art/ folder when this branch is older than the art (the whole-city kit and the remade bosses)
ASSETS = os.environ.get("STORE_ASSETS") or ART
CITY = os.path.join(ASSETS, "export", "city")
CLOTHES = os.path.join(ART, "export", "clothes")
DRAFT = "--draft" in sys.argv


def _load_clothed():
    """clothed.py's definitions (the blocky body, the template UVs, head, hair, face decal) without its renders:
    the script runs its preview at module level, so only the part before the preview branch is run."""
    path = os.path.join(ART, "blender", "clothed.py")
    with open(path) as f:
        src = f.read()
    head = src.split('\nif ROBOT == "heroes":')[0]
    ns = {"__file__": path, "__name__": "clothed_defs"}
    argv = sys.argv
    sys.argv = [path]
    try:
        exec(compile(head, path, "exec"), ns)
    finally:
        sys.argv = argv
    return ns


BODY = _load_clothed()  # also resets the scene (kit.reset)
BLOCKS = BODY["BLOCKS"]
lin = BODY["lin"]


def srgb(c):
    return BODY["srgb"](c)


def lin3(c):
    return (lin(c[0]), lin(c[1]), lin(c[2]), 1)


# ------------------------------------------------------------------------------------------------ the rig
# joints of the blocky R15 body (the same pivots as art/blender/trooper.py's preview and Shared.RigMath)
J = {
    "Waist": Vector((0, 0, 2.4)), "Neck": Vector((0, 0, 4.0)),
    "LeftShoulder": Vector((-1.0, 0, 3.76)), "LeftElbow": Vector((-1.5, 0, 3.15)),
    "LeftWrist": Vector((-1.5, 0, 2.3)), "LeftHip": Vector((-0.5, 0, 2.0)),
    "LeftKnee": Vector((-0.5, 0, 1.15)), "LeftAnkle": Vector((-0.5, 0, 0.3)),
}
for _k in list(J):
    if _k.startswith("Left"):
        J["Right" + _k[4:]] = Vector((-J[_k].x, J[_k].y, J[_k].z))
PARENT = {"UpperTorso": ("LowerTorso", "Waist"), "Head": ("UpperTorso", "Neck")}
for _s in ("Left", "Right"):
    PARENT[_s + "UpperArm"] = ("UpperTorso", _s + "Shoulder")
    PARENT[_s + "LowerArm"] = (_s + "UpperArm", _s + "Elbow")
    PARENT[_s + "Hand"] = (_s + "LowerArm", _s + "Wrist")
    PARENT[_s + "UpperLeg"] = ("LowerTorso", _s + "Hip")
    PARENT[_s + "LowerLeg"] = (_s + "UpperLeg", _s + "Knee")
    PARENT[_s + "Foot"] = (_s + "LowerLeg", _s + "Ankle")
PARTS = ["Head", "UpperTorso", "LowerTorso"] + [s + p for s in ("Left", "Right") for p in
                                                 ("UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot")]
CENTRE = Vector((0, 0, 2.6))


def root_axes(at, up, front, scale=1.0):
    """The figure's matrix from where its head points (up) and where its chest faces (front, made square to up)."""
    z = Vector(up).normalized()
    y = (Vector(front) - z * Vector(front).dot(z)).normalized()
    x = y.cross(z)
    r = Matrix((x, y, z)).transposed().to_4x4()
    return Matrix.Translation(Vector(at)) @ r @ Matrix.Scale(scale, 4) @ Matrix.Translation(-CENTRE)


def view_rot(loc, target):
    """A camera's rotation looking from loc at target (as kit.camera aims it)."""
    return (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_matrix()


def staged(cam_loc, cam_target, ref_loc, ref_target, offset=(0, 0, 0), turn=0.0):
    """Carries a pose staged against a reference camera (ref_loc looking at ref_target, the subject at the
    origin) into a scene camera: returns (where the subject goes, the rotation to apply). offset moves the
    subject in the scene camera's frame (x right, y up, z toward the camera), to frame it off centre."""
    rs, ri = view_rot(cam_loc, cam_target), view_rot(ref_loc, ref_target)
    W = rs @ ri.transposed()
    at = Vector(cam_loc) + W @ (-Vector(ref_loc)) + rs @ Vector(offset)
    # then turn the subject so the camera still sees it from the staged angle (the line of sight moves with the
    # offset, which would otherwise show it from another side)
    for _ in range(3):
        W = view_rot(cam_loc, at + W @ Vector(ref_target)) @ ri.transposed()
    if turn:  # then turn it about the camera's up axis (degrees) for a better side
        W = Matrix.Rotation(math.radians(turn), 3, rs @ Vector((0, 1, 0))) @ W
    return at, W


def rig(root, bends):
    """World matrix per part. root: the figure's matrix (pivot at the body's centre, CENTRE). bends: joint ->
    (x, y, z) degrees, applied in the parent's frame at the joint."""
    out = {}

    def m(n):
        if n in out:
            return out[n]
        if n not in PARENT:
            out[n] = root
            return root
        par, jn = PARENT[n]
        mm = m(par)
        if jn in bends:
            r = Euler([math.radians(a) for a in bends[jn]], "XYZ").to_matrix().to_4x4()
            mm = mm @ Matrix.Translation(J[jn]) @ r @ Matrix.Translation(-J[jn])
        out[n] = mm
        return mm

    for n in PARTS:
        m(n)
    return out


def aim(root, bends, joint, direction):
    """The (x, y, z) degrees for a shoulder or hip so its limb (hanging along -z at rest) points along a world
    direction, given the rest of the pose."""
    parent = {"Shoulder": "UpperTorso", "Hip": "LowerTorso"}[joint.replace("Left", "").replace("Right", "")]
    m = rig(root, {k: v for k, v in bends.items() if k != joint})[parent].to_3x3().normalized()
    d = (m.inverted() @ Vector(direction)).normalized()
    q = Vector((0, 0, -1)).rotation_difference(d)
    return tuple(math.degrees(a) for a in q.to_euler("XYZ"))


def root_matrix(at, rot=(0, 0, 0), scale=1.0):
    """at: where the body's centre goes; rot: degrees (XYZ)."""
    r = Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    return Matrix.Translation(Vector(at)) @ r @ Matrix.Scale(scale, 4) @ Matrix.Translation(-CENTRE)


# ------------------------------------------------------------------------------------------------ materials
_mats = {}


def flat(name, rgb, rough=0.5, metal=0.0, emit=0.0, coat=0.0):
    """A material from a Roblox (sRGB) colour."""
    key = (name, tuple(rgb), rough, metal, emit, coat)
    if key in _mats:
        return _mats[key]
    m = kit.material("%s_%d" % (name, len(_mats)), srgb(rgb), metal=metal, rough=rough, emit=emit)
    p = m.node_tree.nodes["Principled BSDF"]
    if coat > 0:
        p.inputs["Coat Weight"].default_value = coat
        p.inputs["Coat Roughness"].default_value = 0.15
    _mats[key] = m
    return m


def glow_mat(name, rgb, strength=6.0, additive=False):
    """Pure emission. additive: see-through glow (light added over what is behind, like a halo)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = lin3(rgb)
    em.inputs["Strength"].default_value = strength
    out = em.outputs[0]
    if additive:
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        add = nt.nodes.new("ShaderNodeAddShader")
        nt.links.new(tr.outputs[0], add.inputs[0])
        nt.links.new(em.outputs[0], add.inputs[1])
        out = add.outputs[0]
    nt.links.new(out, nt.nodes["Material Output"].inputs["Surface"])
    return m


def _image(path, data=False):
    img = bpy.data.images.load(path, check_existing=True)
    if data:
        img.colorspace_settings.name = "Non-Color"
    img.alpha_mode = "STRAIGHT"
    return img


def clothes_mat(name, skin, layers):
    """The part's skin colour under each (template image, tint) layer, as Roblox shows a tinted Shirt or Pants
    (Clothing.Color3 multiplies the image)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.55
    col = nt.nodes.new("ShaderNodeRGB")
    col.outputs[0].default_value = lin3(skin)
    last = col.outputs[0]
    for img, tint in layers:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        t.interpolation = "Closest"
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(t.outputs["Color"], mul.inputs["A"])
        mul.inputs["B"].default_value = lin3(tint)
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        nt.links.new(t.outputs["Alpha"], mix.inputs["Factor"])
        nt.links.new(last, mix.inputs["A"])
        nt.links.new(mul.outputs["Result"], mix.inputs["B"])
        last = mix.outputs["Result"]
    nt.links.new(last, p.inputs["Base Color"])
    return m


def card_mat(name, tex, rgb=(255, 255, 255), strength=3.0, alpha=1.0, cell=None, emissive=True):
    """A card showing one of the effects textures (black background = clear): emission tinted rgb.
    cell: (col, row, n) picks one frame of an n x n flipbook."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    out = nt.nodes["Material Output"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = _image(os.path.join(FX, tex))
    t.extension = "CLIP"
    if cell:
        cx, cy, n = cell
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (1 / n, 1 / n, 1)
        mp.inputs["Location"].default_value = (cx / n, (n - 1 - cy) / n, 0)
        nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], t.inputs["Vector"])
    else:
        nt.links.new(tc.outputs["UV"], t.inputs["Vector"])
    # coverage: the texture's alpha if it has one, else its brightness
    bw = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(t.outputs["Color"], bw.inputs["Color"])
    cov = nt.nodes.new("ShaderNodeMath")
    cov.operation = "MULTIPLY"
    nt.links.new(t.outputs["Alpha"], cov.inputs[0])
    cov.inputs[1].default_value = alpha
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    if emissive:
        sh = nt.nodes.new("ShaderNodeEmission")
        tint = nt.nodes.new("ShaderNodeMix")
        tint.data_type = "RGBA"
        tint.blend_type = "MULTIPLY"
        tint.inputs["Factor"].default_value = 1.0
        nt.links.new(t.outputs["Color"], tint.inputs["A"])
        tint.inputs["B"].default_value = lin3(rgb)
        nt.links.new(tint.outputs["Result"], sh.inputs["Color"])
        sh.inputs["Strength"].default_value = strength
        add = nt.nodes.new("ShaderNodeAddShader")
        # emission adds light; the transparent part lets the scene through
        nt.links.new(tr.outputs[0], add.inputs[0])
        nt.links.new(sh.outputs[0], add.inputs[1])
        nt.links.new(add.outputs[0], out.inputs["Surface"])
    else:
        sh = nt.nodes.new("ShaderNodeBsdfPrincipled")
        sh.inputs["Base Color"].default_value = lin3(rgb)
        sh.inputs["Roughness"].default_value = 1.0
        sh.inputs["Emission Color"].default_value = lin3(rgb)  # dust glows a little in the light it scatters
        sh.inputs["Emission Strength"].default_value = 0.35
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(cov.outputs[0], mix.inputs["Fac"])
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(sh.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
    return m


TILE = {"Asphalt": 16, "Paving": 8, "Cobble": 8, "Flagstone": 8, "Terrazzo": 8, "RoofTile": 6}
TINTED = set()


def kit_mat(name, tint=None):
    """The city kit's tiling building front (as art/blender/block.py: box-projected from the object's origin,
    one 12-stud storey a tile), optionally tinted (the game picks each front from the building's palette)."""
    tile = TILE.get(name, 12)
    if isinstance(tint, str):
        tint = tuple(PALETTE.get(tint, (255, 255, 255)))
    key = ("kit", name, tint)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("Kit%s_%d" % (name, len(_mats)))
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    s = 1.0 / tile
    mp.inputs["Scale"].default_value = (s, s, s)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])

    def img(kind, data):
        path = os.path.join(CITY, "%s_%s.png" % (name, kind))
        if not os.path.exists(path):
            return None
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = _image(path, data)
        n.projection = "BOX"
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
        return n

    c = img("Color", False)
    if tint:
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0 if (name in TINTED) else 0.6
        nt.links.new(c.outputs["Color"], mul.inputs["A"])
        mul.inputs["B"].default_value = lin3(tint)
        nt.links.new(mul.outputs["Result"], p.inputs["Base Color"])
    else:
        nt.links.new(c.outputs["Color"], p.inputs["Base Color"])
    r = img("Roughness", True)
    nt.links.new(r.outputs["Color"], p.inputs["Roughness"])
    mt = img("Metalness", True)
    if mt:
        nt.links.new(mt.outputs["Color"], p.inputs["Metallic"])
    n = img("Normal", True)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(n.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    _mats[key] = m
    return m


# ------------------------------------------------------------------------------------------------ collections
def collection(name):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c


def put(ob, coll):
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    coll.objects.link(ob)
    return ob


# ------------------------------------------------------------------------------------------------ heroes
def _apply(ob, mat):
    ob.matrix_world = mat @ ob.matrix_world
    return ob


def spiky_hair(rgb, glow=0.0, count=11, seed=3):
    """Anime spikes (the creator's Anime Spikes / Spiky hair): a cap and sharp spikes swept back and up."""
    rng = random.Random(seed)
    cap = BODY["hair"]()
    subs = [cap]
    spikes = [(-0.1, 0.55, 0.55, 0.1, 0.35), (0.3, 0.5, 0.5, 0.0, 0.3), (-0.45, 0.4, 0.45, -0.1, 0.32)]
    # (x, front, length, sideways lean, radius): front fringe spikes, then a crown sweeping back
    for i in range(count):
        a = -math.pi * 0.9 + i * (math.pi * 1.8) / (count - 1)
        spikes.append((math.sin(a) * 0.48, math.cos(a) * 0.38 - 0.08, 0.75 + rng.random() * 0.4,
                       math.sin(a) * 0.8, 0.24 + rng.random() * 0.06))
    for k, (x, y, ln, lean, r) in enumerate(spikes):
        base = Vector((x, y, 5.12))
        d = Vector((lean * 0.7, -0.75 if y < 0.2 else 0.55, 0.85)).normalized()
        if y >= 0.45:  # the fringe points forward and down over the brow
            d = Vector((lean, 0.6, 0.25)).normalized()
            base = Vector((x, y, 5.05))
        tip = base + d * ln
        sp = kit.tube_along("spk%d" % k, [base, base.lerp(tip, 0.5), tip], [r, r * 0.55, 0.0], segs=6)
        subs.append(sp)
    ob = kit.join("SpikyHair", subs)
    ob.data.materials.append(flat("hair", rgb, rough=0.45, emit=glow))
    return ob


def cape(rgb, inner=None, length=3.4, flare=1.35, lift=0.0, wave=0.25, flow=(0, 0, 0), seed=1, segs=(10, 16)):
    """The creator's cape (cape:classic, LookKit: 1.9 wide, from the shoulders) as cloth: pinned across the top of
    the back, flaring, rippling. flow: extra drift (body-local studs) at the hem, quadratic down its length."""
    rng = random.Random(seed)
    nx, ny = segs
    me = bpy.data.meshes.new("Cape")
    verts, faces = [], []
    ph = rng.random() * 6
    for j in range(ny + 1):
        t = j / ny
        w = 1.9 * (1 + (flare - 1) * t) / 2
        for i in range(nx + 1):
            u = i / nx * 2 - 1
            x = u * w
            z = 3.95 - length * t
            y = -0.56 - lift * t * t - 0.12 * t
            y -= wave * t * math.sin(u * 2.6 + ph + t * 4.0)
            z += 0.1 * t * math.cos(u * 3.1 + ph)
            x += flow[0] * t * t
            y += flow[1] * t * t
            z += flow[2] * t * t
            verts.append((x, y, z))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
    me.from_pydata(verts, [], faces)
    ob = bpy.data.objects.new("Cape", me)
    bpy.context.scene.collection.objects.link(ob)
    sol = ob.modifiers.new("S", "SOLIDIFY")
    sol.thickness = 0.07
    sol.use_even_offset = True
    sol.material_offset = 1
    kit.smooth(ob, 1)
    kit.apply_all(ob)
    kit.shade_auto(ob, 50)
    ob.data.materials.append(flat("cape", rgb, rough=0.55, coat=0.2))
    ob.data.materials.append(flat("capein", inner or tuple(int(c * 0.55) for c in rgb), rough=0.7))
    return ob


def domino(rgb=(24, 24, 30), eyes=(255, 255, 255)):
    """The Domino Mask (LookKit: across the eyes) with the comic look's white eye lenses."""
    band = kit.box("mask", 1.3, 0.16, 0.34, at=(0, 0.6, 4.72))
    kit.bevel(band, 0.05, 2)
    kit.deform(band, lambda v: Vector((v.x, v.y - 0.25 * v.x * v.x, v.z + 0.06 * abs(v.x) ** 1.5)))
    band.data.materials.append(flat("mask", rgb, rough=0.35, coat=0.4))
    lenses = []
    for s in (-1, 1):
        e = kit.box("lens", 0.26, 0.06, 0.14, at=(s * 0.24, 0.69 - 0.25 * 0.24 * 0.24, 4.72))
        kit.bevel(e, 0.03, 2)
        kit.deform(e, lambda v, s=s: Vector((v.x, v.y, v.z + (0.05 if v.x * s > 0.24 else 0) * (1 if v.z > 4.72 else 0))))
        e.data.materials.append(flat("lens", eyes, rough=0.2, emit=0.6))
        lenses.append(e)
    return [band] + lenses


def horns(rgb=(46, 30, 70), tip=(200, 80, 255)):
    """A villain's horned mask: a band across the eyes and two horns curling up from the brow (original shape)."""
    band = domino(rgb, eyes=(255, 60, 60))
    out = list(band)
    for s in (-1, 1):
        pts = [Vector((s * 0.42, 0.42, 5.0)), Vector((s * 0.62, 0.3, 5.35)), Vector((s * 0.66, 0.1, 5.75)),
               Vector((s * 0.55, -0.1, 6.0))]
        h = kit.tube_along("horn", pts, [0.16, 0.12, 0.07, 0.0], segs=10)
        h.data.materials.append(flat("horn", tip, rough=0.35, coat=0.5))
        out.append(h)
    return out


def glow_eyes(rgb, strength=8.0):
    out = []
    for s in (-1, 1):
        e = kit.box("geye", 0.24, 0.05, 0.11, at=(s * 0.23, 0.635, 4.68))
        kit.bevel(e, 0.02, 1)
        e.data.materials.append(glow_mat("geye", rgb, strength))
        out.append(e)
    return out


def emblem_star(rgb, edge=(255, 255, 255), at=(0, 0.53, 3.35), size=0.45):
    """A chest emblem: a five-point star on a disc (the creator's starter emblem is a star)."""
    pts = []
    for i in range(10):
        a = math.pi / 2 + i * math.pi / 5
        r = size if i % 2 == 0 else size * 0.45
        pts.append((math.cos(a) * r, math.sin(a) * r))
    me = bpy.data.meshes.new("star")
    vs = [(at[0] + x, at[1] + 0.03, at[2] + z) for x, z in pts] + [(at[0], at[1] + 0.03, at[2])]
    fs = [(10, i, (i + 1) % 10) for i in range(10)]
    me.from_pydata(vs, [], fs)
    star = bpy.data.objects.new("star", me)
    bpy.context.scene.collection.objects.link(star)
    sol = star.modifiers.new("S", "SOLIDIFY")
    sol.thickness = 0.05
    kit.apply_all(star)
    star.data.materials.append(flat("star", rgb, rough=0.3, coat=0.5))
    disc = kit.cyl("disc", size * 1.25, size * 1.25, 0.05, at=(at[0], at[1], at[2]), segs=32, axis="Y")
    disc.data.materials.append(flat("disc", edge, rough=0.3, coat=0.5))
    return [disc, star]


def bolt_emblem(rgb, edge, at=(0, 0.53, 3.35), size=0.5):
    """A lightning-bolt chest emblem on a diamond (the Storm Front look)."""
    dia = kit.box("dia", size * 1.4, 0.05, size * 1.4, at=at)
    dia.rotation_euler = (0, math.radians(45), 0)
    kit.apply_all(dia)
    bpy.context.view_layer.objects.active = dia
    dia.data.transform(Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(45), 4, "Y")
                       @ Matrix.Translation(-Vector(at)))
    dia.data.materials.append(flat("dia", edge, rough=0.3, coat=0.5))
    p = [(-0.1, 0.55), (0.32, 0.55), (0.05, 0.08), (0.3, 0.08), (-0.2, -0.6), (-0.02, -0.1), (-0.28, -0.1)]
    me = bpy.data.meshes.new("bolt")
    vs = [(at[0] + x * size, at[1] + 0.04, at[2] + z * size) for x, z in p]
    me.from_pydata(vs, [], [tuple(range(len(p)))])
    b = bpy.data.objects.new("bolt", me)
    bpy.context.scene.collection.objects.link(b)
    sol = b.modifiers.new("S", "SOLIDIFY")
    sol.thickness = 0.05
    kit.apply_all(b)
    b.data.materials.append(flat("boltem", rgb, rough=0.3, coat=0.5))
    return [dia, b]


def hero(root, bends=None, skin=(240, 190, 150), face="Hero", turned=False, suit=None, shirt=None, pants=None,
         hair="swept", hair_rgb=(70, 46, 30), hair_glow=0.0, cape_rgb=None, cape_kw=None, mask=None,
         gloves=None, boots=None, belt=None, emblem=None, eyes=None, coll=None, extra=None):
    """One hero on the blocky R15 body. suit: (torso, arms, legs) colours (LookKit paints the body) or None for
    clothes: shirt/pants = (template name, tint). gloves/boots/belt: colours of those gear pieces. Returns the
    part matrices (for effects placed on hands and so on) and the objects."""
    bends = bends or {}
    M = rig(root, bends)
    coll = coll or collection("Heroes")
    obs = []
    shirt_img = BODY["image"]("heroes/Shirt_" + shirt[0]) if shirt else None
    pants_img = BODY["image"]("heroes/Pants_" + pants[0]) if pants else None
    for n in PARTS:
        if n == "Head":
            continue
        ob = BODY["part_box"](n)
        short = n.replace("Left", "").replace("Right", "")
        if suit:
            col = suit[0] if "Torso" in short else (suit[1] if "Arm" in short or short == "Hand" else suit[2])
            if short == "Hand" and gloves:
                col = gloves
            if short == "Foot" and boots:
                col = boots
            ob.data.materials.append(flat("suit", col, rough=0.42, coat=0.25))
        else:
            if short in ("UpperTorso", "UpperArm", "LowerArm", "Hand"):
                layers = [(shirt_img, shirt[1])]
            else:
                layers = [(pants_img, pants[1])]
            if "Torso" in short:
                layers = [(pants_img, pants[1]), (shirt_img, shirt[1])]
            ob.data.materials.append(clothes_mat(n, skin, layers))
        obs.append(_apply(ob, M[n]))
    h = BODY["head"]()
    kit.shade_auto(h, 60)
    h.data.materials.append(flat("skin", skin, rough=0.5))
    obs.append(_apply(h, M["Head"]))
    obs.append(_apply(BODY["face_plane"](turned, face), M["Head"]))
    if hair == "swept":
        hr = BODY["hair"]()
        kit.shade_auto(hr, 40)
        hr.data.materials.append(flat("hair", hair_rgb, rough=0.5, emit=hair_glow))
    elif hair == "spiky":
        hr = spiky_hair(hair_rgb, glow=hair_glow)
    else:
        hr = None
    if hr:
        obs.append(_apply(hr, M["Head"]))
    if mask == "horns":
        for ob in horns():
            obs.append(_apply(ob, M["Head"]))
    elif mask:
        for ob in domino(mask):
            obs.append(_apply(ob, M["Head"]))
    if eyes:
        for ob in glow_eyes(eyes):
            obs.append(_apply(ob, M["Head"]))
    # gloves and boots: flared cuffs over the hands and feet (the creator's Gloves and Boots tabs)
    for s in ("Left", "Right"):
        sx = -1 if s == "Left" else 1
        if gloves:
            cuff = kit.box("cuff", 1.14, 1.14, 0.32, at=(sx * 1.5, 0, 2.42))
            kit.bevel(cuff, 0.06, 2)
            cuff.data.materials.append(flat("glove", gloves, rough=0.4, coat=0.3))
            obs.append(_apply(cuff, M[s + "LowerArm"]))
        if boots:
            top = kit.box("boot", 1.12, 1.12, 0.36, at=(sx * 0.5, 0, 1.0))
            kit.bevel(top, 0.06, 2)
            top.data.materials.append(flat("boot", boots, rough=0.4, coat=0.3))
            obs.append(_apply(top, M[s + "LowerLeg"]))
            lower = kit.box("bootl", 1.04, 1.06, 0.7, at=(sx * 0.5, 0, 0.62))
            kit.bevel(lower, 0.04, 2)
            lower.data.materials.append(flat("boot", boots, rough=0.4, coat=0.3))
            obs.append(_apply(lower, M[s + "LowerLeg"]))
    if belt:
        b = kit.box("belt", 2.08, 1.08, 0.26, at=(0, 0, 2.3))
        kit.bevel(b, 0.04, 2)
        b.data.materials.append(flat("belt", belt[0], rough=0.4, coat=0.3))
        buckle = kit.box("buckle", 0.42, 0.1, 0.3, at=(0, 0.54, 2.3))
        kit.bevel(buckle, 0.04, 2)
        buckle.data.materials.append(flat("buckle", belt[1], rough=0.25, metal=0.6))
        obs += [_apply(b, M["LowerTorso"]), _apply(buckle, M["LowerTorso"])]
    if emblem:
        kind, rgb, edge = emblem
        pieces = emblem_star(rgb, edge) if kind == "star" else bolt_emblem(rgb, edge)
        for ob in pieces:
            obs.append(_apply(ob, M["UpperTorso"]))
    if cape_rgb:
        c = cape(cape_rgb, **(cape_kw or {}))
        obs.append(_apply(c, M["UpperTorso"]))
    if extra:
        obs += extra(M)
    for ob in obs:
        put(ob, coll)
    return M, obs


# ------------------------------------------------------------------------------------------------ the robot
_trooper = {}


def _trooper_pieces():
    if _trooper:
        return _trooper
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(ART, "export", "Trooper.fbx"))
    for ob in set(bpy.data.objects) - before:
        if ob.type != "MESH":
            continue
        name = ob.name.split(".")[0]
        ob.hide_render = True
        ob.hide_viewport = True
        ob.matrix_world = Matrix.Identity(4)
        _trooper[name] = ob
    return _trooper


_trooper_tex = {}


def trooper_mat(rgb):
    """The Trooper's texture set over the part colour (SurfaceAppearance Overlay: the colour map's alpha is 0
    where the game's part colour shows)."""
    key = tuple(rgb)
    if key in _trooper_tex:
        return _trooper_tex[key]
    d = os.path.join(ART, "export", "trooper")
    m = bpy.data.materials.new("trooper")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]

    def tex(kind, data):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = _image(os.path.join(d, "Trooper_%s.png" % kind), data)
        return t

    c = tex("Color", False)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = lin3(rgb)
    nt.links.new(c.outputs["Alpha"], mix.inputs["Factor"])
    nt.links.new(c.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], p.inputs["Base Color"])
    nt.links.new(tex("Roughness", True).outputs["Color"], p.inputs["Roughness"])
    nt.links.new(tex("Metalness", True).outputs["Color"], p.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tex("Normal", True).outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    _trooper_tex[key] = m
    return m


def trooper(root, bends=None, suit=(40, 70, 140), trim=(255, 170, 60), skin=(224, 172, 130), hair_rgb=(30, 26, 24),
            turned=True, eye=(255, 70, 40), broken=(), coll=None):
    """The remade Spark Trooper (Config.Enemies colours: suit on the torso, upper arms and thighs; trim on the
    gloves and boots). turned: dark eyes with glowing irises (it has started fighting). broken: parts whose shell
    is gone, showing the chrome endoskeleton (Shared.RobotDamage)."""
    src = _trooper_pieces()
    M = rig(root, bends or {})
    coll = coll or collection("Robots")
    colours = {"Head": skin, "Hair": hair_rgb, "UpperTorso": suit, "LowerTorso": suit}
    for sd in ("Left", "Right"):
        colours[sd + "UpperArm"] = suit
        colours[sd + "UpperLeg"] = suit
        for pn in ("LowerArm", "Hand", "LowerLeg", "Foot"):
            colours[sd + pn] = trim
    blocks = dict(BLOCKS)
    blocks["Head"] = (-0.6, 0.6, -0.6, 0.6, 4.0, 5.2)
    chrome = flat("endo", (170, 176, 190), rough=0.25, metal=1.0)
    obs = []
    for n in PARTS + ["Hair"]:
        parent = "Head" if n == "Hair" else n
        if n in broken:
            if n in blocks:
                x0, x1, y0, y1, z0, z1 = blocks[n]
                r, sz = min(x1 - x0, y1 - y0) * 0.2, (z1 - z0) * 0.94
                e = kit.cyl("endo", r, r * 0.85, sz, at=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), segs=12)
                e.data.materials.append(chrome)
                obs.append(_apply(e, M[n]))
                for k in range(2):
                    jt = kit.sphere("jt", r * 1.25, at=((x0 + x1) / 2, (y0 + y1) / 2, z0 + 0.1 + k * (z1 - z0 - 0.2)))
                    jt.data.materials.append(chrome)
                    obs.append(_apply(jt, M[n]))
            continue
        cp = src[n].copy()
        cp.data = src[n].data.copy()
        bpy.context.scene.collection.objects.link(cp)
        cp.hide_render = False
        cp.hide_viewport = False
        if n == "Hair":
            c = Vector((0, -0.058 * 1.2, 4.6 + 0.313 * 1.2))
        else:
            x0, x1, y0, y1, z0, z1 = blocks[n]
            c = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
        cp.matrix_world = M[parent] @ Matrix.Translation(c)
        cp.data.materials.clear()
        cp.data.materials.append(trooper_mat(colours[n]))
        obs.append(cp)
        if n == "Head":
            for sd in (-1, 1):
                e = kit.box("eye", 0.27, 0.05, 0.1, at=(sd * 0.24, 0.61, 4.66))
                e.data.materials.append(flat("sclera_t" if turned else "sclera", (22, 22, 28) if turned else (242, 240, 234), rough=0.3))
                obs.append(_apply(e, M["Head"]))
                ir = kit.box("iris", 0.15, 0.05, 0.12, at=(sd * 0.22, 0.64, 4.66))
                ir.data.materials.append(glow_mat("iris", eye, 30.0) if turned else flat("iris", (60, 90, 140)))
                obs.append(_apply(ir, M["Head"]))
    for ob in obs:
        put(ob, coll)
    return M, obs


# ------------------------------------------------------------------------------------------------ the city
PALETTE = {  # Config.City.palette
    "concrete": (158, 156, 150), "brick": (140, 98, 82), "slate": (92, 100, 112), "sand": (196, 180, 150),
    "steel": (120, 130, 140), "glass": (70, 96, 120), "roof": (74, 76, 82),
}
FRONTS = ["Curtain", "Office", "Office", "Curtain", "Brick", "Stone"]


def tower(x, y, w, d, h, front, tint=None, coll=None, roof=True, rng=None, crown=True):
    """A box tower with a kit front, a roof slab and roof clutter (tank, vents, antenna). x, y: lower corner."""
    coll = coll or collection("City")
    rng = rng or random.Random(int(x * 7 + y * 13))
    ob = kit.box("tower", w, d, h, at=(w / 2, d / 2, h / 2))
    ob.location = (x, y, 0)
    ob.data.materials.append(kit_mat(front, tint))
    put(ob, coll)
    out = [ob]
    if roof:
        top = kit.box("roof", w + 1.2, d + 1.2, 1.6, at=(x + w / 2, y + d / 2, h + 0.4))
        top.data.materials.append(flat("roofrim", (200, 198, 192), rough=0.8))
        slab = kit.box("roofs", w - 1, d - 1, 0.4, at=(x + w / 2, y + d / 2, h + 0.9))
        slab.data.materials.append(flat("roof", PALETTE["roof"], rough=0.9))
        out += [put(top, coll), put(slab, coll)]
        if crown and front == "Curtain" and rng.random() < 0.6:
            # a stepped crown on glass towers
            c1 = kit.box("crown", w * 0.7, d * 0.7, h * 0.08, at=(x + w / 2, y + d / 2, h + h * 0.04 + 1))
            c1.data.materials.append(kit_mat("Curtain", tint))
            out.append(put(c1, coll))
            ant = kit.cyl("ant", 0.5, 0.2, h * 0.18, at=(x + w / 2, y + d / 2, h + h * 0.08 + h * 0.09 + 1), segs=8)
            ant.data.materials.append(flat("ant", (200, 200, 205), metal=0.8, rough=0.3))
            out.append(put(ant, coll))
            tip = kit.sphere("tip", 0.8, at=(x + w / 2, y + d / 2, h + h * 0.26 + 1))
            tip.data.materials.append(glow_mat("tip", (255, 60, 50), 20))
            out.append(put(tip, coll))
        elif rng.random() < 0.7:
            tx, ty = x + w * (0.25 + rng.random() * 0.5), y + d * (0.25 + rng.random() * 0.5)
            tank = kit.cyl("tank", 4, 4, 7, at=(tx, ty, h + 5), segs=20)
            tank.data.materials.append(flat("tank", (150, 112, 92), rough=0.8))
            cone = kit.cyl("tcone", 4.3, 0.4, 2.6, at=(tx, ty, h + 9.8), segs=20)
            cone.data.materials.append(flat("tcone", (110, 84, 70), rough=0.8))
            out += [put(tank, coll), put(cone, coll)]
            for k in range(4):
                a = k * math.pi / 2 + 0.6
                leg = kit.box("leg", 0.5, 0.5, 2, at=(tx + math.cos(a) * 3, ty + math.sin(a) * 3, h + 1.5))
                leg.data.materials.append(flat("leg", (60, 60, 64), rough=0.6))
                out.append(put(leg, coll))
        for k in range(rng.randint(1, 3)):
            vw = 3 + rng.random() * 4
            v = kit.box("vent", vw, vw * 0.7, 2.2, at=(x + 2 + vw / 2 + rng.random() * max(0.1, w - vw - 4),
                                                      y + 2 + vw / 2 + rng.random() * max(0.1, d - vw - 4), h + 2.2))
            v.data.materials.append(flat("vent", (178, 180, 184), rough=0.5, metal=0.3))
            out.append(put(v, coll))
    return out


def ground(cx, cy, size, coll=None):
    coll = coll or collection("City")
    g = kit.box("ground", size, size, 0.4, at=(size / 2, size / 2, -0.2))
    g.location = (cx - size / 2, cy - size / 2, 0)
    g.data.materials.append(kit_mat("Asphalt"))
    return put(g, coll)


def city(cx, cy, blocks=5, block=96, street=28, seed=7, hmin=40, hmax=220, skip=None, coll=None, centre_boost=1.6,
         tints=True, keep=None):
    """A Downtown grid around (cx, cy): each block one to four towers with kit fronts, taller toward the middle,
    sidewalks (kit Paving) around each block. skip(x, y) -> True leaves a lot empty (camera paths, set pieces).
    keep(x, y, w, d) -> False drops a tower (to clear a view)."""
    if os.environ.get("STORE_NOCITY"):  # quick pose checks
        return []
    rng = random.Random(seed)
    coll = coll or collection("City")
    pitch = block + street
    half = blocks * pitch / 2
    out = []
    for bi in range(blocks):
        for bj in range(blocks):
            bx = cx - half + bi * pitch + street / 2
            by = cy - half + bj * pitch + street / 2
            if skip and skip(bx + block / 2, by + block / 2):
                continue
            side = kit.box("walk", block + 8, block + 8, 0.6, at=(bx + block / 2, by + block / 2, 0.3))
            side.location = (0, 0, 0)
            side.data.materials.append(kit_mat("Paving"))
            out.append(put(side, coll))
            dist = math.hypot(bx + block / 2 - cx, by + block / 2 - cy) / (half + 1)
            tall = 1 + (centre_boost - 1) * max(0.0, 1 - dist)
            split = rng.choice([1, 2, 2, 4])
            lots = []
            if split == 1:
                lots = [(bx + 4, by + 4, block - 8, block - 8)]
            elif split == 2:
                h2 = block / 2
                if rng.random() < 0.5:
                    lots = [(bx + 4, by + 4, h2 - 6, block - 8), (bx + h2 + 2, by + 4, h2 - 6, block - 8)]
                else:
                    lots = [(bx + 4, by + 4, block - 8, h2 - 6), (bx + 4, by + h2 + 2, block - 8, h2 - 6)]
            else:
                h2 = block / 2
                lots = [(bx + 4 + i * h2, by + 4 + j * h2, h2 - 8, h2 - 8) for i in range(2) for j in range(2)]
            for (lx, ly, lw, ld) in lots:
                if keep and not keep(lx, ly, lw, ld):
                    continue
                front = rng.choice(FRONTS)
                h = (hmin + rng.random() * (hmax - hmin)) * tall
                if front in ("Brick", "Stone"):
                    h *= 0.45
                h = max(24, round(h / 12) * 12)
                tint = None
                if tints and front in ("Office", "Brick", "Stone"):
                    tint = rng.choice([None, (255, 236, 214), (214, 232, 255), (255, 220, 200), (230, 240, 230)])
                out += tower(lx, ly, lw, ld, h, front, tint, coll, rng=rng)
    return out


def _wedge(sx, sy, sz):
    """A Roblox WedgePart in Blender axes (as art/blender/block.py): high edge at Roblox +z, sloping to -z."""
    import bmesh
    bm = bmesh.new()
    pts = [(-sx / 2, -sy / 2, -sz / 2), (sx / 2, -sy / 2, -sz / 2), (sx / 2, -sy / 2, sz / 2), (-sx / 2, -sy / 2, sz / 2),
           (-sx / 2, sy / 2, sz / 2), (sx / 2, sy / 2, sz / 2)]
    v = [bm.verts.new((x, -z, y)) for (x, y, z) in pts]
    for f in ((0, 1, 2, 3), (3, 2, 5, 4), (0, 4, 5, 1), (0, 3, 4), (1, 5, 2)):
        bm.faces.new([v[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit._obj("w", bm)


def rb(x, y, z):
    """Roblox (x, up, back) to Blender (x, front, up)."""
    return Vector((x, -z, y))


def layout(area, keep=None, skip_kinds=("mark", "prop", "terminal"), coll=None):
    """The game's own district (art/city/block.luau writes art/export/city/<area>.json from WorldMap), placed the
    way art/blender/block.py places it, with the kit fronts tinted as the game tints them. keep(box) -> False
    leaves a box out (to open a camera path). Returns the layout's data (cams, window)."""
    import json
    path = os.path.join(CITY, area + ".json")
    data = json.load(open(path))
    TILE.update(data.get("studsPerTile", {}))
    TINTED.update(k for k, v in data.get("tinted", {}).items() if v)
    PALETTE.update({k: tuple(v) for k, v in data["palette"].items()})
    coll = coll or collection("City")
    for b in data["boxes"]:
        if b["kind"] in skip_kinds or b["kind"] in ("ground", "sea") or (b["kind"] == "band" and b.get("plain")):
            continue
        if keep and not keep(b):
            continue
        sx, sy, sz = b["sx"], b["sy"], b["sz"]
        shape = b.get("shape")
        if shape == "cylinder":
            ob = kit.cyl("c", sx / 2, sx / 2, sy, segs=20)
            ob.location = rb(b["cx"], b["cy"], b["cz"])
        elif shape == "ball":
            ob = kit.sphere("s", r=max(sx, sy, sz) / 2, segs=16, rings=10)
            ob.location = rb(b["cx"], b["cy"], b["cz"])
        elif shape == "wedge":
            ob = _wedge(sx, sy, sz)
            ob.location = rb(b["cx"], b["cy"], b["cz"])
            ob.rotation_euler = (0, 0, math.radians(b.get("ry") or 0))
        else:
            if (b.get("ry") or 0) % 180 == 90:
                sx, sz = sz, sx
            ob = kit.box("b", sx, sz, sy, at=(sx / 2, sz / 2, sy / 2))
            ob.location = rb(b["cx"] - sx / 2, b["cy"] - sy / 2, b["cz"] + sz / 2)
        name = b.get("kit")
        if name and os.path.exists(os.path.join(CITY, name + "_Color.png")):
            tint = b.get("tint") or (b["color"] if name in TINTED else None)
            ob.data.materials.append(kit_mat(name, tint))
        else:
            rgb = PALETTE.get(b["color"], (160, 160, 160))
            if b["kind"] == "glow":
                ob.data.materials.append(flat("glow", rgb, rough=0.3, emit=2.0))
            elif b["kind"] == "water":
                ob.data.materials.append(flat("water", (56, 120, 168), rough=0.05))
            else:
                ob.data.materials.append(flat("plain", rgb, rough=0.7))
        put(ob, coll)
    x0, z0, x1, z1 = data["window"]
    g = kit.box("ground", 6000, 6000, 2, at=(0, 0, -1))
    g.location = rb((x0 + x1) / 2, data.get("ground", 0), (z0 + z1) / 2)
    g.data.materials.append(flat("grass", PALETTE.get("grass", (92, 130, 78)), rough=0.9))
    put(g, coll)
    return data


BOSS_ANCHORS = {"RustjawPrime": [(-26, 92, 0), (26, 92, 0)]}  # Config.Boss objectives (bosses.py ANCHORS)


def boss_fit(boss):
    """Each piece's role and centre (studs from the boss's feet, Roblox x, up, back) from src/config/BossArt.luau,
    which art/blender/bosses.py generates."""
    import re
    path = os.path.join(os.path.dirname(ASSETS), "src", "config", "BossArt.luau")
    text = open(path).read()
    start = text.index("\t%s = {" % boss)
    nxt = re.search(r"\n\t[A-Za-z]+ = \{", text[start + 4:])
    block = text[start:start + 4 + nxt.start()] if nxt else text[start:]
    out = {}
    for m in re.finditer(r'(\w+) = \{\s*role = "(\w+)",\s*size = \{[^}]*\},\s*offset = \{ ([-\d.]+), ([-\d.]+), ([-\d.]+) \}',
                         block):
        out[m.group(1)] = (m.group(2), (float(m.group(3)), float(m.group(4)), float(m.group(5))))
    return out


def boss_mat(boss):
    d = os.path.join(ASSETS, "export", "bosses")
    m = bpy.data.materials.new(boss)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]

    def tex(kind, data):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = _image(os.path.join(d, "%s_%s.png" % (boss, kind)), data)
        return t

    nt.links.new(tex("Color", False).outputs["Color"], p.inputs["Base Color"])
    nt.links.new(tex("Roughness", True).outputs["Color"], p.inputs["Roughness"])
    nt.links.new(tex("Metalness", True).outputs["Color"], p.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tex("Normal", True).outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    return m


def boss(name, at, yaw=0.0, scale=1.0, glow=(255, 136, 40), weak=(255, 196, 40), objective=(255, 70, 60)):
    """A world boss from the game's own meshes (art/export/Bosses.fbx; PLACEHOLDER LOOK in the game until the
    bosses' lore is decided), placed from its fit table: feet at `at`, turned yaw degrees (0 faces +y)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(ASSETS, "export", "Bosses.fbx"))
    src = {}
    for ob in set(bpy.data.objects) - before:
        if ob.type == "MESH" and ob.name.startswith(name + "_"):
            src[ob.name.split(".")[0][len(name) + 1:]] = ob
        else:
            bpy.data.objects.remove(ob, do_unlink=True)
    fit = boss_fit(name)
    hull = boss_mat(name)
    mats = {"hull": hull, "shed2": hull, "shed3": hull, "objective": hull, "glow": glow_mat("bglow", glow, 6.0),
            "weak": glow_mat("bweak", weak, 6.0), "objectiveGlow": glow_mat("bobj", objective, 8.0)}
    Y = Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Scale(scale, 4)
    coll = collection("Boss")
    for piece, ob in src.items():
        role, off = fit.get(piece, ("hull", (0, 0, 0)))
        anchors = [(0, 0, 0)]
        if role in ("objective", "objectiveGlow"):
            anchors = BOSS_ANCHORS.get(name, [(0, 0, 0)])
        for a in anchors:
            cp = ob.copy()
            cp.data = ob.data.copy()
            coll.objects.link(cp)
            cp.matrix_world = Y @ Matrix.Translation(rb(a[0] + off[0], a[1] + off[1], a[2] + off[2]))
            cp.data.materials.clear()
            cp.data.materials.append(mats[role])
        bpy.data.objects.remove(ob, do_unlink=True)
    return Y


# ------------------------------------------------------------------------------------------------ effects
def billboard(name, mat, at, size, cam, roll=0.0, coll=None):
    """A square card at `at` facing the camera."""
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=at)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (size, size, size)
    d = (cam.location - Vector(at)).normalized()
    q = d.to_track_quat("Z", "Y")
    ob.rotation_euler = (q.to_matrix().to_4x4() @ Matrix.Rotation(roll, 4, "Z")).to_euler()
    ob.data.materials.append(mat)
    ob.visible_shadow = False
    ob.visible_diffuse = False
    ob.visible_glossy = False
    ob.visible_transmission = False
    put(ob, coll or collection("Fx"))
    return ob


def lightning(start, end, rgb=(50, 150, 255), seed=1, jag=0.18, width=0.12, branches=3, strength=14.0, coll=None,
              depth=0):
    """A jagged emissive bolt (Volt) from start to end, with a few side forks."""
    rng = random.Random(seed)
    a, b = Vector(start), Vector(end)
    n = 9
    ln = (b - a).length
    d = (b - a).normalized()
    up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    u = d.cross(up).normalized()
    v = d.cross(u).normalized()
    pts = []
    for i in range(n + 1):
        t = i / n
        off = 0 if i in (0, n) else (rng.random() * 2 - 1) * jag * ln
        off2 = 0 if i in (0, n) else (rng.random() * 2 - 1) * jag * ln * 0.6
        pts.append(a.lerp(b, t) + u * off + v * off2)
    radii = [width * (1 - 0.6 * i / n) for i in range(n + 1)]
    core = kit.tube_along("bolt", pts, radii, segs=6)
    core.data.materials.append(glow_mat("boltcore", (225, 242, 255), strength * 0.9))
    halo = kit.tube_along("bolth", pts, [r * 2.6 for r in radii], segs=6)
    halo.data.materials.append(glow_mat("bolthalo", rgb, strength * 0.12, additive=True))
    out = [put(core, coll or collection("Fx")), put(halo, coll or collection("Fx"))]
    if depth < 1:
        for k in range(branches):
            i = rng.randint(2, n - 2)
            fork_end = pts[i] + (d * 0.4 + u * (rng.random() * 2 - 1) + v * (rng.random() - 0.5)).normalized() * ln * 0.3
            out += lightning(pts[i], fork_end, rgb, seed * 31 + k, jag, width * 0.6, 0, strength, coll, depth + 1)
    return out


def chunks(centre, spread, count, seed=1, size=(1.5, 5.0), mats=None, coll=None, direction=(0, 0, 0), stretch=1.0):
    """Wall and slab chunks flying out (BuildingFx's collapse chunks): bevelled boxes with kit fronts."""
    rng = random.Random(seed)
    mats = mats or [kit_mat("Office"), kit_mat("Stone"), flat("conc", PALETTE["concrete"], rough=0.85)]
    out = []
    c = Vector(centre)
    for i in range(count):
        s = size[0] + (size[1] - size[0]) * rng.random() ** 2
        ob = kit.box("chunk", s * (0.6 + rng.random()), s * (0.3 + rng.random() * 0.5), s * (0.5 + rng.random()))
        kit.bevel(ob, s * 0.06, 1)
        kit.apply_all(ob)
        dirv = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        dist = spread * rng.random() ** 0.7
        ob.location = c + dirv * dist + Vector(direction) * dist * stretch
        ob.rotation_euler = (rng.random() * 6.3, rng.random() * 6.3, rng.random() * 6.3)
        ob.data.materials.append(rng.choice(mats))
        out.append(put(ob, coll or collection("Fx")))
    return out


def smoke(centre, spread, count, cam, seed=1, size=(10, 24), rgb=(230, 224, 214), alpha=0.9, coll=None,
          up=0.5):
    """Dust: cards of the effects library's smoke flipbook (art/export/fx/smoke_4x4.png), lit, not emissive."""
    rng = random.Random(seed)
    out = []
    c = Vector(centre)
    mats = [card_mat("smoke%d" % k, "smoke_4x4.png", rgb, alpha=alpha, cell=(k % 4, k // 4, 4), emissive=False)
            for k in range(8)]
    for i in range(count):
        p = c + Vector((rng.gauss(0, 1), rng.gauss(0, 1), abs(rng.gauss(0, 1)) * up)) * spread
        s = size[0] + (size[1] - size[0]) * rng.random()
        out.append(billboard("smoke", rng.choice(mats), p, s, cam, roll=rng.random() * 6.3, coll=coll))
    return out


def sparks(centre, spread, count, cam, seed=1, rgb=(255, 200, 90), size=(0.6, 1.6), strength=8, coll=None):
    rng = random.Random(seed)
    m = card_mat("sparkc", "spark.png", rgb, strength=strength)
    out = []
    for i in range(count):
        p = Vector(centre) + Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))) * spread
        out.append(billboard("spark", m, p, size[0] + (size[1] - size[0]) * rng.random(), cam,
                             roll=rng.random() * 6.3, coll=coll))
    return out


def crystals(centre, spread, count, seed=1, size=(0.4, 1.4), rgb=(150, 225, 255), coll=None):
    """Frost: clear ice shards (long octahedra) with a cold inner glow."""
    rng = random.Random(seed)
    m = bpy.data.materials.new("ice")
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = lin3(rgb)
    p.inputs["Roughness"].default_value = 0.08
    p.inputs["Transmission Weight"].default_value = 0.75
    p.inputs["Emission Color"].default_value = lin3(rgb)
    p.inputs["Emission Strength"].default_value = 0.8
    out = []
    for i in range(count):
        s = size[0] + (size[1] - size[0]) * rng.random()
        ob = kit.sphere("ice", 0.5, segs=4, rings=2, scale=(s * 0.35, s * 0.35, s))
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        ob.location = Vector(centre) + d * spread * (0.4 + 0.6 * rng.random())
        ob.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        ob.data.materials.append(m)
        out.append(put(ob, coll or collection("Fx")))
    return out


def blade(M, part="RightHand", rgb=(90, 230, 255), length=4.2):
    """Blade: an energy sword in a hand (pointing along the forearm), a white core in a coloured glow."""
    x = 1.5 if part.startswith("Right") else -1.5
    hilt = kit.cyl("hilt", 0.16, 0.16, 0.8, at=(x, 0, 2.0), segs=10)
    hilt.data.materials.append(flat("hilt", (40, 42, 50), rough=0.3, metal=0.8))
    core = kit.box("blade", 0.12, 0.34, length, at=(x, 0, 2.15 - length / 2 - 0.4))
    kit.bevel(core, 0.05, 2)
    core.data.materials.append(glow_mat("bladecore", (235, 252, 255), 8.0))
    halo = kit.box("bladeh", 0.36, 0.62, length + 0.3, at=(x, 0, 2.15 - length / 2 - 0.4))
    kit.bevel(halo, 0.15, 3)
    halo.data.materials.append(glow_mat("bladehalo", rgb, 2.2, additive=True))
    out = []
    for ob in (hilt, core, halo):
        ob.matrix_world = M[part] @ ob.matrix_world
        out.append(put(ob, collection("Fx")))
    return out


def glow(at, size, cam, rgb, strength=3.0, tex="glow.png", coll=None, roll=0.0):
    return billboard("glow", card_mat("glow", tex, rgb, strength=strength), at, size, cam, roll=roll, coll=coll)


def aura(objs, rgb=(255, 200, 60), grow=0.16, strength=4.0, power=2.2):
    """The Awakening aura look: a rim-glow shell around each body piece (bright at the silhouette, clear facing
    the camera), plus whatever cards the caller adds."""
    m = bpy.data.materials.new("aura")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.35
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    nt.links.new(lw.outputs["Facing"], pw.inputs[0])
    pw.inputs[1].default_value = power
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = lin3(rgb)
    em.inputs["Strength"].default_value = strength
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(pw.outputs[0], mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    out = []
    for ob in objs:
        if ob.type != "MESH" or len(ob.data.vertices) < 8:
            continue
        cp = ob.copy()
        cp.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        cp.data.materials.clear()
        cp.data.materials.append(m)
        cp.modifiers.clear()
        disp = cp.modifiers.new("D", "DISPLACE")
        disp.strength = grow
        disp.mid_level = 0
        cp.visible_shadow = False
        cp.visible_diffuse = False
        cp.visible_glossy = False
        out.append(put(cp, collection("Fx")))
    return out


def fog(coll_name, rgb, start=150.0, half=600.0, strength=1.0):
    """Aerial haze on a collection's materials: the shader fades to an emitted sky colour with distance from
    the camera (cheaper and cleaner than a volume). Each material is changed once."""
    done = set()
    for ob in collection(coll_name).all_objects:
        if ob.type != "MESH":
            continue
        for m in ob.data.materials:
            if not m or m.name in done or not m.use_nodes:
                continue
            done.add(m.name)
            nt = m.node_tree
            out = nt.nodes["Material Output"]
            if not out.inputs["Surface"].links:
                continue
            src = out.inputs["Surface"].links[0].from_socket
            cd = nt.nodes.new("ShaderNodeCameraData")
            sub = nt.nodes.new("ShaderNodeMath")
            sub.operation = "SUBTRACT"
            nt.links.new(cd.outputs["View Distance"], sub.inputs[0])
            sub.inputs[1].default_value = start
            mx = nt.nodes.new("ShaderNodeMath")
            mx.operation = "MAXIMUM"
            nt.links.new(sub.outputs[0], mx.inputs[0])
            mx.inputs[1].default_value = 0
            # 1 - 0.5 ^ (d / half)
            pw = nt.nodes.new("ShaderNodeMath")
            pw.operation = "DIVIDE"
            nt.links.new(mx.outputs[0], pw.inputs[0])
            pw.inputs[1].default_value = half
            ex = nt.nodes.new("ShaderNodeMath")
            ex.operation = "POWER"
            ex.inputs[0].default_value = 0.5
            nt.links.new(pw.outputs[0], ex.inputs[1])
            inv = nt.nodes.new("ShaderNodeMath")
            inv.operation = "SUBTRACT"
            inv.inputs[0].default_value = 1.0
            nt.links.new(ex.outputs[0], inv.inputs[1])
            em = nt.nodes.new("ShaderNodeEmission")
            em.inputs["Color"].default_value = lin3(rgb)
            em.inputs["Strength"].default_value = strength
            mix = nt.nodes.new("ShaderNodeMixShader")
            nt.links.new(inv.outputs[0], mix.inputs["Fac"])
            nt.links.new(src, mix.inputs[1])
            nt.links.new(em.outputs[0], mix.inputs[2])
            nt.links.new(mix.outputs[0], out.inputs["Surface"])


# ------------------------------------------------------------------------------------------------ world and render
def sky(top=(40, 110, 220), horizon=(150, 205, 255), bottom=None, ambient=(150, 180, 220), ambient_strength=0.9,
        mid=None):
    """A clean poster sky: a gradient for the camera, a flat ambient colour for lighting."""
    s = bpy.context.scene
    world = bpy.data.worlds.new("StoreSky")
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes["Background"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    bottom = bottom or horizon
    els[0].position = 0.42
    els[0].color = lin3(bottom)
    els[1].position = 0.95
    els[1].color = lin3(top)
    h = els.new(0.5)
    h.color = lin3(horizon)
    if mid:
        e = els.new(0.62)
        e.color = lin3(mid)
    # Generated z runs -1..1 for the view direction; map to 0..1
    mp = nt.nodes.new("ShaderNodeMapRange")
    mp.inputs["From Min"].default_value = -1
    mp.inputs["From Max"].default_value = 1
    nt.links.new(sep.outputs["Z"], mp.inputs["Value"])
    nt.links.new(mp.outputs["Result"], ramp.inputs["Fac"])
    lp = nt.nodes.new("ShaderNodeLightPath")
    amb = nt.nodes.new("ShaderNodeRGB")
    amb.outputs[0].default_value = lin3(ambient)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs["Factor"])
    nt.links.new(amb.outputs[0], mix.inputs["A"])
    nt.links.new(ramp.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = ambient_strength
    s.world = world
    return world


def sun(rot, energy=4.0, rgb=(255, 244, 226), angle=2.0):
    L = bpy.data.lights.new("Sun", "SUN")
    L.energy = energy
    L.angle = math.radians(angle)
    L.color = tuple(lin(c) for c in rgb)
    ob = bpy.data.objects.new("Sun", L)
    ob.rotation_euler = [math.radians(a) for a in rot]
    bpy.context.scene.collection.objects.link(ob)
    return ob


def lamp(at, energy, rgb=(255, 255, 255), size=2.0, kind="POINT"):
    L = bpy.data.lights.new("Lamp", kind)
    L.energy = energy
    L.color = tuple(lin(c) for c in rgb)
    L.shadow_soft_size = size
    ob = bpy.data.objects.new("Lamp", L)
    ob.location = at
    bpy.context.scene.collection.objects.link(ob)
    return ob


def area(at, target, energy, rgb=(255, 255, 255), size=6.0):
    L = bpy.data.lights.new("Area", "AREA")
    L.energy = energy
    L.size = size
    L.color = tuple(lin(c) for c in rgb)
    ob = bpy.data.objects.new("Area", L)
    ob.location = at
    d = Vector(target) - Vector(at)
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(ob)
    return ob


def outlines(coll_names, thickness=2.0, rgb=(14, 14, 22)):
    """The comic look's bold outline: Freestyle lines on the chosen collections only (silhouettes, borders and
    creases), so the city stays clean."""
    s = bpy.context.scene
    s.render.use_freestyle = True
    s.render.line_thickness_mode = "ABSOLUTE"
    s.render.line_thickness = thickness
    vl = bpy.context.view_layer
    fs = vl.freestyle_settings
    for ls in list(fs.linesets):
        fs.linesets.remove(ls)
    for name in coll_names:
        ls = fs.linesets.new("Lines_" + name)
        ls.select_by_collection = True
        ls.collection = collection(name)
        ls.select_by_visibility = True
        ls.select_silhouette = True
        ls.select_border = True
        ls.select_crease = True
        ls.select_contour = True
        ls.linestyle.color = tuple(lin(c) for c in rgb)
        ls.linestyle.thickness = thickness
    fs.crease_angle = math.radians(120)


def settings(res, samples=96, exposure=0.0, look="Punchy", view="AgX"):
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.samples = 24 if DRAFT else samples
    s.cycles.use_denoising = True
    s.cycles.max_bounces = 6
    s.cycles.transparent_max_bounces = 64
    s.cycles.caustics_reflective = False
    s.cycles.caustics_refractive = False
    s.cycles.blur_glossy = 1.0
    scale = 0.5 if DRAFT else 1.0
    s.render.resolution_x, s.render.resolution_y = int(res[0] * scale), int(res[1] * scale)
    s.render.film_transparent = False
    s.view_settings.view_transform = view
    for name in ((view + " - " + look, look) if view == "AgX" else (look,)):
        try:
            s.view_settings.look = name
            break
        except Exception:
            pass
    s.view_settings.exposure = exposure
    s.render.image_settings.file_format = "PNG"
    s.render.image_settings.color_mode = "RGB"


def camera(loc, target, lens=50, roll=0.0, shift=(0, 0)):
    cam = kit.camera(loc, target, lens)
    if roll:
        cam.rotation_euler = (cam.matrix_world.to_3x3() @ Matrix.Rotation(math.radians(roll), 3, "Z")).to_euler()
    cam.data.shift_x, cam.data.shift_y = shift
    cam.data.clip_end = 20000
    cam.data.clip_start = 0.1
    return cam


def render(name):
    os.makedirs(RAW, exist_ok=True)
    path = os.path.join(RAW, name + (".draft" if DRAFT else "") + ".png")
    kit.render(path)
    print("rendered", path)
    return path
