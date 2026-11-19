# wrecks.py: the downed robots' wrecks as Blender meshes, one look a robot kind (gap-wrecks, 2026-11-19; WP6: a robot
# a hero beats leaves its wreck, a medium throwable, ThrowService). Robots look like heroes (Roblox's blocky R15 body
# in their uniform, a catalog face and hair) with a metal endoskeleton that only shows once they are hurt
# (EnemyRenderer, Shared.RobotDamage); a wreck is that body broken open: the chest shell in the kind's suit colour
# cracked over metal ribs, a spine and a dead core, the hips and a snapped leg in its trim, an arm across the top and
# one torn off beside it, and the head rolled away as the bare metal under-head (a chrome skull with a dark visor
# slit and a jaw plate; never a drawn face or hair: those are the catalog's), with cables, a spring and loose nuts,
# plus the kind's own gear (jets, wings, a riot shield, a rifle, a medpack with the green plus, the bandolier, a cap
# and torn cape, the Grappler's hook arm, a Salt Dog's hook, a Burglar's mask and loot sack, the Wind-Up Giant's key
# and clockwork). Cartoon only: machine bits, sparks and nuts, nothing else.
# Each look is built on its heap box (art/export/wrecks/layout.json from `lune run art/wrecks/layout.luau`:
# ThrowMath.wreckSize, the kind's colours and gear flags) about the box's foot (ground middle), front at -z, in the
# kind's colours baked in (one texture set a look, art/blender/hbake.py), the eyes and core a flat mesh ThrowFx
# flickers. The game draws it over the wreck's plain Body box (hidden, kept: the carry, throw and collision are as
# before; Shared.WreckArtKit, ThrowService).
# Output: art/export/Wrecks.fbx (textures embedded), art/export/wrecks/<Look>_*.png, src/config/WreckArt.luau; with
# --preview art/preview/wrecks.png (every kind beside a robot-sized figure) and art/preview/wrecks_street.png.
# Run: lune run art/wrecks/layout.luau && $HOME/tools/bpyenv/bin/python art/blender/wrecks.py [--preview] [--fast]
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402,F401

kit.reset()

import ruinkit as rk  # noqa: E402
from ruinkit import paint, lump, nut, arc, sheet, shard, ragged  # noqa: E402
from studs import mesh, LOOKS, INFO, C, S, T, TOR, turn, shift, rb  # noqa: E402
from vkit import rbox, bend  # noqa: E402

FAST = "--fast" in sys.argv
LAY = json.load(open(os.path.join(kit.ROOT, "export", "wrecks", "layout.json")))
OUT = os.path.join(kit.ROOT, "export", "wrecks")
ONLY = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None

# the blocky body's widths by build (a 5-stud body; the whole wreck is then scaled to the robot's height)
WIDTH = {"slim": 1.8, "normal": 2.0, "heavy": 2.4, "titan": 2.4}
LIMB = {"slim": 0.85, "normal": 0.95, "heavy": 1.15, "titan": 1.15}
# the uniform's pattern on the suit (Config.NpcLooks.robots' notes): stripes, camouflage, quilting, or plain cloth
SUIT_PAT = {"BurglarBot": "stripes", "SaltDog": "stripesw", "Sniper": "camo", "Bomber": "quilt"}
CLOTH = "plastic+soot"  # the suit's plain cloth: smooth, a little burnt
CABLES = ((210, 50, 40), (240, 200, 50), (60, 110, 220))
GOLD = (240, 190, 60)
BRASS = (214, 160, 60)
STEELC = (140, 146, 156)
FRAMES, ORIGINS, SCALE = {}, {}, {}
FIT, FITY = 1.25, 1.25  # a heap may reach this share of its box across and this share of its height (WreckArtKit)


