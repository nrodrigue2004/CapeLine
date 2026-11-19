# deep.py: the underwater areas in Blender meshes (the deep art pass, 2026-11-19). Until the import the game draws
# the Deep from plain parts (Shared.DeepLayout, CityBuilder); once ReplicatedStorage.Art.Deep holds every mesh of a
# look, CityBuilder draws the look over the boxes it stands in for and hides them (kept: they still collide, take
# queries and make the walls robots and heroes use, exactly as before). The meshes never collide.
# Looks, in the game's cartoon kit style (bright colours, chunky shapes, a baked texture set a group: tiles, rust,
# barnacles, algae and occlusion painted in; Neon for lamps and glowing windows), low poly for phones:
# * the Sunken Line: TunnelSegment (tiles, ribs, rails and sleepers, porthole lamps), StationShell (tiled walls,
#   porthole windows, lamps, the tunnel portal), StationPlatform, StationPillar and the flooded TrainCar
# * the reef: CoralBrain, CoralKnob, CoralStag (the round heads), CoralTube, CoralFinger (the tubes), CoralFan,
#   CoralLace (the fans), each tinted by its copy's palette colour, and KelpStrand (swayed in code, DeepClient)
# * the shipwrecks: WreckHull, WreckBow, WreckCabin, WreckMast; the sunken cargo CacheChest
# * the sunken factory: FactoryHall, FactoryRoof, FactoryChimney, FactoryPipe; the harbour basin's QuayWall
# * the sea robots' gear (EnemyRenderer): DiverHelmet (DiverDome glass, HelmetFrame), DiverTank; the Torpedo
#   (CombatFx) and the commuters' AirBubble (DeepClient)
# Each look is built in Roblox studs about the middle of its own frame (x, up, z): the box DeepLayout stretches it
# over (Shared.DeepArtKit fills a placement's box with the frame). src/config/DeepArt.luau (generated) gives each
# look's frame and each mesh's size, centre, colour, material, transparency and whether it has maps or takes the
# copy's tint. Original designs: no real lines, logos or lettering.
# Output: art/export/Deep.fbx (textures embedded), art/export/deep/<Group>_{Color,Normal,Roughness,Metalness}.png,
# src/config/DeepArt.luau; with --preview, art/preview/deep.png (the gallery and the scenes from inside: a tunnel
# stretch and a reef stretch in underwater fog, the station, a wreck, the factory and the basin; the places come from
# art/export/deep/layout.json, which `lune run art/deep/layout.luau` writes from the game's own data).
# Run: ~/tools/bpyenv/bin/python art/blender/deep.py [--preview] [--fast] [--no-bake]
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

kit.reset()

import vkit  # noqa: E402
from vkit import R, P, rbox, join, smooth_shade, lathe  # noqa: E402,F401
from studs import rb, B, C, S, T, TOR, turn, shift, copy, prism, loft_z, hull_z, star, extrude_up  # noqa: E402,F401

FAST = "--fast" in sys.argv
vkit.OUT = os.path.join(kit.ROOT, "export", "deep")


# ================================================================ the bake groups and the looks
class Grp:
    """One baked texture set (vkit.bake_look's look): its textured meshes share one UV atlas."""

    def __init__(self, name, res=1024):
        self.name, self.prefix, self.res = name, "", res
        self.meshes, self.tex, self.extra = {}, [], {}
        self.paint, self.seams, self.wheels, self.rings = None, [], [], []
        GROUPS[name] = self

    def textured(self):
        return [self.meshes[n] for n in self.tex]


GROUPS = {}
LOOKS = {}  # look -> [mesh names]
FRAMES = {}  # look -> (sx, sy, sz): the box the look fills
INFO = {}  # mesh -> dict(group, rgb, mat, alpha, maps, tint)


def look(name, frame):
    FRAMES[name] = frame
    LOOKS.setdefault(name, [])


def add(g, lk, name, parts, rgb=None, mat="SmoothPlastic", alpha=0.0, tint=False):
    """A mesh of look lk in group g: textured (rgb None; every part carries a paint region) or flat (rgb, mat)."""
    parts = [p for p in (parts if isinstance(parts, (list, tuple)) else [parts]) if p is not None]
    if rgb is not None:
        for p in parts:
            p.data.materials.clear()
    ob = join(parts, name)
    smooth_shade(ob)
    assert name not in INFO, "mesh names are unique: " + name
    g.meshes[name] = ob
    if rgb is None:
        g.tex.append(name)
    else:
        g.extra[name] = (tuple(int(c) for c in rgb), mat, alpha)
    LOOKS[lk].append(name)
    INFO[name] = dict(group=g.name, rgb=tuple(int(c) for c in (rgb or (255, 255, 255))), mat=mat, alpha=alpha,
                      maps=rgb is None, tint=tint)
    return ob


# ================================================================ patterns (texture space: the baked position p and
# normal n of each texel, Roblox studs in the look's own frame); a region's pat is a tuple of steps
def _hash(*a):
    x = np.zeros_like(a[0], dtype=np.float64)
    for k, v in zip((12.9898, 78.233, 37.719, 4.581), a):
        x = x + v * k
    h = np.sin(x) * 43758.5453
    return (h - np.floor(h)).astype(np.float32)


def vnoise(p, f, seed=0.0):
    q = p * f + seed
    i = np.floor(q)
    t = q - i
    t = t * t * (3 - 2 * t)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (t[:, 0] if dx else 1 - t[:, 0]) * (t[:, 1] if dy else 1 - t[:, 1]) * (t[:, 2] if dz else 1 - t[:, 2])
                out = out + w * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz)
    return out.astype(np.float32)


def fbm(p, f, seed=0.0):
    return 0.5 * vnoise(p, f, seed) + 0.3 * vnoise(p, f * 2.1, seed + 7) + 0.2 * vnoise(p, f * 4.3, seed + 13)


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def uv2(p, n):
    """Face coordinates: (x, z) on tops, (z, y) on x faces, (x, y) on z faces."""
    ax = np.abs(n)
    top = ax[:, 1] >= np.maximum(ax[:, 0], ax[:, 2])
    sx = (~top) & (ax[:, 0] >= ax[:, 2])
    u = np.where(top, p[:, 0], np.where(sx, p[:, 2], p[:, 0]))
    v = np.where(top, p[:, 2], p[:, 1])
    return u, v, top


def rgbf(c):
    return np.array(c, dtype=np.float32) / 255


def lerp(c, rgb, k):
    return c * (1 - k[:, None]) + rgbf(rgb)[None, :] * k[:, None]


_orig_pattern = vkit._pattern


