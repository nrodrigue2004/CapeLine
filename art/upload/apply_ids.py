"""Fill the game's art ids from nate's upload.

    python3 art/upload/apply_ids.py UPLOAD_DIR IMAGE_IDS_FILE

UPLOAD_DIR holds manifest.json (make_package.py) and ids.json (upload.ps1: file -> Decal id).
IMAGE_IDS_FILE is what resolve_ids.lua printed in Studio ("decal=image,decal=image,..."): the image id
inside each decal, which is what clothes, faces, particles and MaterialVariant maps need. Writes:
  src/config/NpcLooks.luau   robots.<robot>.clothes.<version>, faces.<face>.<which>, people.<id>.<which>
  src/config/Creator.luau    clothes.shirts|pants.<name>, suitArt.kits.<kit>, emblemArt, maskArt.kits.<kit>
  src/config/Fx.luau         lib.textures.<name>.id
  src/materials/Kit<Name>.model.json and the MaterialService entries in default.project.json (the city kit)
Safe to run again: every id is set, not added. A batch without city maps leaves the city materials as they are;
a batch with some merges them into the ones already there.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def path(p):
    return os.path.join(ROOT, p)


def read(p):
    with open(path(p), encoding="utf-8") as f:
        return f.read()


def write(p, s):
    with open(path(p), "w", encoding="utf-8", newline="\n") as f:
        f.write(s)


def block(text, start, pattern):
    """(begin, end) of the { } block opened by the first `pattern` match at or after `start`."""
    m = re.compile(pattern, re.M).search(text, start)
    if not m:
        raise SystemExit("not found: " + pattern)
    i = text.index("{", m.start())
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return i, j + 1
    raise SystemExit("unclosed block: " + pattern)


def set_key(text, span, key, value):
    a, b = span
    inner, n = re.subn(r"\b" + key + r" = \d+", f"{key} = {value}", text[a:b], count=1)
    if n != 1:
        raise SystemExit(f"no `{key} = <number>` in block at {a}")
    return text[:a] + inner + text[b:]


def creator_span(text, t):
    """The { } block of Config.Creator that holds a creator_suit, creator_emblem or creator_mask target's key."""
    k = t["kind"]
    if k == "creator_suit":
        return block(text, text.index("\tsuitArt = {"), r"^\t\t\t" + t["kit"] + r" = \{")
    if k == "creator_mask":
        return block(text, text.index("\tmaskArt = {"), r"^\t\t\t" + t["kit"] + r" = \{")
    at = text.index("\temblemArt = {")
    if t["which"] == "mark":
        return block(text, at, r"^\t\tshapes = \{")
    return block(text, block(text, at, r"^\t\tbackings = \{")[0], r"^\t\t\t" + t["name"] + r" = \{")


