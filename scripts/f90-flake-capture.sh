#!/usr/bin/env bash
# F90: capture Silver tab-close flakes with full evidence.
#
# Phase B measured tab-close at 11/15 but archived only gate logs -- the gate's
# artifact directory was clobbered run-over-run, so the four failures left no
# artifacts to classify. This reruns the weakest gate, archiving the WHOLE artifact
# directory after every run (F84 Part 3 lesson), until 3 failures are captured or
# 15 runs elapse. Idle machine, serial (trap 31); statuses captured directly.
set -u

cd "$HOME/darling/source"
export ITERM2_SHARED_CACHE_ROOT=$HOME/darling/downloads/macos/26.6/dyld-stage18
A=$HOME/darling/artifacts/stage19-iterm2-silver-tab-close
out=$HOME/darling/f90-flake-capture
rm -rf "$out"; mkdir -p "$out"

fails=0; runs=0
while (( runs < 15 && fails < 3 )); do
	runs=$((runs+1))
	tools/verify-iterm2-silver-tab-close-arm64.sh > "$out/run$runs.log" 2>&1
	rc=$?
	keep=$out/run$runs-artifacts; mkdir -p "$keep"
	cp -a "$A/." "$keep/" 2>/dev/null
	if (( rc != 0 )); then
		fails=$((fails+1))
		echo "run $runs: FAIL rc=$rc  [captured #$fails]  last: $(tail -1 "$out/run$runs.log")"
	else
		echo "run $runs: pass"
		rm -rf "$keep"    # keep disk bounded; passing artifacts add nothing
	fi
done
echo "F90 done: $fails failures captured in $runs runs"