def deep_pattern(lk, pat, m, Pp, Nn, col, alpha, rough, height, noise):
    if not (isinstance(pat, tuple) and pat and isinstance(pat[0], tuple)):
        return _orig_pattern(lk, pat, m, Pp, Nn, col, alpha, rough, height, noise)
    p, n = Pp[m], Nn[m]
    c, a, r, h = col[m], alpha[m], rough[m], height[m]
    for step in pat:
        kind = step[0]
        if kind == "tiles":  # ("tiles", size, grout rgb, jitter)
            s, grout, jit = step[1], step[2], step[3]
            u, v, _ = uv2(p, n)
            gw = 0.07 / s
            fu, fv = (u / s) % 1, (v / s) % 1
            g = (fu < gw) | (fu > 1 - gw) | (fv < gw) | (fv > 1 - gw)
            hh = _hash(np.floor(u / s), np.floor(v / s))
            c = c * (1 - jit + 2 * jit * hh)[:, None]
            gone = hh > 0.972
            c[gone] = rgbf((104, 104, 100)) * (0.8 + 0.2 * fbm(p[gone], 1.3))[:, None]
            c[g] = rgbf(grout)
            h = h - g * 0.6 - gone * 0.5
            r = np.where(g | gone, 0.9, r)
        elif kind == "blocks":  # ("blocks", w, h, grout rgb)
            bw, bh, grout = step[1], step[2], step[3]
            u, v, top = uv2(p, n)
            row = np.floor(v / bh)
            uu = u + (row % 2) * bw / 2
            fu, fv = (uu / bw) % 1, (v / bh) % 1
            g = ((fu < 0.025) | (fu > 0.975) | (fv < 0.04) | (fv > 0.96)) & ~top
            hh = _hash(np.floor(uu / bw), row)
            c = c * (0.9 + 0.16 * hh)[:, None] * (0.9 + 0.1 * fbm(p, 0.8))[:, None]
            c[g] = rgbf(grout)
            h = h - g * 0.7
        elif kind == "concrete":
            k = fbm(p, 0.55)
            c = c * (0.86 + 0.18 * k)[:, None]
            pit = _hash(np.floor(p[:, 0] * 3), np.floor(p[:, 1] * 3), np.floor(p[:, 2] * 3)) > 0.985
            c[pit] *= 0.7
            h = h - pit * 0.4
        elif kind == "silt":
            k = fbm(p, 0.4)
            c = c * (0.85 + 0.25 * k)[:, None]
            rip = np.sin(p[:, 0] * 1.7 + p[:, 2] * 0.4 + k * 5) > 0.82
            c[rip] *= 0.86
            h = h + rip * 0.3
        elif kind == "rust":  # ("rust", amount)
            amt = step[1]
            k = fbm(p, 0.32, 3.0)
            patch = sstep(1.0 - amt * 0.55, 1.08 - amt * 0.55, k)
            vert = np.abs(n[:, 1]) < 0.55
            st = vnoise(p * np.array([1.6, 0.11, 1.6], np.float32), 1.0, 11.0)
            streak = sstep(0.66, 0.8, st) * vert * amt
            tone = vnoise(p, 1.4, 5.0)[:, None]
            rc = rgbf((168, 82, 40)) * (1 - tone) + rgbf((112, 56, 34)) * tone
            kk = np.clip(patch * 0.9 + streak * 0.55, 0, 1)
            c = c * (1 - kk[:, None]) + rc * kk[:, None]
            r = r * (1 - kk) + 0.85 * kk
            h = h - patch * 0.25
            a = np.maximum(a, kk)
        elif kind == "barnacle":  # ("barnacle", density[, below y])
            dens = step[1]
            q = np.floor(p / 0.55)
            hh = _hash(q[:, 0], q[:, 1], q[:, 2])
            cen = (q + 0.5) * 0.55
            d = np.linalg.norm(p - cen, axis=1)
            dot = (hh > 1 - dens) & (d < 0.2)
            if len(step) > 2:
                dot &= p[:, 1] < step[2]
            ring = dot & (d > 0.11)
            c[dot] = rgbf((222, 216, 196))
            c[ring] = rgbf((150, 144, 128))
            h = h + dot * 0.9
            a = np.maximum(a, dot.astype(np.float32))
        elif kind == "algae":  # ("algae", y below which it grows, fade)
            y0, fd = step[1], step[2]
            k = np.clip((y0 - p[:, 1]) / fd, 0, 1) * sstep(0.35, 0.6, fbm(p, 0.7, 9.0))
            c = lerp(c, (84, 132, 66), k * 0.8)
            a = np.maximum(a, k * 0.8)
        elif kind == "algaeBand":  # ("algaeBand", waterline y)
            yw = step[1]
            dy = yw - p[:, 1]
            below = np.clip(dy / 1.5, 0, 1) * np.clip(1 - (dy - 3.5) / 5.0, 0, 1)
            band = below * (0.55 + 0.45 * fbm(p, 0.9, 2.0)) + np.clip(dy / 30, 0, 0.25) * fbm(p, 0.3, 8.0)
            c = lerp(c, (70, 118, 60), band * 0.85)
            stain = (p[:, 1] > yw) & (p[:, 1] < yw + 0.45)
            c[stain] *= 0.72
        elif kind == "grime":  # ("grime", y top, y bottom)
            yt, yb = step[1], step[2]
            k = np.clip((yt - p[:, 1]) / (yt - yb), 0, 1) * (0.6 + 0.4 * fbm(p, 0.5, 4.0))
            c = c * (1 - 0.38 * k)[:, None] + rgbf((70, 80, 60))[None, :] * (0.1 * k)[:, None]
        elif kind == "planks":  # ("planks", width, along: "x" or "z")
            wd, along = step[1], step[2]
            top = np.abs(n[:, 1]) > 0.6
            acr = np.where(top, p[:, 2] if along == "x" else p[:, 0], p[:, 1])
            alg = p[:, 0] if along == "x" else p[:, 2]
            idx = np.floor(acr / wd)
            gap = np.abs((acr / wd) % 1 - 0.5) > 0.46
            grain = 0.9 + 0.1 * np.sin(alg * 5 + _hash(idx, idx) * 20 + fbm(p, 1.2) * 4)
            c = c * (grain * (0.88 + 0.2 * _hash(idx, idx * 3.1)))[:, None]
            c[gap] *= 0.45
            h = h - gap * 0.6
        elif kind == "ribs":  # ("ribs", spacing, "v" vertical on walls | "z" along z on tops)
            sp, d = step[1], step[2]
            if d == "v":
                on = np.abs(n[:, 1]) < 0.5
                co = np.where(np.abs(n[:, 0]) > np.abs(n[:, 2]), p[:, 2], p[:, 0])
            else:
                on = n[:, 1] > 0.5
                co = p[:, 0]
            w = np.sin(co * 2 * math.pi / sp) * on
            h = h + w * 0.6
            c = c * (0.9 + 0.1 * w)[:, None]
        elif kind == "bands":  # ("bands", spacing): rivet lines round a column
            sp = step[1]
            f = (p[:, 1] / sp) % 1
            line = (f < 0.04) | (f > 0.96)
            c[line] *= 0.6
            h = h + line * 0.6
            riv = line & (np.sin(np.arctan2(p[:, 0], p[:, 2]) * 24) > 0.85)
            c[riv] = rgbf((90, 86, 80))
        elif kind == "stripesY":  # ("stripesY", width, rgb2, from y)
            wd, rgb2, y0 = step[1], step[2], step[3]
            s = (((p[:, 1] - y0) / wd) % 2 < 1) & (p[:, 1] > y0)
            c[s] = rgbf(rgb2)
        elif kind == "hazard":  # ("hazard", width)
            wd = step[1]
            u, v, _ = uv2(p, n)
            s = ((u + v) / wd) % 2 < 1
            c = np.where(s[:, None], rgbf((244, 196, 36))[None, :], rgbf((36, 36, 40))[None, :]).astype(np.float32)
        elif kind == "dots":  # tactile paving bumps
            u, v, top = uv2(p, n)
            fu, fv = (u / 0.5) % 1 - 0.5, (v / 0.5) % 1 - 0.5
            dot = (fu * fu + fv * fv < 0.05) & top
            h = h + dot * 0.8
            c[dot] *= 1.08
        elif kind == "verdigris":
            k = sstep(0.55, 0.75, fbm(p, 2.2, 1.0))
            c = lerp(c, (84, 170, 146), k * 0.8)
            r = r * (1 - k) + 0.7 * k
        elif kind == "holes":  # dark gaps in a deck: ("holes", amount)
            k = fbm(p, 0.22, 6.0)
            hole = (k > 1 - step[1] * 0.5) & (n[:, 1] > 0.5)
            c[hole] = rgbf((24, 18, 14))
            h = h - hole * 1.0
        # ---- tinted regions: the copy's colour shows where alpha stays low
        elif kind == "brain":
            g = np.sin(p[:, 0] * 2.6 + 2.2 * np.sin(p[:, 2] * 1.9) + 1.6 * np.sin(p[:, 1] * 2.3))
            groove = np.abs(g) < 0.28
            ridge = g > 0.82
            c[groove] = (0.16, 0.06, 0.08)
            a[groove] = 0.6
            c[ridge] = (1.0, 0.96, 0.9)
            a[ridge] = np.maximum(a[ridge], 0.3)
            h = h - groove * 0.7
        elif kind == "polyps":  # ("polyps", scale)
            s = 0.36 * step[1]
            q = np.floor(p / s)
            cen = (q + 0.5) * s
            d = np.linalg.norm(p - cen, axis=1) / s
            hh = _hash(q[:, 0], q[:, 1], q[:, 2])
            dot = (d < 0.3) & (hh > 0.35)
            ring = (d >= 0.3) & (d < 0.42) & (hh > 0.35)
            c[dot] = (1.0, 0.97, 0.88)
            a[dot] = 0.72
            c[ring] = (0.2, 0.08, 0.1)
            a[ring] = np.maximum(a[ring], 0.35)
            h = h + dot * 0.7
        elif kind == "veins":  # kelp blades
            f = (p[:, 1] * 1.4 + 0.35 * np.sin(p[:, 0] * 3 + p[:, 2] * 3)) % 1
            vein = f < 0.07
            c[vein] = (0.1, 0.18, 0.06)
            a[vein] = 0.45
            lite = fbm(p, 1.5, 3.0) > 0.66
            c[lite & ~vein] = (0.85, 0.92, 0.45)
            a[lite & ~vein] = 0.3
        elif kind == "inner":
            c[:] = (0.08, 0.03, 0.05)
            a[:] = 0.8
        elif kind == "tips":  # pale tips on branches above y
            y0 = step[1]
            k = sstep(y0, y0 + 0.8, p[:, 1])
            c = c * (1 - k[:, None]) + np.array([1.0, 0.96, 0.9], np.float32)[None, :] * k[:, None]
            a = np.maximum(a, k * 0.75)
    col[m], alpha[m], rough[m], height[m] = c, a, r, h


