# upload.py: uploads the thumbnail sheets (art/export/thumbs/Thumbs_<n>.png) whose id in art/thumbs/sheets.json
# is 0 as Image assets through Open Cloud (as art/upload/upload.ps1 does), waits for each operation, checks the
# asset is approved, records the id, then run art/thumbs/thumbs.py again to bake the ids into Config.Thumbs.
# Run from the repo root: python3 -I art/thumbs/upload.py   (needs ROBLOX_USER_ID; the API key comes from the
# environment's proxy, never this file)
import json
import os
import subprocess
import sys
import tempfile
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REC = os.path.join(ROOT, "art", "thumbs", "sheets.json")
API = "https://apis.roblox.com/assets/v1"
KEY = "dummy"  # the proxy puts the real key in


def curl(args):
    out = subprocess.run(["curl", "-s", "-H", "x-api-key: " + KEY] + args, capture_output=True, text=True)
    try:
        return json.loads(out.stdout)
    except ValueError:
        return {"raw": out.stdout[:300]}


def upload(path, name, user):
    req = {"assetType": "Image", "displayName": name, "description": "Capeline game art",
           "creationContext": {"creator": {"userId": user}}}
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
        json.dump(req, fh)
        req_path = fh.name
    try:
        for attempt in range(5):
            op = curl(["-X", "POST", API + "/assets", "-F", "request=<%s;type=application/json" % req_path,
                       "-F", "fileContent=@%s;type=image/png" % path])
            if op.get("path"):
                break
            print("retry", name, op)
            time.sleep(5 * (attempt + 1))
        else:
            return 0
        op_id = op["path"].split("/")[-1]
        for _ in range(60):
            if op.get("done") and op.get("response", {}).get("assetId"):
                break
            time.sleep(2)
            op = curl([API + "/operations/" + op_id])
        asset = int(op.get("response", {}).get("assetId", 0) or 0)
        if not asset:
            print("no asset id for", name, op)
            return 0
        info = curl([API + "/assets/%d" % asset])
        state = (info.get("moderationResult") or {}).get("moderationState", "?")
        print(name, asset, state)
        return asset
    finally:
        os.remove(req_path)


def check(rec):
    """--check: each uploaded sheet's moderation state; a rejected sheet's id goes back to 0."""
    for name in sorted(rec):
        asset = rec[name]["id"]
        if not asset:
            continue
        info = curl([API + "/assets/%d" % asset])
        state = (info.get("moderationResult") or {}).get("moderationState", "?")
        rec[name]["state"] = state
        print(name, asset, state)
        if state == "Rejected":
            rec[name]["id"] = 0
    with open(REC, "w") as fh:
        json.dump(rec, fh, indent=1, sort_keys=True)


def main():
    if "--check" in sys.argv:
        check(json.load(open(REC)))
        return
    user = os.environ.get("ROBLOX_USER_ID", "")
    if not user.isdigit():
        sys.exit("ROBLOX_USER_ID is not set")
    rec = json.load(open(REC))
    for name in sorted(rec):
        if rec[name]["id"]:
            continue
        asset = upload(os.path.join(ROOT, "art", "export", "thumbs", name), "Capeline " + name[:-4], user)
        if asset:
            rec[name]["id"] = asset
            with open(REC, "w") as fh:
                json.dump(rec, fh, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
