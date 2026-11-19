# hideout.py: the HQ room shells (2026-11-19, the hideout art pass), built by hq.py (`import hideout;
# hideout.build(layout)`) beside its stations, props and dressing, and exported on their own as
# art/export/Hideout.fbx + src/config/HideoutArt.luau (imported as ReplicatedStorage.Art.Hideout). Every look is a
# module the game repeats over today's plain parts (Shared.HideoutKit says where; the parts stay, hidden, so every
# collision, prompt and light is as before), each with one baked texture set (art/blender/hbake.py):
# * the Vigil's Safehouse under the plaza (Shared.HqRules.hideout): a board-formed concrete wall bay (12 wide), a
#   concrete panel (the stair shaft), the pillars and pilasters (hazard-wrapped feet, steel corner guards, a
#   conduit), a beam bay, a floor slab tile (saw cuts, stains, a drain), a ceiling tile with downstand ribs, the
#   wall kit's run (12 long: a rusty pipe and a steel pipe with flanges and clamps, a ladder cable tray with four
#   cables and hanger rods, the hazard stripe), the caged work lamp (its glowing face stays the game's part), the
#   service stair (12 concrete steps, hazard nosings, a handrail and posts), the city map wall's steel frame and
#   light bar, the monitors' housings on wall arms (their screens stay the game's parts)
# * the plaza stairwell head (HqService): a concrete kiosk with a roof slab and vent, a riveted steel service door
#   with a push bar and kick plate in a steel frame, a blank enamel plate, the lamp's hood and cage, hazard
#   stripes, a conduit and side grilles (the door, its prompt and the lamp stay the game's parts)
# * the Dread Syndicate's Foundry (HqClient's box room): a riveted iron wall bay with half I-beams at its edges and
#   ledges round the red light band (the band stays the game's glowing part), a diamond plate floor tile and a rug
#   tile in the side's colour (tinted: the part's Color shows through the weave)
# Feet: a wall-like module's foot is the middle of its room face at floor level, its front (-z) facing the room; a
# tile's is the middle of its underside; a run's is on the wall face at floor level; the lamp's, the map frame's
# and the monitor's are the middle of the part they stand in for; the stair's is its first step's foot middle.
import math

from studs import mesh, B, C, T, TOR  # noqa: F401
import hbake

LOOKS = []  # the look names this module builds (hq.py exports them into Hideout.fbx)

CONC = (158, 156, 150)  # palette "concrete" (pillars, steps)
WALLC = (88, 92, 98)  # palette "tunnel" (walls, ceiling)
FLOOR = (92, 100, 112)  # palette "slate"
PIPE = (140, 80, 50)  # palette "rust"
STEELC = (120, 130, 140)  # palette "steel"
STRIPE = (210, 170, 60)  # palette "containerC"
BEZEL = (74, 76, 82)  # palette "roof"
DARK = (52, 56, 64)
LAMPY = (214, 168, 44)
SIRON = (74, 66, 82)
SBLACK = (36, 32, 42)
WHITE = (232, 232, 226)
RED = (200, 50, 50)


def P(ob, rgb, mat="Concrete", pat=None, tint=False):
    return hbake.paint(ob, rgb, mat, pat, tint)


def look(name, body, extra=()):
    """One look: its textured Body mesh from painted parts, and any glowing extras (name suffix, parts, rgb)."""
    LOOKS.append(name)
    mesh(name, name + "Body", body, body_rgb(body), "SmoothPlastic")
    for (suffix, parts, rgb) in extra:
        mesh(name, name + suffix, parts, rgb, "Neon")


def body_rgb(parts):
    m = parts[0].data.materials[0]
    return tuple(m["rgb"])


# ================================================================ the Safehouse
def wall():
    look("HideWall", [P(B(12, 30, 2, 0, 15, 1, bev=0.08), WALLC, pat="formwork"),
                      P(B(12, 0.8, 0.5, 0, 29.4, -0.25, bev=0.06), (98, 102, 108))])


def panel():
    look("HidePanel", [P(B(12, 12, 1, 0, 6, 0.5, bev=0.06), WALLC, pat="formwork")])


def pillar():
    parts = [P(B(4, 30, 4, 0, 15, 0, bev=0.25), CONC, pat="formwork"),
             P(B(4.8, 1.2, 4.8, 0, 29.4, 0, bev=0.2), CONC),
             P(B(4.3, 1.6, 4.3, 0, 0.8, 0, bev=0.06), STRIPE, pat="hazard")]
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(P(B(0.8, 3, 0.12, sx * 1.75, 3.1, sz * 2.08), STEELC, "Metal"))
            parts.append(P(B(0.12, 3, 0.8, sx * 2.08, 3.1, sz * 1.75), STEELC, "Metal"))
    parts.append(P(C(0.15, 26, 1.2, 16.6, -2.18, segs=8), DARK, "Metal"))
    for y in (6, 16, 26):
        parts.append(P(B(0.5, 0.25, 0.25, 1.2, y, -2.1), STEELC, "Metal"))
    look("HidePillar", parts)