vkit._pattern = deep_pattern

# ================================================================ paint regions
TILE = R("TileCream", (240, 232, 208), 0.32, pat=(("tiles", 1.5, (124, 120, 110), 0.05), ("rust", 0.22), ("grime", -4, -9)))
TILE_T = R("TileTeal", (52, 168, 166), 0.3, pat=(("tiles", 1.0, (30, 72, 72), 0.06), ("rust", 0.18)))
TILE_L = R("TileLine", (244, 206, 74), 0.32, pat=(("tiles", 1.0, (110, 92, 40), 0.05), ("rust", 0.15)))
PILLAR = R("TilePillar", (238, 236, 228), 0.32, pat=(("tiles", 0.8, (120, 120, 114), 0.04), ("rust", 0.25)))
CONC = R("Concrete", (132, 134, 136), 0.85, pat=(("concrete",), ("rust", 0.12), ("barnacle", 0.06)))
CONC_D = R("ConcreteDark", (96, 100, 108), 0.85, pat=(("concrete",), ("rust", 0.2)))
SILT = R("Silt", (168, 154, 118), 0.95, pat=(("silt",),))
PAVERS = R("Pavers", (150, 150, 146), 0.8, pat=(("tiles", 2.0, (96, 96, 92), 0.07), ("silt",)))
TACTILE = R("Tactile", (246, 200, 40), 0.6, pat=(("dots",),))
RIB = R("Rib", (56, 110, 104), 0.45, 0.6, pat=(("rust", 0.55),))
RAIL = R("RailSteel", (130, 124, 118), 0.35, 0.9, pat=(("rust", 0.55),))
SLEEPER = R("Sleeper", (98, 72, 52), 0.85, pat=(("planks", 0.55, "z"), ("rust", 0.1)))
BRASS = R("BrassD", (222, 168, 70), 0.3, 1.0, pat=(("verdigris",),))
DARK = R("DarkMetal", (48, 50, 58), 0.6, 0.5, pat=(("rust", 0.25),))
CABLE = R("Cable", (32, 32, 36), 0.7)
HAZARD = R("Hazard", (244, 196, 36), 0.5, 0.3, pat=(("hazard", 1.6), ("rust", 0.3)))
POSTER = R("PosterRed", (226, 84, 66), 0.6, pat=(("rust", 0.2),))
POSTER2 = R("PosterBlue", (66, 132, 214), 0.6, pat=(("rust", 0.2),))
DOOR = R("RustDoor", (108, 78, 64), 0.7, 0.5, pat=(("rust", 0.7),))
CARBODY = R("CarBody", (196, 202, 212), 0.35, 0.7, pat=(("rust", 0.42), ("barnacle", 0.16, -3.6), ("algae", -2.8, 2.5)))
CARDOOR = R("CarDoor", (174, 180, 192), 0.35, 0.7, pat=(("rust", 0.35),))
STRIPE = R("CarStripe", (226, 72, 60), 0.4, 0.3, pat=(("rust", 0.3),))
DGLASS = R("DarkGlass", (34, 62, 84), 0.08, 0.3)
ROOFUNIT = R("RoofUnit", (150, 156, 164), 0.5, 0.6, pat=(("ribs", 0.5, "z"), ("rust", 0.5)))
# the reef (tinted: the copy's colour shows through)
C_BRAIN = R("CoralBrain", None, 0.8, pat=(("brain",),))
C_POLYP = R("CoralPolyp", None, 0.75, pat=(("polyps", 1.0),))
C_SMOOTH = R("CoralSmooth", None, 0.7, pat=(("polyps", 1.6), ("tips", 1.6)))
C_INNER = R("CoralInner", None, 0.9, pat=(("inner",),))
KELP = R("Kelp", None, 0.55, pat=(("veins",),))
# the wrecks and the chest
WOOD = R("WreckWood", (138, 96, 62), 0.85, pat=(("planks", 0.9, "z"), ("rust", 0.08), ("barnacle", 0.3), ("algae", -2.0, 4.0)))
DECK = R("WreckDeck", (154, 112, 72), 0.85, pat=(("planks", 0.8, "z"), ("holes", 0.5), ("algae", 6.0, 1.2)))
WREEL = R("WreckWoodDark", (98, 68, 46), 0.85, pat=(("planks", 0.6, "x"), ("barnacle", 0.25)))
CABIN = R("CabinPaint", (214, 206, 186), 0.5, 0.3, pat=(("rust", 0.75), ("barnacle", 0.15)))
CHEST = R("ChestWood", (176, 112, 62), 0.75, pat=(("planks", 0.7, "x"), ("barnacle", 0.12)))
IRON = R("ChestIron", (70, 72, 80), 0.5, 0.8, pat=(("rust", 0.5),))
GOLD = R("ChestGold", (248, 196, 56), 0.25, 1.0)
WEED = R("Seaweed", (78, 150, 70), 0.6)
STAR = R("Figurehead", (240, 190, 60), 0.3, 1.0, pat=(("verdigris",),))
# the factory
PANEL = R("FactoryPanel", (66, 72, 96), 0.5, 0.6, pat=(("ribs", 1.4, "v"), ("rust", 0.42), ("barnacle", 0.12, -20), ("algae", -24, 10)))
PANEL_D = R("FactoryDark", (46, 48, 62), 0.55, 0.6, pat=(("rust", 0.45),))
BEAM = R("FactoryBeam", (92, 96, 120), 0.45, 0.7, pat=(("bands", 4.0), ("rust", 0.5)))
ROOFD = R("RoofDeck", (80, 84, 104), 0.55, 0.6, pat=(("ribs", 2.0, "z"), ("rust", 0.5), ("algae", 3.0, 1.0)))
CHIM = R("ChimneySteel", (164, 92, 62), 0.6, 0.5, pat=(("bands", 3.2), ("rust", 0.65), ("stripesY", 1.6, (236, 232, 220), 13.0)))
PIPE = R("PipePaint", (66, 142, 136), 0.5, 0.6, pat=(("rust", 0.6), ("barnacle", 0.3)))
# the quay
QUAY = R("QuayStone", (164, 158, 144), 0.85, pat=(("blocks", 4.0, 2.0, (96, 92, 86)), ("algaeBand", 16.7), ("barnacle", 0.12, 16.2)))
COPING = R("Coping", (206, 200, 186), 0.7, pat=(("concrete",),))
TIMBER = R("FenderWood", (118, 84, 56), 0.85, pat=(("planks", 0.8, "x"), ("algaeBand", 16.7)))
# the gear
TANK = R("TankPaint", (250, 200, 44), 0.35, 0.4, pat=(("stripesY", 0.5, (40, 40, 44), 1.4),))
TORP = R("TorpedoBody", (52, 64, 104), 0.35, 0.6, pat=(("bands", 0.9),))
REDB = R("TorpedoBand", (230, 54, 48), 0.4, 0.3)
STEEL = R("GearSteel", (172, 180, 190), 0.25, 1.0)

G_TUN = Grp("DeepTunnel")
G_STA = Grp("DeepStation")
G_CAR = Grp("DeepCar")
G_REEF = Grp("DeepReef")
G_WRECK = Grp("DeepWreck")
G_FAC = Grp("DeepFactory")
G_QUAY = Grp("DeepQuay", 512)
G_GEAR = Grp("DeepGear", 512)

LAMP = (255, 206, 130)
PORT = (70, 190, 200)
NULLGLOW = (120, 90, 255)


def rails(parts, x0, x1, y_floor):
    """Two rails (dz -3, 3) from x0 to x1 and sleepers every 2.5 studs, on a floor at y_floor."""
    L, mx = x1 - x0, (x0 + x1) / 2
    for dz in (-3, 3):
        parts += [P(B(L, 0.1, 0.56, mx, y_floor + 0.05, dz), RAIL), P(B(L, 0.3, 0.18, mx, y_floor + 0.25, dz), RAIL),
                  P(B(L, 0.18, 0.44, mx, y_floor + 0.5, dz), RAIL)]
    k = 0
    while x0 + 1.25 + k * 2.5 < x1:
        parts.append(P(B(1.1, 0.22, 9.2, x0 + 1.25 + k * 2.5, y_floor + 0.02, 0), SLEEPER))
        k += 1


