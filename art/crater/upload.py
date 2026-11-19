# upload.py: the Crater's ground and the throw chip (gap-fx3, 2026-11-19), like art/news/upload.py: the CraterFloor
# and CraterRim maps (art/city/crater_materials.py), the burn scars scar_1..3.png and chip.png (art/fx/textures.py
# --scars, --chips) go up as Image assets through Open Cloud (apis.roblox.com/assets/v1; the proxy adds the key, the
# creator is $ROBLOX_USER_ID). Each operation is polled and each asset's moderation checked; art/crater/ids.json
# keeps { file: id } plus each file's sha1 under "sha", so only new or changed files go up again. Then it writes the
# ids in: src/materials/KitCraterFloor|KitCraterRim.model.json, Config.World crater.scars.decals and
# Config.Fx lib.textures.chip.
# Run from the repo root: python3 -I art/crater/upload.py
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
IDS = os.path.join(REPO, "art", "crater", "ids.json")
API = "https://apis.roblox.com/assets/v1"
CITY = os.path.join(REPO, "art", "export", "city")
FX = os.path.join(REPO, "art", "export", "fx")
GROUND = {"CraterFloor": ("Ground", 32), "CraterRim": ("Rock", 24)}
IMAGES = [(os.path.join(CITY, "%s_%s.png" % (g, m)), "%s_%s.png" % (g, m)) for g in GROUND for m in ("Color", "Normal", "Roughness")]
IMAGES += [(os.path.join(FX, f), f) for f in ("scar_1.png", "scar_2.png", "scar_3.png", "chip.png")]


def curl(*args):
    r = subprocess.run(["curl", "-sS", "-m", "300", "-H", "x-api-key: dummy", *args], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"raw": r.stdout[:300], "err": r.stderr[:300]}


def upload(path, user, kind):
    name = os.path.splitext(os.path.basename(path))[0]
    req = {"assetType": kind, "displayName": "Capeline " + name, "description": "Capeline effects and ground art",
           "creationContext": {"creator": {"userId": str(user)}}}
    ctype = "image/png" if kind == "Image" else "model/fbx"
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(req, f)
        rp = f.name
    for attempt in range(5):
        op = curl("-X", "POST", API + "/assets", "-F", "request=<%s;type=application/json" % rp,
                  "-F", "fileContent=@%s;type=%s" % (path, ctype))
        if op.get("path"):
            break
        print("upload.py: retry", os.path.basename(path), op, flush=True)
        time.sleep(5 * (attempt + 1))
    else:
        return None
    os.remove(rp)
    op_id = op["path"].split("/")[-1]
    for _ in range(120):
        if op.get("done") and op.get("response", {}).get("assetId"):
            return op["response"]["assetId"]
        time.sleep(3)
        op = curl(API + "/operations/" + op_id)
    print("upload.py: operation not done", op, flush=True)
    return None


def moderation(asset_id):
    a = curl(API + "/assets/%s" % asset_id, "-G", "--data-urlencode", "readMask=moderationResult")
    return (a.get("moderationResult") or {}).get("moderationState", "?")


def write_ids(ids):
    import re

    for g, (base, studs) in GROUND.items():
        mj = {"className": "MaterialVariant", "properties": {"BaseMaterial": base, "StudsPerTile": float(studs),
              "MaterialPattern": "Organic",
              "ColorMap": "rbxassetid://%d" % ids[g + "_Color.png"],
              "NormalMap": "rbxassetid://%d" % ids[g + "_Normal.png"],
              "RoughnessMap": "rbxassetid://%d" % ids[g + "_Roughness.png"]}}
        with open(os.path.join(REPO, "src", "materials", "Kit%s.model.json" % g), "w") as f:
            json.dump(mj, f, indent=2)
            f.write("\n")
    w = os.path.join(REPO, "src", "config", "World.luau")
    t = open(w).read()
    for k in (1, 2, 3):
        t = re.sub(r'(\{ id = )\d+(, file = "scar_%d\.png" \})' % k, r"\g<1>%d\g<2>" % ids["scar_%d.png" % k], t)
    open(w, "w").write(t)
    fx = os.path.join(REPO, "src", "config", "Fx.luau")
    t = open(fx).read()
    t = re.sub(r'(id = )\d+(,\s*file = "chip\.png")', r"\g<1>%d\g<2>" % ids["chip.png"], t)
    open(fx, "w").write(t)


def main():
    user = os.environ.get("ROBLOX_USER_ID")
    if not user:
        print("upload.py: ROBLOX_USER_ID is not set")
        return 1
    ids = json.load(open(IDS)) if os.path.isfile(IDS) else {}
    sha = ids.setdefault("sha", {})
    failed = []
    for path, key in IMAGES:
        h = hashlib.sha1(open(path, "rb").read()).hexdigest()
        if ids.get(key) and sha.get(key) == h:
            continue
        aid = upload(path, user, "Image")
        if not aid:
            failed.append(key)
            print("upload.py: FAILED", key, flush=True)
            continue
        ids[key] = int(aid)
        sha[key] = h
        json.dump(ids, open(IDS, "w"), indent=1, sort_keys=True)
        print("upload.py: ok", key, aid, flush=True)
    bad = {}
    for _, key in IMAGES:
        if ids.get(key):
            st = moderation(ids[key])
            if st != "Approved":
                bad[key] = st
    if not failed:
        write_ids(ids)
    print("upload.py: %d files, %d failed, moderation not approved: %s" % (len(IMAGES), len(failed), bad or "none"))
    return 1 if failed or bad else 0


if __name__ == "__main__":
    sys.exit(main())