def _pat(kind, rgb, P, N):
    base = rk._pattern
    if kind in ("stripes", "stripesw", "camo", "quilt"):
        col, mult, h, r, m = base("plastic", rgb, P, N)
        u, v, ax = rk.hbake.planar(P, N)
        if kind in ("stripes", "stripesw"):  # broad horizontal bands, dark or white
            band = ((P[:, 1] * 2.2) % 1.0) < 0.42
            alt = rk.np.array((0.12, 0.12, 0.14) if kind == "stripes" else (0.94, 0.94, 0.96), rk.np.float32)
            col = rk.np.where(band[:, None], alt * (0.9 + 0.1 * mult[:, None]), col)
        elif kind == "camo":  # blotches of a darker and a lighter shade
            a = rk.hbake.fbm(P * 1.0 + 5.0, 0.9)
            b = rk.hbake.fbm(P * 1.0 + 19.0, 0.9)
            col = rk.np.where((a > 0.56)[:, None], col * 0.6, rk.np.where((b > 0.6)[:, None], rk.np.clip(col * 1.35, 0, 1), col))
        else:  # quilted squares
            seam = rk.hbake._line(u + v, 0.9, 0.05) | rk.hbake._line(u - v, 0.9, 0.05)
            col = col * rk.np.where(seam, 0.7, 1.0)[:, None]
            h = h - seam * 0.6
        return col, mult, h, r, m
    return base(kind, rgb, P, N)


rk.hbake.pattern = _pat


