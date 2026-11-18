#!/usr/bin/env bash
# art/store/make2.sh: regenerates the store art refresh (overnight queue item 13, 2026-11-18; notes/Store Page.md
# "Store art refresh"): 3 icons and 4 thumbnails rendered with Blender (art/store/store2.py into
# art/export/store2/raw/), then graded and captioned by art/store/post2.py into art/export/store2/*.png and the
# previews art/export/store2/preview_sheet.png and preview_small.png.
# Usage: bash art/store/make2.sh [--draft] [name ...]
#   names: icon_maw icon_fake icon_titan thumb_maw thumb_deep thumb_fakes thumb_giant (default all)
# Renders run under nice -n 15 so the shared test runner keeps the CPU. Each full render takes 5 to 20 minutes on
# 4 cores; --draft renders at half size with few samples. STORE_NOCITY=1 skips the city for quick pose checks.
set -euo pipefail
cd "$(dirname "$0")/../.."
PY=${BPY:-$HOME/tools/bpyenv/bin/python}
FLAGS=()
NAMES=()
for a in "$@"; do
  if [[ $a == --* ]]; then FLAGS+=("$a"); else NAMES+=("$a"); fi
done
[[ ${#NAMES[@]} -eq 0 ]] && NAMES=(icon_maw icon_fake icon_titan thumb_maw thumb_deep thumb_fakes thumb_giant)
for n in "${NAMES[@]}"; do
  case $n in
    icon_maw|icon_fake|icon_titan|thumb_maw|thumb_deep|thumb_fakes|thumb_giant)
      nice -n 15 "$PY" art/store/store2.py "$n" "${FLAGS[@]}" ;;
    *) echo "unknown: $n" >&2; exit 1 ;;
  esac
done
nice -n 15 python3 art/store/post2.py "${FLAGS[@]}"
