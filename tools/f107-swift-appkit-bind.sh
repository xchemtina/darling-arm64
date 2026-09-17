#!/usr/bin/env bash
# f107-swift-appkit-bind.sh [label] — F107 in-VM confirmation + NEXT_STEPS item 1 step 3.
# Drives the s3_appkit_attr.app Swift probe (F106) through the probe engine three times,
# A/B/A over ONE variable: ITERM2_PROBE_PREFER_DISK_FRAMEWORKS (1 = Kevin's hybrid, Darling
# AppKit from disk; 0 = Apple AppKit from the shared cache). Everything else is the F104
# known-good env. DYLD_PRINT_SEGMENTS shows which AppKit was mapped, from where.
# Artifacts preserved per attempt — no attempt may wipe the evidence of the previous one.
set -u
W=$HOME/darling
S=$W/source
cd "$S"
LABEL=${1:-bind}
BUNDLE=$W/downloads/swiftprobe-app/s3_appkit_attr.app
EXE=s3_appkit_attr
[[ -x $BUNDLE/Contents/MacOS/$EXE ]] || { echo "s3_appkit_attr.app missing (F106 bundle)"; exit 2; }
A=$W/artifacts/f107-swift-appkit
out=$W/f107-swift-appkit/$LABEL; mkdir -p "$out"

run_arm() {   # $1 arm label, $2 prefer_disk (1|0)
	local arm=$1 prefer=$2 k rc
	sudo -n rm -rf "$A" 2>/dev/null; mkdir -p "$A"
	docker rm -f darling-arm64-iterm2-launch-probe >/dev/null 2>&1
	echo "[arm $arm] PREFER_DISK_FRAMEWORKS=$prefer  $(date +%H:%M:%S)"
	env \
		APP_PROBE_BUNDLE="$BUNDLE" \
		APP_PROBE_BUNDLE_NAME=$(basename "$BUNDLE") \
		APP_PROBE_EXECUTABLE_NAME=$EXE \
		ITERM2_PROBE_ARTIFACTS="$A" \
		ITERM2_SHARED_CACHE_ROOT=$W/downloads/macos/26.6/dyld-stage18 \
		DARLING_STAGE18_ROOT=$W/install-arm64-f103 \
		DARLING_STAGE18_BUILD_ROOT=$W/build-arm64-f103 \
		ITERM2_PROBE_WAIT_SECONDS=20 \
		ITERM2_PROBE_SHARED_CACHE=1 \
		ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=$prefer \
		ITERM2_PROBE_DYLD_PRINT_SEGMENTS=1 \
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
		ITERM2_PROBE_LIFECYCLE_DEBUG=0 \
		tools/probe-iterm2-launch-arm64.sh > "$out/$arm-probe.log" 2>&1
	rc=$?
	k="$out/$arm"; mkdir -p "$k"
	sudo -n cp -a "$A/." "$k/" 2>/dev/null; sudo -n chown -R "$(id -u):$(id -g)" "$k" 2>/dev/null
	echo "  rc=$rc status=$(cat "$k/status.txt" 2>/dev/null || echo none)"
	echo "  stdout (iterm2-job.out): $(grep -m1 -E 'SWIFT_APPKIT_ATTR_OK' "$k/iterm2-job.out" 2>/dev/null || echo '<no OK line>')"
	echo "  first dyld/crash line in iterm2-job.err:"
	grep -m2 -E 'Symbol not found|Library not loaded|dyld\[|Referenced from|Expected in|abort|Trace/BPT|Segmentation' "$k/iterm2-job.err" 2>/dev/null | sed 's/^/    /' || echo "    <none>"
	echo "  AppKit + libswiftAppKit mapped from (DYLD_PRINT_SEGMENTS):"
	grep -h -E 'AppKit' "$k/iterm2-job.err" "$k/iterm2-job.out" 2>/dev/null | grep -iE 'framework|dylib|cache|segment|__TEXT' | grep -oE '(/[A-Za-z0-9_./-]*AppKit[A-Za-z0-9_./-]*|shared cache[^ ]*)' | sort | uniq -c | sort -rn | head -6 | sed 's/^/    /'
}

run_arm A1 1     # Kevin's hybrid (F106 condition): Darling AppKit from disk
run_arm B  0     # flip: Apple AppKit from the cache
run_arm A2 1     # restore: must reproduce A1

echo
echo "===== F107 SUMMARY (label=$LABEL) — artifacts in $out ====="
for arm in A1 B A2; do
	printf "  %-3s ok=%-3s symbol-not-found=%-3s lib-not-loaded=%-3s status=%s\n" "$arm" \
		"$(grep -c SWIFT_APPKIT_ATTR_OK "$out/$arm/iterm2-job.out" 2>/dev/null)" \
		"$(grep -c 'Symbol not found' "$out/$arm/iterm2-job.err" 2>/dev/null)" \
		"$(grep -c 'Library not loaded' "$out/$arm/iterm2-job.err" 2>/dev/null)" \
		"$(cat "$out/$arm/status.txt" 2>/dev/null || echo none)"
done
echo "F107 COMPLETE $(date +%H:%M:%S)"
