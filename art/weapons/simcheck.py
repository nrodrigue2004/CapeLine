"""simcheck.py: are the weapons whole in game? (fix-weapons, 2026-11-19)

    lune run art/weapons/simdump.luau build/Capeline.rbxl after     (and `before`: the turn left out)
    python3 -I art/upload/meshcheck.py Weapons                      (downloads Roblox's meshes into build/meshcheck)
    python3 -I art/weapons/simcheck.py [after|before] [--render]

Lays Roblox's own geometry (each downloaded MeshId, decoded) on the CFrame and size the game's code gave each piece
(build/weaponsim/<mode>.json), and the Blender layout (art/export/Weapons.fbx read back, the same box) on its body
part's frame, then reports per piece how far Roblox's copy sits from where the Blender sheets draw it (mean and
worst vertex, studs) and per look whether its pieces still touch each other (pieces in contact in the Blender layout
must be in contact in game, 0.08 stud, judged on points over the faces; needs numpy, scipy and DracoPy). --render writes build/weaponsim/<mode>_geo.json for simrender.py, which
draws art/preview/weapons_ingame_<mode>.png (Roblox's geometry where the game puts it, on the blocky body).
"""

import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

CACHE = os.path.join(ROOT, "build", "meshcheck", "Weapons")
TOUCH = 0.08


def decode(name):
    data = open(os.path.join(CACHE, name + ".bin"), "rb").read()
    import struct

    import DracoPy

    i = 13
    while i < len(data):
        nm = data[i:i + 8]
        ver, size = struct.unpack("<II", data[i + 8:i + 16])
        body = data[i + 16:i + 16 + size]
        if nm == b"COREMESH" and ver == 2:
            m = DracoPy.decode(body[body.find(b"DRACO"):])
            return np.array(m.points, float), np.array(m.faces, int)
        i += 16 + size
    raise ValueError(name)


def boxed(v, size):
    v = v - (v.min(0) + v.max(0)) / 2
    ext = np.maximum(v.max(0) - v.min(0), 1e-6)
    return v * (np.array(size) / ext)


RNG = np.random.default_rng(1)


def surface(v, faces, dens=400):
    """Points over a mesh's faces (area-weighted, plus its vertices), so contact is judged on surfaces"""
    a, b, c = v[faces[:, 0]], v[faces[:, 1]], v[faces[:, 2]]
    area = np.linalg.norm(np.cross(b - a, c - a), axis=1) / 2
    idx = np.repeat(np.arange(len(faces)), np.maximum(1, (area * dens).astype(int)))
    r1, r2 = np.sqrt(RNG.random(len(idx))), RNG.random(len(idx))
    pts = (1 - r1)[:, None] * a[idx] + (r1 * (1 - r2))[:, None] * b[idx] + (r1 * r2)[:, None] * c[idx]
    return np.vstack([pts, v])


def mindist(a, b):
    from scipy.spatial import cKDTree

    return float(cKDTree(b).query(a)[0].min())


def groups(clouds):
    n = len(clouds)
    parent = list(range(n))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for i in range(n):
        for j in range(i + 1, n):
            if mindist(clouds[i], clouds[j]) < TOUCH:
                parent[find(i)] = find(j)
    return len({find(i) for i in range(n)})


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else "after"
    sim = json.load(open(os.path.join(ROOT, "build", "weaponsim", mode + ".json")))
    drawn = json.load(open(os.path.join(CACHE, "_fbx.json")))
    geo_cache = {}
    worst, broken, rows, geo = [], [], 0, []
    per_weapon = {}
    for w in sim["weapons"]:
        actual, expect = [], []
        out_pieces = []
        for p in w["pieces"]:
            name = p["mesh"]
            if name not in geo_cache:
                geo_cache[name] = decode(name)
            v, faces = geo_cache[name]
            rot = np.array(p["cf"]["rot"])
            pos = np.array(p["cf"]["pos"])
            a = boxed(v, p["size"]) @ rot.T + pos
            b = np.array(drawn[name])
            b = np.stack([b[:, 0], b[:, 2], -b[:, 1]], 1)
            prot = np.array(w["parts"][p["part"]]["rot"])
            e = boxed(b, p["size"]) @ prot.T + pos
            d = np.sqrt(((a[:, None, :] - e[None, :, :]) ** 2).sum(-1)).min(1)
            rows += 1
            worst.append((d.max(), d.mean(), w["id"], w["style"], name))
            actual.append(surface(a, faces))
            expect.append(surface(e, np.array(drawn[name + "#faces"], int)))
            out_pieces.append({"mesh": name, "part": p["part"], "verts": a.round(4).tolist(), "faces": faces.tolist()})
        ga, ge = groups(actual), groups(expect)
        if ga > ge:
            broken.append((w["id"], w["name"], w["style"], ge, ga))
        key = w["id"]
        per_weapon[key] = max(per_weapon.get(key, 0), max((x[0] for x in worst[-len(w["pieces"]):]), default=0))
        if w["style"] == 1:
            geo.append({"id": w["id"], "name": w["name"], "parts": w["parts"], "pieces": out_pieces})
    worst.sort(reverse=True)
    off = [x for x in worst if x[0] > 0.5]
    offw = sorted({x[2] for x in off})
    print(f"{mode}: {len(sim['weapons'])} looks, {rows} pieces placed by the game's code")
    print(f"  pieces more than 0.5 stud from the Blender layout: {len(off)} (weapons {offw})")
    for x in off[:12]:
        print(f"    weapon {x[2]} style {x[3]} {x[4]}: worst {x[0]:.2f}, mean {x[1]:.2f} studs")
    print(f"  worst piece anywhere: {worst[0][0]:.3f} studs ({worst[0][4]})")
    print(f"  looks whose pieces come apart (more separate groups than drawn): {len(broken)}")
    names = sorted({(b[0], b[1]) for b in broken})
    if names:
        print("    weapons: " + ", ".join(f"{i} {n}" for i, n in names))
    for b in broken[:6]:
        print(f"    {b[0]} {b[1]} style {b[2]}: {b[3]} group(s) drawn, {b[4]} in game")
    if "--render" in sys.argv:
        json.dump({"mode": mode, "weapons": geo}, open(os.path.join(ROOT, "build", "weaponsim", mode + "_geo.json"), "w"))
        print("  wrote build/weaponsim/%s_geo.json" % mode)
    return 1 if (off or broken) else 0


sys.exit(main())
