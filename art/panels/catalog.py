# catalog.py: fetches the Roblox catalog faces and hair that the comic panels and the guides' portraits wear
# (nate's hard rule: faces, hair, facial hair and eyes come only from the Roblox catalog, never drawn or modelled
# by us). Reads the ids from src/config/CatalogLooks.luau (the same list the game offers), downloads each through
# Open Cloud asset delivery (apis.roblox.com/asset-delivery-api; the proxy adds the key) into build/catalog/
# (not in git: the items are Roblox's, fetched again on any machine):
#   faces/<image id>.png             each classic face's image (the id CatalogLooks resolved)
#   hair/<asset id>.rbxm             each hair accessory; art/panels/accessory.luau reads them (Lune) into
#                                    hair/accessories.json (handle, mesh and texture ids, scale, attachment)
#   hair/mesh_<id>.json, tex_<id>.png  each hair's mesh (Roblox mesh versions 1 to 5, read here as plain data)
#                                    and texture; a mesh in a newer format is skipped and that hair is not used
#   hair/index.json                  { asset id: { mesh, texture, fit } } for art/blender/panels.py
#   beard/...                        the same for the catalog beards and moustaches (gap-villains, 2026-11-19)
# Run from the repo root: python3 -I art/panels/catalog.py   (needs curl and ~/tools/lune)
import gzip
import json
import os
import re
import struct
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "build", "catalog")
API = "https://apis.roblox.com/asset-delivery-api/v1/assetId/%d"
LUNE = os.path.expanduser("~/tools/lune")


def catalog_ids():
    src = open(os.path.join(REPO, "src", "config", "CatalogLooks.luau"), encoding="utf-8").read()
    faces_src = src.split("hair = {")[0]
    hair_src = src.split("hair = {")[1].split("beards = {")[0]
    beard_src = src.split("beards = {")[1]
    faces = [(n, int(a), int(i)) for n, a, i in re.findall(r'\{ "([^"]+)", (\d+), (\d+) \}', faces_src)]
    hair = [(n, int(a)) for n, a in re.findall(r'\{ "([^"]+)", (\d+) \}', hair_src)]
    beards = [(n, int(a)) for n, a in re.findall(r'\{ "([^"]+)", (\d+) \}', beard_src)]
    return faces, hair, beards


