"""cloud_model.py (fix-bodies, 2026-11-19): upload one FBX as a Model through Open Cloud and print its asset id.

    python3 -I art/upload/cloud_model.py art/export/BodyTorsos.fbx "Capeline BodyTorsos"

The cloud environment's network secret adds the key (the header is a dummy; no key is read or printed here); the
creator is env ROBLOX_USER_ID. Polls the operation until done, then prints {"assetId": ..., "state": ...}. Pull the
model in with pull_models.py afterwards.
"""

import json
import os
import subprocess
import sys
import tempfile
import time

path, name = sys.argv[1], sys.argv[2]
req = json.dumps({"assetType": "Model", "displayName": name, "description": "Capeline game art",
                  "creationContext": {"creator": {"userId": os.environ["ROBLOX_USER_ID"]}}})
for attempt in range(1, 6):
    raw = subprocess.run(["curl", "-sS", "-X", "POST", "https://apis.roblox.com/assets/v1/assets",
                          "-H", "x-api-key: dummy", "--form-string", "request=" + req,
                          "-F", "fileContent=@" + path + ";type=model/fbx"], capture_output=True, text=True).stdout
    try:
        op = json.loads(raw)["path"]
        break
    except (ValueError, KeyError):
        print("retry:", raw[:200], flush=True)
        time.sleep(5 * attempt)
else:
    raise SystemExit("upload failed")
for _ in range(60):
    time.sleep(3)
    raw = subprocess.run(["curl", "-sS", "-H", "x-api-key: dummy", "https://apis.roblox.com/assets/v1/" + op],
                         capture_output=True, text=True).stdout
    try:
        o = json.loads(raw)
    except ValueError:
        continue
    if o.get("done"):
        r = o.get("response", {})
        print(json.dumps({"assetId": r.get("assetId"), "state": (r.get("moderationResult") or {}).get("moderationState")}))
        sys.exit(0)
raise SystemExit("operation did not finish: " + op)
