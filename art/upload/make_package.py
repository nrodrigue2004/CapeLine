"""Build the upload package: every image the game waits on, a manifest saying where each id goes,
and the scripts nate's PC runs with his Open Cloud key (the key never leaves his PC).

    python3 art/upload/make_package.py OUT_DIR [--all]

OUT_DIR gets files/<name>.png, manifest.json, upload.bat, upload.ps1, resolve_ids.template.lua and README.txt.
nate double-clicks upload.bat; it writes ids.json (file -> Decal id) and resolve_ids.txt (the Studio command bar
step that reads each decal's image id), which come back to Claude to fill the configs.
By default only the images whose id is still 0 in the configs go in (the next batch); --all packages everything.
Targets (manifest "target"):
  npc_clothes  Config.NpcLooks.robots.<robot>.clothes.<version>
  npc_face     Config.NpcLooks.faces.<face>.<human|turned|cracked>
  hero_clothes Config.Creator.clothes.<shirts|pants>.<name>
  fx_texture   Config.Fx.lib.textures.<name>.id
  city_map     MaterialVariant "Kit"<name> in MaterialService (<map>: Color, Normal, Roughness, Metalness)
  npc_person   Config.NpcLooks.people.<id>.<clothes|face|cracked> (the side quests' givers, helpers and finale
               villains: art/clothes/people.py)
  creator_suit Config.Creator.suitArt.kits.<kit>.<shirt|pants> (the Suits tab's overlays: art/clothes/suits.py)
  creator_emblem Config.Creator.emblemArt.shapes.<shape> or .backings.<backing>.<face|rim> (art/clothes/emblems.py)
  creator_mask Config.Creator.maskArt.kits.<kit>.<front|side|back|top> (flat masks as head decals: art/clothes/masks.py)
  rogue_portrait Config.Rogues.portraits.<group>.<page id> (the Rogues File's case-file cards: art/rogues/portraits.py;
               group robots, fakes, villains, bosses, or gold for a world boss's gold page)
The finale models (art/export/finales/<Name>.fbx) are not images: nate imports them in Studio (Tasks.md).
"""

import json
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EXPORT = os.path.join(ROOT, "art", "export")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from apply_ids import block, creator_span, rogue_span  # noqa: E402


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def entries():
    out = []

    def add(src, name, target):
        path = os.path.join(EXPORT, src)
        if not os.path.isfile(path):
            raise SystemExit("missing " + src)
        out.append({"file": name + ".png", "src": src, "type": "Decal", "name": "Capeline " + name, "target": target})

    # robot uniforms: one combined classic clothes image per kind and version
    npc = read("src/config/NpcLooks.luau")
    robots = re.findall(r"^\t\t([A-Za-z]+) = \{\n\t\t\tclothes = \{", npc, re.M)
    for robot in robots:
        for version in ("Grunt", "Veteran", "Elite"):
            add(f"clothes/uniforms/{robot}_{version}.png", f"Uniform_{robot}_{version}",
                {"kind": "npc_clothes", "robot": robot, "version": version})
    # the six shared faces and their turned versions
    faces = re.findall(r"^\t\t([A-Za-z]+) = \{ human = 0, turned = 0", npc, re.M)
    for face in faces:
        add(f"clothes/faces/Face_{face}.png", f"Face_{face}", {"kind": "npc_face", "face": face, "which": "human"})
        add(f"clothes/faces/Face_{face}_Turned.png", f"Face_{face}_Turned",
            {"kind": "npc_face", "face": face, "which": "turned"})
        if os.path.isfile(os.path.join(EXPORT, f"clothes/faces/Face_{face}_Cracked.png")):
            add(f"clothes/faces/Face_{face}_Cracked.png", f"Face_{face}_Cracked",
                {"kind": "npc_face", "face": face, "which": "cracked"})
    # hero shirts and pants
    for f in sorted(os.listdir(os.path.join(EXPORT, "clothes", "heroes"))):
        m = re.match(r"(Shirt|Pants)_([A-Za-z]+)\.png$", f)
        if m:
            group = "shirts" if m.group(1) == "Shirt" else "pants"
            add(f"clothes/heroes/{f}", f"Hero{m.group(1)}_{m.group(2)}",
                {"kind": "hero_clothes", "group": group, "name": m.group(2)})
    # effects library sheets
    fx = read("src/config/Fx.luau")
    for name, file in re.findall(r"([A-Za-z_]+) = \{[^{}]*?file = \"([A-Za-z0-9_]+\.png)\"", fx, re.S):
        add(f"fx/{file}", f"Fx_{file[:-4]}", {"kind": "fx_texture", "name": name})
    # city kit maps
    for f in sorted(os.listdir(os.path.join(EXPORT, "city"))):
        m = re.match(r"([A-Za-z]+)_(Color|Normal|Roughness|Metalness)\.png$", f)
        if m:
            add(f"city/{f}", f"Kit{m.group(1)}_{m.group(2)}", {"kind": "city_map", "name": m.group(1), "map": m.group(2)})
    # the side quests' people: clothes, their own face, a famous fake's cracked face
    at = npc.index("\tpeople = {")
    people = npc[at : block(npc, at, r"^\tpeople = \{")[1]]
    for pid in re.findall(r"^\t\t([A-Za-z]+) = \{ clothes = \d+", people, re.M):
        add(f"clothes/people/{pid}.png", f"Person_{pid}", {"kind": "npc_person", "id": pid, "which": "clothes"})
        for suffix, which in (("", "face"), ("_Cracked", "cracked")):
            src = f"clothes/people/Face_{pid}{suffix}.png"
            if os.path.isfile(os.path.join(EXPORT, src)):
                add(src, f"PersonFace_{pid}{suffix}", {"kind": "npc_person", "id": pid, "which": which})
    # the hero creator's suits, emblems and flat masks (overnight item 12, 2026-11-18)
    for sub, pat, kind in (("suits", r"Suit(Shirt|Pants)_([A-Za-z]+)\.png$", "creator_suit"),
                           ("emblems", r"Emblem(|Back|Rim)_([A-Za-z]+)\.png$", "creator_emblem"),
                           ("masks", r"Mask(Front|Side|Back|Top)_([A-Za-z]+)\.png$", "creator_mask")):
        folder = os.path.join(EXPORT, "clothes", sub)
        if not os.path.isdir(folder):
            continue
        for f in sorted(os.listdir(folder)):
            m = re.match(pat, f)
            if not m:
                continue
            if kind == "creator_suit":
                t = {"kind": kind, "kit": m.group(2), "which": "shirt" if m.group(1) == "Shirt" else "pants"}
            elif kind == "creator_emblem":
                t = {"kind": kind, "name": m.group(2), "which": {"": "mark", "Back": "face", "Rim": "rim"}[m.group(1)]}
            else:
                t = {"kind": kind, "kit": m.group(2), "which": m.group(1).lower()}
            add(f"clothes/{sub}/{f}", "Creator" + f[:-4], t)
    # the Rogues File's portrait cards (WP3 art pass, 2026-11-18): one per page, a gold card per world boss
    rogues = read("src/config/Rogues.luau")
    for group in ("robots", "fakes", "villains", "bosses", "gold"):
        g = rogue_span(rogues, {"group": group})
        for pid in re.findall(r"^\t\t\t([A-Za-z]+) = \d+", rogues[g[0] : g[1]], re.M):
            name = "Rogue_" + pid + ("_Gold" if group == "gold" else "")
            add(f"rogues/{name}.png", name, {"kind": "rogue_portrait", "group": group, "id": pid})
    names = [e["file"] for e in out]
    assert len(names) == len(set(names)), "duplicate upload names"
    return out


