#!/usr/bin/env bash
# Build and stage a Stage 18 runtime. Runs INSIDE the VM, unattended.
#
# WHY THIS EXISTS: nothing in the tree does it. `bootstrap-stable.sh` ends with
#   "The separate Stage 18 iTerm2 asset/bootstrap path is not automated yet."
# and the two prepare-* scripts refuse to create the roots -- they only populate
# roots that already exist. The step that turns a configured build-arm64-stage18
# into a populated install-arm64-stage18/root had to be written, and this is it.
#
# The roots were seeded by copying the known-good Stage 10 install and the existing
# GUI build directory, so the working Stage 10 is never mutated and ~22,000 already
# built edges are reused. Only the Stage 18 delta should recompile.
#
# -j8 not -j12: JavaScriptCore translation units are memory-hungry and this VM has
# 24 GB. CPU is not the binding constraint here.
#
# Logs are FULL, never tailed -- ninja prints the root cause early and hundreds of
# follow-on lines after it (F61 was exactly this mistake).
set -uo pipefail

W=$HOME/darling
SRC=$W/source
B=$W/build-arm64-stage18
S=$W/install-arm64-stage18
IMG=darling-arm64-dev:24.04
LOG=$W/stage18-build.log
JOBS=${JOBS:-8}

say() { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$W/stage18-progress.log"; }

say "stage18 build start (jobs=$JOBS)"
[ -d "$B" ] && [ -d "$S/root" ] || { say "FATAL: roots missing"; exit 2; }

# ---- build -----------------------------------------------------------------
start=$(date +%s)
docker run --rm --platform linux/arm64 \
    -v "$SRC:/work/source:ro" -v "$B:/work/build" \
    "$IMG" bash -lc "cd /work/build && ninja -j$JOBS" > "$LOG" 2>&1
rc=$?          # no pipe: this is really ninja's status (trap 10 / F61)
end=$(date +%s)
say "ninja rc=$rc after $(( (end-start)/60 )) min, $(wc -l < "$LOG") log lines"

if [ "$rc" != 0 ]; then
    say "BUILD FAILED -- first errors:"
    grep -nE "error:|FAILED:" "$LOG" | head -8 | tee -a "$W/stage18-progress.log"
    n=$(grep -nE "error:|FAILED:" "$LOG" | head -1 | cut -d: -f1)
    [ -n "${n:-}" ] && sed -n "$((n>3 ? n-3 : 1)),$((n+25))p" "$LOG" >> "$W/stage18-progress.log"
    exit "$rc"
fi
say "build ok ($(grep -c 'warning:' "$LOG") warnings)"

# ---- stage -----------------------------------------------------------------
# Install the gui component and the stage18-tagged component. Nothing in the tree
# ever runs `--component stage18`; the tag exists with no consumer, so this is the
# missing link.
before=$(find "$S/root" -type f | wc -l)
docker run --rm --platform linux/arm64 \
    -v "$SRC:/work/source:ro" -v "$B:/work/build" -v "$S:/work/stage" \
    "$IMG" bash -lc '
      set -u
      rm -rf /tmp/s18
      for c in cli_gui_common core gui stage18 jsc; do
        DESTDIR=/tmp/s18 cmake --install /work/build --component "$c" >>/tmp/i.log 2>&1 \
          && echo "  installed component: $c" || echo "  (no such component: $c)"
      done
      cp -a /tmp/s18/usr/local/libexec/darling/. /work/stage/root/ 2>/dev/null
      echo staged
    ' 2>&1 | tee -a "$W/stage18-progress.log"
after=$(find "$S/root" -type f | wc -l)
say "staged: $before -> $after files"

# ---- what actually landed --------------------------------------------------
say "Stage 18 delta check:"
for f in JavaScriptCore ScreenCaptureKit Metal MetalKit Quartz QuickLookUI; do
    p="$S/root/System/Library/Frameworks/$f.framework/Versions/A/$f"
    [ -f "$p" ] && say "  $f  $(stat -c %s "$p") bytes" || say "  $f  ABSENT"
done
for l in libaprutil-1.0.dylib libapr-1.0.dylib libappkit_bootstrap.dylib; do
    p=$(find "$S/root" -name "$l" 2>/dev/null | head -1)
    [ -n "$p" ] && say "  $l  present" || say "  $l  ABSENT"
done
say "stage18 build script done"
