"""Build nate's single art package: every image still waiting on an id (make_package.py), every FBX still waiting
on a Studio import, the baked textures that go with some of them, the store art, and one IMPORT.txt.

    python3 art/upload/make_full.py OUT_DIR

OUT_DIR/images/ is the image upload (upload.bat, files/, manifest.json; see README.txt there), OUT_DIR/fbx/ the
models (sort_art.txt is the Studio command-bar step that renames each imported model, moves it into
ReplicatedStorage.Art, selects them all for one Save to File and lists their mesh ids), OUT_DIR/store/ the store
art for the Creator Hub, OUT_DIR/START HERE.txt the order. FBX already pulled into art/models are left out.
"""

import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
EXPORT = os.path.join(ROOT, "art", "export")

# the import order: what changes the most on screen first
SETS = [
    ("Weapons", "Weapons.fbx", None), ("Bodies", "Bodies.fbx", None), ("Street", "Street.fbx", None),
    ("Bosses", "Bosses.fbx", "bosses"), ("SetPieces", "SetPieces.fbx", None), ("Vehicles", "Vehicles.fbx", None),
    ("Hq", "Hq.fbx", None), ("Capes", "Capes.fbx", None), ("Heads", "Heads.fbx", None),
    ("Gloves", "Gloves.fbx", None), ("Boots", "Boots.fbx", None), ("Coats", "Coats.fbx", None),
    ("Belts", "Belts.fbx", None), ("Shoulders", "Shoulders.fbx", None), ("Backs", "Backs.fbx", None),
    ("Hats", "Hats.fbx", None), ("Hair", "Hair.fbx", None), ("Eyes", "Eyes.fbx", None), ("Ears", "Ears.fbx", None),
    ("Necks", "Necks.fbx", None), ("Wrists", "Wrists.fbx", None), ("Arms", "Arms.fbx", None),
    ("Bramblebeast", "finales/Bramblebeast.fbx", "finales:Bramblebeast_"),
    ("Voidhound", "finales/Voidhound.fbx", "finales:Voidhound_"),
    ("WindupGiant", "finales/WindupGiant.fbx", "finales:WindupGiant_"),
    ("Trooper", "Trooper.fbx", "trooper"),
]


def imported():
    return {f[:-5] for f in os.listdir(os.path.join(ROOT, "art", "models")) if f.endswith(".rbxm")}


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    out = sys.argv[1]
    if os.path.exists(out):
        shutil.rmtree(out)
    subprocess.run([sys.executable, os.path.join(HERE, "make_package.py"), os.path.join(out, "images")], check=True)
    fbx = os.path.join(out, "fbx")
    os.makedirs(os.path.join(fbx, "textures"))
    done = imported()
    sets = [s for s in SETS if s[0] not in done]
    for name, src, tex in sets:
        shutil.copyfile(os.path.join(EXPORT, src), os.path.join(fbx, name + ".fbx"))
        if tex:
            folder, _, prefix = tex.partition(":")
            for f in sorted(os.listdir(os.path.join(EXPORT, folder))):
                if f.endswith(".png") and f.startswith(prefix):
                    os.makedirs(os.path.join(fbx, "textures", name), exist_ok=True)
                    shutil.copyfile(os.path.join(EXPORT, folder, f), os.path.join(fbx, "textures", name, f))
    names = ",".join('"%s"' % s[0] for s in sets)
    with open(os.path.join(HERE, "sort_art.lua"), encoding="utf-8") as f:
        lua = " ".join(line.strip() for line in f if line.strip())
    with open(os.path.join(fbx, "sort_art.txt"), "w", encoding="utf-8") as f:
        f.write(lua.replace("__SETS__", names) + "\n")
    store = os.path.join(out, "store")
    for sub in ("store", "store2"):
        for f in sorted(os.listdir(os.path.join(EXPORT, sub))):
            if f.endswith(".png") and not f.startswith("preview"):
                os.makedirs(store, exist_ok=True)
                shutil.copyfile(os.path.join(EXPORT, sub, f), os.path.join(store, f))
    with open(os.path.join(HERE, "START_HERE.txt"), encoding="utf-8") as f:
        text = f.read()
    listing = "\n".join("   %2d. %s.fbx" % (i + 1, s[0]) for i, s in enumerate(sets))
    images = len(os.listdir(os.path.join(out, "images", "files")))
    text = text.replace("__FBX__", listing).replace("__NFBX__", str(len(sets))).replace("__NIMG__", str(images))
    with open(os.path.join(out, "START HERE.txt"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write(text)
    print(images, "images,", len(sets), "FBX,", len(os.listdir(store)), "store images")


if __name__ == "__main__":
    main()
