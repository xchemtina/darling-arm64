#!/usr/bin/env bash
# F77 experiment: what happens to iTerm2's X11 window between ReparentNotify and the
# harness's first look?
#
# F73 established that iTerm2 stays alive, its log shows MapNotify x2 and
# ReparentNotify x2, yet `xwininfo -root -tree` taken AFTER the wait loop shows no
# iTerm2 window. Snapshotting after the fact cannot distinguish:
#   (a) DestroyNotify  -- the client destroyed its own window (e.g. iTerm2 closes a
#       window whose session failed to attach), or
#   (b) UnmapNotify    -- the client or WM withdrew it (still exists, invisible), or
#   (c) never viewable -- mapped with attributes xdotool's --onlyvisible rejects.
#
# This run watches root-window SUBSTRUCTURE EVENTS live (xev -root -event
# substructure) plus a 2 Hz tree poller, both attached to the probe's own container
# via docker exec. Kevin's probe script is NOT modified; the flag set and install
# root are identical to the F73 runs. The observers are the only new variable.
set -uo pipefail

W=$HOME/darling
S=$W/source
A=$W/artifacts/f77-window-lifecycle
rm -rf "$A"; mkdir -p "$A"

# Exact F73 flag configuration (trap 37: copy the WHOLE environment).
export ITERM2_SHARED_CACHE_ROOT=$W/downloads/macos/26.6/dyld-stage18
export ITERM2_PROBE_SHARED_CACHE=1 ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1
export ITERM2_PROBE_FULL_LAUNCHD=1 ITERM2_PROBE_APPKIT_BOOTSTRAP=1 ITERM2_PROBE_APPKIT_REOPEN=1
export ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY=1 ITERM2_PROBE_DIRECT_PTY=1
export ITERM2_PROBE_STABLE_KEYBOARD_SOURCE=1 ITERM2_PROBE_OPAQUE_TEXT=1
export ITERM2_PROBE_DISABLE_METAL=1 ITERM2_PROBE_APPLE_LSD=0 ITERM2_PROBE_APPLE_MDS=0
export ITERM2_PROBE_WAIT_SECONDS=75
export ITERM2_PROBE_ARTIFACTS=$A
# DARLING_STAGE18_ROOT deliberately unset: the probe defaults to
# install-arm64-stage18, the same root the F73 runs used.

"$S/tools/probe-iterm2-launch-arm64.sh" > "$A/probe-driver.log" 2>&1 &
probe_pid=$!

c=darling-arm64-iterm2-launch-probe
up=0
for i in $(seq 1 240); do
	if docker ps --format '{{.Names}}' | grep -qx "$c"; then up=1; break; fi
	sleep 0.5
done
if (( ! up )); then
	echo "FATAL: container $c never appeared; probe log tail:"
	wait "$probe_pid"; tail -20 "$A/probe-driver.log"; exit 1
fi
echo "container up"

if ! docker exec "$c" bash -c \
	'for i in $(seq 1 240); do DISPLAY=:95 xdotool getdisplaygeometry >/dev/null 2>&1 && exit 0; sleep 0.25; done; exit 1'
then
	echo "FATAL: X server on :95 never answered"; wait "$probe_pid"; exit 1
fi
echo "X answering; attaching observers"

# Observer 1: every substructure event on the root window, timestamped per line.
# xev exits by itself when the X server goes away, ending the pipeline cleanly.
docker exec -d "$c" bash -c 'DISPLAY=:95 stdbuf -oL xev -root -event substructure 2>/dev/null \
	| while IFS= read -r l; do printf "%s %s\n" "$(date +%s.%3N)" "$l"; done > /artifacts/f77-xev.log'

# Observer 2: the window tree at 2 Hz, so event ids can be matched to names/classes.
docker exec -d "$c" bash -c 'for i in $(seq 1 600); do
		printf "=== %s ===\n" "$(date +%s.%3N)"
		DISPLAY=:95 xwininfo -root -tree 2>/dev/null
		sleep 0.5
	done > /artifacts/f77-tree.log 2>&1'

wait "$probe_pid"; rc=$?
echo "probe rc=$rc  status=$(cat "$A/status.txt" 2>/dev/null || echo '?')"

echo
echo "== substructure events (headers only) =="
grep -E "Notify event" "$A/f77-xev.log" | head -80
echo
echo "== every distinct named window ever seen in the tree =="
grep -oE '0x[0-9a-f]+ "[^"]*": \("[^"]*" "[^"]*"\)[^+]*' "$A/f77-tree.log" | sort -u
echo
echo "== tree snapshots captured: $(grep -c '^=== ' "$A/f77-tree.log") =="