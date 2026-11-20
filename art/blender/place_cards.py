# place_cards.py: the places' name card pictures (list-combat 2026-11-20, Everything Left 403: "Places on the news
# cards have no picture (text on the plate), for example the Crater"). Stages the game's own meshes for a place into
# one comic shot on a clear background, into build/news/raw/place_<id>.png; art/news/post.py inks it onto the cards'
# sheet like the boss portraits (Config.NewsArt.cards.places, Ui.CinemaHud's card picture).
#   crater  The Crater (Config.Cinema.nameCard.places.crater): Crane Industries' broken lab wall with its C, a cracked
#           containment tank with the Spark still glowing in it, and the old heroes' relics in front: the torn red
#           cape on its rebar, the cracked blue shield half sunk in the dirt, the dented gold helmet (art/export/
#           Crater.fbx with its baked textures). No person is drawn.
# Run: $HOME/tools/bpyenv/bin/python art/blender/place_cards.py [--fast]
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

kit.reset()
ROOT = os.path.dirname(kit.ROOT)
OUT = os.path.join(ROOT, "build", "news", "raw")
os.makedirs(OUT, exist_ok=True)
FAST = "--fast" in sys.argv


def load(fbx):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=fbx)
    got = {}
    for o in set(bpy.data.objects) - before:
        if o.type == "MESH":
            got[o.name.split(".")[0]] = o
        else:
            bpy.data.objects.remove(o, do_unlink=True)
    return got


def clear_parent(o):
    m = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = m


def place(o, at, yaw=0.0, tilt=(0.0, 0.0)):
    clear_parent(o)
    o.rotation_mode = "XYZ"
    o.rotation_euler = (math.radians(tilt[0]), math.radians(tilt[1]), math.radians(yaw))
    o.location = at
    o.hide_render = False


def crater():
    obs = load(os.path.join(kit.ROOT, "export", "Crater.fbx"))
    for o in obs.values():
        o.hide_render = True
    glass = kit.material("glass", (170, 220, 255))
    try:
        b = glass.node_tree.nodes.get("Principled BSDF")
        b.inputs["Alpha"].default_value = 0.25
        glass.blend_method = "BLEND"
    except Exception:
        pass
    glow = kit.material("glow", (90, 240, 230), emit=1.5)
    visor = kit.material("visor", (30, 40, 60))
    # the scene: Blender x across, y away from the camera, z up (studs)
    place(obs["CraterWall3Body"], (0, 12, 8), yaw=0)
    place(obs["CraterTank1Body"], (-13, 5, 6))
    for n, mat in (("CraterTank1Glass", glass), ("CraterTank1Glow", glow)):
        place(obs[n], (-13, 5, 6))
        obs[n].data.materials.clear()
        obs[n].data.materials.append(mat)
    place(obs["CraterCapeBody"], (11, 4, 6), yaw=-20)
    place(obs["CraterShieldBody"], (1, -1, 3.2), yaw=8, tilt=(-28, 0))
    place(obs["CraterHelmetBody"], (-5.5, -5, 2.4), yaw=30, tilt=(0, -12))
    place(obs["CraterHelmetVisor"], (-5.5, -5, 2.4), yaw=30, tilt=(0, -12))
    obs["CraterHelmetVisor"].data.materials.clear()
    obs["CraterHelmetVisor"].data.materials.append(visor)
    place(obs["CraterBitRubbleBody"], (6, -3, 0.8), yaw=40)
    place(obs["CraterBitPlatesBody"], (-10, -4, 0.3), yaw=-20)
    # the dirt floor, cut to a disc so the card's backdrop shows round it
    bpy.ops.mesh.primitive_cylinder_add(radius=19, depth=1, location=(0, 3, -0.5), vertices=48)
    floor = bpy.context.active_object
    floor.data.materials.append(kit.material("dirt", (120, 104, 92)))
    shot("crater", cam=(-11, -30, 7), to=(-2, 3, 5.5), lens=34)


def shot(pid, cam, to, lens):
    s = bpy.context.scene
    kit.studio(res=(900, 900), samples=12 if FAST else 48)
    s.render.film_transparent = True
    kit.camera(cam, to, lens=lens)
    path = os.path.join(OUT, "place_%s.png" % pid)
    kit.render(path)
    print("place card:", path)


crater()
