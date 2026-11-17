"""Build the upload package: every image the game waits on, a manifest saying where each id goes,
and the scripts nate's PC runs with his Open Cloud key (the key never leaves his PC).

    python3 art/upload/make_package.py OUT_DIR

OUT_DIR gets files/<name>.png, manifest.json, upload.bat, upload.ps1 and README.txt. nate double-clicks
upload.bat; it writes ids.json (file -> Decal id), which comes back to Claude to fill the configs.
Targets (manifest "target"):
  npc_clothes  Config.NpcLooks.robots.<robot>.clothes.<version>
  npc_face     Config.NpcLooks.faces.<face>.<human|turned>
  hero_clothes Config.Creator.clothes.<shirts|pants>.<name>
  fx_texture   Config.Fx.lib.textures.<name>.id
  city_map     MaterialVariant "Kit"<name> in MaterialService (<map>: Color, Normal, Roughness, Metalness)
"""

import json
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EXPORT = os.path.join(ROOT, "art", "export")
HERE = os.path.dirname(os.path.abspath(__file__))


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
    faces = re.findall(r"^\t\t([A-Za-z]+) = \{ human = 0, turned = 0 \}", npc, re.M)
    for face in faces:
        add(f"clothes/faces/Face_{face}.png", f"Face_{face}", {"kind": "npc_face", "face": face, "which": "human"})
        add(f"clothes/faces/Face_{face}_Turned.png", f"Face_{face}_Turned",
            {"kind": "npc_face", "face": face, "which": "turned"})
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
    names = [e["file"] for e in out]
    assert len(names) == len(set(names)), "duplicate upload names"
    return out


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    out_dir = sys.argv[1]
    files = os.path.join(out_dir, "files")
    os.makedirs(files, exist_ok=True)
    items = entries()
    for e in items:
        shutil.copyfile(os.path.join(EXPORT, e["src"]), os.path.join(files, e["file"]))
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump({"items": items}, f, indent=1)
    for name in ("upload.bat", "upload.ps1", "README.txt"):
        shutil.copyfile(os.path.join(HERE, name), os.path.join(out_dir, name))
    counts = {}
    for e in items:
        counts[e["target"]["kind"]] = counts.get(e["target"]["kind"], 0) + 1
    print(len(items), "files", counts)


if __name__ == "__main__":
    main()
