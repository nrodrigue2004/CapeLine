# vehicles.py: the side quest escorts and the hub's 40 cars, trams and trucks (remade 2026-11-18 after nate's playtest:
# "vehicles look like trash": plain or grey, too toy-like and blocky). Sleek cartoon vehicles with real detail: curved
# bodies lofted from cross-sections, cut wheel arches, inset windows of tinted see-through glass over simple interiors
# (seats, dash, steering wheel), headlights and tail lights as their own Neon meshes, grilles, bumpers, mirrors, door
# handles, rimmed wheels with treaded tyres, and one baked texture set a look (art/blender/vkit.py: colour with alpha
# where the game's part colour shows through, normal, roughness, metalness; panel seams, rockers and two-tone paint
# painted in, baked occlusion), uploaded as SurfaceAppearances. Original designs: no real makes, badges, logos or
# lettering.
# The game draws a look only once every one of its meshes is imported (Shared.SetPieceKit / Shared.VehicleKit), over
# the vehicle's own parts, which stay hidden and keep the collision, flips, throws and queries exactly as before.
# Looks:
# * the escorts (SetPieceKit.TRUCKS; foot on the road, nose at -z, over the 7 x 14 motorcade box): the Halo Academy
#   field trip bus (FieldTripBus), Scoops's ice cream truck (IceCreamTruck), the Gull Point ferry crew's van
#   (FerryVan), Nora's news van (NewsVan), Ambrose the Astonishing's show van (ShowVan) and Tinker Tess's parts truck
#   (PartsTruck). The farm folk's truck (The Harvest King) is setpieces.py's FarmTruck.
# * the hub (Shared.Vehicles; over VehicleService's boxes): Downtown's CarSedan, CarHatch and CarTaxi, Old Town's
#   CarBubble, the Tram and the Docks' DockTruck. A tinted look's paint is the vehicle's own colour (VehicleKit tints
#   the <Prefix>Body mesh: its paint texels are see-through, so the part colour shows with the baked shading).
# Meshes a look: <Prefix>Body, <Prefix>Detail (textured), <Prefix>Glass, <Prefix>Lamps, <Prefix>Tails (+ Neon extras).
# Output: art/export/Vehicles.fbx (textures embedded), art/export/vehicles/<Look>_{Color,Normal,Roughness,Metalness}.png,
# src/config/VehicleArt.luau; with --preview, art/preview/vehicle_<Look>.png (+ _back), art/preview/vehicles_street.png
# (a Downtown street from art/export/vehicles/layout.json, which `lune run art/vehicles/layout.luau` writes) and the
# sheet art/preview/vehicles.png; --only <Look,...> builds and bakes only those looks (a quick check; no export),
# --fast renders and bakes at low quality.
# Run: python art/blender/vehicles.py [--preview] [--only <Look>] [--fast]   (with the `bpy` module, Blender 5.0)
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402

kit.reset()

import vkit  # noqa: E402
from vkit import (R, P, Look, LOOKS, rbox, bend, boolean, cut_windows, body_loft, stations, smooth_keys, wheel,  # noqa: E402
                  seat, steering, mirror_arm, inward, lathe, gauss)
from studs import rb, C, S, T, TOR, turn, shift, copy, star  # noqa: E402

ONLY = set(sys.argv[sys.argv.index("--only") + 1].split(",")) if "--only" in sys.argv else None
FAST = "--fast" in sys.argv


def want(name):
    return ONLY is None or name in ONLY


# ================================================================ shared regions
TINT = (220, 60, 50)  # a tinted body's colour in the fit table (the game paints each copy)
DARK = R("Dark", (34, 35, 40), 0.75)
RUBBER = R("Rubber", (30, 30, 34), 0.85)
TYRE = R("Tyre", (44, 44, 48), 0.88, pat="tread")
RIM = R("Rim", (196, 202, 210), 0.22, 1.0)
CHROME = R("Chrome", (226, 230, 236), 0.12, 1.0)
HUB = R("Hub", (150, 156, 166), 0.3, 1.0)
GRILLE = R("Grille", (40, 42, 48), 0.5, 0.4, pat="grille")
BLACK = R("BlackTrim", (40, 41, 46), 0.55)
MIRROR = R("MirrorGlass", (150, 170, 190), 0.05, 1.0)
LINER = R("Liner", (104, 100, 106), 0.85)
DASH = R("Dash", (46, 46, 52), 0.7)
WHITEWALL = R("Whitewall", (236, 234, 226), 0.6)
GOLD = R("Gold", (240, 190, 60), 0.25, 1.0)
NAVY = R("Navy", (34, 44, 100), 0.5)
WOOD = R("Wood", (158, 104, 62), 0.75, pat="planks")
BRASS = R("Brass", (226, 168, 58), 0.3, 1.0)


def seat_mat(rgb):
    return R("Seat", rgb, 0.85, pat="fabric")


# ================================================================ seams and paint (texture-space functions of the
# baked object position p (n, 3) and normal n (n, 3), Roblox studs)
def side_v(z0, y0, y1, w=0.03):
    return lambda p, n: gauss(np.abs(p[:, 2] - z0), w) * ((np.abs(n[:, 0]) > 0.35) & (p[:, 1] > y0) & (p[:, 1] < y1))


def side_h(y0, z0, z1, w=0.03):
    return lambda p, n: gauss(np.abs(p[:, 1] - y0), w) * ((np.abs(n[:, 0]) > 0.35) & (p[:, 2] > z0) & (p[:, 2] < z1))


def top_z(z0, xa, w=0.03):
    return lambda p, n: gauss(np.abs(p[:, 2] - z0), w) * ((n[:, 1] > 0.3) & (np.abs(p[:, 0]) < xa))


def top_x(xa, z0, z1, w=0.03):
    return lambda p, n: gauss(np.abs(np.abs(p[:, 0]) - xa), w) * ((n[:, 1] > 0.3) & (p[:, 2] > z0) & (p[:, 2] < z1))


def end_h(y0, face, xa, w=0.03):
    """A line across the nose (face -1) or tail (+1) at height y0."""
    return lambda p, n: gauss(np.abs(p[:, 1] - y0), w) * ((n[:, 2] * face > 0.4) & (np.abs(p[:, 0]) < xa))


def end_v(x0, face, y0, y1, w=0.03):
    """A vertical line on the nose (face -1) or tail (+1) at x0."""
    return lambda p, n: gauss(np.abs(p[:, 0] - x0), w) * ((n[:, 2] * face > 0.4) & (p[:, 1] > y0) & (p[:, 1] < y1))


def disc(sx, y, z, r, w=0.03):
    return lambda p, n: gauss(np.abs(np.sqrt((p[:, 1] - y) ** 2 + (p[:, 2] - z) ** 2) - r), w) * (
        (np.sign(p[:, 0]) == sx) & (np.abs(n[:, 0]) > 0.5))


def rgbf(c):
    return np.array(c, dtype=np.float32) / 255


def paint_tint(rocker=1.0, extra=None):
    """A tinted body: see-through paint (the game's colour), a dark rocker below `rocker`, extra(p, n, rgb, a)."""

    def fn(p, n):
        k = len(p)
        rgb = np.zeros((k, 3), np.float32)
        a = np.zeros(k, np.float32)
        low = p[:, 1] < rocker
        rgb[low] = (0.14, 0.14, 0.16)
        a[low] = 1
        if extra:
            extra(p, n, rgb, a)
        return rgb, a

    return fn


def paint_bands(base, bands, rocker=None):
    """An opaque body: base colour, bands [(y0, y1, rgb)] (lowest first), an optional dark rocker."""

    def fn(p, n):
        k = len(p)
        rgb = np.tile(rgbf(base), (k, 1))
        for (y0, y1, c) in bands:
            m = (p[:, 1] >= y0) & (p[:, 1] < y1)
            rgb[m] = rgbf(c)
        if rocker is not None:
            rgb[p[:, 1] < rocker] = (0.14, 0.14, 0.16)
        return rgb, np.ones(k, np.float32)

    return fn


# ================================================================ the cars (over the 6 x 4.5 x 11 box: body y 1 to 3.5,
# glass to 5.3, wheels under it): a curved lower body and a glass house, unioned, arches cut, windows inset
def car_shell(lower, cabin, arches, paint, n_lower=24, n_cabin=14, segs=24):
    """lower: keys w, yt, yb (lists of (z, v)), p, pb, z0, z1, arch_x; cabin: z0, z1, yt keys, yb, wb, wt, p.
    arches: [(z, y, r)] cut on both sides. Returns the shell and its cabin liner."""
    zs = stations(lower["z0"], lower["z1"], n_lower, 0.55)

    def fl(z):
        w = smooth_keys(lower["w"], z)
        return (w - lower.get("tuck", 0.08), w - lower.get("tumble", 0.16), smooth_keys(lower["yb"], z),
                smooth_keys(lower["yt"], z), lower.get("p", 5.2), lower.get("pb", 6.0))

    lo = P(body_loft(zs, fl, segs), paint)
    zc = stations(cabin["z0"], cabin["z1"], n_cabin, 0.35)

    def fc(z):
        return (cabin["wb"], cabin["wt"], cabin["yb"], smooth_keys(cabin["yt"], z), cabin.get("p", 2.8), 8.0)

    cab = P(body_loft(zc, fc, segs), paint)
    # the cabin liner: the glass house's shape a little inside it, down to the floor, seen from inside
    zl = stations(cabin["z0"] + 0.35, cabin["z1"] - 0.3, 10, 0.2)

    def fli(z):
        wb, wt, yb, yt, p_, pb = fc(z)
        return (min(wb, lower["w"][3][1]) - 0.32, wt - 0.18, lower.get("floor", 1.05), max(yt - 0.14, 2.2), p_, 8.0)

    liner = inward(P(body_loft(zl, fli, 12), LINER))
    boolean(lo, cab, "UNION")
    for (z, y, r) in arches:
        for s_ in (1, -1):
            cut = C(r, 1.9, 0, 0, 0, segs=24, axis="x")
            shift(cut, rb(s_ * lower["arch_x"], y, z))
            P(cut, DARK)
            boolean(lo, cut, "DIFFERENCE")
    return lo, liner


def car_common(lk, wheel_z, r=1.05, wx=2.6, ww=0.95, seat_rgb=(70, 64, 60), rim_m=RIM, white=None, seats=None,
               dash=None, wheel_segs=14):
    """The wheels and the interior every car shares."""
    det = []
    for z in wheel_z:
        for s_ in (1, -1):
            det += wheel(s_ * wx, r, z, r, ww, s_, TYRE, rim_m, HUB, segs=wheel_segs, white=white,
                         spokes=0 if rim_m is CHROME else 5)
            lk.wheels.append((s_ * wx, r, z, r))
    sm = seat_mat(seat_rgb)
    for (x, y, z, w, bench) in seats or []:
        det += seat(x, y, z, w=w, m=sm, bench=bench)
    if dash:
        det.append(P(rbox(*dash, bev=0.15), DASH))
        dy, dz = dash[4], dash[5]
        det += steering(-1.1, dy + 0.2, dz + 0.6, m=BLACK)
    return det


