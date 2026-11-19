# upload.py: the news art's uploads (gap-news, 2026-11-19), like art/panels/upload.py: art/export/news's images
# (NewsCards, NamePlate, TvCase, NewsIdent) go up as Image assets and art/export/News.fbx as a Model through Open
# Cloud (apis.roblox.com/assets/v1; the proxy adds the key, the creator is $ROBLOX_USER_ID). Each operation is
# polled and each asset's moderation checked; art/export/news/ids.json keeps { file: id } plus each file's sha1
# under "sha", so only new or changed files go up again. Then:
#   python3 art/news/post.py                                       (writes the image ids into Config.NewsArt)
#   python3 -I art/upload/pull_models.py art/export/news/models.json News   (Art.News into art/models/News.rbxm)
# Run from the repo root: python3 -I art/news/upload.py
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "art", "export", "news")
FBX = os.path.join(REPO, "art", "export", "News.fbx")
IDS = os.path.join(OUT, "ids.json")
MODELS = os.path.join(OUT, "models.json")
API = "https://apis.roblox.com/assets/v1"
IMAGES = ("NewsCards.png", "NamePlate.png", "TvCase.png", "NewsIdent.png")


def curl(*args):
    r = subprocess.run(["curl", "-sS", "-m", "300", "-H", "x-api-key: dummy", *args], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"raw": r.stdout[:300], "err": r.stderr[:300]}


def upload(path, user, kind):
    name = os.path.splitext(os.path.basename(path))[0]
    req = {"assetType": kind, "displayName": "Capeline " + name, "description": "Capeline news art",
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


def main():
    user = os.environ.get("ROBLOX_USER_ID")
    if not user:
        print("upload.py: ROBLOX_USER_ID is not set")
        return 1
    ids = json.load(open(IDS)) if os.path.isfile(IDS) else {}
    sha = ids.setdefault("sha", {})
    files = [(os.path.join(OUT, f), f, "Image") for f in IMAGES] + [(FBX, "News.fbx", "Model")]
    failed = []
    for path, key, kind in files:
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
    if ids.get("News.fbx"):
        json.dump({"News": ids["News.fbx"]}, open(MODELS, "w"), indent=1)
    bad = {}
    for _, key, _ in files:
        if ids.get(key):
            st = moderation(ids[key])
            if st != "Approved":
                bad[key] = st
    print("upload.py: %d files, %d failed, moderation not approved: %s" % (len(files), len(failed), bad or "none"))
    return 1 if failed or bad else 0


if __name__ == "__main__":
    sys.exit(main())
