# robloxbody.py: fetches Roblox's own blocky R15 body meshes (the default body a blank HumanoidDescription gives,
# the same 15 meshes as Studio's Rig Builder "Block" rig) through Open Cloud asset delivery into build/robloxbody/
# (not in git: the meshes are Roblox's, fetched again on any machine) for the fit renders (art/blender/fit.py).
# Each <Part>.json: positions (Roblox axes, studs, about the mesh's own centre), uvs and faces, scaled to the part's
# size in src/config/RobloxRig.luau. Run from the repo root: python3 -I art/fit/robloxbody.py
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "art", "panels"))
import catalog  # noqa: E402

OUT = os.path.join(REPO, "build", "robloxbody")


def rig():
    """{part: {mesh, size, centre}} read from src/config/RobloxRig.luau."""
    src = open(os.path.join(REPO, "src", "config", "RobloxRig.luau"), encoding="utf-8").read()
    out = {}
    for m in re.finditer(r"(\w+) = \{\s*mesh = (\d+),\s*size = \{ ([-\d., ]+) \},\s*centre = \{ ([-\d., ]+) \}", src):
        out[m.group(1)] = {"mesh": int(m.group(2)), "size": [float(x) for x in m.group(3).split(",")],
                           "centre": [float(x) for x in m.group(4).split(",")]}
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    parts = rig()
    assert len(parts) == 15, sorted(parts)
    for name, row in parts.items():
        bin_ = os.path.join(OUT, "%d.bin" % row["mesh"])
        if not catalog.fetch(row["mesh"], bin_):
            print("robloxbody.py: could not fetch", name)
            return 1
        pos, uvs, faces = catalog.read_mesh(open(bin_, "rb").read())
        lo = [min(p[i] for p in pos) for i in range(3)]
        hi = [max(p[i] for p in pos) for i in range(3)]
        c = [(lo[i] + hi[i]) / 2 for i in range(3)]
        k = [row["size"][i] / max(hi[i] - lo[i], 1e-6) for i in range(3)]
        pos = [tuple((p[i] - c[i]) * k[i] for i in range(3)) for p in pos]
        json.dump({"pos": pos, "uv": uvs, "faces": faces, "size": row["size"], "centre": row["centre"]},
                  open(os.path.join(OUT, name + ".json"), "w"))
        print("robloxbody.py: %-14s %5d verts, mesh %s, native box %s" % (
            name, len(pos), row["mesh"], [round(hi[i] - lo[i], 3) for i in range(3)]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
