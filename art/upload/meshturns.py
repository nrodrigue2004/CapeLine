"""meshturns.py: gather meshcheck.py's verdicts into art/models/meshturns.json (fix-models, 2026-11-19).

    python3 -I art/upload/meshturns.py            (after `meshcheck.py SET` for each set; reads build/meshcheck/*/summary.json)

Per set: how many meshes, how many match Roblox's copy turned 180 degrees about y, how many match as drawn, how
many are symmetric either way, and the verdict (rotY180, identity, symmetric or mixed). Shared.MeshFix's table must
agree; tests/model_fit_test.luau checks it.
"""

import glob
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
out_path = os.path.join(ROOT, "art", "models", "meshturns.json")
out = json.load(open(out_path)) if os.path.exists(out_path) else {}
for f in sorted(glob.glob(os.path.join(ROOT, "build", "meshcheck", "*", "summary.json"))):
    s = json.load(open(f))
    out[s.pop("set")] = s
json.dump(out, open(out_path, "w"), indent=1, sort_keys=True)
for k, v in sorted(out.items()):
    print(f"{k:14s} {v['verdict']:9s} {v['turned']:4d}/{v['meshes']:<4d} turned, {v['either']} symmetric")
