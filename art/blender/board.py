# board.py: the plaza's weekly board (WP2, BoardService.buildProp) as a Blender look (gap-props2, 2026-11-19). The
# board is a navy screen part (the SurfaceGui's adornee, kept and drawn as it is: the rows stay exactly as readable)
# with a frame, a crest and two legs as plain parts; once ReplicatedStorage.Art.Board holds every mesh here the
# server hides those parts (kept, so the collision is as before) and draws this look round the screen: a gold
# bevelled bezel that never covers the screen's face, a navy cabinet behind it with rivets and vents, a crest with
# a glowing star and two bulbs, two posts with gold collars, a brace and foot plates. City kit style: chunky
# bevelled shapes, comic gold and navy, one baked texture set (hbake.py); the neon star and bulbs stay flat glow.
# The board's numbers come from Config.Boards.prop (art/export/pockets/layout.json: `lune run art/pockets/layout.luau`).
# Frame: x right, y up, z back from the screen's centre (its face at z = -0.3, as CFrame.lookAt faces it).
# Output: art/export/Board.fbx (textures embedded), art/export/board/PlazaBoard_*.png, src/config/BoardArt.luau
# (the look's meshes, the screen size it was built for and `clear`: how far any mesh reaches in front of the
# screen's face inside its rectangle, never above 0); with --preview art/preview/board.png.
# Run: lune run art/pockets/layout.luau && $HOME/tools/bpyenv/bin/python art/blender/board.py [--preview] [--fast]
import json
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402,F401

kit.reset()

import hbake  # noqa: E402
import ruinkit as rk  # noqa: E402
from studs import mesh, LOOKS, INFO, C, S, TOR, star, shift, rb  # noqa: E402
from vkit import rbox  # noqa: E402

FAST = "--fast" in sys.argv
LAY = json.load(open(os.path.join(kit.ROOT, "export", "pockets", "layout.json")))
BP = LAY["board"]
W, H = BP["size"]
UP = BP["height"]
OUT = os.path.join(kit.ROOT, "export", "board")
os.makedirs(OUT, exist_ok=True)
LOOK = "PlazaBoard"
FACE = -0.3  # the screen part's face (0.6 thick about its centre)

GOLD = (236, 186, 56)
DGOLD = (176, 128, 36)
NAVY = (30, 40, 92)
DNAVY = (20, 26, 60)
IRON = (48, 50, 62)
STEEL = (140, 148, 160)
STAR = (255, 214, 80)
BULB = (255, 244, 200)


def P(ob, rgb, mat="SmoothPlastic", pat=None):
    return hbake.paint(ob, rgb, mat, pat)


def box(sx, sy, sz, x, y, z, rgb, mat="SmoothPlastic", bev=0.1, pat=None):
    return P(rbox(sx, sy, sz, x, y, z, bev=bev), rgb, mat, pat)


parts = []
B = 1.3  # the bezel's width round the screen
OW, OH = W + 2 * B, H + 2 * B
# the bezel: four bars whose inner faces sit exactly on the screen's edge, from just in front of its face to the back
for s in (-1, 1):
    parts.append(box(OW, B, 1.4, 0, s * (H / 2 + B / 2), 0.15, GOLD, "Foil", 0.18))
    parts.append(box(B, H, 1.4, s * (W / 2 + B / 2), 0, 0.15, GOLD, "Foil", 0.18))
# an inner navy lip just outside the screen and corner bolts on the bezel's front
for s in (-1, 1):
    parts.append(box(OW - 0.8, 0.18, 0.1, 0, s * (H / 2 + 0.12), -0.6, DGOLD, "Metal", 0.03))
for cx in (-1, 1):
    for cy in (-1, 1):
        parts.append(P(C(0.28, 0.14, cx * (W / 2 + B / 2), cy * (H / 2 + B / 2), -0.62, segs=8, axis="z"), DGOLD, "Metal"))
# the cabinet behind the screen: navy, a raised back panel, rivets and vent slits
parts.append(box(OW - 0.4, OH - 0.4, 1.3, 0, 0, 1.4, NAVY, "Metal", 0.2, pat="plates"))
parts.append(box(OW - 3.0, OH - 3.0, 0.3, 0, 0, 2.15, DNAVY, "Metal", 0.1))
for i in range(6):
    parts.append(box(3.0, 0.18, 0.08, -7.5 + i * 3.0, -H / 2 + 1.0, 2.33, IRON, "Metal", 0.02))