# ================================================================ the Sunken Line
# ---------------------------------------------------------------- a tunnel segment (frame 20 x 24 x 30: the four walls
# and both rails over 20 studs; the cavity is y -9..9, z -12..12)
look("TunnelSegment", (20, 24, 30))
sh = [P(B(20, 2.88, 30, 0, -10.56, 0), CONC_D), P(B(20, 0.12, 24, 0, -9.06, 0), SILT),
      P(B(20, 3, 30, 0, 10.5, 0), CONC_D)]
for s_ in (1, -1):
    sh += [P(B(20, 18, 3, 0, 0, s_ * 13.5), TILE), P(B(20, 4, 0.24, 0, -7.0, s_ * 11.88), TILE_T),
           P(B(20, 0.8, 0.22, 0, 3.6, s_ * 11.89), TILE_L),
           P(prism([(s_ * 12, 9.0), (s_ * 12, 7.4), (s_ * 10.4, 9.0)], -10, 10), CONC)]
    for x in (-9.6, 9.6):
        sh.append(P(B(0.8, 16.4, 0.5, x, 0.8, s_ * 11.75), RIB))
    # porthole lamps: a brass ring on a dark plate
    sh += [P(TOR(1.25, 0.22, 0, 0.6, s_ * 11.84, axis="z", segs=20, csegs=6), BRASS),
           P(C(1.6, 0.14, 0, 0.6, s_ * 11.93, segs=20, axis="z"), DARK)]
for x in (-9.6, 9.6):
    sh.append(P(B(0.8, 0.5, 24, x, 8.75, 0), RIB))
rails(sh, -10, 10, -9.0)
sh += [P(C(0.45, 20, 0, 6.2, 11.3, segs=10, axis="x"), RAIL), P(B(0.4, 1.2, 0.8, -5, 6.2, 11.6), DARK),
       P(B(0.4, 1.2, 0.8, 5, 6.2, 11.6), DARK)]
for k in range(3):
    sh.append(P(C(0.14, 20, 0, 4.6 + k * 0.36, -11.7, segs=6, axis="x"), CABLE))
sh.append(P(rbox(3.2, 0.55, 1.3, 0, 8.72, 0, bev=0.1, segs=1), DARK))
add(G_TUN, "TunnelSegment", "TunnelShell", sh)
add(G_TUN, "TunnelSegment", "TunnelLamp", [B(2.7, 0.12, 0.9, 0, 8.4, 0)], LAMP, "Neon")
add(G_TUN, "TunnelSegment", "TunnelPorthole", [C(1.08, 0.08, 0, 0.6, s_ * 11.78, segs=20, axis="z") for s_ in (1, -1)],
    PORT, "Neon")

# ---------------------------------------------------------------- the station platform (frame 85 x 6 x 18; the track
# edge at +z, the top at y 3)
look("StationPlatform", (85, 6, 18))
pl = [P(B(85, 5.6, 17.6, 0, -0.2, -0.2), CONC), P(B(85, 0.4, 16.4, 0, 2.8, -0.8), PAVERS),
      P(B(85, 0.44, 1.2, 0, 2.8, 7.95), TACTILE), P(B(85, 0.5, 0.45, 0, 2.75, 8.78), CONC),
      P(B(85, 4.9, 0.22, 0, -0.6, 8.9), TILE_T)]
add(G_TUN, "StationPlatform", "PlatformBody", pl)

# ---------------------------------------------------------------- a station pillar (frame 2.5 x 12 x 2.5)
look("StationPillar", (2.5, 12, 2.5))
pp = [P(rbox(2.3, 10.6, 2.3, 0, 0, 0, bev=0.12, segs=1), PILLAR), P(rbox(2.9, 0.8, 2.9, 0, -5.6, 0, bev=0.1, segs=1), TILE_T),
      P(rbox(3.0, 0.7, 3.0, 0, 5.65, 0, bev=0.1, segs=1), RIB), P(B(2.6, 0.4, 2.6, 0, 5.1, 0), RIB),
      P(B(2.36, 0.5, 2.36, 0, 1.5, 0), TILE_L)]
add(G_TUN, "StationPillar", "PillarBody", pp)

# ---------------------------------------------------------------- the station's shell (frame 91 x 24 x 70: floor,
# ceiling, the side walls, the west end and the east end's steps round the tunnel; the cavity x -42.5..42.5,
# y -9..9, z -32..32; the platform along -z, the porthole windows along +z)
look("StationShell", (91, 24, 70))
ss = [P(B(91, 2.88, 70, 0, -10.56, 0), CONC_D), P(B(85, 0.12, 64, 0, -9.06, 0), SILT),
      P(B(91, 3, 70, 0, 10.5, 0), CONC_D)]
ss += [P(B(91, 18, 3, 0, 0, 33.5), TILE), P(B(91, 18, 3, 0, 0, -33.5), TILE), P(B(3, 18, 64, -44, 0, 0), TILE),
       P(B(3, 18, 20, 44, 0, -22), TILE), P(B(3, 18, 20, 44, 0, 22), TILE)]
# dado and line bands (the south wall's dado is behind the platform: its band sits above it)
ss += [P(B(85, 4, 0.24, 0, -7, 31.88), TILE_T), P(B(0.24, 4, 64, -42.38, -7, 0), TILE_T),
       P(B(85, 0.8, 0.22, 0, 3.6, 31.89), TILE_L), P(B(85, 0.8, 0.22, 0, 3.6, -31.89), TILE_L),
       P(B(0.22, 0.8, 64, -42.39, 3.6, 0), TILE_L), P(B(85, 1.6, 0.24, 0, -2.2, -31.88), TILE_T)]
for z0 in (-22, 22):
    ss += [P(B(0.24, 4, 20, 42.38, -7, z0), TILE_T), P(B(0.22, 0.8, 20, 42.39, 3.6, z0), TILE_L)]
# porthole windows along the north wall
for i in range(6):
    x = -35 + i * 14
    ss += [P(TOR(2.6, 0.4, x, 0.8, 31.8, axis="z", segs=24, csegs=6), BRASS),
           P(C(3.2, 0.16, x, 0.8, 31.92, segs=24, axis="z"), DARK)]
    for k in range(8):
        a = k * math.pi / 4
        ss.append(P(S(0.2, x + math.cos(a) * 3.0, 0.8 + math.sin(a) * 3.0, 31.8, segs=6, rings=4), BRASS))
# ribs every 17 studs on the walls and the ceiling
for x in (-34, -17, 0, 17, 34):
    ss += [P(B(0.9, 0.6, 64, x, 8.7, 0), RIB), P(B(0.9, 16.4, 0.5, x, 0.8, 31.75), RIB)]
    if abs(x) != 0:
        ss.append(P(B(0.9, 12.4, 0.5, x, 2.8, -31.75), RIB))
for s_ in (1, -1):
    ss.append(P(prism([(s_ * 32, 9.0), (s_ * 32, 7.6), (s_ * 30.6, 9.0)], -42.5, 42.5), CONC))
# the name board's frame (the glowing board itself is the game's own part), two posters, the lamps
ss += [P(B(33, 3.6, 0.3, 0, 7.5, -31.85), DARK)]
for x, reg in ((-25, POSTER), (25, POSTER2)):
    ss += [P(B(7, 4.6, 0.2, x, 4.6, -31.88), DARK), P(B(6.2, 3.8, 0.12, x, 4.6, -31.76), reg),
           P(star(1.2, 0.5, 0.1, x, 4.8, -31.68), TILE_L)]
for x in (-25.5, -8.5, 8.5, 25.5):
    for z in (-16, 16):
        ss.append(P(rbox(4.0, 0.5, 1.4, x, 8.72, z, bev=0.1, segs=1), DARK))
# the tunnel portal (east end) and a rusted service door (west end)
ss += [P(B(1.2, 18, 1.2, 42.3, 0, 12.6), HAZARD), P(B(1.2, 18, 1.2, 42.3, 0, -12.6), HAZARD),
       P(B(1.2, 1.6, 26.4, 42.3, 8.2, 0), HAZARD),
       P(B(0.3, 9, 8, -42.36, -4.5, 20), DOOR), P(B(0.4, 9.8, 0.6, -42.3, -4.1, 15.7), DARK),
       P(B(0.4, 9.8, 0.6, -42.3, -4.1, 24.3), DARK), P(B(0.4, 0.6, 9.2, -42.3, 0.6, 20), DARK)]
# the line's rails run on through the station to the buffer at the west end
rails(ss, -36, 42.5, -9.0)
ss += [P(rbox(1.2, 2.2, 9, -37, -7.9, 0, bev=0.2, segs=1), HAZARD)]
add(G_STA, "StationShell", "StationBody", ss)
lamps = []
for x in (-25.5, -8.5, 8.5, 25.5):
    for z in (-16, 16):
        lamps.append(B(3.5, 0.12, 0.9, x, 8.42, z))
