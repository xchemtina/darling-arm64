#!/usr/bin/env bash
# F78 experiment: WHY does iTerm2's session die at birth?
#
# F77 established the window closes because no session ever spawns (zero children).
# iTerm2 source (v3.6.11) shows every launch-failure flavour funnels into
# brokenPipe -> endAction Close -> [[self window] close], and that the entire failure
# path logs ONLY via DLog, which is a no-op unless debug logging is enabled -- which
# explains why stderr says nothing about the close.
#
# The advanced setting `startDebugLoggingAutomatically` turns DLog on at startup,
# writing /tmp/debuglog.txt inside the Darwin prefix. It is a USER PREFERENCE, seeded
# into the prefix template at
#   <install root>/root/private/var/root/Library/Preferences/com.googlecode.iterm2.plist
# The iTerm2 binary stays byte-identical; only user configuration changes -- the same
# category of input as the probe's own saved preferences.
#
# Grep targets (from source, sources/ file:line in FINDINGS.md F78):
#   brokenPipe / threaded task broken pipe   -> the close chain fired
#   Unable to fork                           -> forkpty failed
#   Fork and exec .* failed                  -> multiserver exec failure
#   Not creating multiserver job manager     -> which job manager ran
#   launchWithPath: / startProgram:          -> how far launch got
#   Remove tab / windowWillClose             -> the F77 window close, from inside
set -uo pipefail

W=$HOME/darling
S=$W/source
A=$W/artifacts/f78-session-launch-debug
rm -rf "$A"; mkdir -p "$A"

# Exact F73/F77 flag configuration; the seeded preference is the only new variable.
export ITERM2_SHARED_CACHE_ROOT=$W/downloads/macos/26.6/dyld-stage18
export ITERM2_PROBE_SHARED_CACHE=1 ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1
export ITERM2_PROBE_FULL_LAUNCHD=1 ITERM2_PROBE_APPKIT_BOOTSTRAP=1 ITERM2_PROBE_APPKIT_REOPEN=1
export ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY=1 ITERM2_PROBE_DIRECT_PTY=1
export ITERM2_PROBE_STABLE_KEYBOARD_SOURCE=1 ITERM2_PROBE_OPAQUE_TEXT=1
export ITERM2_PROBE_DISABLE_METAL=1 ITERM2_PROBE_APPLE_LSD=0 ITERM2_PROBE_APPLE_MDS=0
export ITERM2_PROBE_WAIT_SECONDS=60
export ITERM2_PROBE_ARTIFACTS=$A

"$S/tools/probe-iterm2-launch-arm64.sh" > "$A/probe-driver.log" 2>&1 &
probe_pid=$!

c=darling-arm64-iterm2-launch-probe
up=0
for i in $(seq 1 240); do
	docker ps --format '{{.Names}}' | grep -qx "$c" && { up=1; break; }
	sleep 0.5
done
(( up )) || { echo "FATAL: container never appeared"; wait "$probe_pid"; tail -20 "$A/probe-driver.log"; exit 1; }
echo "container up; attaching debuglog collector"

# Discriminator A: did the seeded plist propagate into the ephemeral prefix?
docker exec -d "$c" bash -c 'for i in $(seq 1 90); do
		if [ -d /tmp/darling-stage18/private/var/root/Library/Preferences ]; then
			ls -la /tmp/darling-stage18/private/var/root/Library/Preferences/ \
				> /artifacts/f78-prefix-prefs.txt 2>&1
			[ -f /tmp/darling-stage18/private/var/root/Library/Preferences/com.googlecode.iterm2.plist ] && break
		fi
		sleep 1
	done'

# The prefix is ephemeral (/tmp/darling-stage18 inside the container) and the probe's
# cleanup() does not preserve private/tmp, so copy debuglog.txt out continuously.
# Discriminator B: also sweep the whole container for the log wherever it lands.
docker exec -d "$c" bash -c 'for i in $(seq 1 400); do
		cp /tmp/darling-stage18/private/tmp/debuglog.txt /artifacts/debuglog.txt 2>/dev/null
		if (( i % 20 == 0 )); then
			find / -xdev -name "debuglog*" -not -path "/proc/*" > /artifacts/f78-debuglog-locations.txt 2>/dev/null
		fi
		sleep 0.5
	done'

wait "$probe_pid"; rc=$?
echo "probe rc=$rc  status=$(cat "$A/status.txt" 2>/dev/null || echo '?')"
echo
if [[ -s $A/debuglog.txt ]]; then
	echo "== debuglog captured: $(wc -l < "$A/debuglog.txt") lines =="
	echo "== launch-failure signatures =="
	grep -nE "brokenPipe|broken pipe|Unable to fork|Fork and exec|multiserver|launchWithPath|startProgram|Remove tab|windowWillClose|ExecFailed|spawn failed" \
		"$A/debuglog.txt" | head -40
else
	echo "NO DEBUGLOG CAPTURED. Discriminators:"
	echo "-- prefix Preferences dir during the run:"
	cat "$A/f78-prefix-prefs.txt" 2>/dev/null || echo "   (never captured: dir never appeared)"
	echo "-- debuglog files anywhere in the container:"
	cat "$A/f78-debuglog-locations.txt" 2>/dev/null || echo "   (sweep never ran)"
fi