# ---------------------------------------------------------------- the car specs
SEDAN = dict(
    lower=dict(
        z0=-5.55, z1=5.55, arch_x=2.75,
        w=[(-5.55, 2.35), (-5.4, 2.72), (-5.0, 2.92), (-3.4, 3.0), (3.6, 3.0), (5.0, 2.94), (5.4, 2.74), (5.55, 2.4)],
        yt=[(-5.55, 2.3), (-5.35, 2.6), (-4.7, 2.78), (-2.6, 2.98), (-1.9, 3.1), (2.9, 3.28), (3.6, 3.32), (5.0, 3.24),
            (5.4, 3.02), (5.55, 2.72)],
        yb=[(-5.55, 1.3), (-5.35, 0.98), (-4.8, 0.8), (4.8, 0.8), (5.35, 0.98), (5.55, 1.3)],
    ),
    cabin=dict(z0=-2.35, z1=3.95, yb=2.6, wb=2.82, wt=2.12, p=2.9,
               yt=[(-2.35, 2.95), (-1.9, 3.5), (-1.25, 4.22), (-0.55, 4.66), (0.3, 4.8), (1.6, 4.8), (2.4, 4.66),
                   (3.05, 4.22), (3.55, 3.62), (3.95, 3.15)]),
    wheel_z=(-3.5, 3.5),
    windows=[
        lambda c, n: n[2] < -0.42 and c[1] > 3.5 and abs(c[0]) < 1.95,  # windscreen
        lambda c, n: n[2] > 0.42 and c[1] > 3.42 and abs(c[0]) < 1.85,  # rear window
        lambda c, n: abs(n[0]) > 0.6 and 3.36 < c[1] < 4.5 and -1.55 < c[2] < 0.55,  # front doors
        lambda c, n: abs(n[0]) > 0.6 and 3.36 < c[1] < 4.45 and 0.85 < c[2] < 2.75,  # rear doors
    ],
    seams=[side_v(-1.8, 1.0, 3.3), side_v(0.7, 1.0, 3.36), side_v(2.95, 1.0, 3.3), side_h(1.06, -1.8, 2.95),
           top_z(-2.3, 2.5), top_x(2.45, -5.25, -2.3), top_z(3.9, 2.45), top_x(2.4, 3.9, 5.3),
           disc(1, 2.75, 3.95, 0.22), end_h(1.75, -1, 2.4), end_h(1.75, 1, 2.4)],
    mirror=(2.5, 3.38, -1.35), handles=(-0.15, 2.05), handle_y=2.98, seat_rgb=(176, 150, 120),
    lights="swept", tails="wrap", bumper=BLACK, grille=(2.7, 0.62, 2.12),
)

HATCH = dict(
    lower=dict(
        z0=-5.5, z1=5.5, arch_x=2.75,
        w=[(-5.5, 2.4), (-5.3, 2.76), (-4.8, 2.94), (-3.0, 3.0), (4.0, 3.0), (5.1, 2.94), (5.38, 2.8), (5.5, 2.55)],
        yt=[(-5.5, 2.4), (-5.25, 2.66), (-4.4, 2.84), (-2.7, 3.0), (-2.0, 3.12), (3.2, 3.3), (5.1, 3.32), (5.4, 3.2),
            (5.5, 3.0)],
        yb=[(-5.5, 1.3), (-5.25, 0.98), (-4.7, 0.8), (4.8, 0.8), (5.3, 1.0), (5.5, 1.3)],
    ),
    cabin=dict(z0=-2.55, z1=5.36, yb=2.6, wb=2.84, wt=2.18, p=2.8,
               yt=[(-2.55, 3.0), (-2.05, 3.6), (-1.35, 4.35), (-0.6, 4.75), (0.5, 4.88), (3.2, 4.86), (4.3, 4.72),
                   (4.95, 4.34), (5.25, 3.8), (5.36, 3.35)]),
    wheel_z=(-3.45, 3.45),
    windows=[
        lambda c, n: n[2] < -0.42 and c[1] > 3.55 and abs(c[0]) < 1.95,
        lambda c, n: n[2] > 0.5 and c[1] > 3.62 and abs(c[0]) < 1.75,  # the hatch's glass
        lambda c, n: abs(n[0]) > 0.6 and 3.38 < c[1] < 4.5 and -1.75 < c[2] < 1.25,  # the long door
        lambda c, n: abs(n[0]) > 0.6 and 3.4 < c[1] < 4.45 and 1.6 < c[2] < 4.0,  # the rear quarter
    ],
    seams=[side_v(-2.0, 1.0, 3.32), side_v(1.48, 1.0, 3.38), side_h(1.06, -2.0, 1.48), top_z(-2.5, 2.5),
           top_x(2.45, -5.2, -2.5), end_h(2.25, 1, 2.45), disc(1, 2.8, 4.25, 0.22), end_h(1.72, -1, 2.45),
           end_h(1.72, 1, 2.45)],
    mirror=(2.52, 3.42, -1.6), handles=(0.95,), handle_y=3.02, seat_rgb=(56, 58, 66),
    lights="round", tails="tall", bumper=BLACK, grille=(2.4, 0.5, 2.05),
)

BUBBLE = dict(
    lower=dict(
        z0=-5.5, z1=5.5, arch_x=2.7, p=3.4, pb=4.6, tumble=0.2,
        w=[(-5.5, 2.0), (-5.2, 2.5), (-4.4, 2.82), (-2.5, 2.92), (3.0, 2.92), (4.6, 2.8), (5.25, 2.45), (5.5, 2.0)],
        yt=[(-5.5, 2.15), (-5.1, 2.66), (-4.0, 2.95), (-2.5, 3.06), (3.0, 3.1), (4.6, 2.96), (5.2, 2.6), (5.5, 2.15)],
        yb=[(-5.5, 1.45), (-5.1, 1.05), (-4.4, 0.85), (4.4, 0.85), (5.1, 1.05), (5.5, 1.45)],
    ),
    cabin=dict(z0=-2.75, z1=4.45, yb=2.6, wb=2.74, wt=1.86, p=2.3,
               yt=[(-2.75, 2.9), (-2.25, 3.66), (-1.45, 4.46), (-0.35, 4.92), (1.3, 5.02), (2.6, 4.84), (3.6, 4.26),
                   (4.12, 3.6), (4.45, 3.0)]),
    wheel_z=(-3.4, 3.4),
    windows=[
        lambda c, n: n[2] < -0.38 and c[1] > 3.45 and abs(c[0]) < 1.65,
        lambda c, n: n[2] > 0.38 and c[1] > 3.4 and abs(c[0]) < 1.5,
        lambda c, n: abs(n[0]) > 0.55 and 3.35 < c[1] < 4.55 and -1.55 < c[2] < 2.95,
    ],
    seams=[side_v(-1.95, 1.0, 3.3), side_v(1.6, 1.0, 3.34), top_z(-2.7, 2.3), top_x(2.2, -5.0, -2.7),
           top_z(4.4, 2.2), end_h(1.6, -1, 2.0), end_h(1.6, 1, 2.0)],
    mirror=(2.45, 3.4, -1.75), handles=(1.25,), handle_y=2.95, seat_rgb=(196, 64, 52),
    lights="bug", tails="round", bumper=CHROME, grille=(1.6, 0.85, 2.05), whitewall=True, hubcaps=True,
)


def taxi_paint(p, n):
    k = len(p)
    rgb = np.tile(rgbf((255, 204, 32)), (k, 1))
    side = np.abs(n[:, 0]) > 0.5
    band = side & (p[:, 1] > 2.3) & (p[:, 1] < 2.76) & (np.abs(p[:, 2]) < 4.6)
    ch = ((np.floor(p[:, 2] / 0.46) + np.floor((p[:, 1] - 2.3) / 0.23)) % 2) == 0
    rgb[band & ch] = (0.07, 0.07, 0.08)
    rgb[p[:, 1] < 1.02] = (0.14, 0.14, 0.16)
    return rgb, np.ones(k, np.float32)


def bubble_paint(p, n, rgb, a):
    roof = p[:, 1] > 4.4  # a cream roof over the car's colour
    rgb[roof] = rgbf((248, 238, 214))
    a[roof] = 1