def pilaster():
    look("HidePilaster", [P(B(4, 30, 3, 0, 15, 0, bev=0.2), CONC, pat="formwork"),
                          P(B(4.6, 1.0, 3.3, 0, 29.5, -0.15, bev=0.15), CONC),
                          P(B(4.3, 1.6, 3.0, 0, 0.8, -0.15, bev=0.05), STRIPE, pat="hazard")])


def beam():
    parts = [P(B(12, 2, 3, 0, 1, 0, bev=0.15), CONC, pat="formwork")]
    for x in (-5.85, 5.85):
        parts.append(P(B(0.3, 2.2, 3.2, x, 1, 0), DARK, "Metal"))
        for y in (0.5, 1.5):
            for z in (-1.0, 1.0):
                parts.append(P(C(0.1, 0.12, x, y, z * 1.62 / 1.0, segs=6, axis="z"), STEELC, "Metal"))
    look("HideBeam", parts)


def floor():
    look("HideFloor", [P(B(24, 0.2, 24, 0, 0.1, 0), FLOOR, pat="slab"), P(B(1.4, 0.04, 1.4, 6, 0.2, 6), DARK, pat="grate")])


def ceiling():
    parts = [P(B(24, 1, 24, 0, 0.5, 0), WALLC, pat="formwork")]
    for s in (-1, 1):
        parts.append(P(B(24, 0.6, 1.0, 0, -0.3, s * 11.5), (96, 100, 106)))
        parts.append(P(B(1.0, 0.6, 22, s * 11.5, -0.3, 0), (96, 100, 106)))
    look("HideCeiling", parts)


def run():
    parts = [P(C(0.7, 12, 0, 26.5, -1.2, segs=14, axis="x"), PIPE, pat="rust"),
             P(B(0.4, 0.4, 0.6, 0, 26.5, -0.3), STEELC, "Metal"),
             P(TOR(0.78, 0.08, 0, 26.5, -1.2, axis="x", segs=14, csegs=4), STEELC, "Metal"),
             P(C(0.45, 12, 0, 24.5, -1.1, segs=12, axis="x"), STEELC, "Metal"),
             P(B(0.3, 0.3, 0.6, 0, 24.5, -0.3), DARK, "Metal"),
             P(TOR(0.52, 0.07, 0, 24.5, -1.1, axis="x", segs=12, csegs=4), DARK, "Metal")]
    for x in (-5.85, 5.85):
        parts.append(P(C(0.9, 0.3, x, 26.5, -1.2, segs=14, axis="x"), PIPE, pat="rust"))
        parts.append(P(C(0.6, 0.25, x, 24.5, -1.1, segs=12, axis="x"), STEELC, "Metal"))
    # the ladder tray (its two parts: the 2.4 wide tray and the lip), its rungs, cables, hanger rods and struts
    parts.append(P(B(12, 0.6, 0.12, 0, 22.2, -1.25), STEELC, "DiamondPlate"))
    parts.append(P(B(12, 0.8, 0.15, 0, 22.4, -3.6), STEELC, "DiamondPlate"))
    for k in range(12):
        parts.append(P(B(0.2, 0.15, 2.3, -5.5 + k, 21.95, -2.4), STEELC, "Metal"))
    for (z, r, rgb) in ((-1.7, 0.18, (196, 44, 44)), (-2.15, 0.14, (44, 92, 188)), (-2.6, 0.2, (34, 34, 38)), (-3.05, 0.15, (226, 186, 44))):
        parts.append(P(T([(-6, 22.2, z), (-2, 22.22, z + 0.05), (2, 22.2, z - 0.05), (6, 22.2, z)], r, segs=6), rgb, pat="rubber"))
    for x in (-5.5, 5.5):
        parts.append(P(C(0.06, 8.4, x, 26.0, -3.85, segs=6), DARK, "Metal"))
        parts.append(P(B(0.25, 0.25, 2.9, x, 21.75, -2.45), DARK, "Metal"))
    parts.append(P(B(12, 0.6, 0.3, 0, 1.2, -0.2), STRIPE, pat="hazard"))
    look("HideRun", parts)


