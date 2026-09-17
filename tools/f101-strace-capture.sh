#!/usr/bin/env bash
# f101-strace-capture.sh <N> — the decisive capture: rerun the debug-amplified gate with
# the probe's strace hook so the fatal signal's full siginfo (si_code, si_addr) is
# recorded. TRAP_BRKPT + si_addr names the trapping module (self-executed brk);
# SI_USER/SI_TKILL would prove external delivery. Also catches mode-B's frozen syscall
# and the killer pid. Temp sed-derived gate/probe variants; committed harnesses untouched.
set -u
cd ~/darling/source
N=${1:-4}

echo "[0] clean rebuild of id26 (source pristine; id26 held the inert latch build)"
tools/f100-build-id26.sh >/tmp/f101-build.log 2>&1 || { echo "BUILD FAILED"; tail -5 /tmp/f101-build.log; exit 1; }
tail -1 /tmp/f101-build.log

echo "[1] temp strace-filtered probe + gate variants"
sed -E 's|strace -ff -s 256 -o /artifacts/strace|strace -ff -s 256 -e trace=close,dup3,futex,kill,tgkill,tkill,rt_sigaction,execve,exit_group,clone,wait4 -o /artifacts/strace|' \
	tools/probe-iterm2-launch-arm64.sh > tools/f101-tmp-probe.sh && chmod +x tools/f101-tmp-probe.sh
grep -q 'trace=close,dup3' tools/f101-tmp-probe.sh || { echo "probe sed failed"; exit 1; }
sed -E 's|"\$source_root/tools/probe-iterm2-launch-arm64.sh"|"$source_root/tools/f101-tmp-probe.sh"|' \
	tools/verify-iterm2-silver-tab-close-arm64.sh > tools/f101-tmp-gate.sh && chmod +x tools/f101-tmp-gate.sh
grep -q 'f101-tmp-probe' tools/f101-tmp-gate.sh || { echo "gate sed failed"; exit 1; }

export ITERM2_SHARED_CACHE_ROOT=~/darling/downloads/macos/26.6/dyld-stage18
export DARLING_STAGE18_ROOT=~/darling/install-arm64-id26
export DARLING_STAGE18_BUILD_ROOT=~/darling/build-arm64-id26
export ITERM2_PROBE_LIFECYCLE_DEBUG=1
export ITERM2_PROBE_TRACE=1
A=~/darling/artifacts/stage19-iterm2-silver-tab-close
out=~/darling/f101-strace; rm -rf "$out"; mkdir -p "$out"

for ((i=1;i<=N;i++)); do
	sudo -n rm -rf "$A" 2>/dev/null
	docker rm -f darling-arm64-iterm2-launch-probe >/dev/null 2>&1
	echo "[run $i] $(date +%H:%M:%S)"
	tools/f101-tmp-gate.sh > "$out/run$i.log" 2>&1; rc=$?
	k="$out/run$i"; mkdir -p "$k"
	cp -a "$A/dserver.log" "$k/" 2>/dev/null
	ls -la "$A"/strace.* > "$k/strace-index.txt" 2>/dev/null
	ipid=$(grep -oE '\[P:[0-9]+\(13\)\]' "$k/dserver.log" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
	# archive iTerm2's strace + every strace file carrying a fatal signal
	[ -n "${ipid:-}" ] && cp -a "$A/strace.$ipid" "$k/" 2>/dev/null
	for f in "$A"/strace.*; do
		[ -f "$f" ] || continue
		if grep -qE -- '--- SIG(TRAP|ABRT|SEGV|ILL|BUS)' "$f" 2>/dev/null; then cp -a "$f" "$k/" 2>/dev/null; fi
	done
	sig=$(grep -rhoE -- '--- SIG[A-Z]+ \{[^}]*\}' "$k"/strace.* 2>/dev/null | grep -vE 'SIGWINCH|SIGCHLD|SIGPIPE' | head -3)
	echo "  rc=$rc iterm2_pid=${ipid:-?} archived_straces=$(ls "$k"/strace.* 2>/dev/null | wc -l)"
	echo "  fatal siginfo: ${sig:-none-captured}"
done

echo "CAPTURE COMPLETE $(date +%H:%M:%S)"
echo "== all fatal-signal lines across the batch =="
grep -rn -- '--- SIG\(TRAP\|ABRT\|SEGV\|ILL\|BUS\)' "$out"/run*/strace.* 2>/dev/null | head -12
