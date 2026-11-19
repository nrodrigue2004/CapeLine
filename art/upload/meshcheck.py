"""meshcheck.py: does Roblox's copy of each uploaded mesh face the way our FBX drew it? (fix-weapons, 2026-11-19)

    python3 -I art/upload/meshcheck.py SET [FBX]      e.g. Weapons (FBX defaults to art/export/<SET>.fbx)

Downloads each mesh id in art/models/<set>_meshids.json through the Open Cloud asset delivery API (the cloud
environment's secret adds the key; the header is a dummy), decodes Roblox's mesh file (version 4-5 plain, 6-7
COREMESH, Draco in v7; needs DracoPy, Apache-2.0), reads the FBX back with Blender (meshdump.py) and turns
it into Roblox's frame (x, up, back: Blender (x, z, -y), as kit.export writes it), then finds which turn of the
FBX geometry about its box centre matches Roblox's: identity, or a 180 degree turn about x, y or z, or a
mirror. Prints a tally and every mesh that does not match as drawn. Cache: build/meshcheck/<SET>/.
Found 2026-11-19: Open Cloud's FBX import turns every mesh 180 degrees about y (x and z flipped) inside its
MeshPart; the box size is the same, so only the geometry inside it is turned (Shared.MeshFix turns it back).
"""

import collections
import gzip
import json
import os
import struct
import subprocess
import sys
import time

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
BPY = os.path.expanduser("~/tools/bpyenv/bin/python")

TURNS = {
    "identity": (1, 1, 1), "rotY180": (-1, 1, -1), "rotX180": (1, -1, -1), "rotZ180": (-1, -1, 1),
    "mirrorX": (-1, 1, 1), "mirrorY": (1, -1, 1), "mirrorZ": (1, 1, -1), "mirrorAll": (-1, -1, -1),
}


def fetch(aid):
    for a in range(5):
        meta = subprocess.run(["curl", "-sS", "-H", "x-api-key: dummy",
                               f"https://apis.roblox.com/asset-delivery-api/v1/assetId/{aid}"],
                              capture_output=True, text=True).stdout
        try:
            loc = json.loads(meta)["location"]
        except (ValueError, KeyError):
            time.sleep(3 * (a + 1))
            continue
        raw = subprocess.run(["curl", "-sSf", loc], capture_output=True).stdout
        return gzip.decompress(raw) if raw[:2] == b"\x1f\x8b" else raw
    raise SystemExit(f"could not download {aid}")


def verts(data):
    head = data[:12].decode("ascii", "replace")
    major = int(head[8])
    if major >= 6:
        import DracoPy

        i = 13
        while i < len(data):
            name = data[i:i + 8]
            ver, size = struct.unpack("<II", data[i + 8:i + 16])
            body = data[i + 16:i + 16 + size]
            if name == b"COREMESH":
                if ver == 2:
                    return np.array(DracoPy.decode(body[body.find(b"DRACO"):]).points)
                nv = struct.unpack("<I", body[0:4])[0]
                return np.frombuffer(body[4:4 + nv * 40], dtype=np.float32).reshape(nv, 10)[:, :3]
            i += 16 + size
        raise ValueError("no COREMESH")
    raise ValueError("mesh " + head + ": only versions 6 and 7 are read")


def nn(a, b):
    d = np.sqrt(((a[:, None, :] - b[None, :, :]) ** 2).sum(-1))
    return d.min(1).mean()


def main():
    s = sys.argv[1]
    fbx = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "art", "export", s + ".fbx")
    cache = os.path.join(ROOT, "build", "meshcheck", s)
    os.makedirs(cache, exist_ok=True)
    dump = os.path.join(cache, "_fbx.json")
    subprocess.run([BPY, os.path.join(HERE, "meshdump.py"), fbx, dump], check=True, capture_output=True)
    drawn = json.load(open(dump))
    ids = json.load(open(os.path.join(ROOT, "art", "models", s.lower() + "_meshids.json")))
    tally, off = collections.Counter(), []
    for path, aid in sorted(ids.items()):
        if not isinstance(aid, int) or "#" in path:
            continue
        name = path.split(".")[-1]
        if name not in drawn:
            continue
        f = os.path.join(cache, name + ".bin")
        if not os.path.exists(f):
            open(f, "wb").write(fetch(aid))
        b = np.array(drawn[name])
        exp = np.stack([b[:, 0], b[:, 2], -b[:, 1]], 1)
        exp -= (exp.min(0) + exp.max(0)) / 2
        got = verts(open(f, "rb").read()).astype(float)
        got -= (got.min(0) + got.max(0)) / 2
        err = {k: nn(exp * np.array(t), got) for k, t in TURNS.items()}
        best = min(err, key=err.get)
        fits = sorted(k for k in err if err[k] < err[best] + 1e-3)
        tally[tuple(fits)] += 1
        if "identity" not in fits:
            off.append((err["identity"], name, best))
    for k, v in tally.most_common():
        print(f"{v:4d} match {', '.join(k)}")
    print(f"{len(off)} of {sum(tally.values())} meshes do not face as drawn")
    for e, n, best in sorted(off, reverse=True)[:20]:
        print(f"   {n}: {e:.3f} studs off as drawn, matches {best}")


if __name__ == "__main__":
    main()
