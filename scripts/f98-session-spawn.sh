#!/usr/bin/env bash
# F98: localize the intermittent session-spawn failure — the shared root of the
# Silver flake (F90) and the merged tree's Silver block (F97).
#
# Symptom: window builds, but ~13% of runs never spawn a shell (silver-tab1-pid.txt
# missing, zero children, no exception). The failing run's app log stops at
# PTYTextView setup; darlingserver shows no fork. We need a PASS and a FAIL captured
# with darlingserver DEBUG logging on, to see whether the session fork request ever
# reaches the server.
#
# ITERM2_PROBE_LIFECYCLE_DEBUG=1 turns on DSERVER_LOG_LEVEL=debug (probe L~475), so
# dserver.log records the fork/thread emulation. Whole-dir archive every run.
set -u
cd "$HOME/darling/source"
export ITERM2_SHARED_CACHE_ROOT=$HOME/darling/downloads/macos/26.6/dyld-stage18
export ITERM2_PROBE_LIFECYCLE_DEBUG=1
A=$HOME/darling/artifacts/stage19-iterm2-silver-tab-close
out=$HOME/darling/f98-session-spawn
rm -rf "$out"; mkdir -p "$out"

pass=0; fail=0; runs=0
while (( runs < 14 )); do
	(( pass >= 1 && fail >= 1 )) && break
	runs=$((runs+1))
	sudo -n rm -rf "$A" 2>/dev/null   # clear stale root-owned artifacts (trap: F97)
	tools/verify-iterm2-silver-tab-close-arm64.sh > "$out/run$runs.log" 2>&1
	rc=$?
	if (( rc == 0 )); then
		if (( pass == 0 )); then
			pass=1; keep=$out/PASS-run$runs; mkdir -p "$keep"; cp -a "$A/." "$keep/" 2>/dev/null
			echo "run $runs: PASS  [captured]"
		else echo "run $runs: pass"; fi
	else
		fail=$((fail+1)); keep=$out/FAIL${fail}-run$runs; mkdir -p "$keep"; cp -a "$A/." "$keep/" 2>/dev/null
		echo "run $runs: FAIL rc=$rc  [captured #$fail]  $(tail -1 "$out/run$runs.log")"
	fi
done
echo "F98 capture: $pass pass, $fail fail in $runs runs"

# ---- the diff that localizes ----------------------------------------------------
P=$(ls -d "$out"/PASS-* 2>/dev/null | head -1)
F=$(ls -d "$out"/FAIL1-* 2>/dev/null | head -1)
echo
if [ -n "$P" ] && [ -n "$F" ]; then
	echo "== app log: how far each got (last line) =="
	echo "PASS: $(tail -1 "$P/iterm2-job.err" 2>/dev/null)"
	echo "FAIL: $(tail -1 "$F/iterm2-job.err" 2>/dev/null)"
	echo
	echo "== session/PTY/fork markers present in PASS but not FAIL =="
	comm -23 \
		<(grep -oE "forkpty|posix_spawn|PTYTask|iTermSessionLauncher|startProgram|launchWithPath|brokenPipe|Session Ended|login" "$P/iterm2-job.err" 2>/dev/null | sort -u) \
		<(grep -oE "forkpty|posix_spawn|PTYTask|iTermSessionLauncher|startProgram|launchWithPath|brokenPipe|Session Ended|login" "$F/iterm2-job.err" 2>/dev/null | sort -u)
	echo
	echo "== darlingserver fork/thread activity: PASS vs FAIL counts =="
	for k in fork thread microthread "process create" spawn; do
		pc=$(grep -ic "$k" "$P/dserver.log" 2>/dev/null)
		fc=$(grep -ic "$k" "$F/dserver.log" 2>/dev/null)
		printf "  %-16s PASS=%s FAIL=%s\n" "$k" "$pc" "$fc"
	done
	echo
	echo "== last 6 dserver.log lines, FAIL run (where it stalls) =="
	tail -6 "$F/dserver.log" 2>/dev/null
else
	echo "INCONCLUSIVE: need one PASS and one FAIL; got pass=$pass fail=$fail"
fi
echo "F98 COMPLETE"