def fetch(asset_id, path):
    """Downloads one asset (asset delivery gives a short-lived CDN link) to path; True when it landed."""
    if os.path.isfile(path) and os.path.getsize(path) > 0:
        return True
    r = subprocess.run(["curl", "-sS", "-m", "40", "-H", "x-api-key: dummy", API % asset_id],
                       capture_output=True, text=True)
    try:
        loc = json.loads(r.stdout)["location"]
    except Exception:
        print("catalog.py: no location for", asset_id, r.stdout[:200])
        return False
    tmp = path + ".part"
    r = subprocess.run(["curl", "-sS", "-m", "90", "-o", tmp, loc], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.isfile(tmp):
        print("catalog.py: download failed", asset_id, r.stderr[:200])
        return False
    data = open(tmp, "rb").read()
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    open(path, "wb").write(data)
    os.remove(tmp)
    return True


# ------------------------------------------------------------------ Roblox mesh files (versions 1 to 5)
def read_mesh(data):
    """-> (positions, uvs, faces) with Roblox's axes (x right, y up, -z front) in studs; uv v as stored."""
    head = data[:16].split(b"\n")[0].strip().decode("ascii", "replace")
    ver = head.replace("version ", "")
    if ver.startswith("1."):
        lines = data.decode("ascii", "replace").splitlines()
        nums = [float(x) for x in re.findall(r"-?[\d.]+(?:e-?\d+)?", lines[2])]
        scale = 0.5 if ver == "1.00" else 1.0
        pos, uvs, faces = [], [], []
        for k in range(0, len(nums) - 8, 9):
            p = nums[k:k + 3]
            t = nums[k + 6:k + 8]
            pos.append((p[0] * scale, p[1] * scale, p[2] * scale))
            uvs.append((t[0], t[1]))
        for f in range(len(pos) // 3):
            faces.append((f * 3, f * 3 + 1, f * 3 + 2))
        return pos, uvs, faces
    o = data.index(b"\n") + 1
    if ver.startswith("2."):
        hs, vs, fs_, nv, nf = struct.unpack_from("<HBBII", data, o)
        o += hs
        lods = None
    elif ver.startswith("3."):
        hs, vs, fs_, ls, nl, nv, nf = struct.unpack_from("<HBBHHII", data, o)
        o += hs
        lods = nl
    elif ver.startswith("4.") or ver.startswith("5."):
        hs, _lt, nv, nf, nl, nb, _bn, _ns = struct.unpack_from("<HHIIHHIH", data, o)
        o += hs
        vs, lods = 40, nl
    else:
        raise ValueError("mesh format %s not read" % ver)
    pos, uvs = [], []
    for i in range(nv):
        x, y, z = struct.unpack_from("<3f", data, o)
        u, v = struct.unpack_from("<2f", data, o + 24)
        pos.append((x, y, z))
        uvs.append((u, v))
        o += vs
    if (ver.startswith("4.") or ver.startswith("5.")) and nb:
        o += nv * 8  # skinning envelopes
    faces = [struct.unpack_from("<3I", data, o + 12 * i) for i in range(nf)]
    o += 12 * nf
    if lods and lods > 1:
        offs = struct.unpack_from("<%dI" % lods, data, o)
        faces = faces[offs[0]:offs[1]]
    return pos, uvs, faces


def accessories(kind, items):
    """Downloads each accessory of a kind (hair or beard) into build/catalog/<kind>/ and writes its index.json
    ({ asset id: { mesh, texture, fit } }). A newer binary model rbx-dom misreads (Tags) is rewritten by
    art/upload/rbxfix.py first; the downloaded items are data only, nothing in them is run."""
    d = os.path.join(OUT, kind)
    os.makedirs(d, exist_ok=True)
    for _, aid in items:
        p = os.path.join(d, "%d.rbxm" % aid)
        if fetch(aid, p) and not os.path.isfile(p + ".fixed"):
            fix = subprocess.run([sys.executable, "-I", os.path.join(REPO, "art", "upload", "rbxfix.py"), p, p + ".tmp"],
                                 capture_output=True, text=True)
            if fix.returncode == 0 and os.path.isfile(p + ".tmp"):
                os.replace(p + ".tmp", p)
            open(p + ".fixed", "w").close()
    r = subprocess.run([LUNE, "run", os.path.join(REPO, "art", "panels", "accessory.luau"), d],
                       capture_output=True, text=True, cwd=REPO)
    print(r.stdout.strip(), r.stderr.strip()[:400])
    rows = json.load(open(os.path.join(d, "accessories.json")))
    index = {}
    for row in rows:
        aid = int(row["id"])
        row["mesh"] = int(row["mesh"]) if row.get("mesh") else None
        row["texture"] = int(row["texture"]) if row.get("texture") else None
        if not row.get("mesh"):
            continue
        mp = os.path.join(d, "mesh_%d.bin" % row["mesh"])
        if not fetch(row["mesh"], mp):
            continue
        try:
            pos, uvs, fc = read_mesh(open(mp, "rb").read())
        except Exception as e:  # noqa: BLE001
            print("catalog.py:", kind, aid, "mesh skipped:", e)
            continue
        json.dump({"pos": pos, "uv": uvs, "faces": fc}, open(os.path.join(d, "mesh_%d.json" % row["mesh"]), "w"))
        tex = None
        if row.get("texture"):
            tp = os.path.join(d, "tex_%d.png" % row["texture"])
            if fetch(row["texture"], tp) and open(tp, "rb").read(4) == b"\x89PNG":
                tex = os.path.basename(tp)
        index[str(aid)] = {"mesh": "mesh_%d.json" % row["mesh"], "texture": tex, "fit": row}
    json.dump(index, open(os.path.join(d, "index.json"), "w"), indent=1)
    print("catalog.py: %d of %d %s usable" % (len(index), len(items), kind))
    names = {str(a): n for n, a in items}
    for aid in sorted(set(names) - set(index)):
        print("  not usable:", aid, names[aid])


def main():
    faces, hair, beards = catalog_ids()
    fdir = os.path.join(OUT, "faces")
    os.makedirs(fdir, exist_ok=True)
    ok = sum(fetch(img, os.path.join(fdir, "%d.png" % img)) for _, _, img in faces)
    print("catalog.py: %d of %d faces" % (ok, len(faces)))
    accessories("hair", hair)
    accessories("beard", beards)


if __name__ == "__main__":
    sys.exit(main())