add(G_STA, "StationShell", "StationLamp", lamps, LAMP, "Neon")
add(G_STA, "StationShell", "StationPorthole",
    [C(2.35, 0.1, -35 + i * 14, 0.8, 31.76, segs=24, axis="z") for i in range(6)], (60, 150, 186), "Neon")

# ---------------------------------------------------------------- a flooded train car (frame 54.2 x 11.8 x 11.8: the
# car's box, its stripe and window bands, and the bogies down to the floor at y -5.9; built along z, then turned so
# the car runs along x as the game's does)
look("TrainCar", (54.2, 11.8, 11.8))
YB, YT, CY = -5.1, 5.9, 0.4
st_ = [(-27.0, 4.7, YB + 0.5, YT - 0.7), (-26.6, 5.3, YB + 0.1, YT - 0.2), (-25.8, 5.5, YB, YT)]
st_ += [(z, 5.5, YB, YT) for z in (-18, -6, 6, 18)]
st_ += [(-z, w, yb, yt) for (z, w, yb, yt) in reversed(st_[:3])]
car = [P(loft_z(st_, segs=20, power=5.0), CARBODY)]
car.append(P(B(11.2, 1.0, 54.2, 0, CY - 2.5, 0), STRIPE))
WINS = [-23, -18.6, -9.6, -5.2, 5.2, 9.6, 18.6, 23]
for s_ in (1, -1):
    for z in WINS:
        car += [P(B(0.12, 2.8, 3.8, s_ * 5.52, CY + 1.5, z), DGLASS), P(B(0.1, 3.3, 4.3, s_ * 5.47, CY + 1.5, z), DARK)]
    for z in (-14, 0, 14):
        car += [P(B(0.14, 7.6, 3.8, s_ * 5.5, CY - 0.4, z), CARDOOR), P(B(0.1, 7.9, 0.12, s_ * 5.58, CY - 0.4, z), DARK),
                P(B(0.16, 2.6, 1.3, s_ * 5.6, CY + 1.6, z - 0.9), DGLASS),
                P(B(0.16, 2.6, 1.3, s_ * 5.6, CY + 1.6, z + 0.9), DGLASS)]
for zf in (-1, 1):
    car += [P(B(7.6, 2.6, 0.12, 0, CY + 2.0, zf * 27.0), DGLASS), P(B(8.2, 3.1, 0.1, 0, CY + 2.0, zf * 26.95), DARK),
            P(C(0.45, 0.14, 3.0, CY - 2.6, zf * 27.02, segs=12, axis="z"), DGLASS),
            P(C(0.45, 0.14, -3.0, CY - 2.6, zf * 27.02, segs=12, axis="z"), DGLASS),
            P(B(1.3, 1.0, 1.0, 0, YB + 1.2, zf * 27.3), DARK)]
for z in (-15, 15):
    car.append(P(rbox(6.0, 0.7, 4.4, 0, YT + 0.2, z, bev=0.15, segs=1), ROOFUNIT))
for z in (-18, 18):
    car.append(P(B(6.4, 0.6, 8.6, 0, -5.35, z), DARK))
    for zz in (z - 2.6, z + 2.6):
        for sx in (-3, 3):
            car.append(P(C(0.4, 0.3, sx, -5.5, zz, segs=12, axis="x"), RAIL))
for p_ in car:
    turn(p_, "up", 90)
add(G_CAR, "TrainCar", "TrainBody", car)

# ================================================================ the reef (tinted: each copy takes its palette colour)


def lumpy(ob, amp, f, seed):
    def fn(v):
        k = 1 + amp * math.sin(v.x * f + seed) * math.sin(v.y * f * 1.3 + seed * 2) * math.sin(v.z * f * 0.9 + seed * 3)
        return v * k
    return kit.deform(ob, fn)


# ---------------------------------------------------------------- a brain coral (frame 5 cube: the box's ball)
look("CoralBrain", (5, 5, 5))
br = lumpy(S(2.3, 0, 0.15, 0, segs=22, rings=14), 0.06, 1.6, 0.4)
lobe = lumpy(S(1.15, 1.45, -1.0, 1.05, segs=14, rings=9), 0.08, 2.2, 1.2)
add(G_REEF, "CoralBrain", "CoralBrainMesh", [P(br, C_BRAIN), P(lobe, C_BRAIN)], tint=True)

# ---------------------------------------------------------------- a knob coral: a mound of lumps
look("CoralKnob", (5, 5, 5))
kn = []
for (x, y, z, r) in ((0, -0.9, 0, 1.6), (1.2, -0.7, 0.9, 1.15), (-1.15, -0.6, -0.8, 1.1), (0.4, 0.5, -0.5, 1.05),
                     (-0.6, 0.7, 0.7, 0.9), (0.9, 1.3, 0.2, 0.75), (-0.2, 1.75, -0.1, 0.6)):
    kn.append(P(lumpy(S(r, x, y, z, segs=12, rings=8), 0.1, 3.0, x + z), C_POLYP))
add(G_REEF, "CoralKnob", "CoralKnobMesh", kn, tint=True)

# ---------------------------------------------------------------- a staghorn coral: branches out of a base
look("CoralStag", (5, 5, 5))
sg = [P(S(0.8, 0, -2.0, 0, sc=(1, 0.6, 1), segs=10, rings=6), C_SMOOTH)]
for k in range(6):
    a = k * math.pi / 3 + 0.3
    dx, dz = math.cos(a), math.sin(a)
    tip = (dx * 1.9, 2.1 - (k % 2) * 0.6, dz * 1.9)
    mid = (dx * 0.9, -0.3, dz * 0.9)
    sg.append(P(T([(0, -2.0, 0), mid, tip], [0.36, 0.28, 0.13], segs=7), C_SMOOTH))
    side = (mid[0] + dz * 0.9, 0.9, mid[2] - dx * 0.9)
    sg.append(P(T([mid, side], [0.22, 0.1], segs=6), C_SMOOTH))
add(G_REEF, "CoralStag", "CoralStagMesh", sg, tint=True)

# ---------------------------------------------------------------- tube sponges (frame 3.2 x 7 x 3.2)
look("CoralTube", (3.2, 7, 3.2))
tb, tin = [], []
for (x, z, h, r) in ((0, 0, 7.0, 0.55), (0.95, 0.45, 5.2, 0.5), (-0.75, 0.8, 4.3, 0.45), (-0.45, -0.95, 3.5, 0.42)):
    y0 = -3.5
    tb.append(P(C(r * 0.85, h - 0.2, x, y0 + (h - 0.2) / 2, z, segs=10, r2=r), C_POLYP))
    tb.append(P(TOR(r * 0.95, 0.11, x, y0 + h - 0.15, z, segs=12, csegs=5), C_POLYP))
    tin.append(P(C(r * 0.82, 0.06, x, y0 + h - 0.12, z, segs=10), C_INNER))
add(G_REEF, "CoralTube", "CoralTubeMesh", tb + tin, tint=True)

# ---------------------------------------------------------------- pillar coral fingers
look("CoralFinger", (3.2, 7, 3.2))
fg = []
for (x, z, h, r) in ((0, 0, 6.6, 0.42), (0.8, 0.5, 5.4, 0.36), (-0.7, 0.6, 4.6, 0.38), (0.5, -0.8, 4.1, 0.33),
                     (-0.6, -0.6, 3.4, 0.32), (1.1, -0.2, 2.8, 0.3)):
    y0 = -3.5
    fg += [P(C(r, h - r, x, y0 + (h - r) / 2, z, segs=10, r2=r * 0.92), C_SMOOTH),
           P(S(r * 0.92, x, y0 + h - r, z, segs=10, rings=6), C_SMOOTH)]
fg.append(P(S(1.3, 0, -3.3, 0, sc=(1, 0.3, 1), segs=12, rings=6), C_SMOOTH))
add(G_REEF, "CoralFinger", "CoralFingerMesh", fg, tint=True)

# ---------------------------------------------------------------- a sea fan: a lattice of veins in the x-y plane
# (frame 6 x 6 x 1.2; the box is a thin plate turned like it)
look("CoralFan", (6, 6, 1.2))
fn_ = [P(T([(0, -3.0, 0), (0, -2.2, 0)], [0.3, 0.22], segs=8), C_SMOOTH)]
ends = []
for k in range(9):
    a = math.radians(-66 + k * 16.5)
    p1 = (math.sin(a) * 1.4, -2.2 + math.cos(a) * 1.6, 0.12 * math.sin(k))
    p2 = (math.sin(a) * 2.9, -2.2 + math.cos(a) * 4.9, 0.3 * math.sin(k * 1.7))
    fn_.append(P(T([(0, -2.2, 0), p1, p2], [0.17, 0.12, 0.07], segs=5), C_SMOOTH))
    ends.append((p1, p2))