def build_car(name, prefix, spec, tint=True, paint=None, taxi=False):
    lk = Look(name, prefix, tint, paint=paint, seams=spec["seams"], body_rgb=TINT if tint else (255, 204, 32))
    pm = R("Paint")
    lw = spec["lower"]
    shell, liner = car_shell(dict(lw), dict(spec["cabin"]), [(z, 1.05, 1.36) for z in spec["wheel_z"]], pm)
    glass = cut_windows(shell, spec["windows"], RUBBER)
    body = [shell]
    det = [liner]
    mx, my, mz = spec["mirror"]
    hy = spec["handle_y"]
    for s_ in (1, -1):
        d_, b_ = mirror_arm(s_, s_ * mx, my, mz, CHROME if spec.get("hubcaps") else pm, MIRROR, BLACK)
        det += d_
        body += b_
        for z in spec["handles"]:
            det.append(P(rbox(0.1, 0.1, 0.5, s_ * 2.97, hy, z, bev=0.04, segs=1), CHROME))
    zf, zb = lw["z0"], lw["z1"]
    bm = spec["bumper"]
    for face, zz in ((-1, zf), (1, zb)):
        if bm is CHROME:  # a chrome bar with overriders
            bp = P(rbox(5.4, 0.42, 0.42, 0, 1.3, zz + face * 0.02, bev=0.19, segs=2), CHROME)
            bend(bp, lambda x, y, z, f=face: (x, y, z - f * 0.09 * x * x))
            det.append(bp)
            for x in (-1.2, 1.2):
                det.append(P(rbox(0.32, 0.75, 0.4, x, 1.45, zz + face * 0.1, bev=0.14, segs=2), CHROME))
        else:
            bp = P(rbox(5.75, 0.62, 0.55, 0, 1.22, zz + face * 0.13, bev=0.22, segs=2), bm)
            bend(bp, lambda x, y, z, f=face: (x, y, z - f * 0.075 * x * x))
            det.append(bp)
            st = P(rbox(4.9, 0.12, 0.1, 0, 1.45, zz + face * 0.43, bev=0.04, segs=1), CHROME)
            bend(st, lambda x, y, z, f=face: (x, y, z - f * 0.075 * x * x))
            det.append(st)
    gw, gh, gy = spec["grille"]
    if spec["lights"] == "bug":  # an upright chrome grille between the wings
        det.append(P(rbox(gw, gh, 0.3, 0, gy, zf + 0.02, bev=0.14, segs=2), CHROME))
        det.append(P(rbox(gw - 0.25, gh - 0.22, 0.3, 0, gy, zf - 0.01, bev=0.06, segs=1),
                     R("Slats", (44, 44, 50), 0.4, 0.6, pat=("slats", 9.0))))
    else:
        det.append(P(rbox(gw, gh, 0.22, 0, gy, zf + 0.05, bev=0.12, segs=2), CHROME))
        det.append(P(rbox(gw - 0.25, gh - 0.2, 0.2, 0, gy, zf + 0.02, bev=0.06, segs=1), GRILLE))
    det.append(P(C(0.13, 0.5, 1.6, 0.85, zb + 0.05, segs=10, axis="z"), CHROME))
    det.append(P(rbox(4.6, 0.12, (zb - zf) - 1.8, 0, 0.78, 0, bev=0.0), DARK))
    seats = [(-1.2, 2.0, 0.25, 1.2, False), (1.2, 2.0, 0.25, 1.2, False), (0, 2.0, 2.35, 4.4, True)]
    if spec.get("hubcaps"):
        seats = [(-1.1, 2.0, 0.6, 1.15, False), (1.1, 2.0, 0.6, 1.15, False), (0, 2.0, 2.5, 3.9, True)]
    det += car_common(lk, spec["wheel_z"], seat_rgb=spec["seat_rgb"], seats=seats,
                      dash=(4.3, 0.6, 0.8, 0, 2.92, spec["cabin"]["z0"] + spec.get("dash_z", 1.1)),
                      white=WHITEWALL if spec.get("whitewall") else None, rim_m=CHROME if spec.get("hubcaps") else RIM)
    lamps, tails = [], []
    for s_ in (1, -1):
        if spec["lights"] == "swept":  # swept headlights in a chrome bezel, following the nose's corner
            for (w_, h_, d_, m_) in ((1.12, 0.4, 0.46, None), (1.3, 0.56, 0.4, CHROME)):
                hl = rbox(w_, h_, d_, s_ * 1.95, 2.5, zf + 0.35 + (0.04 if m_ else 0), bev=0.15 if m_ else 0.17, segs=2)
                bend(hl, lambda x, y, z: (x, y + (abs(x) - 1.95) * 0.12, z + 0.32 * (abs(x) - 1.5) ** 2))
                if m_:
                    det.append(P(hl, m_))
                else:
                    lamps.append(hl)
        elif spec["lights"] == "round":  # round lamps with a chrome ring, set into the nose; fog lamps under
            lamps.append(S(0.42, s_ * 1.95, 2.42, zf + 0.3, sc=(1, 1, 0.55), segs=14, rings=7))
            det.append(P(TOR(0.44, 0.08, s_ * 1.95, 2.42, zf + 0.2, axis="z", segs=16, csegs=4), CHROME))
            lamps.append(rbox(0.5, 0.16, 0.2, s_ * 1.85, 1.62, zf + 0.12, bev=0.06, segs=1))
        else:  # "bug": big round lamps on the wings in chrome cups
            det.append(P(S(0.6, s_ * 1.85, 2.85, zf + 0.75, sc=(1, 1, 0.85), segs=14, rings=8), CHROME))
            lamps.append(S(0.5, s_ * 1.85, 2.85, zf + 0.3, sc=(1, 1, 0.42), segs=14, rings=7))
        if spec["tails"] == "wrap":
            t_ = rbox(1.25, 0.5, 0.36, s_ * 2.12, 2.78, zb - 0.15, bev=0.14, segs=2)
            bend(t_, lambda x, y, z: (x, y, z - 0.28 * (abs(x) - 2.1) ** 2))
            tails.append(t_)
            lamps.append(rbox(0.42, 0.26, 0.2, s_ * 1.2, 2.82, zb - 0.05, bev=0.06, segs=1))
        elif spec["tails"] == "tall":
            tails.append(rbox(0.55, 1.2, 0.34, s_ * 2.55, 2.75, zb - 0.22, bev=0.15, segs=2))
            lamps.append(rbox(0.4, 0.28, 0.2, s_ * 2.55, 2.0, zb - 0.12, bev=0.06, segs=1))
        else:
            tails.append(S(0.34, s_ * 1.9, 2.6, zb - 0.22, sc=(1, 1, 0.6), segs=12, rings=6))
            det.append(P(TOR(0.36, 0.06, s_ * 1.9, 2.6, zb - 0.12, axis="z", segs=14, csegs=4), CHROME))
    if taxi:  # the roof sign: a lit box with checks
        det.append(P(rbox(2.0, 0.18, 0.95, 0, 4.86, 0.95, bev=0.06, segs=1), BLACK))
        det.append(P(rbox(1.9, 0.5, 0.86, 0, 5.18, 0.95, bev=0.12, segs=2), R("TaxiSign", (255, 214, 60), 0.4, pat="checks")))
    lk.add("Body", body)
    lk.add("Detail", det)
    lk.add("Glass", [glass], *lk.glass)
    lk.add("Lamps", lamps, lk.lamp, "Neon")
    lk.add("Tails", tails, lk.tail, "Neon")
    return lk


if want("CarSedan"):
    build_car("CarSedan", "CarSedan", SEDAN, paint=paint_tint(1.02))
if want("CarTaxi"):
    build_car("CarTaxi", "CarTaxi", dict(SEDAN, seat_rgb=(64, 60, 58)), tint=False, paint=taxi_paint, taxi=True)
if want("CarHatch"):
    build_car("CarHatch", "CarHatch", HATCH, paint=paint_tint(1.02))
if want("CarBubble"):
    build_car("CarBubble", "CarBubble", BUBBLE, paint=paint_tint(1.05, bubble_paint))


# ================================================================ box vehicles: trams, trucks, vans and the bus
def van_shell(z0, z1, keys, paint, arches=(), arch_x=3.2, segs=28, n=30, ends=0.5, liner=True, floor=1.3):
    """One lofted shell along z: keys w, yt, yb (lists of (z, v)) and p, pb (numbers or key lists), extra_z (more
    stations); arches [(z, y, r)] cut both sides. Returns the shell and its liner (seen from inside)."""
    zs = sorted(set([round(z, 4) for z in stations(z0, z1, n, ends) + list(keys.get("extra_z", []))]))

    def kv(k, z, d):
        v = keys.get(k, d)
        return smooth_keys(v, z) if isinstance(v, list) else v

    def f(z):
        w = kv("w", z, 3.4)
        return (w - kv("tuck", z, 0.06), w - kv("tumble", z, 0.18), kv("yb", z, 1.0), kv("yt", z, 7.0),
                kv("p", z, 5.0), kv("pb", z, 6.0))

    sh = P(body_loft(zs, f, segs), paint)
    ln = None
    if liner:
        a, b = keys.get("liner_in", (0.5, 0.5))
        zl = stations(z0 + a, z1 - b, 12, 0.2)

        def fl(z):
            wb, wt, yb, yt, p_, pb = f(z)
            return (wb - 0.3, wt - 0.3, floor, yt - 0.25, p_, 8.0)

        ln = inward(P(body_loft(zl, fl, 16), LINER))
    for (z, y, r) in arches:
        for s_ in (1, -1):
            cut = C(r, 2.0, 0, 0, 0, segs=24, axis="x")
            shift(cut, rb(s_ * arch_x, y, z))
            P(cut, DARK)
            boolean(sh, cut, "DIFFERENCE")
    return sh, ln


def bays(z0, z1, n, gap):
    """n window bays from z0 to z1 with `gap` pillars between: [(a, b)]."""
    w = (z1 - z0 - gap * (n - 1)) / n
    return [(z0 + k * (w + gap), z0 + k * (w + gap) + w) for k in range(n)]


def in_bays(z, bs):
    return any(a < z < b for (a, b) in bs)


def benches(xs, zs, y, w, m, back=1.1):
    out = []
    for x in xs:
        for z in zs:
            out += seat(x, y, z, w=w, d=0.95, h=back, m=m, bench=True, back_tilt=8)
    return out


def axle_wheels(lk, zs, r, w, x, rim=None, white=None, segs=16, spokes=5):
    out = []
    for z in zs:
        for s_ in (1, -1):
            out += wheel(s_ * x, r, z, r, w, s_, TYRE, rim or RIM, HUB, segs=segs, spokes=spokes, white=white)
            lk.wheels.append((s_ * x, r, z, r))
    return out


def round_lamp(x, y, z, r, face=-1, ring=CHROME, det=None, lamps=None):
    lamps.append(S(r, x, y, z, sc=(1, 1, 0.5), segs=14, rings=7))
    det.append(P(TOR(r * 1.04, r * 0.16, x, y, z - face * 0.1, axis="z", segs=16, csegs=4), ring))


def rect_lamp(x, y, z, w, h, d=0.3, out=None, bezel=None, det=None):
    out.append(rbox(w, h, d, x, y, z, bev=min(w, h) * 0.3, segs=2))
    if bezel is not None:
        det.append(P(rbox(w + 0.16, h + 0.16, d * 0.8, x, y, z + 0.06, bev=min(w, h) * 0.3, segs=2), bezel))


def finish(lk, body, det, glass, lamps, tails, extra=None):
    lk.add("Body", body)
    lk.add("Detail", det)
    if glass:
        lk.add("Glass", glass if isinstance(glass, list) else [glass], *lk.glass)
    lk.add("Lamps", lamps, lk.lamp, "Neon")
    lk.add("Tails", tails, lk.tail, "Neon")
    for (role, parts, rgb, mat) in extra or []:
        lk.add(role, parts, rgb, mat)
    return lk


# ---------------------------------------------------------------- the tram (over the 9 x 10 x 34 box): the line's
# colour below, a cream window band and roof, a pantograph, both ends alike
TRAM_DOORS = [(-10.7, -8.3), (6.8, 9.2)]
TRAM_BAYS = [b for b in bays(-14.6, 14.6, 10, 0.34) if not any(b[1] > a - 0.3 and b[0] < c + 0.3 for (a, c) in TRAM_DOORS)]


def tram_paint(p, n):
    k = len(p)
    rgb = np.zeros((k, 3), np.float32)
    a = np.zeros(k, np.float32)
    cream = p[:, 1] > 5.3
    rgb[cream] = rgbf((250, 240, 214))
    a[cream] = 1
    stripe = (p[:, 1] > 5.02) & (p[:, 1] <= 5.3)
    rgb[stripe] = rgbf((40, 42, 50))
    a[stripe] = 1
    low = p[:, 1] < 1.35
    rgb[low] = (0.16, 0.16, 0.18)
    a[low] = 1
    return rgb, a


def tram_seams():
    out = []
    for (a, b) in TRAM_DOORS:
        out += [side_v(a, 1.35, 8.5), side_v(b, 1.35, 8.5), side_v((a + b) / 2, 1.35, 8.4), side_h(8.5, a, b)]
    for z in (-15.2, 15.2):
        out.append(side_v(z, 1.35, 5.0))
    return out


