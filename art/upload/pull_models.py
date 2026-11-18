"""Pull uploaded art models into the repo (2026-11-18, the cloud upload).

    python3 -I art/upload/pull_models.py MODEL_IDS_JSON [Set ...]

MODEL_IDS_JSON maps a set name (Weapons, Bosses, ...) to the Model asset id its FBX became (Open Cloud upload of
art/export/*.fbx as assetType Model). For each set: download it through the Open Cloud asset delivery API
(apis.roblox.com/asset-delivery-api, the key's legacy-asset permission; the file comes from Roblox's CDN), make it
Lune-readable with rbxfix.py, then name_model.luau writes art/models/<Set>.rbxm and its ids json.
Rojo maps each under ReplicatedStorage.Art (default.project.json). The key is never read here: the cloud
environment's network secret adds it, so the header below is a dummy.
"""

import json
import os
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
LUNE = os.environ.get("LUNE", "lune")


def fetch(asset_id, out):
    for attempt in range(1, 6):
        meta = subprocess.run(["curl", "-sS", "-H", "x-api-key: dummy",
                               f"https://apis.roblox.com/asset-delivery-api/v1/assetId/{asset_id}"],
                              capture_output=True, text=True).stdout
        try:
            loc = json.loads(meta)["location"]
        except (ValueError, KeyError):
            print("retry", asset_id, meta[:200], flush=True)
            time.sleep(5 * attempt)
            continue
        if subprocess.run(["curl", "-sSf", "-o", out, loc]).returncode == 0:
            return
        time.sleep(5 * attempt)
    raise SystemExit(f"could not download {asset_id}")


def main():
    ids = json.load(open(sys.argv[1], encoding="utf-8-sig"))
    sets = sys.argv[2:] or sorted(ids)
    tmp = tempfile.mkdtemp(prefix="capeline-pull-")
    for s in sets:
        raw, fixed = os.path.join(tmp, s + ".bin"), os.path.join(tmp, s + ".rbxm")
        fetch(ids[s], raw)
        summary = subprocess.run([sys.executable, "-I", os.path.join(HERE, "rbxfix.py"), raw, fixed],
                                 capture_output=True, text=True, check=True).stdout.strip()
        subprocess.run([LUNE, "run", os.path.join(HERE, "name_model.luau"), fixed, s], cwd=ROOT, check=True)
        print("  ", summary, flush=True)


main()