def lamp():
    parts = [P(B(2.4, 1.4, 1.6, 0, 0, 0, bev=0.2), LAMPY, "Metal"), P(C(0.12, 3, 0, 2.2, 0.4, segs=8), DARK, "Metal")]
    for x in (-0.9, -0.3, 0.3, 0.9):
        parts.append(P(T([(x, 0.4, -0.8), (x, 0.3, -1.15), (x, -0.75, -1.15), (x, -0.85, -0.8)], 0.05, segs=4), (40, 42, 48), "Metal"))
    for y in (-0.7, -0.15):
        parts.append(P(T([(-1.05, y, -1.15), (1.05, y, -1.15)], 0.05, segs=4), (40, 42, 48), "Metal"))
    look("HideLamp", parts)


def stair(rise=2.5, run_=3.0, steps=12, depth=8.0):
    parts = []
    for i in range(1, steps + 1):
        parts.append(P(B(run_, i * rise, depth, (i - 0.5) * run_, i * rise / 2, 0), CONC, pat="formwork"))
        parts.append(P(B(0.5, 0.15, depth, (i - 1) * run_ + 0.25, i * rise + 0.05, 0), STRIPE, pat="hazard"))
    top = steps * rise
    z = depth / 2 + 0.4
    parts.append(P(T([(0, 3.4, z), (steps * run_, top + 3.4, z)], 0.16, segs=8), STEELC, "Metal"))
    parts.append(P(T([(0, 1.8, z), (steps * run_, top + 1.8, z)], 0.1, segs=6), STEELC, "Metal"))
    for i in (1, 3, 6, 9, 12):
        x = (i - 0.5) * run_
        y0 = i * rise
        parts.append(P(C(0.15, 3.4, x, y0 + 1.7, z, segs=8), STEELC, "Metal"))
        parts.append(P(B(0.5, 0.15, 0.5, x, y0 + 0.08, z), DARK, "Metal"))
    look("HideStair", parts)


def map_frame():
    parts = [P(B(35.6, 13.6, 0.2, 0, 0, 0.1), DARK, "Metal")]
    for s in (-1, 1):
        parts.append(P(B(35.6, 0.8, 0.8, 0, s * 6.4, -0.2, bev=0.08), STEELC, "Metal"))
        parts.append(P(B(0.8, 12, 0.8, s * 17.4, 0, -0.2, bev=0.08), STEELC, "Metal"))
        parts.append(P(B(1.6, 1.6, 0.1, s * 17.2, 6.2, -0.65), DARK, "Metal"))
        parts.append(P(B(1.6, 1.6, 0.1, s * 17.2, -6.2, -0.65), DARK, "Metal"))
    for x in [-14 + 4 * k for k in range(8)]:
        for y in (-6.4, 6.4):
            parts.append(P(C(0.13, 0.1, x, y, -0.65, segs=6, axis="z"), (180, 186, 196), "Metal"))
    parts.append(P(B(30, 0.6, 1.4, 0, 7.6, -0.6, bev=0.1), DARK, "Metal"))
    for x in (-10, 0, 10):
        parts.append(P(B(0.4, 0.4, 0.8, x, 7.6, 0.2), DARK, "Metal"))
    look("HideMapFrame", parts, [("Glow", [B(28, 0.15, 0.5, 0, 7.25, -1.0)], (255, 236, 200))])


def monitor():
    parts = [P(B(6.4, 4.4, 0.6, 0, 0, 0, bev=0.12), BEZEL, "Metal")]
    for s in (-1, 1):
        parts.append(P(B(6.4, 0.4, 0.3, 0, s * 2.0, -0.45), (46, 48, 54), "SmoothPlastic"))
        parts.append(P(B(0.4, 3.6, 0.3, s * 3.0, 0, -0.45), (46, 48, 54), "SmoothPlastic"))
    parts.append(P(B(1.2, 1.2, 0.4, 0, 0, 0.45), DARK, "Metal"))
    parts.append(P(B(2.0, 2.0, 0.1, 0, 0, 0.58), STEELC, "Metal"))
    look("HideMonitor", parts, [("Led", [B(0.3, 0.12, 0.05, 2.6, -2.05, -0.62)], (90, 236, 140))])