# the crest over the top: a gold shield plate on a navy banner, the star's mount and two bulb sockets
cy = H / 2 + B + 1.5
parts.append(box(W * 0.62, 1.4, 0.9, 0, H / 2 + B + 0.55, 0.4, NAVY, "Metal", 0.2))
shield = rk.vkit.rings_mesh([
    [(x, y, -0.25) for (x, y) in ((-2.4, cy + 1.6), (2.4, cy + 1.6), (2.4, cy - 0.2), (0, cy - 1.7), (-2.4, cy - 0.2))],
    [(x, y, 0.55) for (x, y) in ((-2.4, cy + 1.6), (2.4, cy + 1.6), (2.4, cy - 0.2), (0, cy - 1.7), (-2.4, cy - 0.2))],
])
parts.append(P(shield, GOLD, "Foil"))
for s in (-1, 1):
    parts.append(P(C(0.55, 0.5, s * (W * 0.31 - 0.4), H / 2 + B + 0.55, -0.15, segs=10, axis="z"), DGOLD, "Metal"))
    # little laurel scallops beside the shield
    for k in range(3):
        parts.append(P(S(0.42, s * (3.0 + k * 0.85), cy - 0.3 + k * 0.45, 0.1, sc=(1.0, 0.6, 0.5), segs=8, rings=5), DGOLD, "Foil"))
# the legs: posts with gold collars, a brace between them and foot plates on the plaza
foot = -H / 2 - UP
lx = W / 2 - 1.5
for s in (-1, 1):
    parts.append(box(1.3, UP + 0.4, 1.3, s * lx, foot + (UP + 0.4) / 2, 0.8, IRON, "Metal", 0.15))
    parts.append(box(1.7, 0.5, 1.7, s * lx, -H / 2 - 0.9, 0.8, GOLD, "Metal", 0.1))
    parts.append(box(1.7, 0.4, 1.7, s * lx, foot + 1.0, 0.8, GOLD, "Metal", 0.1))
    parts.append(box(2.8, 0.4, 2.8, s * lx, foot + 0.2, 0.8, IRON, "Metal", 0.12))
    for cx in (-1, 1):
        for cz in (-1, 1):
            parts.append(P(C(0.16, 0.12, s * lx + cx * 1.05, foot + 0.46, 0.8 + cz * 1.05, segs=6), STEEL, "Metal"))
parts.append(box(2 * lx - 1.3, 0.5, 0.5, 0, foot + 2.2, 0.8, IRON, "Metal", 0.1))
mesh(LOOK, LOOK + "Body", parts, (255, 255, 255), "SmoothPlastic")

glow = [shift(star(1.25, 0.55, 0.3, 0, cy + 0.15, -0.35, points=5), (0, 0, 0))]
for s in (-1, 1):
    glow.append(S(0.38, s * (W * 0.31 - 0.4), H / 2 + B + 0.55, -0.45, segs=10, rings=6))
mesh(LOOK, LOOK + "Glow", glow, STAR, "Neon")

MAPPED = rk.bake_all([LOOK], OUT, lambda look, objs: 1024, fast=FAST)

# how far any mesh reaches in front of the screen's face inside its rectangle (must be <= 0: the rows stay clear)
clear = -1e9
for ob in LOOKS[LOOK].values():
    for v in ob.data.vertices:
        p = ob.matrix_world @ v.co
        x, y, z = p.x, p.z, -p.y
        if abs(x) < W / 2 - 0.01 and abs(y) < H / 2 - 0.01:
            clear = max(clear, FACE - z)
lo = [1e9] * 3
hi = [-1e9] * 3
for ob in LOOKS[LOOK].values():
    a, b = rk.bounds(ob)
    for k, (u, w) in enumerate(((a.x, b.x), (a.z, b.z), (-b.y, -a.y))):
        lo[k] = min(lo[k], u)
        hi[k] = max(hi[k], w)

rows = []
total = 0
for name in sorted(LOOKS[LOOK]):
    ob = LOOKS[LOOK][name]
    a, b = rk.bounds(ob)
    c = (a + b) / 2
    size = b - a
    t = kit.tris(ob)
    total += t
    rgb, mat, alpha = INFO[name]
    extra = ", maps = true" if name in MAPPED else ""
    rows.append("\t\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, mat = \"%s\"%s, tris = %d },"
                % (name, size.x, size.z, size.y, c.x, c.z, -c.y, rgb[0], rgb[1], rgb[2], mat, extra, t))