def lua_table(text, name):
    """{ key: value } of a flat `name = { Key = value, ... }` table (numbers and strings)."""
    a, b = block(text, 0, r"^\t\t" + name + r" = \{")
    out = {}
    for k, v in re.findall(r"(\w+) = (\"[^\"]*\"|[\d.]+)", text[a:b]):
        out[k] = v.strip('"') if v.startswith('"') else float(v)
    return out


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    up = sys.argv[1]
    items = json.load(open(os.path.join(up, "manifest.json"), encoding="utf-8-sig"))["items"]
    decals = json.load(open(os.path.join(up, "ids.json"), encoding="utf-8-sig"))
    raw = open(sys.argv[2], encoding="utf-8-sig").read()
    image = {d: i for d, i in re.findall(r"(\d+)=(\d+)", raw)}
    missing = [e["file"] for e in items if image.get(str(decals.get(e["file"], ""))) is None]
    if missing:
        print("no image id for", len(missing), "files (left at 0):", ", ".join(missing[:8]))

    def img(e):
        return image.get(str(decals.get(e["file"], "")))

    npc = read("src/config/NpcLooks.luau")
    creator = read("src/config/Creator.luau")
    fx = read("src/config/Fx.luau")
    robots_at = npc.index("\trobots = {")
    faces_at = npc.index("\tfaces = {")
    people_at = npc.index("\tpeople = {")
    clothes_at = creator.index("\tclothes = {\n\t\ton = ")
    tex_at = fx.index("\t\ttextures = {")
    maps = {}
    done = 0
    for e in items:
        t, i = e["target"], img(e)
        if i is None:
            continue
        k = t["kind"]
        if k == "npc_clothes":
            rb = block(npc, robots_at, r"^\t\t" + t["robot"] + r" = \{")
            cl = block(npc, rb[0], r"clothes = \{")
            npc = set_key(npc, cl, t["version"], i)
        elif k == "npc_face":
            npc = set_key(npc, block(npc, faces_at, r"^\t\t" + t["face"] + r" = \{"), t["which"], i)
        elif k == "npc_person":
            npc = set_key(npc, block(npc, people_at, r"^\t\t" + t["id"] + r" = \{"), t["which"], i)
        elif k == "hero_clothes":
            grp = block(creator, clothes_at, r"^\t\t" + t["group"] + r" = \{")
            creator = set_key(creator, grp, t["name"], i)
        elif k in ("creator_suit", "creator_mask"):
            creator = set_key(creator, creator_span(creator, t), t["which"], i)
        elif k == "creator_emblem":
            key = t["name"] if t["which"] == "mark" else t["which"]
            creator = set_key(creator, creator_span(creator, t), key, i)
        elif k == "fx_texture":
            fx = set_key(fx, block(fx, tex_at, r"^\t\t\t" + t["name"] + r" = \{"), "id", i)
        elif k == "city_map":
            maps.setdefault(t["name"], {})[t["map"]] = i
        else:
            raise SystemExit("unknown target " + k)
        done += 1
    write("src/config/NpcLooks.luau", npc)
    write("src/config/Creator.luau", creator)
    write("src/config/Fx.luau", fx)
    if not maps:
        print(done, "ids set; city materials unchanged")
        return

    # the city kit: one MaterialVariant per texture set, on its base material and tile size (Config.City.kit)
    city = read("src/config/City.luau")
    tiles = lua_table(city, "studsPerTile")
    bases = lua_table(city, "baseMaterial")
    os.makedirs(path("src/materials"), exist_ok=True)
    # keep the maps an earlier batch set (an incremental batch must not wipe the others), then rewrite them all
    for f in os.listdir(path("src/materials")):
        if f.startswith("Kit") and f.endswith(".model.json"):
            props = json.load(open(path("src/materials/" + f), encoding="utf-8"))["properties"]
            old = maps.setdefault(f[3 : -len(".model.json")], {})
            for kind in ("Color", "Normal", "Roughness", "Metalness"):
                m = re.search(r"(\d+)$", props.get(kind + "Map", ""))
                if m and kind not in old:
                    old[kind] = m.group(1)
            os.remove(path("src/materials/" + f))
    ms = {"$className": "MaterialService"}
    for name in sorted(maps):
        m = maps[name]
        if name not in bases or name not in tiles:
            raise SystemExit("Config.City.kit has no baseMaterial/studsPerTile for " + name)
        props = {"BaseMaterial": bases[name], "StudsPerTile": tiles[name], "MaterialPattern": "Regular"}
        for kind in ("Color", "Normal", "Roughness", "Metalness"):
            if kind in m:
                props[kind + "Map"] = "rbxassetid://" + m[kind]
        write(f"src/materials/Kit{name}.model.json",
              json.dumps({"className": "MaterialVariant", "properties": props}, indent=2) + "\n")
        ms["Kit" + name] = {"$path": f"src/materials/Kit{name}.model.json"}
    # the MaterialService entry, written in place so the rest of the project file keeps its layout
    proj = read("default.project.json")
    entry = '    "MaterialService": ' + json.dumps(ms, indent=2).replace("\n", "\n    ") + ",\n"
    if '"MaterialService"' in proj:
        a, b = block(proj, 0, r'^    "MaterialService": \{')
        start = proj.rindex("\n", 0, a) + 1
        end = b + 2 if proj[b : b + 2] == ",\n" else b
        proj = proj[:start] + entry + proj[end:]
    else:
        at = proj.index('    "Players": {')
        proj = proj[:at] + entry + proj[at:]
    json.loads(proj)
    write("default.project.json", proj)
    print(done, "ids set;", len(maps), "city materials")


if __name__ == "__main__":
    main()