def current(e, texts):
    """The id the configs hold now for this item (0 or None: still waiting on an upload)."""
    t = e["target"]
    k = t["kind"]

    def key_in(text, span, key):
        m = re.search(r"\b" + key + r" = (\d+)", text[span[0] : span[1]])
        return int(m.group(1)) if m else None

    npc, creator, fx = texts["npc"], texts["creator"], texts["fx"]
    if k == "npc_clothes":
        rb = block(npc, npc.index("\trobots = {"), r"^\t\t" + t["robot"] + r" = \{")
        return key_in(npc, block(npc, rb[0], r"clothes = \{"), t["version"])
    if k == "npc_face":
        return key_in(npc, block(npc, npc.index("\tfaces = {"), r"^\t\t" + t["face"] + r" = \{"), t["which"])
    if k == "npc_person":
        return key_in(npc, block(npc, npc.index("\tpeople = {"), r"^\t\t" + t["id"] + r" = \{"), t["which"])
    if k == "hero_clothes":
        grp = block(creator, creator.index("\tclothes = {\n\t\ton = "), r"^\t\t" + t["group"] + r" = \{")
        return key_in(creator, grp, t["name"])
    if k in ("creator_suit", "creator_emblem", "creator_mask"):
        key = t["name"] if k == "creator_emblem" and t["which"] == "mark" else t["which"]
        return key_in(creator, creator_span(creator, t), key)
    if k == "fx_texture":
        return key_in(fx, block(fx, fx.index("\t\ttextures = {"), r"^\t\t\t" + t["name"] + r" = \{"), "id")
    if k == "rogue_portrait":
        return key_in(texts["rogues"], rogue_span(texts["rogues"], t), t["id"])
    if k == "city_map":
        mf = os.path.join(ROOT, "src", "materials", "Kit" + t["name"] + ".model.json")
        if not os.path.isfile(mf):
            return None
        props = json.load(open(mf, encoding="utf-8"))["properties"]
        m = re.search(r"(\d+)$", props.get(t["map"] + "Map", ""))
        return int(m.group(1)) if m else None
    raise SystemExit("unknown target " + k)


def pending(items):
    texts = {"npc": read("src/config/NpcLooks.luau"), "creator": read("src/config/Creator.luau"),
             "fx": read("src/config/Fx.luau"), "rogues": read("src/config/Rogues.luau")}
    return [e for e in items if not current(e, texts)]


def main():
    args = [a for a in sys.argv[1:] if a != "--all"]
    if len(args) != 1:
        raise SystemExit(__doc__)
    out_dir = args[0]
    files = os.path.join(out_dir, "files")
    os.makedirs(files, exist_ok=True)
    items = entries()
    if "--all" not in sys.argv:
        items = pending(items)
    for e in items:
        shutil.copyfile(os.path.join(EXPORT, e["src"]), os.path.join(files, e["file"]))
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump({"items": items}, f, indent=1)
    for name in ("upload.bat", "upload.ps1", "README.txt"):
        shutil.copyfile(os.path.join(HERE, name), os.path.join(out_dir, name))
    # the Studio command-bar step that reads each decal's image id (apply_ids.py takes its output): upload.ps1
    # fills in this batch's decal ids and writes resolve_ids.txt
    shutil.copyfile(os.path.join(HERE, "resolve_ids.lua"), os.path.join(out_dir, "resolve_ids.template.lua"))
    counts = {}
    for e in items:
        counts[e["target"]["kind"]] = counts.get(e["target"]["kind"], 0) + 1
    print(len(items), "files", counts)


if __name__ == "__main__":
    main()
