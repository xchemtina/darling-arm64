#!/usr/bin/env bash
# F81: convert "each Silver gate passes once" into a measured stability statement.
#
# 5 consecutive runs of each of the three Silver gates, plus one run of the
# settings-persistence gate (the seventh gate, never run here). Exit codes captured
# directly, never through a pipe (traps 10/30). Runs sequentially on an otherwise
# idle machine (trap 31: these harnesses assert wall-clock deadlines).
#
# A failure is a result, not a problem: report N/15 verbatim. hello-window (F66) is
# precedent that intermittency is real and worth knowing before claiming stability.
set -u

cd "$HOME/darling/source"
export ITERM2_SHARED_CACHE_ROOT=$HOME/darling/downloads/macos/26.6/dyld-stage18
out=$HOME/darling/f81-stability
rm -rf "$out"; mkdir -p "$out"

declare -A totals passes
for round in 1 2 3 4 5; do
	for gate in tabs tab-close splits; do
		log=$out/silver-$gate-r$round.log
		start=$(date +%s)
		"tools/verify-iterm2-silver-$gate-arm64.sh" > "$log" 2>&1
		rc=$?
		secs=$(( $(date +%s) - start ))
		totals[$gate]=$(( ${totals[$gate]:-0} + 1 ))
		(( rc == 0 )) && passes[$gate]=$(( ${passes[$gate]:-0} + 1 ))
		echo "round $round  $gate  rc=$rc  ${secs}s  $(tail -1 "$log")"
	done
done

echo
echo "== settings-persistence (seventh gate, first ever run here) =="
start=$(date +%s)
tools/verify-iterm2-settings-persistence-arm64.sh > "$out/settings-persistence.log" 2>&1
sp_rc=$?
echo "settings-persistence rc=$sp_rc  $(( $(date +%s) - start ))s  $(tail -1 "$out/settings-persistence.log")"

echo
echo "== F81 summary =="
for gate in tabs tab-close splits; do
	echo "silver-$gate: ${passes[$gate]:-0}/${totals[$gate]:-0}"
done
echo "settings-persistence: $( (( sp_rc == 0 )) && echo 1 || echo 0 )/1"