if want("Tram"):
    lk = Look("Tram", "Tram", True, paint=tram_paint, seams=tram_seams(), body_rgb=TINT)
    pm = R("Paint")
    keys = dict(
        w=[(-17.0, 3.3), (-16.6, 4.05), (-15.9, 4.45), (15.9, 4.45), (16.6, 4.05), (17.0, 3.3)],
        yt=[(-17.0, 9.0), (-16.5, 9.62), (-15.6, 9.9), (15.6, 9.9), (16.5, 9.62), (17.0, 9.0)],
        yb=[(-17.0, 1.45), (-16.6, 1.1), (-16.0, 0.95), (16.0, 0.95), (16.6, 1.1), (17.0, 1.45)],
        p=6.5, pb=9.0, tumble=0.22, liner_in=(0.7, 0.7))
    shell, liner = van_shell(-17.0, 17.0, keys, pm, n=34, ends=0.75, floor=1.4)
    glass = cut_windows(shell, [
        lambda c, n: abs(n[0]) > 0.75 and 5.65 < c[1] < 8.3 and in_bays(c[2], TRAM_BAYS),
        lambda c, n: abs(n[0]) > 0.75 and 2.9 < c[1] < 8.25 and any(a + 0.12 < c[2] < b - 0.12 for (a, b) in TRAM_DOORS),
        lambda c, n: n[2] < -0.55 and 5.4 < c[1] < 8.45 and abs(c[0]) < 3.3,
        lambda c, n: n[2] > 0.55 and 5.4 < c[1] < 8.45 and abs(c[0]) < 3.3,
    ], RUBBER, frame=0.1)
    det = [liner]
    sm = seat_mat((150, 60, 52))
    rows = [z for z in [-14.2 + k * 1.65 for k in range(18)] if not any(a - 0.7 < z < b + 0.5 for (a, b) in TRAM_DOORS)]
    det += benches((-2.35, 2.35), rows, 2.9, 2.4, sm)
    for z in (-11.0, 11.0):  # the bogies: frame, springs and four wheels
        det.append(P(rbox(6.4, 0.9, 4.6, 0, 1.05, z, bev=0.12, segs=1), DARK))
        for x in (-3.15, 3.15):
            for dz in (-1.4, 1.4):
                det.append(P(C(0.62, 0.42, x, 0.62, z + dz, segs=14, axis="x"), HUB))
            det.append(P(rbox(0.3, 0.5, 3.6, x * 1.08, 0.75, z, bev=0.08, segs=1), BLACK))
    # the roof: equipment, the pantograph (two arms and the head), a rail along each side
    gear_m = R("RoofGear", (150, 156, 166), 0.5, 0.6)
    det.append(P(rbox(3.4, 0.6, 3.4, 0, 10.15, -3.0, bev=0.14, segs=2), gear_m))
    det.append(P(rbox(4.6, 0.85, 6.4, 0, 10.25, 7.0, bev=0.2, segs=2), gear_m))
    pant = R("Pantograph", (60, 64, 74), 0.5, 0.7)
    for x in (-1.3, 1.3):
        det.append(P(T([(x, 10.4, -3.6), (x, 11.0, -2.3), (x, 11.55, -3.2)], 0.09, segs=5), pant))
    det.append(P(T([(-2.3, 11.6, -3.2), (2.3, 11.6, -3.2)], 0.12, segs=5), pant))
    det.append(P(rbox(1.0, 0.2, 0.6, 0, 10.45, -3.6, bev=0.05, segs=1), pant))
    for x in (-3.9, 3.9):
        det.append(P(T([(x, 9.85, -15.0), (x, 9.85, 15.0)], 0.06, segs=4), CHROME))
    lamps, tails = [], []
    for face in (-1, 1):
        zz = face * 17.0
        for x in (-2.4, 2.4):
            round_lamp(x, 2.7, zz + face * -0.25, 0.42, face=face, det=det, lamps=lamps)
            tails.append(rbox(0.5, 0.3, 0.2, x * 1.25, 1.95, zz - face * 0.16, bev=0.08, segs=1))
        lamps.append(rbox(3.6, 0.62, 0.2, 0, 8.95, zz - face * 0.28, bev=0.1, segs=1))  # the destination board
        det.append(P(rbox(3.9, 0.82, 0.22, 0, 8.95, zz - face * 0.22, bev=0.1, segs=1), BLACK))
        bp = P(rbox(6.6, 0.55, 0.55, 0, 1.45, zz - face * 0.12, bev=0.2, segs=2), BLACK)
        bend(bp, lambda x, y, z, f=face: (x, y, z - f * 0.06 * x * x))
        det.append(bp)
    for s_ in (1, -1):  # grab rails by the doors
        for (a, b) in TRAM_DOORS:
            det.append(P(T([(s_ * 4.42, 3.0, a - 0.2), (s_ * 4.42, 6.6, a - 0.2)], 0.05, segs=4), CHROME))
    finish(lk, [shell], det, glass, lamps, tails)


# ---------------------------------------------------------------- the Docks truck (over the 8 x 9 x 20 box): a cab-over
# tractor in the truck's paint and a ribbed blue container
def truck_paint(p, n):
    k = len(p)
    rgb = np.zeros((k, 3), np.float32)
    a = np.zeros(k, np.float32)
    low = p[:, 1] < 2.35
    rgb[low] = (0.15, 0.15, 0.17)
    a[low] = 1
    stripe = (np.abs(n[:, 0]) > 0.5) & (p[:, 1] > 3.3) & (p[:, 1] < 3.6)
    rgb[stripe] = (0.95, 0.95, 0.93)
    a[stripe] = 1
    return rgb, a


if want("DockTruck"):
    lk = Look("DockTruck", "DockTruck", True, paint=truck_paint, body_rgb=TINT,
              seams=[side_v(-6.9, 2.3, 7.9), side_v(-9.7, 2.3, 7.6), side_h(2.36, -9.7, -6.9), end_h(4.9, -1, 3.4)])
    pm = R("Paint")
    keys = dict(
        w=[(-10.15, 3.3), (-9.85, 3.78), (-9.3, 3.92), (-4.7, 3.92), (-4.55, 3.7)],
        yt=[(-10.15, 7.8), (-9.85, 8.6), (-9.2, 8.95), (-4.8, 8.95), (-4.55, 8.7)],
        yb=[(-10.15, 1.9), (-9.8, 1.7), (-4.6, 1.7)],
        p=7.0, pb=9.0, tumble=0.2, liner_in=(0.5, 0.35))
    shell, liner = van_shell(-10.15, -4.55, keys, pm, arches=[(-7.6, 1.4, 1.75)], arch_x=3.7, n=18, ends=0.6, floor=2.5)
    glass = cut_windows(shell, [
        lambda c, n: n[2] < -0.55 and 5.3 < c[1] < 8.1 and abs(c[0]) < 3.35 and abs(c[0]) > 0.1,
        lambda c, n: abs(n[0]) > 0.75 and 5.3 < c[1] < 7.95 and -9.45 < c[2] < -7.1,
    ], RUBBER, frame=0.1)
    det = [liner]
    det += seat(-1.6, 4.2, -7.3, w=1.4, m=seat_mat((60, 62, 70)))
    det += seat(1.6, 4.2, -7.3, w=1.4, m=seat_mat((60, 62, 70)))
    det.append(P(rbox(6.4, 0.7, 0.9, 0, 5.0, -9.2, bev=0.15, segs=1), DASH))
    det += steering(-1.6, 5.35, -8.6, r=0.5, m=BLACK, tilt=40)
    # the face: a big chrome grille, a steel bumper, steps and the sun visor
    steel = R("Steel", (176, 182, 192), 0.3, 0.9)
    det.append(P(rbox(5.0, 2.3, 0.3, 0, 3.7, -10.12, bev=0.18, segs=2), CHROME))
    det.append(P(rbox(4.6, 1.95, 0.3, 0, 3.7, -10.16, bev=0.08, segs=1),
                 R("TruckGrille", (36, 38, 44), 0.45, 0.5, pat=("slats", 4.0))))
    det.append(P(rbox(7.9, 0.95, 0.7, 0, 1.75, -10.1, bev=0.25, segs=2), steel))
    det.append(P(rbox(7.4, 0.35, 0.8, 0, 9.05, -9.95, bev=0.1, segs=1), BLACK))  # the sun visor
    for s_ in (1, -1):
        det.append(P(rbox(0.9, 0.18, 0.8, s_ * 3.5, 2.6, -6.4, bev=0.05, segs=1), CHROME))  # steps
        det.append(P(T([(s_ * 3.95, 7.5, -9.0), (s_ * 4.45, 7.2, -9.3)], 0.06, segs=4), CHROME))
        det.append(P(rbox(0.25, 1.6, 0.6, s_ * 4.5, 6.8, -9.3, bev=0.08, segs=1), BLACK))  # mirrors
        det.append(P(rbox(0.04, 1.35, 0.45, s_ * 4.64, 6.8, -9.3, bev=0.0), MIRROR))
    # chassis: rails, fuel tanks, air tanks, the exhaust stack
    det.append(P(rbox(3.0, 0.8, 19.0, 0, 1.75, 0.0, bev=0.1, segs=1), DARK))
    for s_ in (1, -1):
        det.append(P(C(0.75, 2.6, s_ * 2.85, 1.75, -4.0, segs=14, axis="z"), R("Tank", (210, 214, 222), 0.25, 1.0)))
        det.append(P(C(0.35, 1.8, s_ * 2.4, 1.3, 0.4, segs=10, axis="z"), DARK))
    det.append(P(C(0.28, 4.6, 3.1, 6.7, -4.25, segs=10), CHROME))
    det.append(P(C(0.34, 0.7, 3.1, 9.2, -4.25, segs=10), BLACK))
    # the container: ribbed walls, corner posts, rails and the doors' lock bars
    det.append(P(rbox(7.7, 7.0, 14.3, 0, 6.15, 2.95, bev=0.08, segs=1),
                 R("Container", (44, 132, 196), 0.6, 0.15, pat="corrugate")))
    frame = R("ContainerFrame", (32, 98, 150), 0.55, 0.2)
    for x in (-3.8, 3.8):
        for z in (-4.2, 10.1):
            det.append(P(rbox(0.32, 7.1, 0.32, x, 6.15, z, bev=0.04, segs=1), frame))
        for y in (2.7, 9.6):
            det.append(P(rbox(0.3, 0.3, 14.4, x, y, 2.95, bev=0.04, segs=1), frame))
    for x in (-2.6, -0.9, 0.9, 2.6):
        det.append(P(T([(x, 2.9, 10.18), (x, 9.4, 10.18)], 0.07, segs=5), CHROME))
    det.append(P(rbox(0.06, 6.8, 0.05, 0, 6.15, 10.12, bev=0.0), DARK))
    det.append(P(rbox(7.6, 0.4, 0.5, 0, 1.75, 10.0, bev=0.1, segs=1), steel))
    for s_ in (1, -1):  # mud flaps
        det.append(P(rbox(0.9, 1.2, 0.08, s_ * 3.3, 1.0, 9.0, bev=0.0), RUBBER))
    det += axle_wheels(lk, (-7.6,), 1.4, 1.15, 3.35)
    det += axle_wheels(lk, (4.5, 7.5), 1.4, 1.35, 3.25)
    det.append(P(rbox(1.0, 0.35, 0.9, -3.5, 2.55, -5.3, bev=0.06, segs=1), DARK))
    lamps, tails = [], []
    for s_ in (1, -1):
        rect_lamp(s_ * 2.85, 2.8, -10.18, 1.2, 0.6, out=lamps, bezel=CHROME, det=det)
        tails.append(rbox(0.7, 0.35, 0.15, s_ * 3.1, 2.25, 10.25, bev=0.08, segs=1))
    for x in (-2.4, -1.2, 0, 1.2, 2.4):  # cab marker lights
        lamps.append(rbox(0.42, 0.22, 0.3, x, 9.0, -9.25, bev=0.06, segs=1))
    finish(lk, [shell], det, glass, lamps, tails)