for k in range(8):  # cross links between neighbouring veins
    for t in (0.45, 0.75):
        a1, b1 = ends[k]
        a2, b2 = ends[k + 1]
        q1 = tuple(a1[i] + (b1[i] - a1[i]) * t for i in range(3))
        q2 = tuple(a2[i] + (b2[i] - a2[i]) * t for i in range(3))
        fn_.append(P(T([q1, q2], [0.06, 0.06], segs=4), C_SMOOTH))
add(G_REEF, "CoralFan", "CoralFanMesh", fn_, tint=True)

# ---------------------------------------------------------------- lettuce coral: ruffled upright plates
look("CoralLace", (6, 6, 1.2))
lc = []
for (r, x, y, ph) in ((2.6, 0, 0.2, 0.0), (1.9, -1.0, -1.0, 1.3), (1.7, 1.2, -1.2, 2.1)):
    poly = [(math.cos(i * math.pi / 14) * r * (1 + 0.1 * math.sin(i * 1.9 + ph)),
             math.sin(i * math.pi / 14) * r * (1 + 0.1 * math.sin(i * 1.9 + ph))) for i in range(28)]
    d = extrude_up(poly, -0.1, 0.1)
    kit.deform(d, lambda v, ph=ph, r=r: Vector(
        (v.x, v.y, v.z + 0.38 * math.sin(math.atan2(v.y, v.x) * 7 + ph) * min(1.0, math.hypot(v.x, v.y) / r))))
    turn(d, "x", 90)
    shift(d, rb(x, y, 0))
    lc.append(P(d, C_POLYP))
lc.append(P(S(0.9, 0, -2.6, 0, sc=(1.4, 0.5, 0.6), segs=10, rings=6), C_POLYP))
add(G_REEF, "CoralLace", "CoralLaceMesh", lc, tint=True)


# ---------------------------------------------------------------- a kelp strand (frame 5 x 20 x 5: the holdfast at
# the foot, y -10; DeepClient sways it about the foot)
def leaf(length, width):
    pts = []
    N = 9
    for i in range(N + 1):
        t = i / N
        pts.append((width * 0.5 * math.sin(math.pi * t) ** 0.7, t * length))
    pts += [(-zz, yy) for (zz, yy) in reversed(pts[1:-1])]
    lf = prism(pts, -0.03, 0.03)
    kit.deform(lf, lambda v: Vector((v.x + 0.18 * math.sin(v.z * 3.0), v.y, v.z)))
    return lf


look("KelpStrand", (5, 20, 5))
kp = [P(S(0.7, 0, -9.6, 0, sc=(1, 0.5, 1), segs=10, rings=6), KELP)]
spine = [(0.25 * math.sin(i * 0.9), -10 + i * 2.0, 0.25 * math.cos(i * 0.7)) for i in range(11)]
kp.append(P(T(spine, [0.2 - i * 0.012 for i in range(11)], segs=6), KELP))
for i in range(10):
    t = (i + 1) / 11
    j = t * 10
    k0 = int(j)
    k1 = min(10, k0 + 1)
    at = tuple(spine[k0][q] + (spine[k1][q] - spine[k0][q]) * (j - k0) for q in range(3))
    lf = leaf(3.4 - t * 1.2, 0.75)
    turn(lf, "x", -28 - 10 * t)
    turn(lf, "up", i * 137.5)
    shift(lf, rb(*at))
    kp.append(P(lf, KELP))
    kp.append(P(S(0.2, at[0], at[1], at[2], segs=6, rings=4), KELP))
add(G_REEF, "KelpStrand", "KelpMesh", kp, tint=True)

# ================================================================ the shipwrecks and the chest
# ---------------------------------------------------------------- the hull (frame 14 x 12 x 60; the bow joins at +z)
look("WreckHull", (14, 12, 60))
hs = [(-30, 4.4, -2.2, 3.8), (-27, 5.8, -4.6, 4.4), (-22, 6.5, -5.8, 4.6), (-10, 6.8, -6.0, 4.7), (10, 6.8, -6.0, 4.7),
      (30, 6.8, -6.0, 4.6)]
hull = hull_z(hs, segs=12)
hl = [P(hull, WOOD)]
hl.append(P(B(12.4, 0.5, 54, 0, 4.4, 2.0), DECK))
for z in range(-24, 30, 6):
    for s_ in (1, -1):
        hl.append(P(C(0.18, 1.5, s_ * 6.3, 5.4, z, segs=6), WREEL))
for s_ in (1, -1):
    hl.append(P(T([(s_ * 6.3, 6.1, -25), (s_ * 6.3, 6.1, 29)], 0.16, segs=5), WREEL))
for z in (-29.0, -27.2):  # the broken stern's bare ribs
    rib = TOR(5.4, 0.28, 0, 0, 0, axis="z", segs=14, csegs=5, arc=math.pi)
    turn(rib, "z", 180)
    shift(rib, rb(0, 3.6, z))
    hl.append(P(rib, WREEL))
hl.append(P(C(0.75, 2.6, 0, 6.0, 8, segs=10, r2=0.6), WREEL))
for p_ in hl:
    turn(p_, "z", 6, pivot=(0, -6, 0))
add(G_WRECK, "WreckHull", "WreckHullMesh", hl)

# ---------------------------------------------------------------- the bow (frame 14 x 12 x 16: the box is a wedge that
# rises to +z, so the broken bow rises out of the sand to its prow there)
look("WreckBow", (14, 12, 16))
bs = [(-8, 6.8, -6.4, -5.0), (-4, 6.6, -6.4, -2.2), (0, 6.0, -6.4, 0.8), (4, 4.4, -5.2, 3.6), (6.6, 2.4, -3.6, 5.2),
      (7.9, 0.4, -1.8, 5.9)]
bw = [P(hull_z(bs, segs=12), WOOD)]
bw.append(P(star(0.9, 0.38, 0.25, 0, 4.4, 7.6), STAR))
bw.append(P(T([(0, 5.6, 7.4), (0, 6.6, 8.6)], [0.22, 0.12], segs=6), WREEL))
add(G_WRECK, "WreckBow", "WreckBowMesh", bw)

# ---------------------------------------------------------------- the cabin (frame 10 x 7 x 12)
look("WreckCabin", (10, 7, 12))
cb = [P(rbox(9.6, 6.4, 11.6, 0, -0.3, 0, bev=0.35, segs=2), CABIN), P(rbox(10.0, 0.45, 12.0, 0, 3.05, 0, bev=0.1, segs=1), DARK),
      P(B(2.2, 4.4, 0.2, 2.0, -1.1, -5.85), DOOR), P(C(0.9, 2.6, -2, 4.4, 2, segs=12, r2=0.75), DARK)]
for s_ in (1, -1):
    for z in (-3, 0, 3):
        cb += [P(TOR(0.62, 0.13, s_ * 4.82, 0.9, z, axis="x", segs=14, csegs=5), BRASS),
               P(C(0.52, 0.06, s_ * 4.84, 0.9, z, segs=12, axis="x"), DGLASS)]
add(G_WRECK, "WreckCabin", "WreckCabinMesh", cb)

# ---------------------------------------------------------------- the broken mast, lying along z (frame 5 x 2.4 x 36)
look("WreckMast", (5, 2.4, 36))
ms = [P(C(0.9, 36, 0, 0, 0, segs=10, r2=0.55, axis="z"), WREEL)]
for z in (-14, -6, 2, 10):
    ms.append(P(TOR(0.86 - (z + 18) * 0.009, 0.1, 0, 0, z, axis="z", segs=12, csegs=4), IRON))
ms += [P(C(0.3, 5.0, 0, 0.6, 6.0, segs=8, axis="x"), WREEL), P(TOR(1.05, 0.14, 0, 0, 12, axis="z", segs=14, csegs=4), WREEL)]
add(G_WRECK, "WreckMast", "WreckMastMesh", ms)

# ---------------------------------------------------------------- a sunken cargo chest (frame 6 x 4 x 6)
look("CacheChest", (6, 4, 6))
lid_poly = [(2.1 * math.cos(i * math.pi / 10), 0.6 + 1.35 * math.sin(i * math.pi / 10)) for i in range(11)]
ch = [P(rbox(5.4, 2.6, 4.2, 0, -0.7, 0, bev=0.12, segs=1), CHEST), P(prism(lid_poly, -2.7, 2.7), CHEST)]
band_poly = [(2.22 * math.cos(i * math.pi / 10), 0.55 + 1.47 * math.sin(i * math.pi / 10)) for i in range(11)]
for x in (-2.55, -1.5, 1.5, 2.55):
    ch += [P(prism(band_poly, x - 0.16, x + 0.16), IRON), P(B(0.32, 2.7, 4.42, x, -0.68, 0), IRON)]
