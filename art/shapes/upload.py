# upload.py: the living world's round 2 (shapes-2, 2026-11-19) through Open Cloud like art/life/upload.py:
# art/export/Shapes.fbx (art/blender/shapes.py) as a Model, and as Images the road decals and pool water
# (art/shapes/decals.py: Zebra, Drain, Water) and the 13 fronts' lit windows (art/city/litwindows.py). The proxy adds
# the key, the creator is $ROBLOX_USER_ID. Each operation is polled and each asset's moderation checked.
# art/shapes/ids.json keeps { file: id } and each file's sha1, so only changed files go up again; the model's id goes
# to art/shapes/model_ids.json for art/upload/pull_models.py.  Run from the repo root: python3 -I art/shapes/upload.py
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
IDS = os.path.join(REPO, "art", "shapes", "ids.json")
MODEL_IDS = os.path.join(REPO, "art", "shapes", "model_ids.json")
API = "https://apis.roblox.com/assets/v1"
SHAPES = os.path.join(REPO, "art", "export", "shapes")
LIT = os.path.join(REPO, "art", "export", "city", "lit")
FRONTS = ("Brick", "Curtain", "Deco", "DockBrick", "Office", "OldBrick", "Panel", "Plaster", "Ribbon", "Siding", "Stone",
          "Timber", "Warehouse")
FILES = [(os.path.join(REPO, "art", "export", "Shapes.fbx"), "Shapes.fbx", "Model")] + [
    (os.path.join(SHAPES, n + ".png"), n + ".png", "Image") for n in ("Zebra", "Drain", "Water", "Dash")
] + [(os.path.join(LIT, "Lit%s.png" % f), "Lit%s.png" % f, "Image") for f in FRONTS]


def curl(*args):
    r = subprocess.run(["curl", "-sS", "-m", "300", "-H", "x-api-key: dummy", *args], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"raw": r.stdout[:300], "err": r.stderr[:300]}


def upload(path, user, kind):
    name = os.path.splitext(os.path.basename(path))[0]
    req = {"assetType": kind, "displayName": "Capeline " + name, "description": "Capeline living world art, round 2",
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
    for _ in range(160):
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
    json.dump({"Shapes": ids["Shapes.fbx"]}, open(MODEL_IDS, "w"), indent=1)


def main():
    user = os.environ.get("ROBLOX_USER_ID")
    if not user:
        print("upload.py: ROBLOX_USER_ID is not set")
        return 1
    ids = json.load(open(IDS)) if os.path.isfile(IDS) else {}
    sha = ids.setdefault("sha", {})
    failed = []
    for path, key, kind in FILES:
        h = hashlib.sha1(open(path, "rb").read()).hexdigest()
        if ids.get(key) and sha.get(key) == h:
            continue
        aid = upload(path, user, kind)
        if not aid:
            failed.append(key)
            print("upload.py: FAILED", key, flush=True)
            continue
        ids[key] = int(aid)
        sha[key] = h
        json.dump(ids, open(IDS, "w"), indent=1, sort_keys=True)
        print("upload.py: ok", key, aid, flush=True)
    bad = {}
    for _, key, _ in FILES:
        if ids.get(key):
            st = moderation(ids[key])
            if st != "Approved":
                bad[key] = st
    if not failed:
        write_ids(ids)
    print("upload.py: %d files, %d failed, moderation not approved: %s" % (len(FILES), len(failed), bad or "none"))
    return 1 if failed else 0


sys.exit(main())