# ================================================================ the escorts (SetPieceKit.TRUCKS): foot on the road,
# nose at -z, over the motorcade box (7 x 4 x 14 at y 2.5 and the 6.6 x 2.4 x 6 cab at y 5.6, z -2)
YB = [(-7.25, 1.6), (-7.0, 1.2), (-6.4, 1.05), (6.6, 1.05), (7.25, 1.45)]


def mirrors_big(det, z, y, x=3.55):
    for s_ in (1, -1):
        det.append(P(T([(s_ * x, y - 0.6, z), (s_ * (x + 0.55), y - 0.3, z - 0.25), (s_ * (x + 0.55), y + 0.8, z - 0.25)],
                       0.05, segs=4), CHROME))
        det.append(P(rbox(0.28, 1.3, 0.6, s_ * (x + 0.62), y + 0.2, z - 0.25, bev=0.1, segs=1), BLACK))
        det.append(P(rbox(0.04, 1.1, 0.46, s_ * (x + 0.62), y + 0.2, z - 0.05, bev=0.0), MIRROR))


def end_bumpers(det, zf, zb, w=6.8, y=1.35, m=CHROME):
    for face, zz in ((-1, zf), (1, zb)):
        bp = P(rbox(w, 0.55, 0.5, 0, y, zz + face * 0.12, bev=0.2, segs=2), m)
        bend(bp, lambda x, y_, z, f=face: (x, y_, z - f * 0.05 * x * x))
        det.append(bp)


if want("FieldTripBus"):
    lk = Look("FieldTripBus", "Bus", False, body_rgb=(255, 196, 28),
              paint=paint_bands((255, 196, 28), [(2.35, 2.55, (30, 30, 34)), (3.55, 3.72, (30, 30, 34)),
                                                 (6.95, 99, (246, 246, 242))], rocker=1.45),
              seams=[side_v(-4.38, 2.6, 6.6), side_v(-3.72, 2.6, 6.6), side_v(-3.05, 2.6, 6.6), top_x(2.3, -7.0, -4.95),
                     end_v(0, 1, 1.6, 6.6), end_v(-1.3, 1, 1.6, 6.6), end_v(1.3, 1, 1.6, 6.6), end_h(1.75, 1, 3.2)])
    pm = R("Paint")
    keys = dict(
        w=[(-7.25, 2.55), (-7.0, 2.9), (-5.0, 2.95), (-4.85, 3.0), (-4.6, 3.5), (7.0, 3.5), (7.25, 3.25)],
        yt=[(-7.25, 3.4), (-7.0, 3.8), (-5.3, 4.0), (-4.85, 4.1), (-4.62, 6.6), (-4.4, 7.05), (6.9, 7.05), (7.25, 6.7)],
        yb=YB, p=[(-7.25, 4.0), (-4.8, 4.0), (-4.5, 7.0)], pb=8.0, tumble=0.12, liner_in=(2.6, 0.4),
        extra_z=[-4.9, -4.8, -4.7, -4.62, -4.55, -4.45])
    shell, liner = van_shell(-7.25, 7.25, keys, pm, arches=[(-5.45, 1.25, 1.55), (4.3, 1.25, 1.55)], arch_x=3.4, n=34,
                             ends=0.35, floor=1.5)
    side_bays = bays(-2.75, 6.5, 5, 0.32)
    glass = cut_windows(shell, [
        lambda c, n: n[2] < -0.6 and 4.4 < c[1] < 6.5 and 0.1 < abs(c[0]) < 3.05,
        lambda c, n: abs(n[0]) > 0.75 and 4.45 < c[1] < 6.45 and in_bays(c[2], side_bays),
        lambda c, n: n[0] > 0.75 and 3.05 < c[1] < 6.45 and -4.32 < c[2] < -3.1,  # the door
        lambda c, n: n[0] < -0.75 and 4.45 < c[1] < 6.45 and -4.32 < c[2] < -3.1,  # the driver's window
        lambda c, n: n[2] > 0.6 and 4.6 < c[1] < 6.4 and 0.12 < abs(c[0]) < 2.4,
    ], RUBBER, frame=0.09)
    det = [liner]
    det += benches((-1.75, 1.75), [-2.4 + k * 1.6 for k in range(6)], 2.6, 2.3, seat_mat((40, 70, 150)))
    det += seat(-1.8, 2.6, -3.7, w=1.1, m=seat_mat((60, 60, 66)))
    det.append(P(rbox(6.2, 0.6, 0.8, 0, 3.9, -4.3, bev=0.12, segs=1), DASH))
    det += steering(-1.8, 4.3, -3.9, r=0.45, m=BLACK, tilt=40)
    det.append(P(rbox(3.4, 1.35, 0.3, 0, 2.6, -7.25, bev=0.14, segs=2), CHROME))
    det.append(P(rbox(3.1, 1.1, 0.3, 0, 2.6, -7.3, bev=0.06, segs=1), R("BusGrille", (36, 38, 44), 0.45, 0.5, pat=("slats", 5.0))))
    end_bumpers(det, -7.25, 7.25, w=6.6, m=BLACK)
    mirrors_big(det, -6.6, 4.3, x=3.0)
    stop = P(C(0.72, 0.1, -3.62, 4.3, -3.6, segs=8, axis="x"), R("StopRed", (214, 36, 40), 0.45))
    turn(stop, "x", 22.5, (-3.62, 4.3, -3.6))
    det.append(stop)
    det.append(P(C(0.76, 0.08, -3.6, 4.3, -3.6, segs=8, axis="x"), R("White", (244, 244, 240), 0.5)))
    # the academy's sign on the roof: a navy board, a gold star each side, the gold halo floating over it
    det.append(P(rbox(0.55, 1.35, 5.4, 0, 7.75, 1.0, bev=0.15, segs=2), NAVY))
    for s_ in (1, -1):
        st_ = star(0.55, 0.23, 0.1, 0, 0, 0)
        turn(st_, "up", 90)
        shift(st_, rb(s_ * 0.32, 7.75, 1.0))
        det.append(P(st_, GOLD))
        st2 = star(0.9, 0.38, 0.12, 0, 0, 0)
        turn(st2, "up", 90)
        shift(st2, rb(s_ * 3.56, 3.05, 1.2))
        det.append(P(st2, GOLD))
    halo = TOR(1.3, 0.2, 0, 0, 0, segs=24, csegs=6)
    turn(halo, "x", -12)
    shift(halo, rb(0, 9.2, 1.0))
    det.append(P(halo, GOLD))
    det += axle_wheels(lk, (-5.45, 4.3), 1.25, 1.0, 2.95)
    lamps, tails, amber = [], [], []
    for s_ in (1, -1):
        round_lamp(s_ * 2.15, 2.75, -7.22, 0.42, det=det, lamps=lamps)
        amber.append(S(0.28, s_ * 2.5, 6.75, -4.6, sc=(1, 1, 0.6), segs=10, rings=5))
        tails.append(S(0.28, s_ * 2.5, 6.75, 7.2, sc=(1, 1, 0.6), segs=10, rings=5))
        tails.append(rbox(0.6, 0.6, 0.2, s_ * 2.6, 2.3, 7.2, bev=0.1, segs=1))
    finish(lk, [shell], det, glass, lamps, tails, extra=[("Amber", amber, (255, 170, 40), "Neon")])