ch += [P(rbox(1.0, 1.2, 0.24, 0, 0.35, -2.22, bev=0.08, segs=1), GOLD), P(B(0.2, 0.42, 0.06, 0, 0.25, -2.36), IRON),
       P(T([(-2.6, -1.9, -2.2), (-2.0, 0.4, -2.25), (-1.0, 1.7, -1.4), (0.4, 2.0, -0.4), (1.6, 1.6, 0.8)],
           [0.12, 0.1, 0.1, 0.08, 0.06], segs=5), WEED)]
add(G_WRECK, "CacheChest", "ChestMesh", ch)
coins = [C(0.36, 0.1, x, 0.55, -2.02, segs=10, axis="z") for x in (-1.3, -0.6, 0.6, 1.3)]
add(G_WRECK, "CacheChest", "ChestGlint", coins, (255, 214, 90), "Neon")

# ================================================================ the sunken factory
# ---------------------------------------------------------------- the hall (frame 180 x 70 x 110; the gate on -z)
look("FactoryHall", (180, 70, 110))
fh = [P(B(176, 64, 106, 0, -1, 0), PANEL), P(B(180, 6, 110, 0, -32, 0), CONC_D), P(B(180, 4, 110, 0, 33, 0), PANEL_D)]
for x in range(-80, 81, 20):
    for s_ in (1, -1):
        fh.append(P(B(3, 64, 2.2, x, -1, s_ * 54.0), BEAM))
for z in range(-45, 46, 15):
    for s_ in (1, -1):
        fh.append(P(B(2.2, 64, 3, s_ * 89.0, -1, z), BEAM))
frames, mull = [], []
for x in range(-70, 71, 20):
    for s_ in (1, -1):
        frames.append(P(B(17, 12.6, 0.5, x, 18, s_ * 53.15), PANEL_D))
        mull += [P(B(0.5, 11.2, 0.3, x + dx, 18, s_ * 53.55), DARK) for dx in (-4.2, 0, 4.2)]
        mull.append(P(B(16.2, 0.5, 0.3, x, 18, s_ * 53.55), DARK))
for z in range(-37, 38, 15):
    for s_ in (1, -1):
        frames.append(P(B(0.5, 12.6, 11, s_ * 88.15, 18, z), PANEL_D))
        mull += [P(B(0.3, 11.2, 0.5, s_ * 88.55, 18, z), DARK), P(B(0.3, 0.5, 10.4, s_ * 88.55, 18, z), DARK)]
fh += frames + mull
# the gate's frame round the game's glowing gate, the sign over it, pipes, the back loading door
fh += [P(B(46, 3, 3, 0, -2.5, -54.5), HAZARD), P(B(3, 32, 3, -21.5, -19, -54.5), HAZARD),
       P(B(3, 32, 3, 21.5, -19, -54.5), HAZARD), P(C(6.4, 0.6, 0, 9, -53.6, segs=24, axis="z"), DARK),
       P(C(1.3, 170, 0, 4, -54.7, segs=10, axis="x"), PIPE), P(C(1.3, 170, 0, 4, 54.7, segs=10, axis="x"), PIPE),
       P(B(30, 24, 0.6, 30, -21, 53.4), DOOR), P(B(32, 1.6, 1.2, 30, -8.2, 53.8), HAZARD)]
for x in (-86, 86):
    for s_ in (1, -1):
        fh.append(P(C(1.0, 62, x, -2, s_ * 54.7, segs=8), PIPE))
add(G_FAC, "FactoryHall", "FactoryHallMesh", fh)
add(G_FAC, "FactoryHall", "FactoryWindows",
    [B(16, 11.2, 0.2, x, 18, s_ * 53.4) for x in range(-70, 71, 20) for s_ in (1, -1)]
    + [B(0.2, 11.2, 10.2, s_ * 88.4, 18, z) for z in range(-37, 38, 15) for s_ in (1, -1)], (84, 66, 186), "Neon")
sign = [TOR(5.0, 0.55, 0, 9, -53.15, axis="z", segs=24, csegs=6)]
for k in range(8):
    tt = B(1.4, 1.6, 0.6, 0, 0, 0)
    turn(tt, "z", k * 45)
    shift(tt, rb(math.cos(k * math.pi / 4) * 5.9, 9 + math.sin(k * math.pi / 4) * 5.9, -53.15))
    sign.append(tt)
sign.append(star(2.6, 1.0, 0.5, 0, 9, -53.15, points=4))
add(G_FAC, "FactoryHall", "FactorySign", sign, NULLGLOW, "Neon")

# ---------------------------------------------------------------- the roof (frame 186 x 6 x 116; the chimneys stand at
# x +-22.5, +-67.5, z 27.5)
look("FactoryRoof", (186, 6, 116))
fr = [P(B(186, 3, 116, 0, -1.5, 0), PANEL_D), P(B(184, 0.6, 114, 0, 0.3, 0), ROOFD)]
for s_ in (1, -1):
    fr += [P(B(186, 1.4, 1, 0, 1.3, s_ * 57.5), PANEL_D), P(B(1, 1.4, 116, s_ * 92.5, 1.3, 0), PANEL_D)]
for z in (-42, -26, -10, 6):
    fr.append(P(B(162, 0.9, 6.6, 0, 1.0, z), DARK))
for x in (-45, 0, 45):
    fr += [P(rbox(7, 2.2, 7, x, 1.7, 46, bev=0.2, segs=1), PANEL_D), P(C(2.6, 0.3, x, 2.9, 46, segs=16), DARK)]
add(G_FAC, "FactoryRoof", "FactoryRoofMesh", fr)
add(G_FAC, "FactoryRoof", "FactorySkylights", [B(160, 0.12, 5.4, 0, 1.5, z) for z in (-42, -26, -10, 6)], (70, 56, 160), "Neon")

# ---------------------------------------------------------------- a chimney (frame 12 x 40 x 12; the game's glowing cap
# sits on top)
look("FactoryChimney", (12, 40, 12))
cm = [P(C(5.6, 37, 0, -1.5, 0, segs=20, r2=4.6), CHIM), P(C(6.0, 2.0, 0, -19.0, 0, segs=20), CONC_D),
      P(C(4.95, 1.6, 0, 18.4, 0, segs=20, r2=4.8), DARK)]
for y in (-12, -2, 8):
    rr = 5.6 - (y + 20) / 37 * 1.0
    cm.append(P(TOR(rr + 0.05, 0.32, 0, y, 0, segs=20, csegs=5), DARK))
add(G_FAC, "FactoryChimney", "ChimneyMesh", cm)

# ---------------------------------------------------------------- a standing pipe (frame 6 x 60 x 6; the trench floor
# at y -3: it stands half buried as the game's box does)
look("FactoryPipe", (6, 60, 6))
pi_ = [P(C(2.5, 58, 0, -1, 0, segs=14), PIPE), P(C(2.6, 1.6, 0, 28.6, 0, segs=14, r2=2.0), DARK),
       P(C(3.0, 1.4, 0, -2.4, 0, segs=14), CONC_D)]
for y in (5, 17):
    pi_.append(P(C(2.95, 0.8, 0, y, 0, segs=14), DARK))
pi_ += [P(TOR(1.1, 0.16, 2.75, 10, 0, axis="x", segs=14, csegs=4), REDB), P(C(0.3, 0.5, 2.6, 10, 0, segs=8, axis="x"), DARK)]
for k in range(4):
    sp = B(0.12, 2.1, 0.16, 2.75, 10, 0)
    turn(sp, "x", k * 45, pivot=(2.75, 10, 0))
    pi_.append(P(sp, REDB))
add(G_FAC, "FactoryPipe", "PipeMesh", pi_)

# ================================================================ the harbour basin's quay wall (frame 24 x 36.6 x 4:
# one segment; the waterline at y 16.7, the top at 18.3)
look("QuayWall", (24, 36.6, 4))
qw = [P(B(24, 34.6, 4, 0, -1.0, 0), QUAY), P(rbox(24, 2.0, 4.6, 0, 17.3, 0, bev=0.15, segs=1), COPING)]
for s_ in (1, -1):
    qw += [P(TOR(0.66, 0.13, 0, 12.6, s_ * 2.16, axis="z", segs=14, csegs=4), IRON),
           P(B(0.45, 0.6, 0.3, 0, 13.3, s_ * 2.12), IRON),
           P(rbox(0.9, 15, 0.6, 7.0, 8.6, s_ * 2.28, bev=0.1, segs=1), TIMBER),
           P(rbox(0.9, 15, 0.6, -7.0, 8.6, s_ * 2.28, bev=0.1, segs=1), TIMBER)]