def build(kind, d):
    look = "Wreck" + kind
    FRAMES[look] = d["frame"]
    h = d["height"]
    s = h / 5.0  # everything below is built for a 5-stud body, then scaled
    ORIGINS[look] = (0.0, d["frame"][1] / 2, 0.0)
    bld = d["build"]
    W, Lm = WIDTH[bld], LIMB[bld]
    suit, trim, metal, dark, eye = (tuple(d[k]) for k in ("suit", "trim", "metal", "dark", "eye"))
    flags = set(d["flags"])
    rnd = random.Random(sum(ord(c) for c in kind))
    sp = SUIT_PAT.get(kind, CLOTH)
    boot = tuple(int(c * 0.6) for c in trim)
    parts, eyes, glass = [], [], []

    def P(ob, rgb, mat="SmoothPlastic", pat=None):
        parts.append(paint(ob, rgb, mat, pat))
        return ob

    # ---- a heap, not a sprawl (the heap box is small): the chest lies on its back (head end +z), rolled a little,
    # the back half of its shell in the suit colour; a leg, an arm and the head are piled on top of it
    roll = rnd.uniform(-10, 10)
    tz0, tz1 = -0.45, 0.88
    tl = tz1 - tz0
    tc = (tz0 + tz1) / 2
    back = rbox(W, 0.5, tl, 0, 0, 0, bev=0.12)
    turn(back, "z", roll)
    P(shift(back, rb(0, 0.3, tc)), suit, "Fabric", sp)
    # the front of the shell broken off: two cracked plates left, the ribs, spine and core showing between them
    for (fx, fz, fw, fl_) in ((-W * 0.3, tc + 0.22, W * 0.4, tl * 0.66), (W * 0.3, tc - 0.3, W * 0.36, tl * 0.42)):
        pl = lump(fw, 0.18, fl_, 0, 0, 0, rnd.randint(0, 9999), 0.05, 0.05, (rnd.uniform(-8, 8), 0, roll + rnd.uniform(-10, 10)))
        P(shift(pl, rb(fx, 0.66, fz)), suit, "Fabric", sp)
    for k in range(4):
        zz = tz0 + 0.25 + k * (tl - 0.4) / 3
        P(arc(0, 0.48, zz, W * 0.34, 10, 170, 0.07, n=10), metal, "Metal")
    P(rbox(0.28, 0.24, tl * 0.95, 0, 0.52, tc, bev=0.06), dark, "Metal", "diamond")
    eyes.append(C(0.24, 0.1, 0.05, 0.72, tc + 0.12, segs=14))  # the dead core in its chest
    P(TOR(0.3, 0.06, 0.05, 0.7, tc + 0.12, segs=14, csegs=5), dark, "Metal")
    # the hips in the trim, and the joint balls where the legs were
    P(rbox(W * 0.94, 0.72, 0.5, 0, 0.38, tz0 - 0.24, bev=0.1), trim, "Fabric", CLOTH)
    for k in (-1, 1):
        P(S(Lm * 0.3, k * W * 0.24, 0.4, tz0 - 0.52, segs=10, rings=6), dark, "Metal")
    # a leg snapped at the knee, thrown across the hips (trim), its knee joint and a bare metal shin; its boot apart
    thigh = rbox(Lm, Lm, 1.0, 0, 0, 0, bev=0.1)
    turn(thigh, "up", 78 + rnd.uniform(-8, 8))
    turn(thigh, "z", 6)
    P(shift(thigh, rb(-0.05, 0.74 + Lm * 0.45, tz0 - 0.2)), trim, "Fabric", CLOTH)
    P(S(Lm * 0.3, W * 0.42, 0.74 + Lm * 0.45, tz0 - 0.12, segs=10, rings=6), metal, "Metal")
    P(T([(W * 0.42, 0.74 + Lm * 0.45, tz0 - 0.12), (W * 0.52, 0.45, tz0 + 0.1)], 0.12, segs=6), metal, "Metal")
    bt = rbox(Lm * 0.9, Lm * 0.55, 0.95, 0, 0, 0, bev=0.12)
    turn(bt, "up", -20)
    P(shift(bt, rb(-W * 0.32, Lm * 0.28, tz0 - 0.5)), boot, "Fabric", "rubber")
    # an arm piled on top: the sleeve (suit) torn at the elbow, the bare metal forearm and hand hanging off the side
    yaw = rnd.uniform(-22, -10)
    ax, az = -math.sin(math.radians(yaw)), -math.cos(math.radians(yaw))
    a0 = (-W * 0.2, 0.78 + Lm * 0.42, tz1 - 0.15)
    sl = rbox(Lm * 0.86, Lm * 0.86, 0.95, 0, 0, 0, bev=0.1)
    turn(sl, "up", yaw)
    P(shift(sl, rb(a0[0] + ax * 0.45, a0[1], a0[2] + az * 0.45)), suit, "Fabric", sp)
    e = (a0[0] + ax * 0.98, a0[1] - 0.05, a0[2] + az * 0.98)
    f = (-W * 0.5 - 0.05, 0.3, e[2] - 0.15)
    P(S(0.2, *e, segs=10, rings=6), dark, "Metal")
    P(T([e, f], 0.12, segs=6), metal, "Metal")
    hand = rbox(0.4, 0.42, 0.3, -W * 0.5 - 0.08, 0.22, f[2] - 0.05, bev=0.08)
    P(hand, metal, "Metal")
    for k in range(3):  # fingers
        P(rbox(0.08, 0.26, 0.08, -W * 0.5 - 0.12, 0.05, f[2] - 0.15 + k * 0.1, bev=0.02), metal, "Metal")
    # the other arm torn off at the shoulder, lying along the near side (a cut sleeve, the bare metal shoulder)
    arm2 = rbox(Lm * 0.84, Lm * 0.84, 1.3, 0, 0, 0, bev=0.1)
    turn(arm2, "up", 8)
    P(shift(arm2, rb(W * 0.5 + Lm * 0.3, Lm * 0.42, tc + 0.1)), suit, "Fabric", sp)
    P(S(Lm * 0.34, W * 0.5 + Lm * 0.32, Lm * 0.42, tc + 0.8, segs=10, rings=6), metal, "Metal")
    P(rbox(Lm * 0.7, Lm * 0.7, 0.3, W * 0.5 + Lm * 0.28, Lm * 0.38, tc - 0.62, bev=0.08),
      trim if "hookArm" not in flags else metal, "Fabric", "rubber")
    # the head knocked off and rolled onto the pile: the bare metal under-head (a chrome skull, a jaw plate, a dark
    # visor slit), never a face or hair
    hx, hz = W * 0.18, tc + 0.22
    hr = rnd.uniform(-40, -20)

    def head(ob):  # built upright about the head's middle (face at -z), then tipped on its side and turned
        turn(ob, "z", 70)
        turn(ob, "up", hr)
        return shift(ob, rb(hx, 1.05, hz))
    P(head(rbox(1.0, 0.95, 0.95, 0, 0, 0, bev=0.26)), metal, "Metal")
    P(head(rbox(0.7, 0.2, 0.38, 0, -0.4, -0.32, bev=0.06)), dark, "Metal")  # the jaw plate
    P(head(rbox(0.86, 0.13, 0.12, 0, 0.28, -0.47, bev=0.03)), dark, "Metal")  # the brow ridge
    for k in (-1, 1):
        P(head(rbox(0.18, 0.48, 0.86, k * 0.52, 0.0, 0.0, bev=0.05)), dark, "Metal")  # the ear plates
    eyes.append(head(rbox(0.62, 0.12, 0.08, 0, 0.09, -0.48, bev=0.02)))  # the dark visor slit
    eyes.append(head(rbox(0.18, 0.06, 0.06, 0, -0.17, -0.49, bev=0.01)))  # the speaker grille light
    # cables out of its neck to the head, a spring and loose nuts
    for k, col in enumerate(CABLES):
        pts = [((k - 1) * 0.16, 0.6, tz1 - 0.02), ((k - 1) * 0.2 + 0.05, 0.8 + 0.08 * k, tz1 + 0.12), (hx - 0.1 + (k - 1) * 0.1, 0.9, hz + 0.25)]
        P(T(pts, 0.05, segs=5), col, "SmoothPlastic", "rubber")
    helix = [(-W * 0.32 + 0.16 * math.cos(t * 0.5), 0.75 + t * 0.022, tz1 - 0.2 + 0.16 * math.sin(t * 0.5)) for t in range(0, 26)]
    P(T(helix, 0.04, segs=5), STEELC, "Metal")
    for k in range(6):
        a = rnd.uniform(0, 2 * math.pi)
        rr = rnd.uniform(0.55, 0.95)
        P(nut(math.cos(a) * rr * W * 0.55, 0.06, math.sin(a) * rr * 1.0, 0.09), STEELC, "Metal")

    # ---- the kind's own gear
    if "jets" in flags:  # a jet pack knocked off, two thrusters
        jc = tuple(d["jet"]) if d.get("jet") else trim
        for k in (-1, 1):
            P(C(0.24, 0.8, W * 0.12 + k * 0.32, 0.26, -0.95, segs=12, axis="x"), dark, "Metal")
            P(C(0.26, 0.2, W * 0.12 + k * 0.32 + 0.48, 0.26, -0.95, segs=12, axis="x", r2=0.32), jc, "Metal")
        P(rbox(0.7, 0.3, 0.5, W * 0.12, 0.3, -0.95, bev=0.06), trim, "Metal")
    if "wings" in flags:  # a snapped wing leaning on the heap
        wing = vkit_plate([(0, 0), (1.2, 0.12), (1.3, 0.5), (0.2, 0.55)], 0.08)
        turn(wing, "z", 40)
        turn(wing, "up", 15)
        P(shift(wing, rb(-W * 0.45, 0.4, -0.75)), (230, 234, 240), "Metal")
    if "riot" in flags:  # the riot shield fallen across the legs, cracked
        P(_riot(glass, trim), trim, "Metal")
    if "shield" in flags:  # the Warden's round arm shield, dented
        sh_ = C(0.75, 0.14, 0, 0, 0, segs=20)
        turn(sh_, "x", 70)
        P(shift(sh_, rb(-W * 0.48, 0.6, -0.5)), trim, "Metal", "metal+soot")
        P(shift(turn(S(0.22, 0, 0, 0, segs=10, rings=6), "x", 70), rb(-W * 0.48, 0.62, -0.57)), GOLD, "Foil")
    if "cape" in flags:  # a torn cape draped over the hips and trailing out behind
        cc = tuple(d["cape"])
        hem = [rnd.uniform(0, 0.3) for _ in range(8)]
        P(sheet(lambda u, v: ((u - 0.5) * W * 1.05, 0.78 - v * 0.55 + 0.08 * math.sin(u * 9),
                              tz0 - 0.05 - v * 0.9 * (1 - hem[min(7, int(u * 7.99))] * v)), 8, 6, 0.05), cc, "Fabric", "fabric+soot")
    if "cap" in flags:  # the officer's cap knocked off
        P(C(0.42, 0.28, -W * 0.2, 0.14, tz1 + 0.25, segs=16), trim, "Fabric", CLOTH)
        P(C(0.46, 0.05, -W * 0.2, 0.04, tz1 + 0.08, segs=16, r2=0.36), dark, "SmoothPlastic")
        P(S(0.1, -W * 0.2, 0.2, tz1 - 0.12, segs=8, rings=5), GOLD, "Foil")
    if "rifle" in flags:  # the long rifle broken in two
        P(rbox(0.16, 0.2, 1.5, -W * 0.55, 0.12, -0.1, bev=0.03), (40, 44, 40), "Metal")
        P(rbox(0.2, 0.32, 0.5, -W * 0.55, 0.18, -0.9, bev=0.05), (90, 70, 50), "Wood")
        P(C(0.08, 0.7, -W * 0.3, 0.1, 1.05, segs=8, axis="z"), (40, 44, 40), "Metal")
    if "visor" in flags:  # the sniper's visor band still on the skull
        eyes.append(head(rbox(0.8, 0.24, 0.1, 0, 0.12, -0.56, bev=0.03)))
    if "medpack" in flags:  # the backpack with the green plus (never a red cross)
        P(rbox(0.95, 0.5, 0.6, W * 0.2, 0.25, -0.95, bev=0.1), (236, 240, 242), "SmoothPlastic")
        for (a, b) in ((0.5, 0.14), (0.14, 0.5)):
            P(rbox(a, 0.06, b, W * 0.2, 0.52, -0.95, bev=0.01), (60, 200, 120), "SmoothPlastic")
    if "bandolier" in flags:  # the crossed bandolier with its capsules
        P(_band(tz0, tz1, W, trim), (60, 50, 40), "Fabric", "rubber")
        for k in range(5):
            P(C(0.1, 0.22, -W * 0.4 + k * W * 0.2, 0.8, tz0 + 0.15 + k * 0.25, segs=8), (240, 190, 40), "Metal", "hazard")
    if "hookArm" in flags:  # the Grappler's armoured hook arm
        P(T([(W * 0.5 + 0.3, 0.42, tc - 0.75), (W * 0.42, 0.35, -1.0)], 0.2, segs=8), metal, "Metal")
        P(arc(W * 0.2, 0.35, -1.0, 0.3, 90, 330, 0.1, n=12, plane="xz"), (200, 120, 50), "Metal")
    if "hook" in flags:  # a Salt Dog's hand hook
        P(arc(-W * 0.5 - 0.1, 0.12, f[2] - 0.45, 0.2, 60, 320, 0.06, n=10, plane="xz"), STEELC, "Metal")
    if "mask" in flags:  # the Burglar's domino mask and its loot sack (no face under it: the head is bare metal)
        P(rbox(0.6, 0.05, 0.22, W * 0.3, 0.03, tz0 - 0.75, bev=0.02), (24, 24, 28), "Fabric")
        P(S(0.38, -W * 0.25, 0.32, tz1 + 0.1, sc=(1, 0.8, 1), segs=12, rings=8), (200, 180, 140), "Fabric", "fabric")
        P(TOR(0.14, 0.05, -W * 0.25, 0.64, tz1 + 0.1, segs=10, csegs=4), (120, 90, 60), "Fabric")
    if "planted" in flags:  # the Sentry's guard badge on its chest and its baton
        P(C(0.16, 0.05, -0.55, 0.78, tc + 0.3, segs=6), GOLD, "Foil")
        P(T([(-W * 0.45, 0.08, -0.9), (-W * 0.2, 0.08, -0.95)], 0.08, segs=6), (30, 30, 34), "SmoothPlastic")
    if "windKey" in flags:  # the Wind-Up Giant's big brass key and clockwork spilling out
        P(C(0.1, 0.7, -W * 0.3, 1.1, tc, segs=8), BRASS, "Metal")
        for k in (-1, 1):
            P(TOR(0.26, 0.07, -W * 0.3 + k * 0.28, 1.5, tc, axis="z", segs=14, csegs=5), BRASS, "Metal")
        for k in range(4):
            g = C(0.3 + 0.06 * k, 0.08, 0, 0, 0, segs=12)
            turn(g, "x", rnd.uniform(-30, 30))
            P(shift(g, rb(W * 0.35 - k * 0.22, 0.08, -0.9 + k * 0.4)), BRASS, "Metal")
    if kind == "BruteBot":  # the champion's belt on the hips
        P(rbox(W * 0.98, 0.2, 0.55, 0, 0.62, tz0 - 0.24, bev=0.04), (40, 30, 26), "Fabric", "rubber")
        P(rbox(0.5, 0.36, 0.08, 0, 0.64, tz0 - 0.52, bev=0.04), GOLD, "Foil")
    if kind == "SneakBot":  # the sash across the chest
        P(_band(tz0, tz1, W, trim), trim, "Fabric", CLOTH)

    # scale to the robot's height (about the foot), shrunk if need be so the heap stays within FIT of its box
    # across (the box is its collider and what a carry holds), then set on the ground
    allp = parts + eyes + glass
    lo, hi = [1e9] * 3, [-1e9] * 3
    for ob in allp:
        kit.apply_all(ob)
        for v in ob.data.vertices:
            for k, c in enumerate((v.co.x, v.co.z, -v.co.y)):
                lo[k], hi[k] = min(lo[k], c), max(hi[k], c)
    # centred on the heap's middle across (x and z) first
    mx, mz = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2
    for ob in allp:
        for v in ob.data.vertices:
            v.co.x -= mx
            v.co.y += mz
        ob.data.update()
    lo[0], hi[0], lo[2], hi[2] = lo[0] - mx, hi[0] - mx, lo[2] - mz, hi[2] - mz
    fx, fy, fz = d["frame"]
    k_ = min(1.0, FIT * fx / 2 / (s * max(-lo[0], hi[0])), FIT * fz / 2 / (s * max(-lo[2], hi[2])), FITY * fy / (s * (hi[1] - lo[1])))
    SCALE[look] = k_
    for ob in allp:
        for v in ob.data.vertices:
            v.co.z -= lo[1]
            v.co *= s * k_
        ob.data.update()
    mesh(look, look + "Body", parts, suit, "SmoothPlastic")
    mesh(look, look + "Eyes", eyes, tuple(int(c * 0.45) for c in eye), "SmoothPlastic")
    if glass:
        mesh(look, look + "Glass", glass, (200, 230, 255), "Glass", 0.5)


