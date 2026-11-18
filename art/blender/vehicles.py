# vehicles.py: the side quest escorts and the hub's 40 cars, trams and trucks as Blender meshes, in the set pieces'
# style (art/blender/setpieces.py: flat colours, one colour region a mesh, chunky silhouettes, low poly for phones;
# the shared helpers are art/blender/studs.py). Until nate imports them the game builds every vehicle from plain parts
# (SideQuestService's motorcade box, VehicleService's boxes and wheel cylinders); once ReplicatedStorage.Art.Vehicles
# holds a look's meshes, the game draws them over those parts and hides the parts, which keep their collision, flips,
# throws and queries exactly as before (Shared.SetPieceKit for the escorts, Shared.VehicleKit for the hub).
# Looks (original designs, no real makes, badges or logos):
# * the escorts (SetPieceKit.TRUCKS; foot on the road, nose at -z, over the 7 x 14 motorcade box): the Halo Academy
#   field trip bus (The Hero Academy), Scoops's ice cream truck (Wind-Up Lane), the Gull Point ferry crew's van (The
#   Salt Dogs), Nora's news van (The Scoop), Ambrose the Astonishing's old show van (The Last Owner) and Tinker Tess's
#   parts truck (Suit Recall). The farm folk's truck (The Harvest King) is setpieces.py's FarmTruck.
# * the hub (Shared.Vehicles: foot at the ground, nose at -z, long axis along z, over VehicleService's boxes): three
#   Downtown cars (CarHatch, CarSedan, CarTaxi), Old Town's little round CarBubble, the Tram and the Docks' DockTruck.
#   A car's, tram's or truck's paint is the vehicle's own colour (VehicleKit tints the <Look>Body mesh).
# Output: art/export/Vehicles.fbx, src/config/VehicleArt.luau; with --preview, art/preview/vehicles.png (the looks
# side by side with a hero for scale, then a Downtown street where the game parks them, from
# art/export/vehicles/layout.json, which `lune run art/vehicles/layout.luau` writes, and the same street in today's
# parts; --only <shot> renders one shot alone to art/preview/vehicles_<shot>.png, --fast at low quality).
# Run: python art/blender/vehicles.py [--preview] [--only <shot>] [--fast]   (with the `bpy` module, Blender 5.0)
import json
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

kit.reset()

from studs import *  # noqa: E402,F401,F403  (the colours and shape helpers)
from studs import LOOKS, INFO  # noqa: E402

# ---------------------------------------------------------------- the vehicles' own colours (bright comic paints)
TAXI = (255, 204, 32)
BUSYELLOW = (255, 196, 28)
CHROME = (206, 212, 220)
LAMP = (255, 246, 206)
TAIL = (232, 40, 44)
WINDOW = (120, 196, 238)  # the cartoon window blue: opaque, so a window never shows the body through it
MINT = (140, 228, 200)
ICEPINK = (255, 118, 176)
WAFFLE = (224, 166, 92)
PLUM = (118, 42, 124)
SHOWGOLD = (246, 196, 64)
BULB = (255, 222, 150)
NEWSWHITE = (244, 246, 250)
DISH = (222, 226, 232)
PARTSORANGE = (250, 132, 28)
CRANE = (252, 206, 40)
SEANAVY = (30, 52, 112)
LIFERING = (250, 96, 40)
TRAMCREAM = (250, 240, 214)
CONTAINER = (44, 132, 196)
PAINT = (220, 60, 50)  # a tinted body's colour in the FBX and the fit table (the game paints each copy)


# ---------------------------------------------------------------- helpers
def body(poly, hw, bev=0.35, segs=2):
    """A body panel from its side profile (z, up) pushed out to +-hw across, its edges rounded."""
    ob = prism(poly, -hw, hw)
    if bev:
        kit.bevel(ob, bev, segs)
        kit.apply_all(ob)
    return ob


def slab(a, b, hw, t=0.12, inside=(0.0, 3.0), x=0.0):
    """A thin plate lying on the profile segment a -> b ((z, up) points), hw either side of x, pushed out of the
    body (away from the inside point) by t: windscreens and back windows on slanted faces."""
    (z1, y1), (z2, y2) = a, b
    dz, dy = z2 - z1, y2 - y1
    n = math.hypot(dz, dy)
    nz, ny = -dy / n, dz / n
    mz, my = (z1 + z2) / 2, (y1 + y2) / 2
    if (inside[0] - mz) * nz + (inside[1] - my) * ny > 0:
        nz, ny = -nz, -ny
    lo = [(x - hw, y1 + ny * 0.01, z1 + nz * 0.01), (x + hw, y1 + ny * 0.01, z1 + nz * 0.01),
          (x + hw, y2 + ny * 0.01, z2 + nz * 0.01), (x - hw, y2 + ny * 0.01, z2 + nz * 0.01)]
    hi = [(px, py + ny * t, pz + nz * t) for (px, py, pz) in lo]
    return rings_mesh([lo, hi])


def inset(a, b, f0, f1):
    """The part of segment a -> b from fraction f0 to f1."""
    return ((a[0] + (b[0] - a[0]) * f0, a[1] + (b[1] - a[1]) * f0), (a[0] + (b[0] - a[0]) * f1, a[1] + (b[1] - a[1]) * f1))


def sides(poly, hw, t=0.08):
    """A flat panel of this side profile on both sides of a body hw across (windows, stripes, decals)."""
    return prism(poly, -hw - t, hw + t)


def rect(z0, z1, y0, y1):
    return [(z0, y0), (z0, y1), (z1, y1), (z1, y0)]


