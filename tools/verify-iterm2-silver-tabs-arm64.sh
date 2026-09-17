#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
artifact_root=${ITERM2_SILVER_TABS_ARTIFACTS:-$workspace_root/artifacts/stage19-iterm2-silver-tabs}
bundle=${ITERM2_BUNDLE:-$workspace_root/downloads/iterm2/3.6.11/reference/iTerm.app}
expected_hash=42824bb06b3106f5cdc8a831848a0fd0cd58da8938435035a053bcab5a83d240

case "$artifact_root" in "$workspace_root"/*) ;; *)
	echo "Silver tab artifacts must remain below $workspace_root." >&2
	exit 2
esac

actual_hash=$(sha256sum "$bundle/Contents/MacOS/iTerm2" | awk '{print $1}')
[[ $actual_hash == "$expected_hash" ]] || {
	echo "Official iTerm2 executable checksum mismatch." >&2
	exit 1
}

env \
	ITERM2_PROBE_ARTIFACTS="$artifact_root" \
	ITERM2_PROBE_WAIT_SECONDS=15 \
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
	ITERM2_PROBE_TYPE_TEXT='printf %s $$ >/artifacts/silver-tab1-pid.txt;printf ready >/artifacts/silver-tab1-ready.txt' \
	ITERM2_PROBE_QUIT_DIALOG=0 \
	ITERM2_PROBE_QUIT_CONFIRM=0 \
	ITERM2_PROBE_SHUTDOWN_PREFIX=0 \
	ITERM2_PROBE_APPLE_LSD=0 \
	ITERM2_PROBE_APPLE_MDS=0 \
	"$source_root/tools/probe-iterm2-launch-arm64.sh" >/tmp/iterm2-silver-tabs.log

value() {
	local key=$1 file=$2
	awk -F= -v key="$key" '$1 == key { print $2; exit }' "$file"
}

for file in silver-tab1-pid.txt silver-tab2-pid.txt \
	silver-tab1-return-pid.txt silver-tab2-return-pid.txt \
	silver-tab1-kernel-pid.txt \
	silver-tab2-kernel-pid.txt \
	silver-tabs.txt silver-tabs.png \
	status.txt processes.txt; do
	[[ -s $artifact_root/$file ]] || {
		echo "Missing Silver tab evidence: $file" >&2
		exit 1
	}
done

tab1_pid=$(cat "$artifact_root/silver-tab1-pid.txt")
tab2_pid=$(cat "$artifact_root/silver-tab2-pid.txt")
tab1_return_pid=$(cat "$artifact_root/silver-tab1-return-pid.txt")
tab2_return_pid=$(cat "$artifact_root/silver-tab2-return-pid.txt")
tab1_kernel_pid=$(cat "$artifact_root/silver-tab1-kernel-pid.txt")
tab2_kernel_pid=$(cat "$artifact_root/silver-tab2-kernel-pid.txt")
[[ $tab1_pid =~ ^[1-9][0-9]*$ && $tab2_pid =~ ^[1-9][0-9]*$ ]] || {
	echo "Tab shell identifiers are not positive integers." >&2
	exit 1
}
[[ $tab1_pid != "$tab2_pid" ]] || {
	echo "Command-T reused the original tab shell." >&2
	exit 1
}
[[ $tab1_return_pid == "$tab1_pid" ]] || {
	echo "Command-1 did not return to the original tab shell." >&2
	exit 1
}
[[ $tab2_return_pid == "$tab2_pid" ]] || {
	echo "Command-2 did not return to the second tab shell." >&2
	exit 1
}

[[ $tab1_kernel_pid =~ ^[1-9][0-9]*$ && $tab2_kernel_pid =~ ^[1-9][0-9]*$ && \
	$tab1_kernel_pid != "$tab2_kernel_pid" ]] || {
	echo "Tab kernel process identifiers are invalid or reused." >&2
	exit 1
}
[[ $(value shells "$artifact_root/silver-tabs.txt") == 2 ]] || {
	echo "Expected exactly two live tab shells." >&2
	exit 1
}
[[ $(cat "$artifact_root/status.txt") == running ]]
[[ $(awk '$8 == "/Applications/iTerm.app/Contents/MacOS/iTerm2" { count++ }
	END { print count + 0 }' "$artifact_root/processes.txt") == 1 ]]
if rg -i -q 'uncaught exception|segmentation fault|trace/bpt trap' \
	"$artifact_root/iterm2-job.err" "$artifact_root/darlingserver.err"; then
	echo "Fatal runtime diagnostic found in Silver tab logs." >&2
	exit 1
fi

cat >"$artifact_root/verification.txt" <<EOF
tab1_shell_pid=$tab1_pid
tab2_shell_pid=$tab2_pid
tab1_return_shell_pid=$tab1_return_pid
tab2_return_shell_pid=$tab2_return_pid
tab1_kernel_pid=$tab1_kernel_pid
tab2_kernel_pid=$tab2_kernel_pid
live_shells=2
iterm2_sha256=$actual_hash
apple_lsd=disabled
apple_mds=disabled
EOF

echo "iTerm2 Silver tabs passed: independent shells $tab1_pid and $tab2_pid"