def vkit_plate(pts, thick):
    """A flat plate from (x, z) points, thick tall."""
    import studs
    return studs.rings_mesh([[(x, -thick / 2, z) for (x, z) in pts], [(x, thick / 2, z) for (x, z) in pts]])


def _riot(glass, trim):
    """The riot shield fallen over the legs: its frame (returned, painted by the caller) and its cracked clear face."""
    fr = rbox(1.9, 0.14, 2.2, 0, 0, 0, bev=0.06)
    inner = rbox(1.6, 0.3, 1.9, 0, 0, 0, bev=0)
    kit.apply_all(fr)
    import vkit
    vkit.boolean(fr, inner)
    turn(fr, "x", 14)
    turn(fr, "up", 18)
    face = shard(ragged(8, 0.78, 0.92, 77), 0.06, 0, 0, 0, tilt=(90, 0))
    turn(face, "x", 14)
    turn(face, "up", 18)
    glass.append(shift(face, rb(0.1, 0.72, -0.4)))
    return shift(fr, rb(0.1, 0.72, -0.4))


def _band(tz0, tz1, W, trim):
    """A strap across the chest, corner to corner."""
    return T([(-W * 0.45, 0.6, tz0 + 0.05), (-0.1, 0.8, (tz0 + tz1) / 2), (W * 0.35, 0.6, tz1 - 0.05)], 0.07, segs=5)


