#!/usr/bin/env bash
# F97: does implementing -[X11Window setAlphaValue:] restore unmodified iTerm2 launch
# on Kevin's Jul 14-16 tail (the gap-merged tree)?
#
# All work on the ISOLATED gap roots and a cocotron branch off gap-integration; the
# reviewed tree and its runtime are never touched. Serial, statuses direct.
set -u
W=$HOME/darling
S=$W/source
OUT=$W/f97-alphavalue
mkdir -p "$OUT"
R=$OUT/F97-REPORT.md
: > "$R"
note() { printf '%s\n' "$*" >> "$R"; }
say()  { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }

note "# F97 — restore iTerm2 launch on the merged tail via setAlphaValue: — $(date)"

# ---- source: merged superproject + cocotron gap branch + the F97 patch ----------
say "phase 0: apply patch on cocotron gap branch"
cd "$S"
git checkout -q north-star/gap-integration || { note "ABORT: no gap-integration branch"; exit 1; }
cd src/external/cocotron
git checkout -q gap-integration 2>/dev/null || git checkout -q -b gap-integration
python3 "$HOME/patch-f97.py" > "$OUT/patch.log" 2>&1
pc=$?
cat "$OUT/patch.log" >> "$R"
(( pc == 0 )) || { note "ABORT: patch failed"; exit 1; }
git commit -aqm "F97: implement -[X11Window setAlphaValue:] (EWMH opacity) so the merged tail launches iTerm2" 2>/dev/null
note "- cocotron gap+F97: $(git rev-parse --short=9 HEAD)"
cd "$S"

# ---- baseline recall: the merged tree WITHOUT the patch already died at setAlpha --
note "- baseline (F91): merged tree died at -[X11Window setAlphaValue:], silver-tabs rc=1"

# ---- rebuild the gap roots with the patch ---------------------------------------
say "phase 1: rebuild build-arm64-gap with the patch"
docker run --rm --platform linux/arm64 \
	-v "$S:/work/source:ro" -v "$W/build-arm64-gap:/work/build" \
	darling-arm64-dev:24.04 bash -lc "cd /work/build && ninja -j8" \
	> "$OUT/build.log" 2>&1
bc=$?
note "- patched build: rc=$bc"
(( bc == 0 )) || { note "ABORT: build failed"; grep -m4 -E "error:|FAILED:" "$OUT/build.log" >> "$R"; exit 1; }

say "phase 2: restage install-arm64-gap"
docker run --rm --platform linux/arm64 \
	-v "$S:/work/source:ro" -v "$W/build-arm64-gap:/work/build" -v "$W/install-arm64-gap:/work/stage" \
	darling-arm64-dev:24.04 bash -lc '
		set -u; rm -rf /tmp/g
		for c in cli_gui_common core gui stage18 jsc Unspecified; do
			DESTDIR=/tmp/g cmake --install /work/build --component "$c" >>/tmp/i.log 2>&1 || true
		done
		src=/tmp/g/usr/local/libexec/darling; dst=/work/stage/root
		for e in "$src"/*; do b=${e##*/}
			if [ -L "$e" ] && [ -d "$dst/$b" ] && [ ! -L "$dst/$b" ]; then continue
			elif [ -d "$e" ] && [ ! -L "$e" ]; then mkdir -p "$dst/$b" && cp -a "$e/." "$dst/$b/"
			else cp -a "$e" "$dst/"; fi
		done' > "$OUT/stage.log" 2>&1
note "- restaged"

# ---- the test: does iTerm2 launch now? -----------------------------------------
say "phase 3: launch probe on the merged+patched tree"
export ITERM2_SHARED_CACHE_ROOT=$W/downloads/macos/26.6/dyld-stage18
export DARLING_STAGE18_ROOT=$W/install-arm64-gap DARLING_STAGE18_BUILD_ROOT=$W/build-arm64-gap
PA=$W/artifacts/f97-launch-probe
export ITERM2_PROBE_SHARED_CACHE=1 ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1
export ITERM2_PROBE_FULL_LAUNCHD=1 ITERM2_PROBE_APPKIT_BOOTSTRAP=1 ITERM2_PROBE_APPKIT_REOPEN=1
export ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY=1 ITERM2_PROBE_DIRECT_PTY=1
export ITERM2_PROBE_STABLE_KEYBOARD_SOURCE=1 ITERM2_PROBE_OPAQUE_TEXT=1
export ITERM2_PROBE_DISABLE_METAL=1 ITERM2_PROBE_APPLE_LSD=0 ITERM2_PROBE_APPLE_MDS=0
export ITERM2_PROBE_WAIT_SECONDS=45 ITERM2_PROBE_ARTIFACTS=$PA
tools/probe-iterm2-launch-arm64.sh > "$OUT/probe.log" 2>&1
note "- probe status: $(cat "$PA/status.txt" 2>/dev/null || echo unknown)"
exc=$(grep -am1 "Terminating app due to uncaught" "$PA/iterm2-job.err" 2>/dev/null)
if [ -n "$exc" ]; then
	note "- STILL DIES: $exc"
	note "  (if a NEW abstract method: implement it too, next iteration)"
else
	note "- NO uncaught exception -- setAlphaValue trap cleared"
fi
unset DARLING_STAGE18_ROOT DARLING_STAGE18_BUILD_ROOT ITERM2_PROBE_ARTIFACTS ITERM2_PROBE_WAIT_SECONDS

# ---- the gate: silver-tabs on the merged tree ----------------------------------
say "phase 4: silver-tabs on the merged+patched tree"
export DARLING_STAGE18_ROOT=$W/install-arm64-gap DARLING_STAGE18_BUILD_ROOT=$W/build-arm64-gap
tools/verify-iterm2-silver-tabs-arm64.sh > "$OUT/silver-tabs.log" 2>&1
rc=$?
note "- merged+patched silver-tabs: rc=$rc  ($(tail -1 "$OUT/silver-tabs.log"))"
if (( rc == 0 )); then
	note ""
	note "=> **KEVIN'S Jul 14-16 TAIL NOW LAUNCHES iTerm2 AND PASSES SILVER TABS.**"
fi

note ""
note "*(finished $(date))*"
echo "F97 COMPLETE"