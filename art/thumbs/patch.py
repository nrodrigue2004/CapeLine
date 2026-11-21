# patch.py: puts a few re-rendered or new tiles into the existing sheets without re-rendering every cell (the
# cells in art/thumbs/cells are not committed, so a full thumbs.py run needs every Blender set rendered first).
# Reads art/thumbs/pieces.json and whatever renders are in art/thumbs/cells; for each creator piece whose render is
# there: replaces its cell if Config.Thumbs has one, else takes the first free cell before the pose sheet. Changed
# sheets get id 0 in art/thumbs/sheets.json and Config.Thumbs (run art/thumbs/upload.py, then this again with
# --ids to write the new ids). Run from the repo root: python3 art/thumbs/patch.py [--ids]
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import thumbs as T  # noqa: E402

CFG = os.path.join(T.ROOT, "src", "config", "Thumbs.luau")


def read_cfg():
    s = open(CFG).read()
    ids = [int(x) for x in re.findall(r"\d+", s.split("sheets = {", 1)[1].split("}", 1)[0])]
    cells = {k: int(v) for k, v in re.findall(r'\["([^"]+)"\] = (\d+),', s)}
    return ids, cells


def main():
    ids, cells = read_cfg()
    rec = T.load(os.path.join(T.ART, "thumbs", "sheets.json"))
    if "--ids" in sys.argv:
        ids = [rec["Thumbs_%d.png" % (i + 1)]["id"] for i in range(len(ids))]
        T.write_config(ids, cells)
        import json
        with open(os.path.join(T.ART, "thumbs", "ids.json"), "w") as fh:
            json.dump({"rbxassetid://%d" % i: os.path.join("art", "export", "thumbs", "Thumbs_%d.png" % (s + 1))
                       for s, i in enumerate(ids) if i}, fh, indent=1, sort_keys=True)
        print("ids written", ids)
        return
    per = T.PER * T.PER
    P = T.load(os.path.join(T.ART, "thumbs", "pieces.json"))
    poses = [v for k, v in cells.items() if k.startswith("emote/")]
    pose_sheet = min((v - 1) // per for v in poses) if poses else len(ids)
    used = set(cells.values())
    free = [c for c in range(1, pose_sheet * per + 1) if c not in used]
    sheets = {}
    changed = []
    done = set()
    for p in P["creator"]:
        key = p.get("key")
        if not key or key in done or p["tab"] not in T.SETS:
            continue
        src = T.render_cell(T.SETS[p["tab"]], p["kit"])
        if src is None:
            continue
        done.add(key)
        im = T.framed_render(src, T.CARD.get(T.AREA.get(p["tab"], "torso"), T.PAPER))
        if key not in cells:
            cells[key] = free.pop(0)
        s, k = divmod(cells[key] - 1, per)
        if s not in sheets:
            sheets[s] = T.Image.open(os.path.join(T.OUT, "Thumbs_%d.png" % (s + 1))).convert("RGBA")
        x, y = (k % T.PER) * T.CELL, (k // T.PER) * T.CELL
        sheets[s].paste(T.Image.new("RGBA", (T.CELL, T.CELL), (0, 0, 0, 0)), (x, y))
        sheets[s].alpha_composite(im, (x, y))
        changed.append(key)
    for s, im in sheets.items():
        name = "Thumbs_%d.png" % (s + 1)
        im.save(os.path.join(T.OUT, name))
        rec[name] = {"hash": T.sheet_hash(im), "id": 0}
        ids[s] = 0
    import json
    with open(os.path.join(T.ART, "thumbs", "sheets.json"), "w") as fh:
        json.dump(rec, fh, indent=1, sort_keys=True)
    T.write_config(ids, cells)
    print("patched %d tiles on sheets %s" % (len(changed), sorted(s + 1 for s in sheets)), changed)


if __name__ == "__main__":
    main()