for kind in sorted(LAY):
    if ONLY and kind not in ONLY:
        continue
    build(kind, LAY[kind])
ALL = sorted(LOOKS)


def res_of(look, objs):
    return 512 if LAY[look[len("Wreck"):]]["height"] >= 6.5 else 256


# the dead eyes stay plain (their part colour), so ThrowFx can light them for a blink as the wreck sparks
MAPPED = rk.bake_all(ALL, OUT, res_of, fast=FAST, plain={look + "Eyes" for look in ALL})
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "WreckArt.luau"))
if not ONLY:
    tris, total, count = rk.write_fit(FIT, [
        "-- GENERATED by art/blender/wrecks.py: do not edit by hand.",
        "-- The downed robots' wrecks in Blender meshes, one look a robot kind (ReplicatedStorage.Art.Wrecks;",
        "-- Shared.WreckArtKit, ThrowService): look -> its frame (the kind's heap box, ThrowMath.wreckSize: studs x, up, z)",
        "-- and its meshes: each mesh's size and its centre from the frame's middle, its colour, material, transparency,",
        "-- maps (a baked texture set in its SurfaceAppearance) and triangles. <Look>Eyes is the dead visor and core that",
        "-- ThrowFx flickers.",
    ], ALL, FRAMES, MAPPED, ORIGINS)
    print("wrecks: %d looks, %d meshes, %d tris" % (len(ALL), count, total))
    for look in ALL:
        print("  %-18s %5d tris" % (look, sum(tris[n] for n in LOOKS[look])))
    rk.export_fbx(os.path.join(kit.ROOT, "export", "Wrecks.fbx"), ALL, MAPPED)

