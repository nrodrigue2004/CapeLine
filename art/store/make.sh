#!/usr/bin/env bash
# art/store/make.sh: regenerates nate's store art picks (notes/Store Page.md, 2026-11-17): 2 icons and 3 thumbnails
# rendered with Blender (art/store/icons.py, art/store/thumbs.py into art/export/store/raw/), then graded and
# captioned by art/store/post.py into art/export/store/*.png and the contact sheet art/preview/store_picks.png.
# Usage: bash art/store/make.sh [--draft] [name ...]   (names: clash smash build boss twist; default all)
# STORE_ASSETS=<a checkout>/art reads the city layouts, kit textures and boss meshes from a newer checkout.
# Each full render takes 10 to 25 minutes on 4 CPU cores; --draft renders at half size with few samples.
set -euo pipefail
cd "$(dirname "$0")/../.."
PY=${BPY:-$HOME/tools/bpyenv/bin/python}
FLAGS=()
NAMES=()
for a in "$@"; do
  if [[ $a == --* ]]; then FLAGS+=("$a"); else NAMES+=("$a"); fi
done
[[ ${#NAMES[@]} -eq 0 ]] && NAMES=(clash smash build boss twist)
for n in "${NAMES[@]}"; do
  case $n in
    clash|smash) "$PY" art/store/icons.py "$n" "${FLAGS[@]}" ;;
    build|boss|twist) "$PY" art/store/thumbs.py "$n" "${FLAGS[@]}" ;;
    *) echo "unknown: $n" >&2; exit 1 ;;
  esac
done
python3 art/store/post.py "${FLAGS[@]}"
