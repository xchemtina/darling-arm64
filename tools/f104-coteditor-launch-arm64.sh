#!/usr/bin/env bash
# f104-coteditor-launch-arm64.sh <N> [label] — Stage 20 (CotEditor Bronze) launch probe.
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
N=${1:-1}
LABEL=${2:-launch}
BUNDLE=${COTEDITOR_BUNDLE:-$W/downloads/coteditor/7.0.7/reference/CotEditor.app}
EXE=${PROBE_EXE:-CotEditor}
[[ -x $BUNDLE/Contents/MacOS/$EXE ]] || { echo "CotEditor bundle missing; run prepare-coteditor-artifact-arm64.sh"; exit 2; }

A=$W/artifacts/f104-coteditor
out=$W/f104-coteditor/$LABEL; rm -rf "$out"; mkdir -p "$out"

orig_pattern=$(cat /proc/sys/kernel/core_pattern)
restore() { printf '%s' "$orig_pattern" | sudo -n tee /proc/sys/kernel/core_pattern >/dev/null; }
trap restore EXIT
echo "/artifacts/core.%e.%p" | sudo -n tee /proc/sys/kernel/core_pattern >/dev/null

# temp probe variant with core dumps enabled (same trick as f101-core-capture)
sed -E 's|--name "\$container" --rm|--name "$container" --rm --ulimit core=-1|' \
	tools/probe-iterm2-launch-arm64.sh > tools/f104-tmp-probe.sh && chmod +x tools/f104-tmp-probe.sh
grep -q 'ulimit core' tools/f104-tmp-probe.sh || { echo "probe sed failed"; exit 1; }

echo "Stage 20 / CotEditor 7.0.7 — $N attempt(s), label=$LABEL"
echo "  bundle: $BUNDLE (unmodified, read-only)"

for ((i=1;i<=N;i++)); do
	sudo -n rm -rf "$A" 2>/dev/null; mkdir -p "$A"
	docker rm -f darling-arm64-iterm2-launch-probe >/dev/null 2>&1
	echo "[attempt $i] $(date +%H:%M:%S)"
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
		ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1 \
		ITERM2_PROBE_FULL_LAUNCHD=1 \
		ITERM2_PROBE_APPKIT_BOOTSTRAP=1 \
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
		tools/f104-tmp-probe.sh > "$out/attempt$i-probe.log" 2>&1
	rc=$?
	k="$out/attempt$i"; mkdir -p "$k"
	sudo -n cp -a "$A/." "$k/" 2>/dev/null; sudo -n chown -R "$(id -u):$(id -g)" "$k" 2>/dev/null
	win=$(grep -c "^ *0x" "$k/windows.txt" 2>/dev/null); win=${win:-0}
	st=$(cat "$k/status.txt" 2>/dev/null); st=${st:-none}
	cores=$(ls "$k"/core.* 2>/dev/null | wc -l)
	proc=$(grep -c "MacOS/CotEditor" "$k/processes.txt" 2>/dev/null); proc=${proc:-0}
	echo "  rc=$rc status=$st x11_windows=$win coteditor_procs=$proc cores=$cores"
	# the boundary question: any window that is NOT the ~512x129 alert Kevin recorded?
	if [[ -s $k/window-details.txt ]]; then
		echo "  window geometries:"; grep -oE "[0-9]+x[0-9]+\+[0-9-]+\+[0-9-]+" "$k/window-details.txt" 2>/dev/null | sort | uniq -c | head -6 | sed 's/^/    /'
	fi
done
restore; trap - EXIT
rm -f tools/f104-tmp-probe.sh
echo "STAGE-20 ATTEMPTS COMPLETE — artifacts in $out"
