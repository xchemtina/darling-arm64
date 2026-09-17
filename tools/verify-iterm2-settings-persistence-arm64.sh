#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
artifact_root=${ITERM2_SETTINGS_PERSISTENCE_ARTIFACTS:-$workspace_root/artifacts/stage22-iterm2-settings-persistence}
bundle=${ITERM2_BUNDLE:-$workspace_root/downloads/iterm2/3.6.11/reference/iTerm.app}
expected_hash=42824bb06b3106f5cdc8a831848a0fd0cd58da8938435035a053bcab5a83d240

case "$artifact_root" in "$workspace_root"/*) ;; *)
	echo "Settings persistence artifacts must remain below the workspace." >&2
	exit 2
esac

actual_hash=$(sha256sum "$bundle/Contents/MacOS/iTerm2" | awk '{print $1}')
[[ $actual_hash == "$expected_hash" ]] || {
	echo "Official iTerm2 executable checksum mismatch." >&2
	exit 1
}
env \
	ITERM2_PROBE_ARTIFACTS="$artifact_root" \
	ITERM2_PROBE_WAIT_SECONDS="${ITERM2_SETTINGS_PERSISTENCE_WAIT_SECONDS:-75}" \
	ITERM2_PROBE_SHARED_CACHE=1 \
	ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1 \
	ITERM2_PROBE_FULL_LAUNCHD=1 \
	ITERM2_PROBE_APPKIT_BOOTSTRAP=1 \
	ITERM2_PROBE_APPKIT_REOPEN=1 \
	ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY=1 \
	ITERM2_PROBE_DIRECT_PTY=1 \
	ITERM2_PROBE_STABLE_KEYBOARD_SOURCE=1 \
	ITERM2_PROBE_OPAQUE_TEXT=1 \
	ITERM2_PROBE_SHALLOW_TOKENIZER=1 \
	ITERM2_PROBE_DISABLE_METAL=1 \
	ITERM2_PROBE_SETTINGS_PERSISTENCE=1 \
	ITERM2_PROBE_TYPE_TEXT='printf ready >/artifacts/settings-persistence-shell-ready.txt' \
	ITERM2_PROBE_QUIT_DIALOG=0 \
	ITERM2_PROBE_QUIT_CONFIRM=0 \
	ITERM2_PROBE_SHUTDOWN_PREFIX=0 \
	ITERM2_PROBE_APPLE_LSD=0 \
	ITERM2_PROBE_APPLE_MDS=0 \
	ITERM2_PROBE_CFPREFSD=1 \
	ITERM2_PROBE_CFPREFSD_DEBUG=0 \
	ITERM2_PROBE_APPLE_CFPREFSD=0 \
	"$source_root/tools/probe-iterm2-launch-arm64.sh" \
	>/tmp/iterm2-settings-persistence.log

value() {
	local key=$1 file=$2
	awk -F= -v key="$key" '$1 == key { print $2; exit }' "$file"
}

for file in \
	settings-persistence-before.png \
	settings-persistence-mutated.png \
	settings-persistence-relaunch.png \
	settings-persistence-before-crop.png \
	settings-persistence-mutated-crop.png \
	settings-persistence-relaunch-crop.png \
	settings-persistence-pixels.txt \
	settings-persistence-first-quit.txt \
	settings-persistence-relaunch-quit.txt \
	settings-persistence-result.txt \
	settings-persistence-after-first-quit-files.txt \
	settings-persistence-after-relaunch-quit-files.txt \
	com.googlecode.iterm2.plist \
	status.txt processes.txt; do
	[[ -s $artifact_root/$file ]] || {
		echo "Missing Settings persistence evidence: $file" >&2
		exit 1
	}
done

python3 - "$artifact_root/com.googlecode.iterm2.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    preferences = plistlib.load(stream)
if "OpenBookmark" not in preferences:
    raise SystemExit("Persisted iTerm2 plist does not contain OpenBookmark")
PY

first_pid=$(value first_pid "$artifact_root/settings-persistence-result.txt")
relaunch_pid=$(value relaunch_pid "$artifact_root/settings-persistence-result.txt")
[[ $first_pid =~ ^[1-9][0-9]*$ && $relaunch_pid =~ ^[1-9][0-9]*$ && \
	$first_pid != "$relaunch_pid" ]] || {
	echo "Settings verifier did not observe two distinct iTerm2 processes." >&2
	exit 1
}
[[ $(value exited "$artifact_root/settings-persistence-first-quit.txt") == 1 ]]
[[ $(value exited "$artifact_root/settings-persistence-relaunch-quit.txt") == 1 ]]

before_mutated=$(value before_mutated_pixels \
	"$artifact_root/settings-persistence-pixels.txt")
mutated_relaunch=$(value mutated_relaunch_pixels \
	"$artifact_root/settings-persistence-pixels.txt")
[[ $before_mutated =~ ^[1-9][0-9]*$ ]] || {
	echo "The real Settings checkbox did not visibly mutate." >&2
	exit 1
}
[[ $mutated_relaunch == 0 ]] || {
	echo "The Settings checkbox did not retain its state after relaunch." >&2
	exit 1
}

[[ $(cat "$artifact_root/status.txt") == running ]]
[[ $(awk '$8 == "/Applications/iTerm.app/Contents/MacOS/iTerm2" { count++ }
	END { print count + 0 }' "$artifact_root/processes.txt") == 0 ]]
if rg -i -q 'uncaught exception|segmentation fault|trace/bpt trap' \
	"$artifact_root/iterm2-job.err" \
	"$artifact_root/settings-persistence-relaunch.err" \
	"$artifact_root/darlingserver.err"; then
	echo "Fatal runtime diagnostic found in Settings persistence logs." >&2
	exit 1
fi

cat >"$artifact_root/verification.txt" <<EOF
first_iterm2_pid=$first_pid
relaunch_iterm2_pid=$relaunch_pid
checkbox_changed_pixels=$before_mutated
checkbox_relaunch_difference_pixels=$mutated_relaunch
first_application_exited=1
relaunch_application_exited=1
iterm2_sha256=$actual_hash
apple_lsd=disabled
apple_mds=disabled
darling_cfprefsd=enabled
persisted_preference_key=OpenBookmark
EOF

echo "iTerm2 Settings persistence passed across processes $first_pid and $relaunch_pid"
