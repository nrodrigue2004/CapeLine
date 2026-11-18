#!/usr/bin/env bash
# Runs the Lune suite safely: one run at a time on this machine, with a freeze watchdog and retries.
# Lune 0.8.9 can freeze for good (one core spinning in user code, no output, memory flat to the byte) when
# the CPUs are busy (other Lune runs, Blender renders). Alone, the full suite takes under a minute.
#   tests/run.sh build/Capeline.rbxl          (same arguments as lune run tests/run.luau)
#   ONLY="name" tests/run.sh build/Capeline.rbxl
# A run whose memory has not changed for LUNE_STILL seconds is frozen (a live run's memory moves every
# second as Luau collects garbage); it is killed and retried. LUNE_LIMIT caps any one try. Lune runs at
# nice -10 so renders and other jobs yield to it (fewer freezes); run Blender and big renders under nice 15.
set -u
LOCK="${LUNE_LOCK:-/tmp/capeline-lune.lock}"
LIMIT="${LUNE_LIMIT:-600}"
STILL="${LUNE_STILL:-25}"
TRIES="${LUNE_TRIES:-8}"
OUT="$(mktemp)"
# Renders (Blender/bpy and other art scripts) are paused while Lune runs, then resumed: busy CPUs are
# what freezes Lune, and a render loses nothing by waiting a minute.
PAUSE="${LUNE_PAUSE:-bpyenv/bin/python}"
resume() { [ -n "$PAUSE" ] && pkill -CONT -f "$PAUSE" 2>/dev/null; true; }
trap 'resume; rm -f "$OUT"' EXIT

one_try() {
	[ -n "$PAUSE" ] && pkill -STOP -f "$PAUSE" 2>/dev/null
	nice -n -10 lune run tests/run.luau "$@" >"$OUT" 2>&1 &
	local pid=$! last="" same=0 waited=0 rss
	while kill -0 "$pid" 2>/dev/null; do
		sleep 1
		waited=$((waited + 1))
		rss="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')"
		if [ -n "$rss" ] && [ "$rss" = "$last" ]; then
			same=$((same + 1))
		else
			same=0
			last="$rss"
		fi
		if [ "$same" -ge "$STILL" ] || [ "$waited" -ge "$LIMIT" ]; then
			kill -9 "$pid" 2>/dev/null
			wait "$pid" 2>/dev/null
			return 124
		fi
	done
	wait "$pid"
}

code=1
for try in $(seq 1 "$TRIES"); do
	exec 9>"$LOCK"
	flock 9
	one_try "$@"
	code=$?
	resume
	flock -u 9
	if [ "$code" -ne 124 ]; then
		break
	fi
	echo "tests/run.sh: Lune froze (try $try of $TRIES), retrying" >&2
done
cat "$OUT"
if [ "$code" -eq 124 ]; then
	echo "tests/run.sh: gave up after $TRIES tries (no result, not a pass)" >&2
fi
exit "$code"
