#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
artifact_root=${ITERM2_SILVER_TAB_CLOSE_ARTIFACTS:-$workspace_root/artifacts/stage19-iterm2-silver-tab-close}
bundle=${ITERM2_BUNDLE:-$workspace_root/downloads/iterm2/3.6.11/reference/iTerm.app}
expected_hash=42824bb06b3106f5cdc8a831848a0fd0cd58da8938435035a053bcab5a83d240

case "$artifact_root" in "$workspace_root"/*) ;; *)
	echo "Silver tab-close artifacts must remain below $workspace_root." >&2
	exit 2
esac

actual_hash=$(sha256sum "$bundle/Contents/MacOS/iTerm2" | awk '{print $1}')
[[ $actual_hash == "$expected_hash" ]] || {
	echo "Official iTerm2 executable checksum mismatch." >&2
	exit 1
}

env \
	ITERM2_PROBE_ARTIFACTS="$artifact_root" \
	ITERM2_PROBE_WAIT_SECONDS=30 \
	ITERM2_PROBE_SHARED_CACHE=1 \
	ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1 \
	ITERM2_PROBE_FULL_LAUNCHD=1 \
	ITERM2_PROBE_APPKIT_BOOTSTRAP=1 \
	ITERM2_PROBE_APPKIT_REOPEN=1 \
	ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY=1 \
	ITERM2_PROBE_DIRECT_PTY=1 \
	ITERM2_PROBE_STABLE_KEYBOARD_SOURCE=1 \
	ITERM2_PROBE_OPAQUE_TEXT=1 \
	ITERM2_PROBE_DISABLE_METAL=1 \
	ITERM2_PROBE_TAB_WORKFLOW=1 \
	ITERM2_PROBE_TAB_CLOSE_WORKFLOW=1 \
	ITERM2_PROBE_TYPE_TEXT='printf %s $$ >/artifacts/silver-tab1-pid.txt;printf ready >/artifacts/silver-tab1-ready.txt' \
	ITERM2_PROBE_QUIT_DIALOG=0 \
	ITERM2_PROBE_APPLE_LSD=0 \
	ITERM2_PROBE_APPLE_MDS=0 \
	"$source_root/tools/probe-iterm2-launch-arm64.sh" >/tmp/iterm2-silver-tab-close.log

value() {
	local key=$1 file=$2
	awk -F= -v key="$key" '$1 == key { print $2; exit }' "$file"
}

for file in silver-tab1-pid.txt silver-tab2-pid.txt \
	silver-tab1-return-pid.txt silver-tab2-return-pid.txt \
	silver-tab-close-survivor-pid.txt \
	silver-tab-close-survivor-ready.txt silver-tabs.txt \
	silver-tab-close.txt silver-tab-close.png \
	silver-tab-close-windows.txt status.txt processes.txt; do
	[[ -s $artifact_root/$file ]] || {
		echo "Missing Silver tab-close evidence: $file" >&2
		exit 1
	}
done

tab1_pid=$(cat "$artifact_root/silver-tab1-pid.txt")
tab2_pid=$(cat "$artifact_root/silver-tab2-pid.txt")
tab1_return_pid=$(cat "$artifact_root/silver-tab1-return-pid.txt")
tab2_return_pid=$(cat "$artifact_root/silver-tab2-return-pid.txt")
survivor_pid=$(cat "$artifact_root/silver-tab-close-survivor-pid.txt")

[[ $tab1_pid =~ ^[1-9][0-9]*$ && $tab2_pid =~ ^[1-9][0-9]*$ && \
	$tab1_pid != "$tab2_pid" ]] || {
	echo "Initial tab shell identifiers are invalid or reused." >&2
	exit 1
}
[[ $tab1_return_pid == "$tab1_pid" ]] || {
	echo "Command-1 did not select the first tab before close." >&2
	exit 1
}
[[ $tab2_return_pid == "$tab2_pid" ]] || {
	echo "Command-2 did not select the second tab before returning to close the first." >&2
	exit 1
}
[[ $survivor_pid == "$tab2_pid" ]] || {
	echo "The second tab did not survive the first tab's shell exit." >&2
	exit 1
}
[[ $(value shells "$artifact_root/silver-tabs.txt") == 2 ]]
[[ $(value app_alive "$artifact_root/silver-tab-close.txt") == 1 ]]
[[ $(value shells "$artifact_root/silver-tab-close.txt") == 1 ]]
[[ $(value survivor_ready "$artifact_root/silver-tab-close.txt") == 1 ]]
[[ $(cat "$artifact_root/silver-tab-close-survivor-ready.txt") == ready ]]
[[ $(cat "$artifact_root/status.txt") == running ]]
[[ $(awk '$8 == "/Applications/iTerm.app/Contents/MacOS/iTerm2" { count++ }
	END { print count + 0 }' "$artifact_root/processes.txt") == 1 ]]
rg -q '"iTerm2"' "$artifact_root/silver-tab-close-windows.txt"

if rg -i -q 'unhandled ARM64 SIGSEGV|uncaught exception|segmentation fault|trace/bpt trap' \
	"$artifact_root/iterm2-job.out" "$artifact_root/iterm2-job.err" \
	"$artifact_root/darlingserver.err"; then
	echo "Fatal runtime diagnostic found in Silver tab-close logs." >&2
	exit 1
fi

cat >"$artifact_root/verification.txt" <<EOF
tab1_shell_pid=$tab1_pid
tab2_shell_pid=$tab2_pid
tab1_return_shell_pid=$tab1_return_pid
tab2_return_shell_pid=$tab2_return_pid
surviving_shell_pid=$survivor_pid
live_shells=1
iterm2_alive=1
iterm2_sha256=$actual_hash
apple_lsd=disabled
apple_mds=disabled
EOF

echo "iTerm2 Silver tab close passed: shell $tab1_pid closed; shell $tab2_pid survived"
