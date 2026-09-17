#!/usr/bin/env bash
# F99-A1: capture 3 session-spawn failures at high resolution to pin the exact
# stuck semaphore/waiter. darlingserver debug logging is on; the whole artifact dir
# (incl. dserver.log) is archived per fail. Reviewed tree, tab-close (weakest gate).
set -u
cd "$HOME/darling/source"
export ITERM2_SHARED_CACHE_ROOT=$HOME/darling/downloads/macos/26.6/dyld-stage18
export ITERM2_PROBE_LIFECYCLE_DEBUG=1
A=$HOME/darling/artifacts/stage19-iterm2-silver-tab-close
out=$HOME/darling/f99-race-capture; rm -rf "$out"; mkdir -p "$out"

fail=0; runs=0; pass_kept=0
while (( runs < 30 && fail < 3 )); do
	runs=$((runs+1))
	sudo -n rm -rf "$A" 2>/dev/null
	tools/verify-iterm2-silver-tab-close-arm64.sh > "$out/run$runs.log" 2>&1
	rc=$?
	if (( rc != 0 )); then
		fail=$((fail+1)); k=$out/FAIL${fail}; mkdir -p "$k"; cp -a "$A/." "$k/" 2>/dev/null
		# classify mode: empty app log = Mode A (early livelock); non-empty = Mode B
		al=$(wc -l < "$k/iterm2-job.err" 2>/dev/null || echo 0)
		echo "run $runs FAIL#$fail  app-log-lines=$al  mode=$( (( al == 0 )) && echo A-early || echo B-late )"
	elif (( pass_kept == 0 )); then
		pass_kept=1; mkdir -p "$out/PASS"; cp -a "$A/." "$out/PASS/" 2>/dev/null
		echo "run $runs pass [kept as control]"
	else echo "run $runs pass"; fi
done
echo "F99-A1: $fail fails in $runs runs"

# ---- pin the stuck call across the Mode-A fails ----
echo
for k in "$out"/FAIL*; do
	[ -d "$k" ] || continue
	al=$(wc -l < "$k/iterm2-job.err" 2>/dev/null || echo 0)
	(( al == 0 )) || { echo "$(basename "$k"): Mode B (late), skip"; continue; }
	echo "== $(basename "$k") Mode A — last 25 distinct dserver calls before the tail =="
	grep -oE "dserver_callnum_[a-z_]+|semaphore_[a-z]+|waitq_[a-z_]+|mach_msg[a-z_]*" "$k/dserver.log" 2>/dev/null \
		| tail -400 | sort | uniq -c | sort -rn | head -12
	echo "-- exact tail (the livelock loop) --"
	tail -10 "$k/dserver.log" 2>/dev/null | sed -E 's/\[[0-9.]+\]//'
	echo
done
echo "F99-A1 COMPLETE"