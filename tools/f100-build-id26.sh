#!/usr/bin/env bash
# f100-build-id26.sh — incrementally rebuild darlingserver from the CURRENT source tree
# and stage it into install-arm64-id26 (the A/B/A scratch). Edit source first, then run
# this, then run tools/f100-spawn-probe.sh. Reverting the source + re-running this is the
# A/B/A "restore" phase.
set -euo pipefail
SRC=$HOME/darling/source
BLD=$HOME/darling/build-arm64-id26
INST=$HOME/darling/install-arm64-id26
TARGET=$INST/bin/darlingserver
echo "[build] ninja darlingserver  ($(date +%H:%M:%S))"
docker run --rm --platform linux/arm64 \
	-v "$SRC:/work/source:ro" \
	-v "$BLD:/work/build" \
	darling-arm64-dev:24.04 bash -lc "cd /work/build && ninja darlingserver"
prev=$(stat -c %s "$TARGET" 2>/dev/null || echo 0)
cp -a "$BLD/src/external/darlingserver/darlingserver" "$TARGET"
echo "[build] staged -> $TARGET"
echo "[build]   size ${prev} -> $(stat -c %s "$TARGET") bytes, mtime $(stat -c %y "$TARGET" | cut -d. -f1)"