add(G_QUAY, "QuayWall", "QuayMesh", qw)

# ================================================================ the sea robots' gear, the torpedo and the bubble
# (EnemyRenderer sizes the helmet and tank to its own pieces; CombatFx the torpedo to 1.4 x 1.4 x 4, nose at -z)
look("DiverHelmet", (1.0, 1.0, 1.0))
add(G_GEAR, "DiverHelmet", "DiverDome", [S(0.5, segs=16, rings=10)], (190, 230, 255), "Glass", 0.55)
hf = [P(TOR(0.27, 0.045, 0, 0.02, -0.42, axis="z", segs=14, csegs=4), BRASS)]
for s_ in (1, -1):
    hf.append(P(TOR(0.2, 0.04, s_ * 0.45, 0.02, 0, axis="x", segs=12, csegs=4), BRASS))
top = TOR(0.48, 0.03, 0, 0, 0, axis="x", segs=16, csegs=3, arc=math.pi)
hf.append(P(top, BRASS))
hf.append(P(TOR(0.36, 0.06, 0, -0.38, 0, segs=16, csegs=4), BRASS))
for k in range(6):
    a = k * math.pi / 3
    hf.append(P(S(0.045, math.cos(a) * 0.36, -0.32, math.sin(a) * 0.36, segs=5, rings=3), BRASS))
add(G_GEAR, "DiverHelmet", "HelmetFrame", hf)

look("DiverTank", (1.0, 4.8, 1.0))
tk = [P(C(0.5, 3.4, 0, -0.3, 0, segs=16), TANK), P(S(0.5, 0, 1.4, 0, sc=(1, 0.55, 1), segs=16, rings=8), TANK),
      P(S(0.5, 0, -2.0, 0, sc=(1, 0.4, 1), segs=16, rings=8), TANK), P(C(0.16, 0.5, 0, 1.85, 0, segs=10), STEEL),
      P(C(0.26, 0.14, 0, 2.15, 0, segs=12), STEEL), P(T([(0.12, 1.9, 0), (0.4, 2.0, 0), (0.48, 1.4, 0)], 0.06, segs=5), IRON)]
add(G_GEAR, "DiverTank", "DiverTank", tk)

look("Torpedo", (1.4, 1.4, 4.0))
ts = [(-2.0, 0.06, -0.06, 0.06), (-1.85, 0.42, -0.42, 0.42), (-1.5, 0.64, -0.64, 0.64), (-1.0, 0.7, -0.7, 0.7),
      (1.2, 0.7, -0.7, 0.7), (1.6, 0.55, -0.55, 0.55), (1.85, 0.3, -0.3, 0.3)]
tp = [P(loft_z(ts, segs=16, power=2.0), TORP), P(C(0.72, 0.3, 0, 0, -0.9, segs=16, axis="z"), REDB),
      P(C(0.72, 0.16, 0, 0, 0.6, segs=16, axis="z"), REDB)]
for k in range(4):
    fin = B(0.07, 0.62, 0.55, 0, 0.62, 1.45)
    turn(fin, "z", k * 90)
    tp.append(P(fin, TORP))
tp.append(P(C(0.14, 0.22, 0, 0, 1.92, segs=10, axis="z"), BRASS))
for k in range(3):
    bl = B(0.06, 0.5, 0.14, 0, 0.28, 1.95)
    turn(bl, "z", k * 120)
    tp.append(P(bl, BRASS))
tp.append(P(S(0.12, 0, 0, -1.96, segs=8, rings=5), REDB))
add(G_GEAR, "Torpedo", "Torpedo", tp)

look("AirBubble", (7.0, 7.0, 7.0))
add(G_GEAR, "AirBubble", "AirBubbleGlass", [S(3.5, segs=28, rings=16)], (200, 240, 255), "Glass", 0.72)
shine = []
for (maj, arc, rot) in ((3.3, 1.4, (35, 30)), (3.0, 0.5, (60, 70))):
    t_ = TOR(maj, 0.09, 0, 0, 0, axis="z", segs=16, csegs=4, arc=arc)
    turn(t_, "z", 95)
    turn(t_, "up", rot[1])
    turn(t_, "x", -rot[0])
    shine.append(t_)
shine.append(S(0.32, -1.3, 2.5, -1.9, sc=(1, 0.7, 0.4), segs=8, rings=5))
add(G_GEAR, "AirBubble", "AirBubbleShine", shine, (255, 255, 255), "Neon", 0.4)

# ================================================================ bake, the fit table and the export
MAPS = {}
if "--no-bake" not in sys.argv:
    for gname, g in GROUPS.items():
        if not g.tex:
            continue
        print("baking", gname, flush=True)
        vkit.RES = g.res
        MAPS[gname] = vkit.bake_look(g, ao_samples=6 if FAST else 16)


def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    return lo, hi


TRIS = {}
total = 0
rows = []
for lk in sorted(LOOKS):
    fx, fy, fz = FRAMES[lk]
    rows.append("\t%s = {" % lk)
    rows.append("\t\tframe = { %.3f, %.3f, %.3f }," % (fx, fy, fz))
    rows.append("\t\tmeshes = {")
    for name in sorted(LOOKS[lk]):
        g = GROUPS[INFO[name]["group"]]
        ob = g.meshes[name]
        lo, hi = bounds(ob)
        c = [(lo[i] + hi[i]) / 2 for i in range(3)]
        size = [hi[i] - lo[i] for i in range(3)]
        t = kit.tris(ob)
        TRIS[name] = t
        total += t
        inf = INFO[name]
        extra = (", alpha = %g" % inf["alpha"]) if inf["alpha"] else ""
        extra += ", maps = true" if inf["maps"] else ""
        extra += ", tint = true" if inf["tint"] else ""
        rgb = inf["rgb"]
        rows.append("\t\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, mat = \"%s\"%s, tris = %d },"
                    % (name, max(size[0], 0.05), max(size[2], 0.05), max(size[1], 0.05), c[0], c[2], -c[1], rgb[0], rgb[1], rgb[2],
                       inf["mat"], extra, t))
    rows.append("\t\t},")
    rows.append("\t},")
print("deep: %d looks, %d meshes, %d tris" % (len(LOOKS), len(TRIS), total))
for lk in sorted(LOOKS):
    print("  %-16s %6d tris  (%s)" % (lk, sum(TRIS[n] for n in LOOKS[lk]), ", ".join(sorted(LOOKS[lk]))))
text = "\n".join([
    "-- GENERATED by art/blender/deep.py: do not edit by hand.",
    "-- The underwater areas in Blender meshes (ReplicatedStorage.Art.Deep; Shared.DeepArtKit, Shared.DeepLayout's art):",
    "-- look -> its frame (the box a placement stretches it over, studs x, up, z) and its meshes: each mesh's size and its",
    "-- centre from the frame's middle, its colour, material, transparency, maps (a baked texture set in its",
    "-- SurfaceAppearance: the colour map's alpha lets the part colour show, AlphaMode Overlay), tint (the copy's palette",
    "-- colour paints it) and triangles. %d meshes in %d looks, %d triangles." % (len(TRIS), len(LOOKS), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "DeepArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT], check=False)

if MAPS and "--no-export" not in sys.argv:
    export = []
    for gname, g in GROUPS.items():
        pm = vkit.export_material(g, MAPS[gname]) if gname in MAPS else None
        for name, ob in g.meshes.items():
            cp = copy(ob)
            cp.name = name + "_x"
            kit.centre(cp)
            cp.name = name
            cp.data.name = name
            cp.data.materials.clear()
            if name in g.tex:
                cp.data.materials.append(pm)
            else:
                rgb, mat, alpha = g.extra[name]
                cp.data.materials.append(kit.material(name + "Mat", rgb))
            export.append(cp)
    bpy.ops.object.select_all(action="DESELECT")
    for o in export:
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(kit.ROOT, "export", "Deep.fbx"), use_selection=True,
        apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", object_types={"MESH"},
        use_mesh_modifiers=True, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False,
        path_mode="COPY", embed_textures=True)
    for cp in export:
        bpy.data.objects.remove(cp, do_unlink=True)

if "--preview" in sys.argv:
    import deep_preview  # noqa: E402

    deep_preview.run(GROUPS, LOOKS, FRAMES, INFO, MAPS, fast=FAST)
