#!/usr/bin/env bash
# f111-coteditor-no-bootstrap.sh [label] — F110 follow-up: Apple AppKit bound (PREFER_DISK=0) WITH
# Darling's AppKit bootstrap shim (arm B, reproduces F110 B) vs WITHOUT it (arm C). One variable:
# ITERM2_PROBE_APPKIT_BOOTSTRAP. F107/F110 saw duplicate classes between Apple's AppKit and
# libDarlingAppKitBootstrap and then a SIGSEGV in the cache; is the shim the collision?
# Derived from the F104 CotEditor
# launch probe, A/B/A over ONE variable, ITERM2_PROBE_PREFER_DISK_FRAMEWORKS (1 = Darling
# AppKit, F104 condition; 0 = Apple AppKit from the cache, which resolved the Swift symbol in
# F107). Everything else is F104 verbatim. Does CotEditor get past the symbol — and to what?
# Drives the existing iTerm2 probe engine with the pinned, UNMODIFIED CotEditor 7.0.7
# bundle via its APP_PROBE_* parameters. TYPE_TEXT is empty, so the iTerm2-specific
# workflow is skipped and the probe's generic capture runs: windows.txt (xwininfo -root
# -tree), window-details.txt, screen.png, processes.txt, status.txt, app logs, dserver.log.
#
# Launch env mirrors the KNOWN-GOOD iTerm2 env exactly (change one variable at a time);
# Kevin's Stage-20 contract additions: Apple LSD + MDS off, Metal off.
# Cores enabled (zero perturbation; strace suppresses these bugs). Artifacts preserved
# per attempt -- no run may wipe the evidence of the previous one.
set -u
W=$HOME/darling
S=$W/source
cd "$S"
N=3
LABEL=${1:-aba}
ARMS=(B:0:1 C:0:0)
BUNDLE=${COTEDITOR_BUNDLE:-$W/downloads/coteditor/7.0.7/reference/CotEditor.app}
EXE=${PROBE_EXE:-CotEditor}
[[ -x $BUNDLE/Contents/MacOS/$EXE ]] || { echo "CotEditor bundle missing; run prepare-coteditor-artifact-arm64.sh"; exit 2; }

A=$W/artifacts/f111-coteditor
out=$W/f111-coteditor/$LABEL; mkdir -p "$out"

orig_pattern=$(cat /proc/sys/kernel/core_pattern)
restore() { printf '%s' "$orig_pattern" | sudo -n tee /proc/sys/kernel/core_pattern >/dev/null; }
trap restore EXIT
echo "/artifacts/core.%e.%p" | sudo -n tee /proc/sys/kernel/core_pattern >/dev/null

# temp probe variant with core dumps enabled (same trick as f101-core-capture)
sed -E 's|--name "\$container" --rm|--name "$container" --rm --ulimit core=-1|' \
	tools/probe-iterm2-launch-arm64.sh > tools/f111-tmp-probe.sh && chmod +x tools/f111-tmp-probe.sh
grep -q 'ulimit core' tools/f111-tmp-probe.sh || { echo "probe sed failed"; exit 1; }

echo "F111: Stage 20 / CotEditor 7.0.7 — A/B/A over PREFER_DISK_FRAMEWORKS, label=$LABEL"
echo "  bundle: $BUNDLE (unmodified, read-only)"

for spec in "${ARMS[@]}"; do
	IFS=: read -r i prefer boot <<<"$spec"
	sudo -n rm -rf "$A" 2>/dev/null; mkdir -p "$A"
	docker rm -f darling-arm64-iterm2-launch-probe >/dev/null 2>&1
	echo "[arm $i] PREFER_DISK_FRAMEWORKS=$prefer APPKIT_BOOTSTRAP=$boot $(date +%H:%M:%S)"
	env \
		APP_PROBE_BUNDLE="$BUNDLE" \
		APP_PROBE_BUNDLE_NAME=$(basename "$BUNDLE") \
		APP_PROBE_EXECUTABLE_NAME=$EXE \
		ITERM2_PROBE_ARTIFACTS="$A" \
		ITERM2_SHARED_CACHE_ROOT=$W/downloads/macos/26.6/dyld-stage18 \
		DARLING_STAGE18_ROOT=${STAGE18_ROOT_OVERRIDE:-$W/install-arm64-f103} \
		DARLING_STAGE18_BUILD_ROOT=$W/build-arm64-f103 \
		ITERM2_PROBE_WAIT_SECONDS=45 \
		ITERM2_PROBE_SHARED_CACHE=1 \
		ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=$prefer \
		ITERM2_PROBE_DYLD_PRINT_SEGMENTS=1 \
		ITERM2_PROBE_FULL_LAUNCHD=1 \
		ITERM2_PROBE_APPKIT_BOOTSTRAP=$boot \
		ITERM2_PROBE_APPKIT_REOPEN=1 \
		ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY=1 \
		ITERM2_PROBE_DIRECT_PTY=1 \
		ITERM2_PROBE_STABLE_KEYBOARD_SOURCE=1 \
		ITERM2_PROBE_OPAQUE_TEXT=1 \
		ITERM2_PROBE_DISABLE_METAL=1 \
		ITERM2_PROBE_TAB_WORKFLOW=0 \
		ITERM2_PROBE_TAB_CLOSE_WORKFLOW=0 \
		ITERM2_PROBE_QUIT_DIALOG=0 \
		ITERM2_PROBE_APPLE_LSD=0 \
		ITERM2_PROBE_APPLE_MDS=0 \
		ITERM2_PROBE_LIFECYCLE_DEBUG=1 \
		tools/f111-tmp-probe.sh > "$out/$i-probe.log" 2>&1
	rc=$?
	k="$out/$i"; mkdir -p "$k"
	sudo -n cp -a "$A/." "$k/" 2>/dev/null; sudo -n chown -R "$(id -u):$(id -g)" "$k" 2>/dev/null
	win=$(grep -c "^ *0x" "$k/windows.txt" 2>/dev/null); win=${win:-0}
	st=$(cat "$k/status.txt" 2>/dev/null); st=${st:-none}
	cores=$(ls "$k"/core.* 2>/dev/null | wc -l)
	proc=$(grep -c "MacOS/CotEditor" "$k/processes.txt" 2>/dev/null); proc=${proc:-0}
	echo "  rc=$rc status=$st x11_windows=$win coteditor_procs=$proc cores=$cores"
	echo "  first failure line: $(grep -h -m1 -E "Symbol not found|Library not loaded|Terminating app|uncaught exception|abort_with_payload|unhandled ARM64|Trace/BPT" "$k/iterm2-job.out" "$k/iterm2-job.err" 2>/dev/null || echo "<none>")"
	# the boundary question: any window that is NOT the ~512x129 alert Kevin recorded?
	if [[ -s $k/window-details.txt ]]; then
		echo "  window geometries:"; grep -oE "[0-9]+x[0-9]+\+[0-9-]+\+[0-9-]+" "$k/window-details.txt" 2>/dev/null | sort | uniq -c | head -6 | sed 's/^/    /'
	fi
done
restore; trap - EXIT
rm -f tools/f111-tmp-probe.sh
echo "F111 COMPLETE $(date +%H:%M:%S) — artifacts in $out"
