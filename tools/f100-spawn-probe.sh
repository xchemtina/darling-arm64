#!/usr/bin/env bash
# f100-spawn-probe.sh — lean session-spawn A/B/A probe for the psynch flake (F100).
# Strips the Silver gate to its core: launch iTerm2 -> does the login `-sh` fork appear?
# Signal: probe writes /artifacts/shell-ready.txt the instant `-sh` is detected
# (probe-iterm2-launch-arm64.sh:1480), independent of xdotool/tab-workflow.
# Classifies each run pass / crash / no-spawn, N times; prints rate + 95% Wilson CI.
#
#   Usage: f100-spawn-probe.sh <N> <label>
#   Env:   DARLING_STAGE18_ROOT / DARLING_STAGE18_BUILD_ROOT (scratch; default id26)
#          ITERM2_PROBE_WAIT_SECONDS (default 25)
set -u
cd "$HOME/darling/source"
N=${1:-120}
LABEL=${2:-baseline}
WAIT=${ITERM2_PROBE_WAIT_SECONDS:-30}
export ITERM2_SHARED_CACHE_ROOT=${ITERM2_SHARED_CACHE_ROOT:-$HOME/darling/downloads/macos/26.6/dyld-stage18}
export DARLING_STAGE18_ROOT=${DARLING_STAGE18_ROOT:-$HOME/darling/install-arm64-id26}
export DARLING_STAGE18_BUILD_ROOT=${DARLING_STAGE18_BUILD_ROOT:-$HOME/darling/build-arm64-id26}
A=$HOME/darling/artifacts/f100-spawn-probe
out=$HOME/darling/f100-runs/$LABEL; rm -rf "$out"; mkdir -p "$out"
echo "f100 [$LABEL] N=$N WAIT=${WAIT}s ROOT=$DARLING_STAGE18_ROOT"

pass=0; crash=0; nospawn=0
for ((i=1;i<=N;i++)); do
	sudo -n rm -rf "$A" 2>/dev/null; mkdir -p "$A"
	docker rm -f darling-arm64-iterm2-launch-probe >/dev/null 2>&1
	# Full gate bootstrap env (FULL_LAUNCHD/APPKIT_BOOTSTRAP/DIRECT_PTY/DISABLE_METAL are
	# what let iTerm2 start headless + spawn the first session); only the tab/close
	# workflows are stripped — the flake signal (shell-ready.txt) lands before them.
	env \
	ITERM2_PROBE_ARTIFACTS="$A" \
	ITERM2_PROBE_WAIT_SECONDS=$WAIT \
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
	ITERM2_PROBE_TYPE_TEXT='printf %s $$ >/artifacts/silver-tab1-pid.txt;printf ready >/artifacts/silver-tab1-ready.txt' \
	ITERM2_PROBE_QUIT_DIALOG=0 \
	ITERM2_PROBE_APPLE_LSD=0 \
	ITERM2_PROBE_APPLE_MDS=0 \
		tools/probe-iterm2-launch-arm64.sh > "$A/probe.log" 2>&1
	rc=$?
	if [[ -s "$A/shell-ready.txt" ]]; then
		pass=$((pass+1)); cls=pass
	elif grep -qiE "CoreDumping:[[:space:]]*1|SIGSEGV|segmentation fault|uncaught exception|trace/bpt trap|process dying" "$A/dserver.log" "$A/iterm2-job.err" "$A/probe.log" 2>/dev/null; then
		crash=$((crash+1)); cls=crash
	else
		nospawn=$((nospawn+1)); cls=nospawn
	fi
	echo "$i $cls rc=$rc" >> "$out/log.txt"
	if [[ $cls != pass ]]; then
		k=$out/$cls-$i; mkdir -p "$k"
		cp -a "$A/dserver.log" "$A/iterm2-job.err" "$A/probe.log" "$k/" 2>/dev/null
	fi
	fails=$((crash+nospawn))
	printf "\r[%s] %d/%d pass=%d crash=%d nospawn=%d failrate=%.1f%%   " \
		"$LABEL" "$i" "$N" "$pass" "$crash" "$nospawn" "$(awk "BEGIN{print ($fails/$i)*100}")"
done
echo
fails=$((crash+nospawn))
python3 - "$pass" "$fails" "$N" "$LABEL" "$crash" "$nospawn" <<'PY'
import sys,math
p,f,n,label,cr,ns=int(sys.argv[1]),int(sys.argv[2]),int(sys.argv[3]),sys.argv[4],int(sys.argv[5]),int(sys.argv[6])
rate=f/n if n else 0
z=1.96; den=1+z*z/n
centre=(rate+z*z/(2*n))/den
half=(z*math.sqrt(rate*(1-rate)/n+z*z/(4*n*n)))/den
lo,hi=max(0.0,centre-half),min(1.0,centre+half)
print(f"F100 [{label}] n={n} pass={p} fail={f} (crash={cr} nospawn={ns}) fail-rate={rate*100:.1f}% 95% Wilson CI [{lo*100:.1f}%, {hi*100:.1f}%]")
PY
echo "f100 [$LABEL] COMPLETE — records in $out"