if want("IceCreamTruck"):
    def ice_paint(p, n):
        k = len(p)
        rgb = np.tile(rgbf((140, 228, 200)), (k, 1))
        top = 2.72 + 0.12 * np.sin(p[:, 2] * 2.8)
        band = (p[:, 1] > 1.95) & (p[:, 1] < top)
        rgb[band] = rgbf((255, 118, 176))
        rgb[p[:, 1] > 6.7] = rgbf((248, 248, 244))
        rgb[p[:, 1] < 1.4] = (0.15, 0.15, 0.17)
        return rgb, np.ones(k, np.float32)

    lk = Look("IceCreamTruck", "Ice", False, paint=ice_paint, body_rgb=(140, 228, 200), seams=[
        side_v(-3.5, 1.4, 6.3), side_v(-5.6, 1.4, 4.2), top_x(2.3, -7.0, -5.8), end_v(0, 1, 1.5, 6.5),
        end_h(1.75, 1, 3.0)])
    pm = R("Paint")
    keys = dict(
        w=[(-7.2, 2.7), (-6.95, 3.05), (-6.0, 3.1), (-5.6, 3.45), (6.95, 3.45), (7.2, 3.15)],
        yt=[(-7.2, 3.3), (-6.95, 3.7), (-6.1, 3.85), (-5.75, 4.3), (-4.75, 6.45), (-4.4, 6.85), (6.85, 6.85), (7.2, 6.4)],
        yb=YB, p=[(-7.2, 4.0), (-5.7, 4.5), (-5.0, 6.5)], pb=8.0, tumble=0.14, liner_in=(1.6, 0.4),
        extra_z=[-5.8, -5.6, -5.3, -5.0, -4.7])
    shell, liner = van_shell(-7.2, 7.2, keys, pm, arches=[(-5.2, 1.25, 1.55), (4.6, 1.25, 1.55)], arch_x=3.4, n=32,
                             ends=0.35, floor=1.5)
    glass = cut_windows(shell, [
        lambda c, n: n[2] < -0.4 and c[1] > 4.25 and 0.1 < abs(c[0]) < 2.9,
        lambda c, n: abs(n[0]) > 0.7 and 4.05 < c[1] < 6.0 and -5.35 < c[2] < -3.7,
        lambda c, n: n[0] > 0.75 and 3.9 < c[1] < 5.9 and -1.4 < c[2] < 3.4,  # the serving window
        lambda c, n: n[2] > 0.6 and 4.4 < c[1] < 6.2 and 0.12 < abs(c[0]) < 2.5,
    ], RUBBER, frame=0.09)
    det = [liner]
    det += seat(-1.7, 2.7, -4.4, w=1.2, m=seat_mat((240, 120, 170)))
    det.append(P(rbox(5.8, 0.6, 0.8, 0, 3.8, -5.3, bev=0.12, segs=1), DASH))
    det += steering(-1.7, 4.1, -4.8, r=0.42, m=BLACK, tilt=45)
    det.append(P(rbox(1.6, 2.0, 4.4, 1.6, 2.5, 1.0, bev=0.15, segs=1), R("Freezer", (232, 238, 242), 0.35)))
    det.append(P(rbox(0.8, 0.12, 5.0, 3.75, 3.85, 1.0, bev=0.04, segs=1), CHROME))  # the counter
    aw = P(rbox(1.7, 0.12, 5.4, 4.3, 6.05, 1.0, bev=0.04, segs=1),
           R("Awning", (255, 118, 176), 0.7, pat=("stripes", (250, 250, 246), 0.6)))
    turn(aw, "z", -22, (3.45, 6.35, 1.0))
    det.append(aw)
    for z in (-1.5, 3.5):
        det.append(P(T([(3.47, 6.3, z), (4.95, 5.7, z)], 0.05, segs=4), CHROME))
    # the giant cone on the roof: waffle, a drippy scoop with sprinkles and a cherry
    scoop = R("Scoop", (255, 150, 190), 0.55, pat="sprinkles")
    det.append(P(C(0.15, 2.5, 0, 8.1, 1.2, segs=16, r2=1.15), R("Waffle", (224, 166, 92), 0.7, pat="waffle")))
    det.append(P(S(1.32, 0, 9.85, 1.2, sc=(1, 0.92, 1), segs=18, rings=10), scoop))
    det.append(P(TOR(1.15, 0.26, 0, 9.35, 1.2, segs=18, csegs=6), scoop))
    det.append(P(S(0.34, 0, 11.3, 1.2, segs=10, rings=6), R("Cherry", (220, 30, 44), 0.25)))
    det.append(P(T([(0, 11.55, 1.2), (0.15, 12.0, 1.35)], 0.04, segs=4), R("Stem", (80, 120, 50), 0.6)))
    det.append(P(C(0.12, 0.8, 0, 7.25, -4.0, segs=10, r2=0.45), CHROME))  # the chime horn
    det.append(P(rbox(1.8, 0.9, 0.3, 0, 2.55, -7.2, bev=0.12, segs=2), CHROME))
    det.append(P(rbox(1.55, 0.65, 0.3, 0, 2.55, -7.25, bev=0.06, segs=1), GRILLE))
    end_bumpers(det, -7.2, 7.2, w=6.6)
    mirrors_big(det, -5.5, 4.4, x=3.3)
    det += axle_wheels(lk, (-5.2, 4.6), 1.25, 1.0, 2.95)
    lamps, tails = [], []
    for s_ in (1, -1):
        round_lamp(s_ * 2.15, 2.8, -7.12, 0.44, det=det, lamps=lamps)
        tails.append(S(0.3, s_ * 2.6, 2.6, 7.15, sc=(1, 1, 0.6), segs=10, rings=5))
        tails.append(S(0.3, s_ * 2.6, 3.3, 7.15, sc=(1, 1, 0.6), segs=10, rings=5))
    finish(lk, [shell], det, glass, lamps, tails)

if want("FerryVan"):
    lk = Look("FerryVan", "Ferry", False, body_rgb=(30, 52, 112), rings=[(3.62, 3.0, 2.3, 0.45, 0.95, "x")],
              paint=paint_bands((246, 246, 244), [(-99, 3.75, (30, 52, 112)), (3.75, 3.95, (226, 44, 44))]),
              seams=[side_v(-4.9, 1.4, 6.4), side_v(-2.4, 1.4, 6.4), side_v(0.3, 1.4, 6.4), end_v(0, 1, 1.5, 6.4)])
    pm = R("Paint")
    keys = dict(
        w=[(-7.15, 2.85), (-6.95, 3.28), (-6.4, 3.45), (6.8, 3.45), (7.1, 3.1)],
        yt=[(-7.15, 5.7), (-6.95, 6.35), (-6.4, 6.85), (6.6, 6.9), (7.1, 6.35)],
        yb=[(-7.15, 1.6), (-6.95, 1.2), (-6.3, 1.05), (6.5, 1.05), (7.1, 1.5)], p=3.6, pb=6.0, tumble=0.25,
        liner_in=(0.6, 0.5))
    shell, liner = van_shell(-7.15, 7.1, keys, pm, arches=[(-4.6, 1.25, 1.55), (4.6, 1.25, 1.55)], arch_x=3.4, n=26,
                             ends=0.6, floor=1.5, segs=24)
    sb = bays(-4.4, 6.1, 4, 0.42)
    glass = cut_windows(shell, [
        lambda c, n: n[2] < -0.35 and 4.25 < c[1] < 6.1 and 0.12 < abs(c[0]) < 2.6,
        lambda c, n: abs(n[0]) > 0.55 and 4.25 < c[1] < 5.95 and (in_bays(c[2], sb) or -6.2 < c[2] < -4.95),
        lambda c, n: n[2] > 0.55 and 4.3 < c[1] < 6.05 and 0.12 < abs(c[0]) < 2.4,
    ], RUBBER, frame=0.09, cuts=[("y", 4.25), ("y", 5.95), ("y", 6.1), ("y", 4.3), ("y", 6.05), ("z", -6.2), ("z", -4.95)]
        + [("z", v) for b_ in sb for v in b_] + [("x", v) for v in (-2.6, -2.4, -0.12, 0.12, 2.4, 2.6)])
    det = [liner]
    det += benches((-1.6, 1.6), [-2.6, -0.6, 1.4, 3.4], 2.7, 2.4, seat_mat((90, 160, 200)))
    det += seat(-1.6, 2.7, -4.9, w=1.2, m=seat_mat((60, 60, 66)))
    det += seat(1.6, 2.7, -4.9, w=1.2, m=seat_mat((60, 60, 66)))
    det.append(P(rbox(6.0, 0.6, 0.7, 0, 3.8, -6.3, bev=0.12, segs=1), DASH))
    det += steering(-1.6, 4.15, -5.85, r=0.42, m=BLACK, tilt=45)
    for y in (2.05, 2.4, 2.75):  # the nose grille bars
        det.append(P(rbox(2.6, 0.14, 0.14, 0, y, -7.16, bev=0.05, segs=1), CHROME))
    det.append(P(TOR(0.42, 0.07, 0, 3.65, -7.2, axis="z", segs=16, csegs=4), GOLD))  # a ship's wheel badge
    det.append(P(C(0.12, 0.12, 0, 3.65, -7.2, segs=8, axis="z"), GOLD))
    for k in range(8):
        a_ = k * math.pi / 4
        det.append(P(T([(math.cos(a_) * 0.1, 3.65 + math.sin(a_) * 0.1, -7.22),
                         (math.cos(a_) * 0.62, 3.65 + math.sin(a_) * 0.62, -7.22)], 0.045, segs=4), GOLD))
    end_bumpers(det, -7.15, 7.1, w=6.6)
    mirrors_big(det, -6.2, 4.6, x=3.35)
    # the life ring on the side, the roof rack with an oar and a coil of rope
    det.append(P(TOR(0.7, 0.24, 3.62, 3.0, 2.3, axis="x", segs=20, csegs=8), R("LifeRing", (250, 96, 40), 0.6, pat="ring")))
    for x in (-2.4, 2.4):
        det.append(P(T([(x, 6.95, -5.0), (x, 7.4, -4.6), (x, 7.4, 5.2), (x, 6.95, 5.6)], 0.07, segs=5), CHROME))
    for z in (-3.6, 0.0, 3.6):
        det.append(P(T([(-2.4, 7.4, z), (2.4, 7.4, z)], 0.06, segs=4), CHROME))
    oar_m = R("Oar", (196, 140, 80), 0.6)
    det.append(P(T([(-1.4, 7.55, -4.0), (1.0, 7.55, 3.8)], 0.08, segs=6), oar_m))
    blade = rbox(0.5, 0.08, 1.2, 1.25, 7.55, 4.6, bev=0.04, segs=1)
    turn(blade, "up", -17, (1.25, 7.55, 4.6))
    det.append(P(blade, oar_m))
    rope = R("Rope", (218, 186, 120), 0.9)
    det.append(P(TOR(0.8, 0.2, 0.6, 7.6, -1.6, segs=18, csegs=6), rope))
    det.append(P(TOR(0.55, 0.18, 0.6, 7.92, -1.6, segs=16, csegs=6), rope))
    det += axle_wheels(lk, (-4.6, 4.6), 1.25, 1.0, 2.95, white=WHITEWALL)
    lamps, tails = [], []
    for s_ in (1, -1):
        round_lamp(s_ * 2.2, 2.75, -7.08, 0.46, det=det, lamps=lamps)
        tails.append(rbox(0.45, 0.9, 0.2, s_ * 2.7, 2.9, 7.0, bev=0.12, segs=1))
    finish(lk, [shell], det, glass, lamps, tails)

