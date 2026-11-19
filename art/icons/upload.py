"""Uploads the icon sheets from the cloud as Image assets (gap-icons, 2026-11-19), like art/upload/upload.ps1.

The key never appears here: the cloud proxy adds it to apis.roblox.com requests (header x-api-key: dummy).
Creator: env ROBLOX_USER_ID. Writes art/icons/ids.json (file -> image id), skipping files already in it, then
waits for each asset's moderation. Run icons.py afterwards so src/config/Icons.luau takes the ids.

    python3 -I art/icons/upload.py [--check]
"""

import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SHEETS = os.path.join(ROOT, "art", "export", "icons")
IDS = os.path.join(HERE, "ids.json")
API = "https://apis.roblox.com/assets/v1"


def curl(args):
    out = subprocess.run(["curl", "-sS", "-H", "x-api-key: dummy"] + args, capture_output=True, text=True)
    try:
        return json.loads(out.stdout)
    except ValueError:
        return {"raw": out.stdout[:300], "err": out.stderr[:300]}


def upload(path, user):
    req = json.dumps({"assetType": "Image", "displayName": "Capeline " + os.path.basename(path)[:-4],
                      "description": "Capeline game art", "creationContext": {"creator": {"userId": user}}})
    for attempt in range(5):
        op = curl(["-X", "POST", API + "/assets", "--form-string", "request=" + req,
                   "-F", "fileContent=@%s;type=image/png" % path])
        if op.get("path"):
            op_id = op["path"].split("/")[-1]
            for _ in range(40):
                if op.get("done") and op.get("response", {}).get("assetId"):
                    return str(op["response"]["assetId"])
                time.sleep(2)
                op = curl([API + "/operations/" + op_id])
        print("retry", os.path.basename(path), op)
        time.sleep(5 * (attempt + 1))
    return None


def state(asset_id):
    info = curl([API + "/assets/" + asset_id])
    return (info.get("moderationResult") or {}).get("moderationState", "?")


def main():
    ids = json.load(open(IDS)) if os.path.exists(IDS) else {}
    if "--check" not in sys.argv:
        user = os.environ.get("ROBLOX_USER_ID", "")
        assert user.isdigit(), "ROBLOX_USER_ID is not set"
        for name in sorted(os.listdir(SHEETS)):
            if not name.endswith(".png") or name in ids:
                continue
            got = upload(os.path.join(SHEETS, name), user)
            print(name, "->", got)
            if got:
                ids[name] = got
                with open(IDS, "w") as f:
                    json.dump(ids, f, indent=1, sort_keys=True)
    for _ in range(30):
        states = {n: state(i) for n, i in ids.items()}
        print(states)
        if all(s != "Reviewing" for s in states.values()):
            break
        time.sleep(10)


if __name__ == "__main__":
    main()