def round_rect(z0, z1, y0, y1, r, n=2):
    """A rectangle with its corners cut round (n points a corner) in the (z, up) plane."""
    pts = []
    for (cz, cy, a0) in ((z0 + r, y0 + r, math.pi), (z0 + r, y1 - r, math.pi / 2), (z1 - r, y1 - r, 0), (z1 - r, y0 + r, -math.pi / 2)):
        for k in range(n + 1):
            a = a0 - (math.pi / 2) * k / n
            pts.append((cz + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def wheels(xa, zs, r, w=0.9, hub=0.55, segs=12, hub_segs=8):
    """Tyres at +-xa (the tyre's middle) and the given z's, and their hubcaps outside."""
    tyres, hubs = [], []
    for z in zs:
        for s_ in (-1, 1):
            tyres.append(C(r, w, s_ * xa, r, z, segs=segs, axis="x"))
            hubs.append(C(hub, 0.14, s_ * (xa + w / 2 + 0.05), r, z, segs=hub_segs, axis="x"))
    return tyres, hubs


def lamps(z, y, xs, r=0.42, face=-1, segs=8):
    """Round lamps on a face at z (face -1 the nose, +1 the tail)."""
    return [C(r, 0.2, x, y, z + face * 0.08, segs=segs, axis="z") for x in xs]


def pillar(a, b, x, r=0.16):
    """A thin post in the body colour from a to b ((z, up) points) at x."""
    return T([(x, a[1], a[0]), (x, b[1], b[0])], r, segs=5)


def side_star(r_out, r_in, x, y, z, depth=0.12):
    """A flat star on the side of a body (facing +x or -x)."""
    s_ = star(r_out, r_in, depth, 0, 0, 0)
    turn(s_, "up", 90)
    return shift(s_, rb(x, y, z))


def side_disc(r, x, y, z, t=0.12, segs=16):
    return C(r, t, x, y, z, segs=segs, axis="x")


def both(fn):
    """fn(sign) for the right (+1) and the left (-1) side, as one list."""
    out = []
    for s_ in (1, -1):
        r_ = fn(s_)
        out += r_ if isinstance(r_, list) else [r_]
    return out


# ================================================================ the escorts (SetPieceKit.TRUCKS): foot on the road,
# nose at -z, over the motorcade box (7 x 4 x 14 at y 2.5 and the 6.6 x 2.4 x 6 cab at y 5.6, z -2)
# ---------------------------------------------------------------- the Halo Academy field trip bus (The Hero Academy):
# a short school bus with a bonnet, the academy's sign and gold halo on the roof and its star on each side
L = "FieldTripBus"
bon = [(-7.0, 1.1), (-7.0, 3.3), (-6.6, 3.85), (-4.6, 3.95), (-4.6, 1.1)]
main = [(-4.8, 1.0), (-4.8, 6.5), (-4.3, 7.0), (6.6, 7.0), (7.0, 6.5), (7.0, 1.0)]
bb = [body(bon, 3.0, 0.3), body(main, 3.5, 0.4)]
for z in (-3.2, -1.3, 0.6, 2.5, 4.4):  # the window posts
    bb.append(B(7.18, 2.2, 0.32, 0, 5.4, z))
mesh(L, "BusBody", bb, BUSYELLOW)
mesh(L, "BusRoof", [B(6.4, 0.45, 11.2, 0, 7.15, 1.1, bev=0.15)], WHITE)
mesh(L, "BusGlass", [sides(rect(-4.2, 6.2, 4.3, 6.5), 3.5), B(5.8, 2.1, 0.14, 0, 5.4, -4.86), B(5.0, 1.8, 0.14, 0, 5.4, 7.06)], WINDOW)
tyres, hubs = wheels(2.95, (-4.6, 4.2), 1.25, w=1.0)
rub = tyres + [sides(rect(-4.7, 6.9, 2.3, 2.6), 3.5, 0.06), sides(rect(-4.7, 6.9, 3.5, 3.8), 3.5, 0.06),
               B(4.2, 1.6, 0.16, 0, 2.5, -7.05)]  # the rubbing strips and the grille
mesh(L, "BusRubber", rub, TYRE)
chrome = hubs + [B(6.6, 0.6, 0.5, 0, 1.35, -7.2, bev=0.12), B(7.2, 0.6, 0.5, 0, 1.35, 7.2, bev=0.12)]
for s_ in (-1, 1):  # the big mirrors on stalks
    chrome += [B(0.7, 0.16, 0.16, s_ * 3.75, 5.0, -4.95), B(0.25, 1.1, 0.6, s_ * 4.12, 5.0, -5.0, bev=0.08)]
mesh(L, "BusChrome", chrome, CHROME)
mesh(L, "BusLights", lamps(-7.0, 2.45, (-2.0, 2.0), r=0.5) + [B(0.9, 0.5, 0.12, x, 6.7, -4.86) for x in (-2.2, 2.2)], LAMP)
red = [B(0.7, 0.6, 0.12, x, 2.3, 7.06) for x in (-2.5, 2.5)] + [B(0.8, 0.5, 0.12, x, 6.7, 7.06) for x in (-2.3, 2.3)]
stop = C(0.75, 0.12, -3.62, 4.0, -3.7, segs=8, axis="x")  # the stop arm on the driver's side
turn(stop, "x", 22.5, (-3.62, 4.0, -3.7))
mesh(L, "BusRed", red + [stop], TAIL)
mesh(L, "BusNavy", [B(0.5, 1.4, 5.6, 0, 8.05, 1.0, bev=0.12)] + both(lambda s_: side_disc(1.05, s_ * 3.58, 3.05, 1.4)), NAVY)
halo = TOR(1.35, 0.22, 0, 0, 0, segs=16, csegs=5)  # the academy's halo, floating over its sign
turn(halo, "x", -12)
shift(halo, rb(0, 9.25, 1.0))
gold = [halo] + both(lambda s_: side_star(0.85, 0.36, s_ * 3.68, 3.05, 1.4))
gold += both(lambda s_: side_star(0.5, 0.21, s_ * 0.3, 8.05, 1.0))
mesh(L, "BusGold", gold, GOLD)

# ---------------------------------------------------------------- Scoops's ice cream truck (Wind-Up Lane): a mint van
# with a giant cone on the roof, a serving hatch with a striped awning on the kerb side and a cone painted on the other
L = "IceCreamTruck"
nose = [(-7.0, 1.1), (-7.0, 3.3), (-6.6, 3.7), (-5.6, 3.8), (-5.6, 1.1)]
van = [(-6.3, 1.0), (-6.3, 4.0), (-4.7, 6.4), (-4.2, 6.85), (6.6, 6.85), (7.0, 6.4), (7.0, 1.0)]
mesh(L, "IceBody", [body(nose, 3.2, 0.3), body(van, 3.45, 0.4)], MINT)
ws = inset((-6.3, 4.0), (-4.7, 6.4), 0.1, 0.9)
glass = [slab(ws[0], ws[1], 2.7, inside=(0, 3))]
glass += [sides([(-6.0, 4.2), (-4.8, 6.0), (-3.2, 6.0), (-3.2, 4.2)], 3.45)]
mesh(L, "IceGlass", glass, WINDOW)
pink, awn_w = [sides(rect(-6.2, 6.9, 1.9, 2.7), 3.45, 0.05)], []
for k in range(6):  # the awning over the hatch: pink and white stripes, sloping down and out
    pz = -0.85 + k * 0.94
    st = B(1.6, 0.14, 0.94, 3.45 + 0.8, 6.0, pz)
    turn(st, "z", -18, (3.45, 6.25, pz))
    (pink if k % 2 == 0 else awn_w).append(st)
scoop = S(1.75, 0, 10.7, 0.6, sc=(1, 0.9, 1), segs=14, rings=8)
drips = [S(0.38, math.cos(a) * 1.22, 9.62 - 0.2 * (k % 2), 0.6 + math.sin(a) * 1.22, sc=(1, 0.8, 1), segs=6, rings=4)
         for k, a in enumerate(math.radians(d) for d in range(0, 360, 45))]  # the scalloped, melting rim
pink += [scoop] + drips + [side_disc(1.0, -3.55, 5.2, 2.6, segs=14)]
mesh(L, "IcePink", pink, ICEPINK)
cone = C(0.3, 3.4, 0, 8.65, 0.6, segs=14, r2=1.7)
dec = prism([(1.75, 4.95), (3.45, 4.95), (2.6, 2.85)], -3.55, -3.45 - 0.14)
mesh(L, "IceCone", [cone, dec], WAFFLE)
tyres, hubs = wheels(3.05, (-4.5, 4.4), 1.2)
mesh(L, "IceWhite", awn_w + [B(6.4, 0.4, 10.4, 0, 6.95, 1.2, bev=0.15), B(0.3, 0.25, 5.4, 3.75, 3.65, 1.5),
                             B(6.4, 0.6, 0.5, 0, 1.35, -7.15, bev=0.12), B(7.0, 0.6, 0.5, 0, 1.35, 7.2, bev=0.12)] + hubs, WHITE)
mesh(L, "IceRubber", tyres + [B(0.14, 2.0, 5.0, 3.5, 4.8, 1.5)], TYRE)
mesh(L, "IceCherry", [S(0.5, 0, 12.55, 0.6, segs=10, rings=6), S(0.36, -3.6, 6.1, 2.6, segs=8, rings=5)] +
     [B(0.7, 0.55, 0.12, x, 2.3, 7.06) for x in (-2.5, 2.5)], TAIL)
spr = []
for k, (a_, h_) in enumerate(((0.3, 0.55), (1.4, 0.3), (2.5, 0.65), (3.6, 0.2), (4.7, 0.5), (5.6, 0.7), (0.9, -0.1), (3.0, -0.05))):
    rr = 1.72 * math.cos(h_)
    sp = B(0.14, 0.14, 0.45, math.cos(a_) * rr, 10.7 + 1.55 * math.sin(h_), 0.6 + math.sin(a_) * rr)
    turn(sp, "up", math.degrees(a_) + 30, (math.cos(a_) * rr, 0, 0.6 + math.sin(a_) * rr))
    spr.append(sp)
mesh(L, "IceLights", lamps(-7.0, 2.4, (-1.9, 1.9)) + spr, (255, 232, 120))

# ---------------------------------------------------------------- the Gull Point ferry crew's van (The Salt Dogs): navy
# below and white above like the ferry, a life ring and portholes on each side, an oar and a rope coil on the rack
L = "FerryVan"
low = [(-7.0, 1.0), (-7.0, 3.3), (-6.6, 3.85), (7.0, 3.85), (7.0, 1.0)]
up_ = [(-6.5, 3.7), (-6.5, 4.2), (-4.8, 6.45), (-4.3, 6.85), (6.6, 6.85), (7.0, 6.4), (7.0, 3.7)]
anchor = [B(0.18, 1.6, 0.12, 0, 5.2, 7.08), B(1.0, 0.18, 0.12, 0, 5.75, 7.08),
          TOR(0.55, 0.1, 0, 4.75, 7.1, axis="z", segs=10, csegs=4, arc=math.pi)]
turn(anchor[2], "z", 180, (0, 4.75, 7.1))
mesh(L, "FerryNavy", [body(low, 3.5, 0.35)] + anchor, SEANAVY)
mesh(L, "FerryWhite", [body(up_, 3.42, 0.4)], WHITE)
ws = inset((-6.5, 4.2), (-4.8, 6.45), 0.1, 0.9)
glass = [slab(ws[0], ws[1], 2.7), sides([(-6.2, 4.3), (-5.0, 6.0), (-3.4, 6.0), (-3.4, 4.3)], 3.42)]
glass += both(lambda s_: [C(0.62, 0.14, s_ * 3.47, 5.1, z, segs=12, axis="x") for z in (-0.6, 5.2)])
glass += [B(2.2, 1.4, 0.12, x, 5.4, 7.04) for x in (-1.4, 1.4)]
mesh(L, "FerryGlass", glass, WINDOW)
tyres, hubs = wheels(3.05, (-4.5, 4.4), 1.2)
mesh(L, "FerryRubber", tyres, TYRE)
rack = [T([(x, 7.0, -3.6), (x, 7.6, -3.3), (x, 7.6, 5.9), (x, 7.0, 6.2)], 0.12, segs=5) for x in (-2.5, 2.5)]
rack += [B(5.2, 0.2, 0.2, 0, 7.6, z) for z in (-2.4, 1.2, 4.8)]
mesh(L, "FerryChrome", hubs + rack + [B(6.6, 0.6, 0.5, 0, 1.35, -7.15, bev=0.12), B(7.1, 0.6, 0.5, 0, 1.35, 7.2, bev=0.12)], CHROME)
ring = both(lambda s_: TOR(1.0, 0.28, s_ * 3.62, 4.9, 2.3, axis="x", segs=14, csegs=5))
mesh(L, "FerryRing", ring + [B(0.7, 0.55, 0.12, x, 2.3, 7.06) for x in (-2.5, 2.5)], LIFERING)
coil = [TOR(0.85, 0.24, 0.9, 7.95, 3.3, segs=12, csegs=5), TOR(0.55, 0.22, 0.9, 8.35, 3.3, segs=10, csegs=5)]
bands = both(lambda s_: [B(0.3, 0.62, 0.62, s_ * 3.62, 4.9 + dy * 1.0, 2.3 + dz * 1.0) for (dy, dz) in ((1, 0), (-1, 0), (0, 1), (0, -1))])
mesh(L, "FerryRope", coil + bands, ROPE)
oar = [B(0.3, 0.2, 7.2, -1.3, 7.85, 0.4), B(0.9, 0.16, 1.8, -1.3, 7.85, -3.9, bev=0.06)]
mesh(L, "FerryOar", oar, WOOD)
mesh(L, "FerryLights", lamps(-7.0, 2.4, (-1.9, 1.9)), LAMP)

# ---------------------------------------------------------------- Nora's news van (The Scoop): a white van with a red
# band, a satellite dish and a folded mast on the roof, a light bar, and a broadcast tower on a navy disc each side
L = "NewsVan"
mesh(L, "NewsBody", [body(nose, 3.2, 0.3), body(van, 3.45, 0.4)], NEWSWHITE)
ws = inset((-6.3, 4.0), (-4.7, 6.4), 0.1, 0.9)
glass = [slab(ws[0], ws[1], 2.7), sides([(-6.0, 4.2), (-4.8, 6.0), (-3.2, 6.0), (-3.2, 4.2)], 3.45)]
glass += [B(2.2, 1.4, 0.12, x, 5.3, 7.04) for x in (-1.4, 1.4)]
mesh(L, "NewsGlass", glass, WINDOW)
redb = [sides([(-6.2, 2.0), (-6.2, 3.0), (2.8, 3.0), (4.4, 4.8), (6.9, 4.8), (6.9, 3.8), (4.9, 3.8), (3.3, 2.0)], 3.45, 0.05)]
mesh(L, "NewsBand", redb + [B(0.7, 0.55, 0.12, x, 2.3, 7.06) for x in (-2.5, 2.5)], (255, 166, 28))
mesh(L, "NewsNavy", both(lambda s_: side_disc(1.15, s_ * 3.55, 4.75, 0.4)), (44, 70, 190))
tower = []
for s_ in (1, -1):  # the broadcast tower and its waves (white on navy)
    xo = s_ * 3.63
    tw = prism([(0.0, 5.45), (0.42, 4.0), (-0.42, 4.0)], xo - 0.07, xo + 0.07)
    tower.append(tw)
    for k, rr in enumerate((0.55, 0.85)):
        for side_ in (-1, 1):
            a = TOR(rr, 0.07, 0, 0, 0, axis="x", segs=6, csegs=3, arc=math.pi / 2)
            turn(a, "x", 45 if side_ > 0 else 135)
            tower.append(shift(a, rb(xo, 5.45, 0.4)))
tower += lamps(-7.0, 2.4, (-1.9, 1.9))
mesh(L, "NewsLights", tower + [B(1.0, 0.7, 0.5, x, 7.55, -3.6, bev=0.1) for x in (-1.2, 1.2)], (255, 250, 228))
tyres, hubs = wheels(3.05, (-4.5, 4.4), 1.2)
mesh(L, "NewsRubber", tyres, TYRE)
mast = [B(1.4, 0.6, 1.4, 0, 7.15, 3.2, bev=0.1), C(0.2, 1.4, 0, 7.9, 3.2, segs=8), B(3.6, 0.3, 0.5, 0, 7.05, -3.6)]
mast += [T([(-1.8, 7.3, -2.2), (-1.8, 7.3, 6.2)], 0.22, segs=6), T([(-1.8, 7.3, -2.2), (-1.8, 7.3, 6.2)], 0.12, segs=6),
         B(0.6, 0.5, 0.6, -1.8, 7.2, 6.2), B(0.5, 0.3, 0.3, -1.8, 7.2, -1.0), B(0.5, 0.3, 0.3, -1.8, 7.2, 3.0)]
mast += [B(6.6, 0.6, 0.5, 0, 1.35, -7.15, bev=0.12), B(7.0, 0.6, 0.5, 0, 1.35, 7.2, bev=0.12)] + hubs
mesh(L, "NewsSteel", mast, STEEL)
dish = S(1.6, 0, 0, 0, sc=(1, 1, 0.42), segs=14, rings=7)
kit.cut(dish, (0, 1, 0), keep_positive=False)  # keep the bowl (Blender -y = Roblox +z)
turn(dish, "x", -50)
shift(dish, rb(0, 9.0, 3.4))
mesh(L, "NewsDish", [dish, C(0.18, 1.0, 0, 9.2, 2.6, segs=6, axis="z")], DISH)

# ---------------------------------------------------------------- Ambrose the Astonishing's old show van (The Last
# Owner): a rounded vintage van in plum and gold, marquee bulbs round its side panels, a top hat and a trunk on the roof
L = "ShowVan"
st_ = [(-7.0, 2.7, 1.2, 3.3), (-6.7, 3.2, 1.0, 4.5), (-6.0, 3.42, 0.95, 5.9), (-5.0, 3.48, 0.9, 6.8), (-3.6, 3.5, 0.9, 7.05),
       (5.6, 3.5, 0.9, 7.05), (6.6, 3.42, 1.0, 6.6), (7.0, 3.1, 1.2, 5.6)]
mesh(L, "ShowBody", [loft_z(st_, segs=16, power=3.2)], PLUM)
ws = ((-6.62, 4.65), (-5.95, 6.0))
mesh(L, "ShowGlass", [slab(ws[0], ws[1], 1.15, x=-1.3, t=0.14), slab(ws[0], ws[1], 1.15, x=1.3, t=0.14),
                      sides(round_rect(-5.3, -3.6, 4.6, 6.2, 0.35), 3.44), B(2.4, 1.3, 0.12, 0, 5.5, 7.0)], WINDOW)
panel = round_rect(-2.6, 5.4, 2.0, 6.2, 0.6)
mesh(L, "ShowCream", [sides(panel, 3.5, 0.06)], CREAM)
frame = []
for s_ in (1, -1):
    pts = round_rect(-2.6, 5.4, 2.0, 6.2, 0.6)
    frame.append(T([(s_ * 3.6, y, z) for (z, y) in pts + [pts[0]]], 0.13, segs=4))
frame += both(lambda s_: side_star(1.35, 0.55, s_ * 3.62, 4.1, 1.4))
frame += [B(6.0, 0.6, 0.5, 0, 1.3, -7.05, bev=0.2), B(6.4, 0.6, 0.5, 0, 1.3, 7.05, bev=0.2)]
tyres, hubs = wheels(3.0, (-4.6, 4.5), 1.2, w=0.95, hub=0.7)
frame += hubs + [TOR(1.08, 0.13, 0.6, 7.6, -1.2, segs=14, csegs=4)]  # the hat's band
frame += [B(0.3, 0.3, 0.3, x, 7.15 + yy, z) for x in (-1.9, 1.9) for z in (3.0, 6.2) for yy in (0.0, 1.6)]
mesh(L, "ShowGold", frame, SHOWGOLD)
bulbs = []
for s_ in (1, -1):
    pts = []
    for k in range(5):
        pts.append((-2.6 + 8.0 * (k + 0.5) / 5, 6.42))
        pts.append((-2.6 + 8.0 * (k + 0.5) / 5, 1.78))
    for (z, y) in pts:
        bulbs.append(S(0.2, s_ * 3.62, y, z, segs=6, rings=3))
bulbs += lamps(-7.0, 2.3, (-1.7, 1.7), r=0.5)
mesh(L, "ShowBulbs", bulbs, BULB, "Neon")
hat = [C(1.0, 2.0, 0.6, 8.26, -1.2, segs=14, r2=1.08), C(1.65, 0.22, 0.6, 7.15, -1.2, segs=14)]
mesh(L, "ShowBlack", tyres + hat, BLACK)
mesh(L, "ShowTrunk", [B(4.0, 1.7, 3.4, 0, 7.85, 4.6, bev=0.15)], DARKWOOD, "Wood")

# ---------------------------------------------------------------- Tinker Tess's parts truck (Suit Recall): an orange
# pickup with a flatbed of crates, a spare tyre and a big gear, a little crane on the back and a beacon on the cab
L = "PartsTruck"
bon = [(-7.0, 1.1), (-7.0, 3.2), (-6.6, 3.75), (-4.2, 3.95), (-4.2, 1.1)]
cab = [(-4.4, 1.0), (-4.4, 4.0), (-3.4, 6.3), (-3.0, 6.7), (-1.3, 6.7), (-1.3, 1.0)]
mesh(L, "PartsCab", [body(bon, 3.25, 0.3), body(cab, 3.4, 0.35), sides(rect(-1.3, 7.0, 1.3, 2.4), 3.3, 0.0)], PARTSORANGE)
ws = inset((-4.4, 4.0), (-3.4, 6.3), 0.08, 0.92)
mesh(L, "PartsGlass", [slab(ws[0], ws[1], 2.7), sides([(-4.1, 4.3), (-3.3, 6.1), (-1.8, 6.1), (-1.8, 4.3)], 3.4),
                       B(5.4, 1.4, 0.12, 0, 5.15, -1.24)], WINDOW)
steel = [B(7.0, 0.45, 8.4, 0, 2.6, 2.85, bev=0.08)]
for s_ in (-1, 1):
    steel += [B(0.22, 1.3, 8.2, s_ * 3.35, 3.4, 2.85), B(0.25, 0.25, 8.2, s_ * 3.35, 4.1, 2.85)]
steel += [B(6.9, 1.3, 0.22, 0, 3.4, 6.95), T([(2.4, 6.9, 3.9), (2.4, 6.3, 3.9)], 0.06, segs=4),
          TOR(0.35, 0.09, 2.4, 6.0, 3.9, axis="z", segs=8, csegs=3, arc=math.pi * 1.4)]
steel += [B(6.6, 0.6, 0.5, 0, 1.35, -7.15, bev=0.12), B(7.0, 0.6, 0.4, 0, 1.6, 7.2, bev=0.12)]
tyres, hubs = wheels(3.0, (-4.6, 4.4), 1.25, w=1.0)
mesh(L, "PartsSteel", steel + hubs, STEEL, "DiamondPlate")
spare = C(1.15, 0.8, -1.5, 3.25, 5.3, segs=12)
mesh(L, "PartsRubber", tyres + [spare], TYRE)
mesh(L, "PartsWood", [B(2.4, 2.2, 2.4, -1.6, 3.95, 1.2, bev=0.12), B(2.1, 1.8, 2.1, -1.5, 5.95, 1.3, bev=0.12),
                      B(2.6, 2.0, 2.6, 1.6, 3.85, 0.6, bev=0.12)], WOOD, "Wood")
gear = [C(1.35, 0.5, 0, 0, 0, segs=16, axis="x"), C(0.45, 0.62, 0, 0, 0, segs=8, axis="x")]
for k in range(10):
    t_ = B(0.5, 0.6, 0.5, 0, 1.55, 0)
    turn(t_, "x", k * 36)
    gear.append(t_)
for g in gear:  # standing on edge in the bed
    shift(g, rb(1.6, 5.3, 4.6))
mesh(L, "PartsBrass", gear + [C(0.42, 0.36, -1.5, 3.81, 5.3, segs=8)], BRASS)
crane = [B(0.6, 3.3, 0.6, 2.4, 4.4, 6.4), T([(2.4, 5.9, 6.4), (2.4, 7.1, 3.6)], 0.24, segs=6), B(1.2, 0.5, 1.2, 2.4, 2.95, 6.4)]
mesh(L, "PartsYellow", crane, CRANE)
mesh(L, "PartsLights", lamps(-7.0, 2.45, (-1.9, 1.9), r=0.48), LAMP)
mesh(L, "PartsBeacon", [C(0.42, 0.55, 0, 7.0, -2.2, segs=10, r2=0.34), S(0.34, 0, 7.3, -2.2, segs=8, rings=4)], (255, 150, 40),
     "Neon")


# ================================================================ the hub (Shared.Vehicles): foot at the ground, nose at -z
# ---------------------------------------------------------------- the cars (over the 6 x 4.5 x 11 box: body y 1 to 3.5,
# glass to 5.3, wheels under it); a body is the car's own paint
def car(L, lower, cabin, roof, posts, rgb=PAINT, extra_body=None):
    """lower: the body's side profile; cabin: the glass house's profile; roof: (z0, z1, y) of the roof cap;
    posts: the window pillars' (z, up) segments."""
    # (one bevel segment and lighter wheels than the escorts: up to 30 cars stand in the hub)
    bd = [body(lower, 2.88, 0.35, 1), B(4.7, 0.35, roof[1] - roof[0], 0, roof[2], (roof[0] + roof[1]) / 2, bev=0.14)]
    for (a, b) in posts:
        bd += [pillar(a, b, 2.28), pillar(a, b, -2.28)]
    mesh(L, L + "Body", bd + (extra_body or []), rgb)
    mesh(L, L + "Glass", [body(cabin, 2.3, 0.12, 1)], WINDOW)
    tyres, hubs = wheels(2.62, (-3.55, 3.55), 1.1, w=0.85, hub=0.5, segs=10, hub_segs=6)
    mesh(L, L + "Tyres", tyres, TYRE)
    return hubs


hubs = car("CarHatch", [(-5.45, 1.0), (-5.45, 2.55), (-4.9, 3.15), (5.1, 3.35), (5.45, 3.0), (5.45, 1.0)],
           [(-2.4, 3.0), (-0.75, 4.85), (4.35, 4.85), (5.15, 3.0)], (-0.95, 4.5, 5.05),
           [((-2.3, 3.1), (-0.8, 4.85)), ((1.55, 3.1), (1.55, 4.85)), ((4.2, 4.85), (5.05, 3.1))])
mesh("CarHatch", "CarHatchTrim", hubs + [B(5.9, 0.55, 0.45, 0, 1.4, -5.5, bev=0.15), B(5.9, 0.55, 0.45, 0, 1.4, 5.5, bev=0.15)], CHROME)
mesh("CarHatch", "CarHatchLamps", lamps(-5.45, 2.4, (-1.85, 1.85), r=0.5), LAMP)
mesh("CarHatch", "CarHatchTails", [B(0.8, 0.6, 0.12, x, 2.65, 5.47) for x in (-2.0, 2.0)], TAIL)

hubs = car("CarSedan", [(-5.5, 1.0), (-5.5, 2.5), (-5.0, 2.95), (-2.6, 3.1), (3.6, 3.2), (5.2, 3.1), (5.5, 2.75), (5.5, 1.0)],
           [(-2.5, 3.0), (-1.05, 4.7), (2.15, 4.75), (3.55, 3.05)], (-1.2, 2.3, 4.85),
           [((-2.4, 3.1), (-1.1, 4.7)), ((0.6, 3.1), (0.6, 4.72)), ((2.1, 4.75), (3.45, 3.1))])
mesh("CarSedan", "CarSedanTrim", hubs + [B(5.9, 0.55, 0.45, 0, 1.35, -5.55, bev=0.15), B(5.9, 0.55, 0.45, 0, 1.35, 5.55, bev=0.15),
                                         B(2.6, 0.7, 0.12, 0, 2.2, -5.55)], CHROME)
mesh("CarSedan", "CarSedanLamps", [B(1.2, 0.5, 0.14, x, 2.45, -5.52, bev=0.05) for x in (-1.95, 1.95)], LAMP)
mesh("CarSedan", "CarSedanTails", [B(1.1, 0.5, 0.12, x, 2.55, 5.52) for x in (-1.95, 1.95)], TAIL)

hubs = car("CarTaxi", [(-5.5, 1.0), (-5.5, 2.5), (-5.0, 2.95), (-2.6, 3.1), (3.6, 3.2), (5.2, 3.1), (5.5, 2.75), (5.5, 1.0)],
           [(-2.5, 3.0), (-1.05, 4.7), (2.15, 4.75), (3.55, 3.05)], (-1.2, 2.3, 4.85),
           [((-2.4, 3.1), (-1.1, 4.7)), ((0.6, 3.1), (0.6, 4.72)), ((2.1, 4.75), (3.45, 3.1))], rgb=TAXI)
mesh("CarTaxi", "CarTaxiTrim", hubs + [B(5.9, 0.55, 0.45, 0, 1.35, -5.55, bev=0.15), B(5.9, 0.55, 0.45, 0, 1.35, 5.55, bev=0.15),
                                        B(2.6, 0.7, 0.12, 0, 2.2, -5.55)], CHROME)
chk = []
for k in range(9):  # the checker belt: two rows, offset
    z = -4.4 + k * 1.1
    for row, y in ((0, 2.45), (1, 2.95)):
        if (k + row) % 2 == 0:
            chk += [B(5.86, 0.5, 1.1, 0, y, z)]
chk += [B(2.0, 0.65, 0.95, 0, 5.3, 0.5, bev=0.12)]
mesh("CarTaxi", "CarTaxiChecks", chk, BLACK)
mesh("CarTaxi", "CarTaxiLamps", [B(1.2, 0.5, 0.14, x, 2.45, -5.52, bev=0.05) for x in (-1.95, 1.95)] + [B(1.7, 0.42, 1.05, 0, 5.4, 0.5)],
     LAMP)
mesh("CarTaxi", "CarTaxiTails", [B(1.1, 0.5, 0.12, x, 2.55, 5.52) for x in (-1.95, 1.95)], TAIL)

# ---------------------------------------------------------------- Old Town's little round car: a bubble cabin, round
# headlights on the wings and whitewall tyres
L = "CarBubble"
lo_ = loft_z([(-5.45, 2.2, 1.25, 2.4), (-5.0, 2.75, 0.95, 3.0), (-3.4, 2.95, 0.85, 3.3), (2.6, 2.95, 0.85, 3.35),
              (4.7, 2.8, 0.95, 3.15), (5.45, 2.3, 1.2, 2.7)], segs=14, power=2.6)
cab_ = loft_z([(-2.5, 2.15, 2.8, 3.3), (-1.6, 2.35, 2.8, 4.55), (1.2, 2.45, 2.8, 4.95), (3.3, 2.35, 2.8, 4.5), (4.3, 2.0, 2.8, 3.35)],
              segs=14, power=2.3)
mesh(L, "CarBubbleBody", [lo_, cab_], PAINT)
mesh(L, "CarBubbleGlass", [sides([(-1.35, 3.2), (-0.85, 4.25), (2.55, 4.3), (3.15, 3.2)], 2.4, 0.1),
                           slab((-2.3, 3.35), (-1.45, 4.45), 1.6, inside=(0.5, 3.6)), slab((3.45, 4.35), (4.1, 3.45), 1.5, inside=(0.5, 3.6))], WINDOW)
tyres, hubs = wheels(2.62, (-3.45, 3.45), 1.1, w=0.85, hub=0.62, segs=10, hub_segs=6)
mesh(L, "CarBubbleTyres", tyres, TYRE)
mesh(L, "CarBubbleTrim", hubs + [B(5.4, 0.45, 0.4, 0, 1.45, -5.55, bev=0.18), B(5.4, 0.45, 0.4, 0, 1.45, 5.55, bev=0.18)], CREAM)
mesh(L, "CarBubbleLamps", [S(0.62, x, 2.9, -4.65, sc=(1, 1, 0.8), segs=10, rings=5) for x in (-1.85, 1.85)], LAMP)
mesh(L, "CarBubbleTails", [S(0.34, x, 2.75, 5.3, segs=8, rings=4) for x in (-1.9, 1.9)], TAIL)

# ---------------------------------------------------------------- the tram (over the 9 x 10 x 34 box): the line's
# colour below, a cream window band and roof, a pantograph, both ends alike
L = "Tram"
ends = lambda w, yb, yt: [(-17.0, w - 0.8, yb, yt), (-16.5, w - 0.25, yb, yt), (-15.6, w, yb, yt),
                          (15.6, w, yb, yt), (16.5, w - 0.25, yb, yt), (17.0, w - 0.8, yb, yt)]
mesh(L, "TramBody", [loft_z(ends(4.5, 0.9, 5.3), segs=16, power=5)], PAINT)
mesh(L, "TramGlass", [loft_z([(z, w - 0.06, yb, yt) for (z, w, yb, yt) in ends(4.5, 5.1, 8.5)], segs=16, power=5)], WINDOW)
cream = [loft_z(ends(4.55, 8.4, 9.9), segs=16, power=3.2)]
for z in [-13.2 + k * 2.93 for k in range(10)]:
    cream.append(B(9.16, 3.5, 0.38, 0, 6.8, z))
for z in (-16.0, 16.0):  # the corner posts round each end's windscreen
    for x in (-3.4, 3.4):
        cream.append(B(0.8, 3.5, 0.9, x, 6.8, z * 1.035))
cream += [sides(rect(-15.6, 15.6, 5.1, 5.5), 4.5, 0.08)]
mesh(L, "TramCream", cream, TRAMCREAM)
doors = both(lambda s_: [B(0.14, 6.8, 2.4, s_ * 4.56, 4.45, z) for z in (-8.8, 7.4)])
gear = [B(7.0, 1.3, 4.6, 0, 1.0, z) for z in (-10.5, 10.5)]
gear += [C(0.62, 0.5, x, 0.62, z, segs=8, axis="x") for x in (-3.0, 3.0) for z in (-11.9, -9.1, 9.1, 11.9)]  # the bogies' wheels
gear += [B(3.0, 0.6, 3.0, 0, 10.15, -2.0), B(4.6, 0.9, 6.0, 0, 10.2, 7.5, bev=0.15)]
gear += [T([(x, 10.4, -3.0), (x, 11.6, -1.6), (x, 12.2, -2.6)], 0.11, segs=4) for x in (-1.2, 1.2)]
gear += [T([(-2.2, 12.2, -2.6), (2.2, 12.2, -2.6)], 0.13, segs=4)]
gear += [B(6.4, 0.7, 0.5, 0, 1.6, z) for z in (-17.05, 17.05)]
mesh(L, "TramGear", gear + doors, CHARCOAL)
tl = []
for z, f in ((-17.0, -1), (17.0, 1)):
    tl += lamps(z, 2.6, (-2.4, 2.4), r=0.48, face=f)
    tl.append(B(3.4, 0.7, 0.14, 0, 9.0, z))  # the destination board
mesh(L, "TramLamps", tl, LAMP)

# ---------------------------------------------------------------- the Docks truck (over the 8 x 9 x 20 box): a cab-over
# tractor in the truck's paint and a blue container with ribs
L = "DockTruck"
cab = [(-10.0, 1.5), (-10.0, 7.7), (-9.4, 8.9), (-4.6, 8.9), (-4.6, 1.5)]
mesh(L, "DockTruckBody", [body(cab, 3.85, 0.45)], PAINT)
mesh(L, "DockTruckGlass", [B(6.6, 2.1, 0.14, 0, 6.6, -10.04), sides(rect(-9.5, -7.2, 5.4, 7.7), 3.85)], WINDOW)
box_ = [B(7.7, 7.0, 13.6, 0, 6.15, 3.0, bev=0.12)]
mesh(L, "DockTruckBox", box_, CONTAINER)
rib = []
for z in [-3.2 + k * 1.24 for k in range(11)]:
    rib.append(B(7.95, 6.6, 0.3, 0, 6.15, z))
rib += [B(0.25, 6.6, 0.25, x, 6.15, 9.86) for x in (-1.2, 1.2)]
mesh(L, "DockTruckRibs", rib, (32, 104, 164))
chas = [B(5.6, 1.2, 19.0, 0, 1.55, 0.4)]
tyres, hubs = wheels(3.3, (-7.6, 4.6, 7.6), 1.4, w=1.1, hub=0.65)
mesh(L, "DockTruckTyres", tyres + chas, TYRE)
mesh(L, "DockTruckTrim", hubs + [B(7.4, 0.8, 0.5, 0, 1.7, -10.2, bev=0.15), B(5.0, 2.0, 0.14, 0, 3.6, -10.05),
                                  T([(3.6, 5.0, -4.3), (3.6, 10.0, -4.3)], 0.2, segs=6)], CHROME)
mesh(L, "DockTruckLamps", lamps(-10.0, 2.7, (-2.7, 2.7), r=0.55) + [B(0.7, 0.3, 0.4, x, 9.05, -9.0) for x in (-2.2, 0, 2.2)], LAMP)


# ================================================================ the fit table and the export (as setpieces.py's)
_mine = {o.name for look in LOOKS.values() for o in look.values()}
_stray = [o.name for o in bpy.context.scene.objects if o.type == "MESH" and o.name not in _mine]
assert not _stray, "every shape built belongs to a mesh: " + ", ".join(_stray[:8])
def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


TRIS = {}
rows = []
total = 0
for look in sorted(LOOKS):
    rows.append("\t%s = {" % look)
    for name in sorted(LOOKS[look]):
        ob = LOOKS[look][name]
        lo, hi = bounds(ob)
        c = (lo + hi) / 2
        size = hi - lo
        t = kit.tris(ob)
        TRIS[name] = t
        total += t
        rgb, mat, alpha = INFO[name]
        extra = (", alpha = %g" % alpha) if alpha else ""
        rows.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, mat = \"%s\"%s, tris = %d },"
                    % (name, max(size.x, 0.05), max(size.z, 0.05), max(size.y, 0.05), c.x, c.z, -c.y, rgb[0], rgb[1], rgb[2], mat,
                       extra, t))
    rows.append("\t},")
text = "\n".join([
    "-- GENERATED by art/blender/vehicles.py: do not edit by hand.",
    "-- The side quest escorts and the hub's cars, trams and trucks in Blender meshes (ReplicatedStorage.Art.Vehicles;",
    "-- Shared.SetPieceKit for the escorts, Shared.VehicleKit for the hub): look -> mesh -> its size and its centre from",
    "-- the look's foot point, in studs (x, up, z; nose at -z), its colour (a vehicle's paint may replace a body's),",
    "-- material, transparency and triangles. %d meshes in %d looks, %d triangles." % (len(INFO), len(LOOKS), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "VehicleArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT], check=False)
print("vehicles: %d looks, %d meshes, %d tris" % (len(LOOKS), len(INFO), total))
for look in sorted(LOOKS):
    print("  %-14s %5d tris  (%s)" % (look, sum(TRIS[n] for n in LOOKS[look]), ", ".join(sorted(LOOKS[look]))))

if "--no-export" not in sys.argv:
    export = []
    for look in LOOKS:
        for name, ob in LOOKS[look].items():
            cp = copy(ob)
            cp.name = name + "_x"
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            export.append(cp)
    kit.export_fbx(export, os.path.join(kit.ROOT, "export", "Vehicles.fbx"))
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

# ================================================================ previews
if "--preview" in sys.argv:
    FAST = "--fast" in sys.argv
    ONLY = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    lay_path = os.path.join(kit.ROOT, "export", "vehicles", "layout.json")
    LAYOUT = json.load(open(lay_path)) if os.path.exists(lay_path) else None
    for look in LOOKS.values():
        for ob in look.values():
            ob.hide_render = True
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 8 if FAST else 40
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = (560, 350) if FAST else (760, 475)
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.52, 0.7, 0.95, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    sc.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.6
    sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(38), math.radians(12), math.radians(30))
    sc.collection.objects.link(sun)

    def lin(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    MATS = {}
    ROUGH = {"Wood": 0.7, "Fabric": 0.9, "Glass": 0.05, "Pavement": 0.9, "DiamondPlate": 0.4, "SmoothPlastic": 0.45}

    def mat(rgb, kind="SmoothPlastic", alpha=0.0):
        key = (tuple(int(c) for c in rgb), kind, round(alpha, 2))
        if key in MATS:
            return MATS[key]
        m = bpy.data.materials.new("m%d" % len(MATS))
        m.use_nodes = True
        p = m.node_tree.nodes["Principled BSDF"]
        col = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1)
        p.inputs["Base Color"].default_value = col
        p.inputs["Roughness"].default_value = ROUGH.get(kind, 0.5)
        if kind == "Neon":
            p.inputs["Emission Color"].default_value = col
            p.inputs["Emission Strength"].default_value = 3.0
        if alpha > 0:
            p.inputs["Alpha"].default_value = max(0.05, 1 - alpha)
        MATS[key] = m
        return m

    SHOWN = []

    def keep(o):
        o.hide_render = False
        SHOWN.append(o)
        return o

    def clear():
        for o in SHOWN:
            bpy.data.objects.remove(o, do_unlink=True)
        SHOWN.clear()

    def place_look(look, at, ry=0.0, tint=None):
        M = Matrix.Translation(Vector(rb(*at))) @ Matrix.Rotation(math.radians(ry), 4, "Z")
        tint = tint or {}
        for name, ob in LOOKS[look].items():
            rgb, kind, alpha = INFO[name]
            cp = keep(copy(ob))
            cp.matrix_world = M
            cp.data.materials.clear()
            cp.data.materials.append(mat(tint.get(name, rgb), kind, alpha))

    def draw_box(size, at, rgb, ry=0.0, cyl_x=False, kind="SmoothPlastic", alpha=0.0):
        sx, sy, sz = size
        if cyl_x:
            ob = kit.cyl("bx", sy / 2, sy / 2, sx, at=(0, 0, 0), segs=16, axis="X")
        else:
            ob = kit.box("bx", sx, sz, sy, at=(0, 0, 0))
        turn(ob, "up", 0)
        shift(ob, rb(*at))
        if ry:
            turn(ob, "up", ry)
        keep(ob).data.materials.append(mat(rgb, kind, alpha))
        return ob

    def ground(size, rgb=(150, 150, 146), at=(0, 0, 0)):
        g = keep(kit.box("ground", size, size, 0.4, at=(at[0], -at[2], at[1] - 0.2)))
        g.data.materials.append(mat(rgb, "Pavement"))

    def hero(x, y, z, yaw=0):
        """A blocky 5-stud hero for scale."""
        for (s_, c, rgb) in (((2, 2, 1), (0, 3.0, 0), (60, 120, 220)), ((1.2, 1.2, 1.2), (0, 4.6, 0), SKIN),
                             ((0.95, 2, 1), (-0.5, 1.0, 0), (40, 50, 90)), ((0.95, 2, 1), (0.5, 1.0, 0), (40, 50, 90)),
                             ((1, 2, 1), (-1.5, 3.0, 0), SKIN), ((1, 2, 1), (1.5, 3.0, 0), SKIN)):
            o = kit.box("hero", s_[0], s_[2], s_[1], at=rb(*c))
            move(o, x, y, z, yaw)
            keep(o).data.materials.append(mat(rgb))

    def today(v, at=None):
        """A hub vehicle as VehicleService builds it today (boxes and wheel cylinders), for comparison."""
        sx, sy, sz = v["size"]
        x, y, z = at or v["at"]
        ry = v["ry"]
        col = tuple(v["paint"])
        glass, dark = (70, 96, 120), (30, 32, 38)
        boxes = [((sx, sy * 0.55, sz), (0, sy * 0.275 + 1, 0), col)]
        if v["kind"] == "car":
            boxes.append(((sx * 0.9, sy * 0.4, sz * 0.5), (0, sy * 0.75 + 1, -0.5), glass))
        elif v["kind"] == "truck":
            boxes += [((sx, sy * 0.6, sz * 0.3), (0, sy * 0.6 + 1, -sz * 0.35), glass),
                      ((sx * 0.95, sy * 0.8, sz * 0.6), (0, sy * 0.6 + 1, sz * 0.18), col)]
        else:
            boxes += [((sx * 0.98, sy * 0.35, sz * 0.96), (0, sy * 0.72 + 1, 0), glass), ((sx * 0.6, 0.6, sz * 0.9), (0, sy + 1.3, 0), dark)]
        for (s_, o, c) in boxes:
            ob = draw_box(s_, o, c)
            turn(ob, "up", ry)
            shift(ob, rb(x, y, z))
        wh = min(2.6, sy * 0.45)
        for (a, b) in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
            ob = draw_box((1.2, wh, wh), (a * (sx / 2 - 0.4), wh / 2, b * (sz / 2 - wh)), dark, cyl_x=True)
            turn(ob, "up", ry)
            shift(ob, rb(x, y, z))

    def motorcade(at):
        """The escort's motorcade box today."""
        draw_box((7, 4, 14), (at[0], at[1] + 2.5, at[2]), (30, 30, 40))
        draw_box((6.6, 2.4, 6), (at[0], at[1] + 5.6, at[2] - 2), (90, 70, 160))

    ESC = ["FieldTripBus", "IceCreamTruck", "FerryVan", "NewsVan", "ShowVan", "PartsTruck"]
    CARS = [("CarHatch", {"CarHatchBody": (226, 64, 52)}), ("CarSedan", {"CarSedanBody": (52, 128, 220)}), ("CarTaxi", None),
            ("CarBubble", {"CarBubbleBody": (80, 184, 96)}), ("CarHatch", {"CarHatchBody": (244, 244, 240)}),
            ("CarSedan", {"CarSedanBody": (40, 180, 190)})]

    def row(looks, gap, z=0.0):
        n = len(looks)
        for i, (lk, tint) in enumerate(looks):
            place_look(lk, ((i - (n - 1) / 2) * gap, 0, z), 0, tint)

    def street(dressed):
        """A stretch of Downtown with its parked cars and trams where the game puts them."""
        vs = LAYOUT["vehicles"]

        def near_(c):
            return [v for v in vs if abs(v["at"][0] - c[0]) < 90 and abs(v["at"][2] - c[2]) < 90]

        # the busiest spot with a tram in it (the 40 are spread over the hub, a few to a street)
        c = max((v["at"] for v in vs), key=lambda c: (len(near_(c)), any(w["kind"] == "tram" for w in near_(c)), -c[0]))
        near = near_(c)
        c = [sum(v["at"][k] for v in near) / len(near) for k in range(3)]  # framed on their middle
        ground(320, (64, 66, 74), at=(c[0], c[1], c[2]))
        for v in near:
            if dressed:
                place_look(v["look"], v["at"], v["ry"], v.get("tint"))
            else:
                today(v)
        hero(c[0] + 8, c[1], c[2] + 12, yaw=200)
        return c

    made = []
    SHOTS = ["close_" + e for e in ESC] + ["escorts_back", "escorts_today", "cars", "big", "street", "street_today"]
    CAPTIONS = {
        "close_FieldTripBus": "The Halo Academy field trip bus", "close_IceCreamTruck": "Scoops's ice cream truck",
        "close_FerryVan": "The Gull Point ferry crew's van", "close_NewsVan": "Nora's news van",
        "close_ShowVan": "Ambrose the Astonishing's show van", "close_PartsTruck": "Tinker Tess's parts truck",
        "escorts_back": "The escorts from behind (the other side)", "escorts_today": "An escort today (the motorcade box)",
        "cars": "Hub cars: hatch, sedan, taxi, Old Town bubble", "big": "The tram and the Docks truck",
        "street": "Downtown: the cars and trams where they park", "street_today": "The same street today (the plain parts)",
    }
    for shot in SHOTS:
        if ONLY and ONLY not in shot:
            continue
        if shot in ("street", "street_today") and not LAYOUT:
            print("no layout: run `lune run art/vehicles/layout.luau` first; skipping", shot)
            continue
        if shot.startswith("close_"):
            ground(140, (64, 66, 74))
            place_look(shot[6:], (0, 0, 0), 0)
            hero(6.8, 0, 3.5, yaw=210)
            cam = ((15, 9, -19), (-0.5, 4.0, 0.5), 30)
        elif shot == "escorts_back":
            ground(160, (64, 66, 74))
            for i, e in enumerate(ESC):
                place_look(e, ((i - 2.5) * 10, 0, 0), 0)
            cam = ((-30, 15, 46), (0, 4, 0), 30)
        elif shot == "escorts_today":
            ground(140, (64, 66, 74))
            motorcade((0, 0, 0))
            hero(6.8, 0, 3.5, yaw=210)
            cam = ((15, 9, -19), (-0.5, 4.0, 0.5), 30)
        elif shot == "cars":
            ground(140, (64, 66, 74))
            row(CARS[:4], 8.5)
            hero(-17.5, 0, -4, yaw=210)
            cam = ((18, 10, -30), (0, 2.5, 0), 30)
        elif shot == "big":
            ground(160, (64, 66, 74))
            place_look("Tram", (-7, 0, 0), 0, {"TramBody": (250, 196, 44)})
            place_look("DockTruck", (8, 0, 4), 0, {"DockTruckBody": (226, 64, 52)})
            hero(1, 0, -14, yaw=210)
            cam = ((34, 18, -44), (0, 5, 0), 30)
        else:
            c = street(shot == "street")
            cam = ((c[0] + 60, c[1] + 40, c[2] + 76), (c[0], c[1] + 2, c[2]), 36)
        frm, to, lens = cam
        cm = keep(kit.camera(rb(*frm), rb(*to), lens=lens))
        cm.data.clip_end = 3000
        out = os.path.join(kit.ROOT, "preview", "vehicles_%s.png" % shot)
        kit.render(out)
        made.append((shot, out))
        clear()
    if not ONLY:
        args = json.dumps([[CAPTIONS[s_], p_] for (s_, p_) in made])
        sheet = os.path.join(kit.ROOT, "preview", "vehicles.png")
        code = (
            "import json,sys\n"
            "from PIL import Image, ImageDraw, ImageFont\n"
            "shots=json.loads(sys.argv[1]); out=sys.argv[2]\n"
            "ims=[Image.open(p).convert('RGB') for _,p in shots]\n"
            "w,h=ims[0].size; cols=4; rows=(len(ims)+cols-1)//cols; bar=44\n"
            "sheet=Image.new('RGB',(cols*w,rows*(h+bar)),(24,26,32)); d=ImageDraw.Draw(sheet)\n"
            "try:\n f=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',22)\n"
            "except Exception:\n f=ImageFont.load_default()\n"
            "for i,(im,(cap,_)) in enumerate(zip(ims,shots)):\n"
            " x=(i%cols)*w; y=(i//cols)*(h+bar); sheet.paste(im,(x,y+bar)); d.text((x+14,y+8),cap,fill=(255,236,150),font=f)\n"
            "sheet.save(out)\n"
        )
        subprocess.run(["python3", "-c", code, args, sheet], check=True)
        for (_, p_) in made:
            os.remove(p_)
        print("preview:", sheet)
