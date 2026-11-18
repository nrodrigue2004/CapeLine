#!/usr/bin/env bash
# Runs the Lune suite safely: one run at a time on this machine, with a watchdog and retries.
# Lune 0.8.9 can freeze for good (one core spinning, no output) when several Lune runs share the CPUs.
# Alone, the full suite takes under a minute, so a run past LUNE_LIMIT seconds is a freeze, not slowness.
#   tests/run.sh build/Capeline.rbxl          (same arguments as lune run tests/run.luau)
#   ONLY="name" tests/run.sh build/Capeline.rbxl
set -u
LOCK="${LUNE_LOCK:-/tmp/capeline-lune.lock}"
LIMIT="${LUNE_LIMIT:-300}"
TRIES="${LUNE_TRIES:-4}"
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT
code=1
for try in $(seq 1 "$TRIES"); do
	flock "$LOCK" timeout "$LIMIT" lune run tests/run.luau "$@" >"$OUT" 2>&1
	code=$?
	if [ "$code" -ne 124 ]; then
		break
	fi
	echo "tests/run.sh: Lune froze or ran past ${LIMIT} s (try $try of $TRIES), retrying" >&2
done
cat "$OUT"
if [ "$code" -eq 124 ]; then
	echo "tests/run.sh: gave up after $TRIES tries (no result, not a pass)" >&2
fi
exit "$code"
