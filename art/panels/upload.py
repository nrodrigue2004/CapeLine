# upload.py: the comic art pass, step 4: uploads art/export/panels' images (Panel_*.png, Portraits_*.png) as
# Image assets through Open Cloud (apis.roblox.com/assets/v1; the proxy adds the key, the creator is
# $ROBLOX_USER_ID), polls each operation, checks moderation, and keeps art/export/panels/ids.json
# ({ file: id }, plus each file's sha1 under "sha", so only new or changed images go up again).
# Then run python3 art/panels/post.py again to write the ids into src/config/ComicArt.luau (same images).
# Run from the repo root: python3 -I art/panels/upload.py
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "art", "export", "panels")
IDS = os.path.join(OUT, "ids.json")
API = "https://apis.roblox.com/assets/v1"


def curl(*args):
    r = subprocess.run(["curl", "-sS", "-m", "120", "-H", "x-api-key: dummy", *args], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"raw": r.stdout[:300], "err": r.stderr[:300]}


def upload(path, user):
    req = {"assetType": "Image", "displayName": "Capeline " + os.path.basename(path)[:-4].replace("_", " "),
           "description": "Capeline comic art", "creationContext": {"creator": {"userId": str(user)}}}
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(req, f)
        rp = f.name
    for attempt in range(5):
        op = curl("-X", "POST", API + "/assets", "-F", "request=<%s;type=application/json" % rp,
                  "-F", "fileContent=@%s;type=image/png" % path)
        if op.get("path"):
            break
        print("upload.py: retry", os.path.basename(path), op)
        time.sleep(5 * (attempt + 1))
    else:
        return None
    os.remove(rp)
    op_id = op["path"].split("/")[-1]
    for _ in range(60):
        if op.get("done") and op.get("response", {}).get("assetId"):
            return op["response"]["assetId"]
        time.sleep(2)
        op = curl(API + "/operations/" + op_id)
    return None


def moderation(asset_id):
    a = curl(API + "/assets/%s" % asset_id, "-G", "--data-urlencode", "readMask=moderationResult")
    return (a.get("moderationResult") or {}).get("moderationState", "?")


def main():
    user = os.environ.get("ROBLOX_USER_ID")
    if not user:
        print("upload.py: ROBLOX_USER_ID is not set")
        return 1
    ids = json.load(open(IDS)) if os.path.isfile(IDS) else {}
    sha = ids.setdefault("sha", {})
    files = sorted(f for f in os.listdir(OUT) if f.endswith(".png") and (f.startswith("Panel_") or
                                                                         f.startswith("Portraits_")))
    failed = []
    for f in files:
        path = os.path.join(OUT, f)
        h = hashlib.sha1(open(path, "rb").read()).hexdigest()
        if ids.get(f) and sha.get(f) == h:
            continue
        aid = upload(path, user)
        if not aid:
            failed.append(f)
            print("upload.py: FAILED", f)
            continue
        ids[f] = int(aid)
        sha[f] = h
        json.dump(ids, open(IDS, "w"), indent=1, sort_keys=True)
        print("upload.py: ok", f, aid, flush=True)
        time.sleep(1)
    states = {}
    for f in files:
        if ids.get(f):
            states[f] = moderation(ids[f])
    bad = {f: s for f, s in states.items() if s != "Approved"}
    print("upload.py: %d files, %d failed, moderation not approved: %s" % (len(files), len(failed), bad or "none"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