text = "\n".join([
    "-- GENERATED by art/blender/board.py: do not edit by hand.",
    "-- The plaza weekly board in Blender meshes (ReplicatedStorage.Art.Board; BoardService.buildProp, Shared.BoardArtKit):",
    "-- the look's meshes (size and centre from the screen's centre: x right, y up, z back, the screen's face at z = -0.3),",
    "-- the screen size it was built for (Config.Boards.prop.size), its bounds (lo, hi) and clear: how far any mesh",
    "-- reaches in front of the screen's face inside the screen's rectangle (never above 0, so the rows stay readable).",
    "-- %d meshes, %d triangles." % (len(rows), total),
    "return {",
    "\t%s = {" % LOOK,
    "\t\tscreen = { %g, %g }," % (W, H),
    "\t\tlo = { %.3f, %.3f, %.3f }," % tuple(lo),
    "\t\thi = { %.3f, %.3f, %.3f }," % tuple(hi),
    "\t\tclear = %.3f," % clear,
    "\t\tmeshes = {",
] + rows + ["\t\t},", "\t},", "}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "BoardArt.luau"))
with open(FIT, "w") as fh:
    fh.write(text)
st = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(st):
    subprocess.run([st, "--config-path", os.path.join(kit.ROOT, "..", "stylua.toml"), FIT], check=False)
print("board: %d meshes, %d tris, clear %.3f" % (len(rows), total, clear))
rk.export_fbx(os.path.join(kit.ROOT, "export", "Board.fbx"), [LOOK], MAPPED)

if "--preview" in sys.argv:
    import vpreview as vp  # noqa: E402
    PREV = os.path.join(kit.ROOT, "preview")
    vp._scene(FAST, (640, 400) if FAST else (1400, 800))
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))  # light the board's front (Roblox -z)
    fill.data.energy = 2.6
    fill.rotation_euler = (math.radians(-50), math.radians(-12), math.radians(-25))
    bpy.context.scene.collection.objects.link(fill)
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.hide_render = True
    # (PIL is the system python's: the stand-in image is drawn there)
    tex = os.path.join(OUT, "_screen_preview.png")
    draw = (
        "import sys\nfrom PIL import Image, ImageDraw, ImageFont\n"
        "W,H,ppi=float(sys.argv[2]),float(sys.argv[3]),24\n"
        "img=Image.new('RGB',(int(W*ppi),int(H*ppi)),(16,22,44)); d=ImageDraw.Draw(img)\n"
        "try:\n font=ImageFont.truetype('DejaVuSans-Bold.ttf',20); small=ImageFont.truetype('DejaVuSans-Bold.ttf',15)\n"
        "except OSError:\n font=small=ImageFont.load_default()\n"
        "d.text((10,4),\"THIS WEEK'S TOP 10\",fill=(250,200,60),font=font)\n"
        "d.text((img.width-200,6),'ENDS IN 3D 4H',fill=(220,230,255),font=small)\n"
        "for b in range(3):\n"
        " x0=10+b*(img.width-20)//3\n"
        " d.text((x0,36),('HEROIC','ROBOTS','RESCUES')[b],fill=(120,200,255),font=small)\n"
        " for r in range(10): d.text((x0,60+r*22),'%d  Hero%02d   %d'%(r+1,r+7,980-r*61),fill=(240,240,240),font=small)\n"
        "img.save(sys.argv[1])\n"
    )
    subprocess.run(["python3", "-c", draw, tex, str(W), str(H)], check=True)
    scr = kit.box("screen", W, 0.6, H, at=rb(0, 0, 0))
    m = bpy.data.materials.new("scr")
    m.use_nodes = True
    nt = m.node_tree
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(tex)
    pr = nt.nodes["Principled BSDF"]
    nt.links.new(t.outputs["Color"], pr.inputs["Base Color"])
    nt.links.new(t.outputs["Color"], pr.inputs["Emission Color"])
    pr.inputs["Emission Strength"].default_value = 0.6
    scr.data.materials.append(m)
    # project the image on the front face (Blender -y is Roblox's -z: the face toward the plaza)
    me = scr.data
    uv = me.uv_layers.new()
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = (0.5 - co.x / W, co.z / H + 0.5)
    vp._keep(scr)
    vp._ground(200, (150, 146, 138), at=(0, -H / 2 - UP, 0))
    for name, ob in LOOKS[LOOK].items():
        cp = ob.copy()
        cp.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(cp)
        cp.data.materials.clear()
        rgb, mat, alpha = INFO[name]
        cp.data.materials.append(MAPPED[name] if name in MAPPED else vp._mat_flat(tuple(rgb), mat, alpha))
        vp._keep(cp)
    vp._hero(-W / 2 - 4, -H / 2 - UP, -6)
    shots = []
    for (frm, to, n) in (((0, 1, -40), (0, 0, 0), "a"), ((-26, 6, -26), (0, 0, 0), "b"), ((18, 2, 22), (0, -1, 0), "c")):
        vp._camera(frm, to, lens=32)
        out = os.path.join(PREV, "board_%s.png" % n)
        kit.render(out)
        shots.append(out)
    code = (
        "import sys\nfrom PIL import Image\n"
        "ims=[Image.open(p).convert('RGB') for p in sys.argv[2:]]\n"
        "w,h=ims[0].size\n"
        "sheet=Image.new('RGB',(w*len(ims),h),(24,26,32))\n"
        "for i,im in enumerate(ims): sheet.paste(im,(i*w,0))\n"
        "sheet.save(sys.argv[1])\n"
    )
    subprocess.run(["python3", "-c", code, os.path.join(PREV, "board.png")] + shots, check=True)
    for p_ in shots + [tex]:
        os.remove(p_)
    print("preview:", os.path.join(PREV, "board.png"))
