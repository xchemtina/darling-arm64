#!/usr/bin/env bash
# F82: the profile-dependency matrix.
#
# The upstream record says the iTerm2-specific bootstrap behaviours "must become
# general AppKit/X11 behavior or be removed before the Definition of Done", and the
# Silver gates switch them on. Nobody has measured which of them Silver actually
# depends on. Now that Silver passes (F80), the ablation is meaningful.
#
# Method: replicate the silver-tabs gate's EXACT probe environment (its env list,
# tools/verify-iterm2-silver-tabs-arm64.sh L21-41), invoke the PROBE directly (the
# gate itself stays unmodified), and flip ONE flag per run. A control run with all
# flags at gate values comes first: if the control does not reproduce the gate's
# pass, the harness is wrong and no cell below it means anything.
#
# Cells: only the five ITERM2-specific sub-flags plus APPKIT_REOPEN are ablated.
# ITERM2_PROBE_APPKIT_BOOTSTRAP=0 is deliberately NOT a cell -- it zeroes DYLD
# insertion and all sub-flags at once (probe L908-934), so it measures "everything
# off", not one dependency. PREFER_DISK_FRAMEWORKS=0 is also not a cell: trap 37
# already established it loads Apple's AppKit from the cache and dies instantly.
#
# Success criterion per cell = the gate's own behavioural core, checked from the
# artifacts: both tab PID round-trips match, shells=2, status=running. One run per
# cell -- reported as such, never as a stability statement.
set -u

cd "$HOME/darling/source"
export ITERM2_SHARED_CACHE_ROOT=$HOME/darling/downloads/macos/26.6/dyld-stage18
out=$HOME/darling/f82-matrix
rm -rf "$out"; mkdir -p "$out"

# silver-tabs gate environment, replicated verbatim
base=(
	ITERM2_PROBE_WAIT_SECONDS=15
	ITERM2_PROBE_SHARED_CACHE=1
	ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1
	ITERM2_PROBE_FULL_LAUNCHD=1
	ITERM2_PROBE_APPKIT_BOOTSTRAP=1
	ITERM2_PROBE_APPKIT_REOPEN=1
	ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY=1
	ITERM2_PROBE_DIRECT_PTY=1
	ITERM2_PROBE_STABLE_KEYBOARD_SOURCE=1
	ITERM2_PROBE_OPAQUE_TEXT=1
	ITERM2_PROBE_DISABLE_METAL=1
	ITERM2_PROBE_TAB_WORKFLOW=1
	'ITERM2_PROBE_TYPE_TEXT=printf %s $$ >/artifacts/silver-tab1-pid.txt;printf ready >/artifacts/silver-tab1-ready.txt'
	ITERM2_PROBE_QUIT_DIALOG=0
	ITERM2_PROBE_QUIT_CONFIRM=0
	ITERM2_PROBE_SHUTDOWN_PREFIX=0
	ITERM2_PROBE_APPLE_LSD=0
	ITERM2_PROBE_APPLE_MDS=0
)

cells=(
	CONTROL
	ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY
	ITERM2_PROBE_DIRECT_PTY
	ITERM2_PROBE_STABLE_KEYBOARD_SOURCE
	ITERM2_PROBE_OPAQUE_TEXT
	ITERM2_PROBE_DISABLE_METAL
	ITERM2_PROBE_APPKIT_REOPEN
)

score() {
	# behavioural core of the silver-tabs gate, from the artifacts
	local a=$1 t1p t1r t2p t2r
	t1p=$(cat "$a/silver-tab1-pid.txt" 2>/dev/null)
	t1r=$(cat "$a/silver-tab1-return-pid.txt" 2>/dev/null)
	t2p=$(cat "$a/silver-tab2-pid.txt" 2>/dev/null)
	t2r=$(cat "$a/silver-tab2-return-pid.txt" 2>/dev/null)
	local shells status
	shells=$(grep -o "shells=[0-9]*" "$a/silver-tabs.txt" 2>/dev/null)
	status=$(cat "$a/status.txt" 2>/dev/null)
	if [[ -n $t1p && $t1p == "$t1r" && -n $t2p && $t2p == "$t2r" \
	      && $shells == shells=2 && $status == running ]]; then
		echo "PASS (tab1=$t1p tab2=$t2p)"
	else
		echo "FAIL (tab1='$t1p'/'$t1r' tab2='$t2p'/'$t2r' $shells status=$status)"
	fi
}

for cell in "${cells[@]}"; do
	a=$out/artifacts-$cell
	env_args=("${base[@]}" "ITERM2_PROBE_ARTIFACTS=$a")
	if [[ $cell != CONTROL ]]; then
		# flip exactly one flag off
		env_args=("${env_args[@]/$cell=1/$cell=0}")
	fi
	start=$(date +%s)
	timeout 300 env "${env_args[@]}" tools/probe-iterm2-launch-arm64.sh \
		> "$out/$cell.log" 2>&1
	rc=$?
	secs=$(( $(date +%s) - start ))
	printf "%-42s rc=%-3s %4ss  %s\n" "$cell" "$rc" "$secs" "$(score "$a")"
	if [[ $cell == CONTROL ]]; then
		grep -q "PASS" <<<"$(score "$a")" || {
			echo "CONTROL DID NOT REPRODUCE THE GATE PASS -- harness invalid, stopping." >&2
			exit 1
		}
	fi
done
echo
echo "One run per cell. A FAIL names a flag Silver depends on; a PASS means one run"
echo "survived without it, nothing stronger."