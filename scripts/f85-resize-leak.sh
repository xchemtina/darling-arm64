#!/usr/bin/env bash
# F85: does the resize leak depend on window SIZE or on resize DIRECTION?
#
# F84 measured a bimodal per-iteration leak (2,274 KiB at 760x500 vs 5,049 KiB at
# 900x600) but could not attribute it: the Bronze soak strictly alternates two sizes,
# so every 900x600 step is a grow and every 760x500 step is a shrink. Target size and
# direction are perfectly confounded, and "growing leaks more" fits the data exactly
# as well as "bigger window leaks more".
#
# THE DESIGN THAT BREAKS THE CONFOUND
# -----------------------------------
# Drive a three-size cycle so the SAME target size is reached from both directions:
#
#     700x450  ->  900x600  ->  1100x750  ->  900x600  ->  (repeat)
#                  ^grow          ^grow        ^shrink
#
# 900x600 is now arrived at by growing (from 700x450) and by shrinking (from
# 1100x750), N times each, in one run, same process, same conditions.
#
#   * leak depends on TARGET SIZE  -> both arrivals at 900x600 leak the same
#   * leak depends on DIRECTION    -> the two arrivals differ
#
# Kevin's gates and probe are NOT modified: this drives xdotool from outside, inside
# the probe's own container, exactly as the F77 observers did.
set -uo pipefail

W=$HOME/darling
S=$W/source
A=$W/artifacts/f85-resize-leak
rm -rf "$A"; mkdir -p "$A"

export ITERM2_SHARED_CACHE_ROOT=$W/downloads/macos/26.6/dyld-stage18
export ITERM2_PROBE_SHARED_CACHE=1 ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1
export ITERM2_PROBE_FULL_LAUNCHD=1 ITERM2_PROBE_APPKIT_BOOTSTRAP=1 ITERM2_PROBE_APPKIT_REOPEN=1
export ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY=1 ITERM2_PROBE_DIRECT_PTY=1
export ITERM2_PROBE_STABLE_KEYBOARD_SOURCE=1 ITERM2_PROBE_OPAQUE_TEXT=1
export ITERM2_PROBE_DISABLE_METAL=1 ITERM2_PROBE_APPLE_LSD=0 ITERM2_PROBE_APPLE_MDS=0
export ITERM2_PROBE_WAIT_SECONDS=240
export ITERM2_PROBE_ARTIFACTS=$A

"$S/tools/probe-iterm2-launch-arm64.sh" > "$A/probe-driver.log" 2>&1 &
probe_pid=$!

c=darling-arm64-iterm2-launch-probe
for i in $(seq 1 240); do
	docker ps --format '{{.Names}}' | grep -qx "$c" && break
	sleep 0.5
done
docker ps --format '{{.Names}}' | grep -qx "$c" || {
	echo "FATAL: container never appeared"; wait "$probe_pid"; exit 1; }

docker exec "$c" bash -c \
	'for i in $(seq 1 240); do DISPLAY=:95 xdotool getdisplaygeometry >/dev/null 2>&1 && exit 0; sleep 0.25; done; exit 1' \
	|| { echo "FATAL: X never answered"; wait "$probe_pid"; exit 1; }

# Let iTerm2 finish building its window before the first measurement, so startup
# allocation is not attributed to a resize.
sleep 25
echo "driving resize cycle"

docker exec "$c" bash -c '
	set -u
	export DISPLAY=:95
	pid=$(pgrep -f "MacOS/iTerm2" | head -1)
	[ -n "$pid" ] || { echo "no iTerm2 process"; exit 1; }
	win=$(xdotool getactivewindow 2>/dev/null)
	[ -n "$win" ] || { echo "no active window"; exit 1; }
	echo "pid=$pid win=$win"

	# NB: no escaping needed -- this block is already single-quoted for the outer
	# shell, so $pid expands in the container shell. Over-escaping made every sample
	# read empty on run 1. NO APOSTROPHES ANYWHERE IN THIS BLOCK (STATE.md trap 12):
	# one apostrophe terminates the single-quoted argument and the rest runs on the
	# host. That trap was already recorded and I still hit it, in a comment.
	# smaps_rollup may not exist for a Darling process, so fall back to VmRSS.
	smaps=/proc/$pid/smaps_rollup
	stat=/proc/$pid/status
	rss() {
		local v
		v=$(grep -m1 "^Rss:" "$smaps" 2>/dev/null | grep -oE "[0-9]+")
		[ -n "$v" ] || v=$(grep -m1 "^VmRSS:" "$stat" 2>/dev/null | grep -oE "[0-9]+")
		printf "%s" "$v"
	}
	[ -n "$(rss)" ] || { echo "FATAL: cannot read RSS for pid $pid"; ls /proc/$pid/ | head; exit 1; }

	# cycle: grow, grow, shrink, (shrink back to start)
	sizes=("700 450" "900 600" "1100 750" "900 600")
	dirs=(shrink grow grow shrink)
	idx=0
	prev=$(rss)
	echo "# idx w h direction rss_kb delta_kb" > /artifacts/f85-samples.txt
	for round in $(seq 1 12); do
		for k in 0 1 2 3; do
			set -- ${sizes[$k]}
			xdotool windowsize "$win" "$1" "$2" 2>/dev/null
			sleep 1.2
			cur=$(rss)
			[ -n "$cur" ] || cur=$prev
			idx=$((idx+1))
			echo "$idx $1 $2 ${dirs[$k]} $cur $((cur-prev))" >> /artifacts/f85-samples.txt
			prev=$cur
		done
	done
	echo "done: $(wc -l < /artifacts/f85-samples.txt) samples"
' 2>&1 | tail -5

kill "$probe_pid" 2>/dev/null
wait "$probe_pid" 2>/dev/null
docker rm -f "$c" >/dev/null 2>&1

echo
echo "== samples =="
head -3 "$A/f85-samples.txt" 2>/dev/null
echo "..."
tail -3 "$A/f85-samples.txt" 2>/dev/null
echo "total: $(( $(wc -l < "$A/f85-samples.txt" 2>/dev/null || echo 1) - 1 )) resizes"