def stair_head(w=10.0, h=11.0, d=8.0):
    parts = [P(B(w, h, d, 0, h / 2, d / 2, bev=0.25), CONC, pat="formwork"),
             P(B(w + 1, 0.6, d + 1, 0, h + 0.3, d / 2, bev=0.1), WALLC),
             P(B(w + 1, 0.4, 0.2, 0, h - 0.1, -0.4), WALLC),
             P(B(2, 1.2, 2, 2.5, h + 1.2, d / 2 + 1), DARK, "Metal"),
             P(B(2.4, 0.2, 2.4, 2.5, h + 1.9, d / 2 + 1), DARK, "Metal"),
             # the steel door frame, the door (riveted), its kick plate, push bar and hinges
             P(B(0.5, 8.6, 0.5, -2.55, 4.3, -0.15), STEELC, "Metal"),
             P(B(0.5, 8.6, 0.5, 2.55, 4.3, -0.15), STEELC, "Metal"),
             P(B(5.6, 0.5, 0.5, 0, 8.35, -0.15), STEELC, "Metal"),
             P(B(4.6, 7.8, 0.3, 0, 3.95, -0.25), (88, 108, 128), pat="plates"),
             P(B(4.4, 1.2, 0.05, 0, 0.75, -0.42), STEELC, "DiamondPlate"),
             P(B(3.4, 0.25, 0.25, 0, 3.8, -0.6), (180, 186, 196), "Metal"),
             P(B(0.25, 0.4, 0.3, -1.6, 3.8, -0.47), DARK, "Metal"),
             P(B(0.25, 0.4, 0.3, 1.6, 3.8, -0.47), DARK, "Metal"),
             P(B(1.6, 0.9, 0.05, 0, 6.6, -0.42), DARK, pat="grate")]
    for y in (1.2, 4.0, 6.8):
        parts.append(P(C(0.15, 0.9, -2.2, y, -0.42, segs=8), DARK, "Metal"))
    # the blank enamel plate over the door, the lamp's hood and cage, the hazard stripes either side
    parts.append(P(B(4, 0.8, 0.12, 0, 9.1, -0.3), WHITE))
    parts.append(P(B(4, 0.14, 0.13, 0, 8.86, -0.31), RED))
    parts.append(P(B(1.8, 0.2, 1.2, 0, 10.25, -0.45), DARK, "Metal"))
    for x in (-0.6, 0, 0.6):
        parts.append(P(T([(x, 10.2, -0.05), (x, 9.6, -0.1), (x, 9.55, -0.95), (x, 10.2, -1.0)], 0.04, segs=4), (40, 42, 48), "Metal"))
    for s in (-1, 1):
        parts.append(P(B(2.0, 0.6, 0.15, s * 4.0, 0.9, -0.1), STRIPE, pat="hazard"))
        parts.append(P(B(0.1, 1.5, 2.5, s * (w / 2 + 0.02), 8, d / 2), DARK, pat="grate"))
    parts.append(P(C(0.12, 9, 4.2, 5.2, -0.13, segs=8), DARK, "Metal"))
    parts.append(P(B(0.8, 1.0, 0.35, 4.2, 4.2, -0.2), (110, 116, 124), "Metal"))
    look("HideStairHead", parts)


# ================================================================ the Foundry
def foundry_wall():
    parts = [P(B(12, 30, 2, 0, 15, 1), SIRON, pat="plates"),
             P(B(12, 0.6, 0.6, 0, 29.7, -0.3), SBLACK, "Metal"),
             P(B(12, 2, 0.15, 0, 1, -0.08), SIRON, "DiamondPlate"),
             P(B(12, 0.4, 1.0, 0, 21.2, -0.5), SBLACK, "Metal"),
             P(B(12, 0.4, 1.0, 0, 14.8, -0.5), SBLACK, "Metal")]
    for s in (-1, 1):
        parts.append(P(B(0.3, 30, 0.9, s * 5.85, 15, -0.45), SBLACK, "Metal"))
        parts.append(P(B(0.6, 30, 0.2, s * 5.7, 15, -0.95), SBLACK, "Metal"))
        for y in (4, 10, 24):
            parts.append(P(C(0.14, 0.12, s * 5.7, y, -1.08, segs=6, axis="z"), (236, 190, 58), "Metal"))
    look("FoundryWall", parts)


def foundry_floor():
    parts = [P(B(22.4, 0.2, 22.4, 0, 0.1, 0), (62, 58, 68), "DiamondPlate")]
    for s in (-1, 1):
        parts.append(P(B(22.4, 0.22, 0.3, 0, 0.11, s * 11.05), SBLACK, "Metal"))
        parts.append(P(B(0.3, 0.22, 21.8, s * 11.05, 0.11, 0), SBLACK, "Metal"))
    look("FoundryFloor", parts)


def foundry_rug():
    look("FoundryRug", [P(B(24, 0.25, 24, 0, 0.125, 0), (210, 60, 60), "Fabric", tint=True)])


def build(layout=None):
    wall()
    panel()
    pillar()
    pilaster()
    beam()
    floor()
    ceiling()
    run()
    lamp()
    stair()
    map_frame()
    monitor()
    stair_head()
    foundry_wall()
    foundry_floor()
    foundry_rug()
    return LOOKS


GRIME = {"HideWall": 0.25, "HidePillar": 0.2, "HidePilaster": 0.2, "HideStairHead": 0.25, "FoundryWall": 0.2, "HidePanel": 0.15}
_ = math
