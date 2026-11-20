# upload.py: the sound atlases (art/export/audio/<Atlas>.ogg from build.py, and music.py's tracks) up through Open
# Cloud as Audio assets, like art/life/upload.py (the proxy adds the key, the creator is $ROBLOX_USER_ID). Each
# operation is polled and each asset's moderation checked. art/audio/ids.json keeps { atlas: id } and each file's
# sha1, so only changed files go up again (Roblox limits audio uploads a month: re-upload only what changed).
# After an upload, run build.py again (or `--ids`) so src/config/AudioClips.luau carries the ids.
#   python3 -I art/audio/upload.py [Atlas ...] [--check]
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
IDS = os.path.join(HERE, "ids.json")
API = "https://apis.roblox.com/assets/v1"
AUD = os.path.join(REPO, "art", "export", "audio")
ORDER = ["Hits", "World", "Ui", "Loops", "Music", "Ambient"]


def curl(*args):
    r = subprocess.run(["curl", "-sS", "-m", "300", "-H", "x-api-key: dummy", *args], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"raw": r.stdout[:400], "err": r.stderr[:300]}


def upload(path, user, name):
    req = {"assetType": "Audio", "displayName": "Capeline " + name, "description": "Capeline game sounds (CC0 sources)",
           "creationContext": {"creator": {"userId": str(user)}}}
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(req, f)
        rp = f.name
    op = {}
    for attempt in range(3):
        op = curl("-X", "POST", API + "/assets", "-F", "request=<%s;type=application/json" % rp,
                  "-F", "fileContent=@%s;type=audio/ogg" % path)
        if op.get("path"):
            break
        print("upload.py: refused or failed", name, json.dumps(op)[:400], flush=True)
        if op.get("code") in ("PERMISSION_DENIED", "INVALID_ARGUMENT", "RESOURCE_EXHAUSTED") or "quota" in json.dumps(op).lower():
            return None, op  # a limit or a refusal: stop, never hammer
        time.sleep(5 * (attempt + 1))
    else:
        return None, op
    os.remove(rp)
    op_id = op["path"].split("/")[-1]
    for _ in range(200):
        if op.get("done"):
            aid = (op.get("response") or {}).get("assetId")
            return aid, op
        time.sleep(3)
        op = curl(API + "/operations/" + op_id)
    return None, op


def moderation(asset_id):
    a = curl(API + "/assets/%s" % asset_id, "-G", "--data-urlencode", "readMask=moderationResult")
    return (a.get("moderationResult") or {}).get("moderationState", "?")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    ids = json.load(open(IDS)) if os.path.isfile(IDS) else {}
    sha = ids.setdefault("sha", {})
    if check:
        for k in ORDER:
            if ids.get(k):
                print("upload.py:", k, ids[k], moderation(ids[k]))
        return 0
    user = os.environ.get("ROBLOX_USER_ID")
    if not user:
        print("upload.py: ROBLOX_USER_ID is not set")
        return 1
    failed = []
    for name in args or ORDER:
        path = os.path.join(AUD, name + ".ogg")
        if not os.path.isfile(path):
            continue
        h = hashlib.sha1(open(path, "rb").read()).hexdigest()
        if ids.get(name) and sha.get(name) == h:
            continue
        aid, op = upload(path, user, name)
        if not aid:
            failed.append(name)
            print("upload.py: FAILED", name, json.dumps(op)[:600], flush=True)
            break  # stop at the first refusal (a monthly limit would refuse the rest too)
        ids[name] = int(aid)
        sha[name] = h
        json.dump(ids, open(IDS, "w"), indent=1, sort_keys=True)
        print("upload.py: ok", name, aid, flush=True)
    for k in ORDER:
        if ids.get(k):
            print("upload.py: moderation", k, ids[k], moderation(ids[k]))
    return 1 if failed else 0


sys.exit(main())