# ================================================================ previews
if "--preview" in sys.argv:
    import vpreview as vp  # noqa: E402

    PREV = os.path.join(kit.ROOT, "preview")
    vp._scene(FAST, (760, 420) if FAST else (1400, 780))
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.hide_render = True
    vp._ground(400, (128, 130, 136))
    cols = 6
    shots = []
    x, row, zrow = 0.0, 0, 0.0
    order = ALL
    for i, look in enumerate(order):
        c, r = i % cols, i // cols
        f = FRAMES[look]
        rk.placed(look, MAPPED, (c * 7.5, 0, r * 7.5), 20, vp._keep)
    for r in range((len(order) + cols - 1) // cols):
        vp._hero(-5, 0, r * 7.5, yaw=30)
    vp._camera((17, 26, -20), (17, 0, 7.5), lens=32)
    out = os.path.join(PREV, "wrecks.png")
    kit.render(out)
    vp._clear()
    # close-ups: a normal, a heavy and a slim wreck beside a robot-sized figure
    vp._ground(200, (90, 92, 98))
    for (i, look) in enumerate([lk for lk in ("WreckSparkDrone", "WreckBruteBot", "WreckShieldBearer", "WreckCaptain") if lk in LOOKS]):
        rk.placed(look, MAPPED, (i * 6.0, 0, 0), 25 + i * 30, vp._keep)
    vp._hero(-4.5, 0, 1.5, yaw=20)
    vp._camera((12, 9, -16), (8, 1, 0), lens=30)
    kit.render(os.path.join(PREV, "wrecks_close.png"))
    print("preview:", out)