if want("NewsVan"):
    def news_paint(p, n):
        rgb, a = paint_bands((244, 246, 250), [(2.55, 3.35, (255, 150, 28)), (3.45, 3.62, (44, 70, 190))], rocker=1.4)(p, n)
        side = np.abs(n[:, 0]) > 0.5  # a navy swoosh rising toward the back
        sw = side & (p[:, 2] > 0.2) & (np.abs(p[:, 1] - (3.95 + (p[:, 2] - 0.2) * 0.36)) < 0.2)
        rgb[sw] = rgbf((44, 70, 190))
        return rgb, a

    lk = Look("NewsVan", "News", False, paint=news_paint, body_rgb=(244, 246, 250), seams=[
        side_v(-3.4, 1.4, 6.7), side_v(-1.4, 1.4, 6.9), side_v(2.6, 1.4, 6.9), side_h(6.9, -1.4, 2.6),
        end_v(0, 1, 1.5, 7.0), top_x(2.2, -7.0, -5.5)])
    pm = R("Paint")
    keys = dict(
        w=[(-7.2, 2.8), (-6.95, 3.15), (-6.0, 3.35), (-5.2, 3.45), (7.0, 3.45), (7.2, 3.2)],
        yt=[(-7.2, 3.3), (-6.9, 3.75), (-6.0, 4.05), (-5.45, 4.6), (-4.3, 7.0), (-3.9, 7.35), (6.9, 7.35), (7.2, 6.9)],
        yb=YB, p=[(-7.2, 4.2), (-5.5, 4.6), (-4.6, 6.5)], pb=8.0, tumble=0.12, liner_in=(2.75, 0.4),
        extra_z=[-5.5, -5.2, -4.9, -4.6, -4.3])
    shell, liner = van_shell(-7.2, 7.2, keys, pm, arches=[(-4.7, 1.25, 1.55), (4.7, 1.25, 1.55)], arch_x=3.4, n=32,
                             ends=0.35, floor=1.5)
    glass = cut_windows(shell, [
        lambda c, n: n[2] < -0.4 and 4.3 < c[1] < 6.75 and 0.1 < abs(c[0]) < 2.8,
        lambda c, n: abs(n[0]) > 0.7 and 4.1 < c[1] < 6.25 and -5.2 < c[2] < -3.55,
        lambda c, n: n[2] > 0.6 and 4.6 < c[1] < 6.4 and 0.12 < abs(c[0]) < 2.4,
    ], RUBBER, frame=0.09)
    det = [liner]
    det += seat(-1.6, 2.7, -3.9, w=1.2, m=seat_mat((50, 54, 66)))
    det += seat(1.6, 2.7, -3.9, w=1.2, m=seat_mat((50, 54, 66)))
    det.append(P(rbox(5.6, 0.6, 0.7, 0, 3.9, -4.35, bev=0.12, segs=1), DASH))
    det += steering(-1.6, 4.2, -3.95, r=0.42, m=BLACK, tilt=45)
    det.append(P(rbox(6.2, 4.8, 0.2, 0, 4.1, -2.9, bev=0.05, segs=1), R("Bulkhead", (206, 210, 216), 0.6)))
    det.append(P(rbox(5.0, 2.4, 2.4, 0, 2.7, 3.6, bev=0.15, segs=1), R("Racks", (70, 74, 84), 0.5, 0.4, pat=("slats", 3.0))))
    det.append(P(rbox(2.4, 0.7, 0.3, 0, 2.55, -7.2, bev=0.12, segs=2), CHROME))
    det.append(P(rbox(2.15, 0.48, 0.3, 0, 2.55, -7.24, bev=0.06, segs=1), GRILLE))
    end_bumpers(det, -7.2, 7.2, w=6.6, m=BLACK)
    mirrors_big(det, -5.3, 4.3, x=3.3)
    # the roof: a mast with the uplink dish, an equipment box, a light bar (white and amber; never red and blue)
    det.append(P(C(0.16, 2.0, 0, 8.35, 3.4, segs=10), CHROME))
    dish = lathe([(0.02, 0.0), (0.7, 0.12), (1.25, 0.42), (1.45, 0.62), (1.38, 0.68), (1.18, 0.5), (0.66, 0.24),
                  (0.02, 0.12)], (0, 0, 0), "y", 18)
    turn(dish, "x", -55)
    shift(dish, rb(0, 9.4, 3.2))
    det.append(P(dish, R("Dish", (226, 230, 236), 0.35, 0.3)))
    det.append(P(T([(0, 9.4, 3.2), (0, 10.0, 2.4)], 0.05, segs=4), CHROME))
    det.append(P(S(0.14, 0, 10.0, 2.4, segs=8, rings=4), BLACK))
    det.append(P(rbox(2.6, 0.7, 2.2, 0, 7.7, 0.4, bev=0.12, segs=1), R("RoofBox", (200, 206, 214), 0.5)))
    det.append(P(rbox(4.4, 0.3, 0.7, 0, 7.5, -3.3, bev=0.1, segs=1), BLACK))
    det.append(P(T([(2.4, 7.35, 6.0), (2.4, 9.6, 6.0)], 0.035, segs=4), BLACK))
    for x in (-1.0, 1.0):  # the rear ladder
        det.append(P(T([(x, 1.8, 7.32), (x, 7.2, 7.32)], 0.05, segs=4), CHROME))
    for y in (2.6, 3.6, 4.6, 5.6, 6.6):
        det.append(P(T([(-1.0, y, 7.32), (1.0, y, 7.32)], 0.04, segs=4), CHROME))
    det += axle_wheels(lk, (-4.7, 4.7), 1.25, 1.0, 2.95)
    lamps, tails, amber = [], [], []
    for s_ in (1, -1):
        rect_lamp(s_ * 2.15, 2.85, -7.08, 1.0, 0.5, out=lamps, bezel=CHROME, det=det)
        tails.append(rbox(0.45, 1.2, 0.2, s_ * 2.85, 3.0, 7.18, bev=0.12, segs=1))
        amber.append(rbox(0.9, 0.3, 0.55, s_ * 1.4, 7.75, -3.3, bev=0.1, segs=1))
    lamps.append(rbox(1.3, 0.3, 0.55, 0, 7.75, -3.3, bev=0.1, segs=1))
    finish(lk, [shell], det, glass, lamps, tails, extra=[("Amber", amber, (255, 170, 40), "Neon")])

if want("ShowVan"):
    def show_paint(p, n):
        k = len(p)
        rgb = np.tile(rgbf((118, 42, 124)), (k, 1))
        wav = 3.38 + 0.12 * np.sin(p[:, 2] * 1.6)
        rgb[np.abs(p[:, 1] - wav) < 0.13] = rgbf((246, 196, 64))
        side = np.abs(n[:, 0]) > 0.6
        pan = side & (p[:, 2] > -2.3) & (p[:, 2] < 4.7) & (p[:, 1] > 3.75) & (p[:, 1] < 6.15)
        edge = side & (p[:, 2] > -2.42) & (p[:, 2] < 4.82) & (p[:, 1] > 3.63) & (p[:, 1] < 6.27) & ~pan
        rgb[edge] = rgbf((246, 196, 64))
        rgb[pan] = rgbf((248, 238, 214))
        rgb[p[:, 1] < 1.45] = (0.12, 0.1, 0.12)
        return rgb, np.ones(k, np.float32)

    lk = Look("ShowVan", "Show", False, paint=show_paint, body_rgb=(118, 42, 124),
              seams=[side_v(-3.6, 1.45, 6.2), side_v(-5.7, 1.45, 4.8), end_v(0, 1, 1.6, 6.2)])
    pm = R("Paint")
    keys = dict(
        w=[(-7.15, 2.5), (-6.9, 3.0), (-6.0, 3.4), (6.2, 3.4), (6.9, 3.05), (7.15, 2.6)],
        yt=[(-7.15, 4.2), (-6.9, 5.2), (-6.2, 6.3), (-5.0, 6.8), (5.6, 6.8), (6.6, 6.3), (7.15, 5.2)],
        yb=[(-7.15, 1.8), (-6.9, 1.3), (-6.2, 1.05), (6.2, 1.05), (6.9, 1.3), (7.15, 1.8)], p=2.8, pb=5.0,
        tumble=0.3, liner_in=(0.8, 0.6))
    shell, liner = van_shell(-7.15, 7.15, keys, pm, arches=[(-4.5, 1.25, 1.55), (4.6, 1.25, 1.55)], arch_x=3.35, n=28,
                             ends=0.6, floor=1.5, segs=28)
    glass = cut_windows(shell, [
        lambda c, n: n[2] < -0.3 and 4.7 < c[1] < 6.1 and 0.12 < abs(c[0]) < 2.3,
        lambda c, n: abs(n[0]) > 0.55 and 4.4 < c[1] < 5.9 and -5.4 < c[2] < -3.9,
    ], RUBBER, frame=0.09, cuts=[("y", 4.7), ("y", 6.1), ("y", 4.4), ("y", 5.9), ("z", -5.4), ("z", -3.9)]
        + [("x", v) for v in (-2.3, -0.12, 0.12, 2.3)])
    det = [liner]
    det += seat(-1.6, 2.7, -3.9, w=1.2, m=seat_mat((200, 40, 60)))
    det += seat(1.6, 2.7, -3.9, w=1.2, m=seat_mat((200, 40, 60)))
    det.append(P(rbox(5.6, 0.6, 0.7, 0, 3.7, -5.6, bev=0.12, segs=1), R("WoodDash", (120, 76, 44), 0.5)))
    det += steering(-1.6, 4.05, -5.1, r=0.42, m=BLACK, tilt=45)
    for s_ in (1, -1):  # the side star on its cream panel
        st_ = star(1.0, 0.42, 0.14, 0, 0, 0)
        turn(st_, "up", 90)
        shift(st_, rb(s_ * 3.3, 4.95, 1.2))
        det.append(P(st_, GOLD))
    # the top hat, the roof rack and two travel trunks
    hat = R("Hat", (30, 30, 36), 0.5)
    det.append(P(C(0.95, 2.0, 0, 7.75, -1.4, segs=18, r2=1.05), hat))
    det.append(P(C(1.6, 0.14, 0, 6.8, -1.4, segs=20), hat))
    det.append(P(C(0.99, 0.4, 0, 7.15, -1.4, segs=18, r2=1.0), R("HatBand", (200, 30, 50), 0.5)))
    for x in (-2.2, 2.2):
        det.append(P(T([(x, 6.75, 0.9), (x, 7.2, 1.3), (x, 7.2, 5.6), (x, 6.6, 6.0)], 0.06, segs=4), BRASS))
    for (z, w_, h_) in ((2.5, 3.6, 1.2), (4.6, 3.0, 1.0)):
        det.append(P(rbox(w_, h_, 1.6, 0, 7.25 + h_ / 2, z, bev=0.1, segs=1), WOOD))
        for dz in (-0.55, 0.55):
            det.append(P(rbox(w_ + 0.06, h_ + 0.06, 0.16, 0, 7.25 + h_ / 2, z + dz, bev=0.03, segs=1), BRASS))
    end_bumpers(det, -7.15, 7.15, w=6.0)
    mirrors_big(det, -5.6, 4.6, x=3.25)
    det.append(P(rbox(2.0, 0.9, 0.3, 0, 2.5, -7.12, bev=0.14, segs=2), GOLD))
    det.append(P(rbox(1.7, 0.65, 0.3, 0, 2.5, -7.16, bev=0.06, segs=1), R("Slats", (44, 44, 50), 0.4, 0.6, pat=("slats", 9.0))))
    det += axle_wheels(lk, (-4.5, 4.6), 1.25, 1.0, 2.95, rim=GOLD, white=WHITEWALL, spokes=0)
    spare = wheel(0, 3.6, 7.2, 1.0, 0.7, 1, TYRE, GOLD, HUB, segs=16, spokes=0, white=WHITEWALL)  # the spare on the back
    for sp_ in spare:
        turn(sp_, "up", -90, (0, 3.6, 7.2))
        shift(sp_, rb(0, 0, 0.32))
    lk.wheels.append((0, 3.6, 7.5, 1.0))
    det += spare
    lamps, tails, bulbs = [], [], []
    for s_ in (1, -1):
        round_lamp(s_ * 2.1, 2.9, -6.98, 0.48, det=det, lamps=lamps, ring=GOLD)
        tails.append(S(0.3, s_ * 2.3, 2.7, 7.08, sc=(1, 1, 0.6), segs=10, rings=5))
        for k in range(9):  # the marquee bulbs round the panel
            bulbs.append(S(0.13, s_ * 3.42, 6.35, -2.2 + k * 0.86, segs=8, rings=4))
            bulbs.append(S(0.13, s_ * 3.47, 3.52, -2.2 + k * 0.86, segs=8, rings=4))
    finish(lk, [shell], det, glass, lamps, tails, extra=[("Bulbs", bulbs, (255, 222, 150), "Neon")])

