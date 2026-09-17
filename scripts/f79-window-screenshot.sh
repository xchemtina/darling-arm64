#!/usr/bin/env bash
# F79 experiment: photograph the terminal window during its 1.42 s of life.
#
# iTerm2 v3.6.11 source: when the forked child cannot exec the session program, it
# writes a plain-text banner INTO THE PTY -- "The program could not be run (execvp
# failed)" / "The failing command was:" / "The reason for the failure was:" plus
# strerror(errno) -- then sleep(1); _exit(1)  (iTermPosixTTYReplacements.c). F77
# showed the window visible for 1.42 s, which fits that sleep. If the banner is what
# the window displays, a screenshot burst catches the exact failing command and errno
# without touching the binary, the probe, or even a preference.
set -uo pipefail

W=$HOME/darling
S=$W/source
A=$W/artifacts/f79-window-screenshot
rm -rf "$A"; mkdir -p "$A"

export ITERM2_SHARED_CACHE_ROOT=$W/downloads/macos/26.6/dyld-stage18
export ITERM2_PROBE_SHARED_CACHE=1 ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1
export ITERM2_PROBE_FULL_LAUNCHD=1 ITERM2_PROBE_APPKIT_BOOTSTRAP=1 ITERM2_PROBE_APPKIT_REOPEN=1
export ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY=1 ITERM2_PROBE_DIRECT_PTY=1
export ITERM2_PROBE_STABLE_KEYBOARD_SOURCE=1 ITERM2_PROBE_OPAQUE_TEXT=1
export ITERM2_PROBE_DISABLE_METAL=1 ITERM2_PROBE_APPLE_LSD=0 ITERM2_PROBE_APPLE_MDS=0
export ITERM2_PROBE_WAIT_SECONDS=45
export ITERM2_PROBE_ARTIFACTS=$A

"$S/tools/probe-iterm2-launch-arm64.sh" > "$A/probe-driver.log" 2>&1 &
probe_pid=$!

c=darling-arm64-iterm2-launch-probe
up=0
for i in $(seq 1 240); do
	docker ps --format '{{.Names}}' | grep -qx "$c" && { up=1; break; }
	sleep 0.5
done
(( up )) || { echo "FATAL: container never appeared"; wait "$probe_pid"; exit 1; }

docker exec "$c" bash -c \
	'for i in $(seq 1 240); do DISPLAY=:95 xdotool getdisplaygeometry >/dev/null 2>&1 && exit 0; sleep 0.25; done; exit 1' \
	|| { echo "FATAL: X never answered"; wait "$probe_pid"; exit 1; }
echo "X up; screenshot burst starting"

# 4 fps for 60 s. Frames are timestamped; only frames where something is mapped
# differ, and the interesting ones are trivially found by size (a mapped terminal
# window changes the root image size dramatically after PNG compression).
docker exec -d "$c" bash -c 'mkdir -p /artifacts/frames
	for i in $(seq 1 240); do
		DISPLAY=:95 import -window root "/artifacts/frames/$(date +%s.%2N).png" 2>/dev/null
		sleep 0.25
	done'

wait "$probe_pid"; rc=$?
echo "probe rc=$rc  status=$(cat "$A/status.txt" 2>/dev/null || echo '?')"
echo "== frames by size (largest = most content on screen) =="
ls -laS "$A/frames" 2>/dev/null | head -12
echo "== frame count: $(ls "$A/frames" 2>/dev/null | wc -l) =="