if want("PartsTruck"):
    lk = Look("PartsTruck", "Parts", False, body_rgb=(250, 132, 28),
              paint=paint_bands((250, 132, 28), [(3.35, 3.58, (250, 250, 246))], rocker=1.5),
              seams=[side_v(-4.55, 1.5, 6.6), side_v(-2.0, 1.5, 6.7), top_x(2.2, -7.0, -4.9), end_h(2.0, -1, 2.6)])
    pm = R("Paint")
    keys = dict(
        w=[(-7.2, 2.7), (-6.95, 3.0), (-5.0, 3.05), (-4.7, 3.3), (-1.8, 3.3), (-1.6, 3.1)],
        yt=[(-7.2, 3.4), (-6.95, 3.85), (-5.1, 4.1), (-4.75, 4.5), (-3.9, 6.6), (-3.6, 6.9), (-1.85, 6.9), (-1.6, 6.6)],
        yb=[(-7.2, 1.6), (-6.95, 1.25), (-6.3, 1.1), (-1.6, 1.1)], p=[(-7.2, 4.2), (-4.8, 4.5), (-4.2, 6.5)], pb=8.0,
        tumble=0.12, liner_in=(2.6, 0.25), extra_z=[-4.9, -4.75, -4.5, -4.2, -3.9])
    shell, liner = van_shell(-7.2, -1.6, keys, pm, arches=[(-5.2, 1.25, 1.55)], arch_x=3.3, n=22, ends=0.4, floor=1.6)
    glass = cut_windows(shell, [
        lambda c, n: n[2] < -0.4 and c[1] > 4.45 and 0.1 < abs(c[0]) < 2.8,
        lambda c, n: abs(n[0]) > 0.7 and 4.3 < c[1] < 6.3 and -4.3 < c[2] < -2.05,
        lambda c, n: n[2] > 0.6 and 4.6 < c[1] < 6.2 and abs(c[0]) < 2.2,
    ], RUBBER, frame=0.09)
    det = [liner]
    det += seat(-1.5, 2.8, -2.6, w=1.25, m=seat_mat((60, 62, 70)))
    det += seat(1.5, 2.8, -2.6, w=1.25, m=seat_mat((60, 62, 70)))
    det.append(P(rbox(5.6, 0.6, 0.7, 0, 3.9, -3.9, bev=0.12, segs=1), DASH))
    det += steering(-1.5, 4.25, -3.4, r=0.42, m=BLACK, tilt=45)
    det.append(P(rbox(3.0, 1.3, 0.3, 0, 2.7, -7.2, bev=0.14, segs=2), CHROME))
    det.append(P(rbox(2.7, 1.05, 0.3, 0, 2.7, -7.25, bev=0.06, segs=1),
                 R("TruckGrille", (36, 38, 44), 0.45, 0.5, pat=("slats", 4.0))))
    # the flatbed: a steel deck, wooden sides, a headboard rack, fenders and the load
    det.append(P(rbox(6.6, 0.5, 8.8, 0, 2.5, 2.9, bev=0.08, segs=1), R("Deck", (128, 136, 148), 0.45, 0.7)))
    det.append(P(rbox(2.6, 0.8, 9.0, 0, 1.7, 2.6, bev=0.05, segs=1), DARK))
    for s_ in (1, -1):
        det.append(P(rbox(0.22, 1.2, 8.8, s_ * 3.2, 3.35, 2.9, bev=0.05, segs=1), WOOD))
        fender = TOR(1.45, 0.14, 0, 0, 0, axis="x", segs=14, csegs=4, arc=math.pi)  # the upper half, over the wheel
        turn(fender, "x", 90)
        shift(fender, rb(s_ * 2.95, 1.25, 4.4))
        det.append(P(fender, BLACK))
    det.append(P(rbox(6.6, 1.2, 0.22, 0, 3.35, 7.2, bev=0.05, segs=1), WOOD))
    for x in (-2.6, -1.3, 0, 1.3, 2.6):
        det.append(P(T([(x, 2.75, -1.35), (x, 6.2, -1.35)], 0.07, segs=5), CHROME))
    det.append(P(T([(-3.0, 6.2, -1.35), (3.0, 6.2, -1.35)], 0.08, segs=5), CHROME))
    for (x, y, z, sx, sy, sz) in ((-1.6, 2.75, 1.2, 2.4, 2.2, 2.4), (-1.5, 4.95, 1.3, 2.0, 1.8, 2.0), (1.6, 2.75, 0.6, 2.4, 1.9, 2.6)):
        det.append(P(rbox(sx, sy, sz, x, y + sy / 2, z, bev=0.1, segs=1), WOOD))
    gear = [C(1.35, 0.5, 0, 0, 0, segs=18, axis="x"), C(0.45, 0.62, 0, 0, 0, segs=10, axis="x")]
    for k in range(10):
        t_ = rbox(0.5, 0.55, 0.5, 0, 1.55, 0, bev=0)
        turn(t_, "x", k * 36)
        gear.append(t_)
    for g_ in gear:
        shift(g_, rb(1.6, 4.25, 4.6))
        det.append(P(g_, BRASS))
    crane = R("Crane", (252, 206, 40), 0.5)
    det.append(P(rbox(0.6, 3.3, 0.6, 2.4, 4.4, 6.4, bev=0.08, segs=1), crane))
    det.append(P(T([(2.4, 5.9, 6.4), (2.4, 7.2, 3.8)], 0.24, segs=6), crane))
    det.append(P(T([(2.4, 7.1, 3.8), (2.4, 5.9, 3.8)], 0.03, segs=4), BLACK))
    det.append(P(TOR(0.22, 0.06, 2.4, 5.75, 3.8, axis="x", segs=10, csegs=4, arc=math.pi * 1.4), CHROME))
    det.append(P(rbox(2.2, 0.9, 0.9, -1.6, 3.2, -0.9, bev=0.08, segs=1), R("Toolbox", (214, 40, 44), 0.4)))
    end_bumpers(det, -7.2, 7.25, w=6.6)
    mirrors_big(det, -4.4, 4.4, x=3.2)
    det += axle_wheels(lk, (-5.2, 4.4), 1.25, 1.05, 2.95)
    lamps, tails = [], []
    for s_ in (1, -1):
        round_lamp(s_ * 2.05, 2.95, -7.12, 0.44, det=det, lamps=lamps)
        tails.append(rbox(0.55, 0.35, 0.2, s_ * 2.6, 2.0, 7.32, bev=0.08, segs=1))
    det.append(P(C(0.5, 0.12, 0, 6.88, -2.6, segs=12), BLACK))
    beacon = [C(0.42, 0.55, 0, 7.18, -2.6, segs=12, r2=0.34), S(0.34, 0, 7.45, -2.6, segs=10, rings=5)]
    finish(lk, [shell], det, glass, lamps, tails, extra=[("Beacon", beacon, (255, 150, 40), "Neon")])


# ================================================================ the fit table, the texture bake and the export
def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    return lo, hi


MAPS = {}
for name, lk in LOOKS.items():
    print("baking", name, flush=True)
    MAPS[name] = vkit.bake_look(lk, ao_samples=8 if FAST else 32)

TRIS = {}
total = 0
rows = []
for look in sorted(LOOKS):
    lk = LOOKS[look]
    rows.append("\t%s = {" % look)
    for mname in sorted(lk.meshes):
        ob = lk.meshes[mname]
        lo, hi = bounds(ob)
        c = [(lo[i] + hi[i]) / 2 for i in range(3)]
        size = [hi[i] - lo[i] for i in range(3)]
        t = kit.tris(ob)
        TRIS[mname] = t
        total += t
        textured = ob in lk.textured()
        if textured:
            rgb, mat, alpha = (lk.body_rgb if mname.endswith("Body") else lk.detail_rgb), "SmoothPlastic", 0.0
        else:
            rgb, mat, alpha = lk.extra[mname]
        extra = (", alpha = %g" % alpha) if alpha else ""
        extra += ", maps = true" if textured else ""
        rows.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, mat = \"%s\"%s, tris = %d },"
                    % (mname, max(size[0], 0.05), max(size[2], 0.05), max(size[1], 0.05), c[0], c[2], -c[1], rgb[0], rgb[1],
                       rgb[2], mat, extra, t))
    rows.append("\t},")
print("vehicles: %d looks, %d meshes, %d tris" % (len(LOOKS), len(TRIS), total))
for look in sorted(LOOKS):
    lk = LOOKS[look]
    print("  %-14s %5d tris  (%s)" % (look, sum(TRIS[n] for n in lk.meshes), ", ".join(
        "%s %d" % (n[len(lk.prefix):], TRIS[n]) for n in sorted(lk.meshes))))

if ONLY is None:
    text = "\n".join([
        "-- GENERATED by art/blender/vehicles.py: do not edit by hand.",
        "-- The side quest escorts and the hub's cars, trams and trucks in Blender meshes (ReplicatedStorage.Art.Vehicles;",
        "-- Shared.SetPieceKit for the escorts, Shared.VehicleKit for the hub): look -> mesh -> its size and its centre from",
        "-- the look's foot point, in studs (x, up, z; nose at -z), its colour (a vehicle's paint may replace a body's),",
        "-- material, transparency, maps (a baked texture set in its SurfaceAppearance: the colour map's alpha lets the",
        "-- part colour show through, AlphaMode Overlay) and triangles. %d meshes in %d looks, %d triangles."
        % (len(TRIS), len(LOOKS), total),
        "return {",
    ] + rows + ["}", ""])
    FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "VehicleArt.luau"))
    with open(FIT, "w") as f:
        f.write(text)
    _stylua = shutil.which("stylua") or os.path.expanduser("~/tools/bin/stylua")
    if os.path.exists(_stylua):
        subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                       check=False)
    export = []
    for look, lk in LOOKS.items():
        pm = vkit.export_material(lk, MAPS[look])
        for mname, ob in lk.meshes.items():
            cp = copy(ob)
            cp.name = mname + "_x"
            kit.centre(cp)
            cp.name = mname
            cp.data.name = mname
            cp.data.materials.clear()
            if ob in lk.textured():
                cp.data.materials.append(pm)
            else:
                rgb, mat, alpha = lk.extra[mname]
                cp.data.materials.append(kit.material(mname + "Mat", rgb))
            export.append(cp)
    bpy.ops.object.select_all(action="DESELECT")
    for o in export:
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(kit.ROOT, "export", "Vehicles.fbx"), use_selection=True,
        apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", object_types={"MESH"},
        use_mesh_modifiers=True, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False,
        path_mode="COPY", embed_textures=True)
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    import vpreview  # noqa: E402

    vpreview.run(LOOKS, MAPS, fast=FAST, only=ONLY)
