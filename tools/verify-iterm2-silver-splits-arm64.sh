#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
artifact_root=${ITERM2_SILVER_SPLITS_ARTIFACTS:-$workspace_root/artifacts/stage19-iterm2-silver-splits}
bundle=${ITERM2_BUNDLE:-$workspace_root/downloads/iterm2/3.6.11/reference/iTerm.app}
expected_hash=42824bb06b3106f5cdc8a831848a0fd0cd58da8938435035a053bcab5a83d240

case "$artifact_root" in "$workspace_root"/*) ;; *)
	echo "Silver split artifacts must remain below $workspace_root." >&2
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
	ITERM2_PROBE_SPLIT_WORKFLOW=1 \
	ITERM2_PROBE_TYPE_TEXT='printf %s $$ >/artifacts/silver-pane1-pid.txt;printf ready >/artifacts/silver-pane1-ready.txt' \
	ITERM2_PROBE_QUIT_DIALOG=0 \
	ITERM2_PROBE_APPLE_LSD=0 \
	ITERM2_PROBE_APPLE_MDS=0 \
	"$source_root/tools/probe-iterm2-launch-arm64.sh" >/tmp/iterm2-silver-splits.log

value() {
	local key=$1 file=$2
	awk -F= -v key="$key" '$1 == key { print $2; exit }' "$file"
}

for file in silver-pane1-pid.txt silver-pane2-pid.txt \
	silver-pane1-return-pid.txt silver-pane2-return-pid.txt \
	silver-pane1-kernel-pid.txt silver-pane2-kernel-pid.txt \
	silver-split-survivor-pid.txt silver-split-survivor-ready.txt \
	silver-splits.txt silver-splits.png silver-split-close.txt \
	silver-split-close.png silver-split-close-windows.txt \
	status.txt processes.txt; do
	[[ -s $artifact_root/$file ]] || {
		echo "Missing Silver split evidence: $file" >&2
		exit 1
	}
done

pane1_pid=$(cat "$artifact_root/silver-pane1-pid.txt")
pane2_pid=$(cat "$artifact_root/silver-pane2-pid.txt")
pane1_return_pid=$(cat "$artifact_root/silver-pane1-return-pid.txt")
pane2_return_pid=$(cat "$artifact_root/silver-pane2-return-pid.txt")
pane1_kernel_pid=$(cat "$artifact_root/silver-pane1-kernel-pid.txt")
pane2_kernel_pid=$(cat "$artifact_root/silver-pane2-kernel-pid.txt")
survivor_pid=$(cat "$artifact_root/silver-split-survivor-pid.txt")

[[ $pane1_pid =~ ^[1-9][0-9]*$ && $pane2_pid =~ ^[1-9][0-9]*$ && \
	$pane1_pid != "$pane2_pid" ]] || {
	echo "Split pane shell identifiers are invalid or reused." >&2
	exit 1
}
[[ $pane1_return_pid == "$pane1_pid" && $pane2_return_pid == "$pane2_pid" ]] || {
	echo "Command-[ or Command-] did not select the expected split pane." >&2
	exit 1
}
[[ $pane1_kernel_pid =~ ^[1-9][0-9]*$ && $pane2_kernel_pid =~ ^[1-9][0-9]*$ && \
	$pane1_kernel_pid != "$pane2_kernel_pid" ]] || {
	echo "Split pane kernel process identifiers are invalid or reused." >&2
	exit 1
}
[[ $survivor_pid == "$pane2_pid" ]] || {
	echo "The second pane did not survive the first pane's shell exit." >&2
	exit 1
}
[[ $(value shells "$artifact_root/silver-splits.txt") == 2 ]]
[[ $(value app_alive "$artifact_root/silver-split-close.txt") == 1 ]]
[[ $(value shells "$artifact_root/silver-split-close.txt") == 1 ]]
[[ $(value survivor_ready "$artifact_root/silver-split-close.txt") == 1 ]]
[[ $(cat "$artifact_root/silver-split-survivor-ready.txt") == ready ]]
[[ $(cat "$artifact_root/status.txt") == running ]]
[[ $(awk '$8 == "/Applications/iTerm.app/Contents/MacOS/iTerm2" { count++ }
	END { print count + 0 }' "$artifact_root/processes.txt") == 1 ]]
rg -q '"iTerm2"' "$artifact_root/silver-split-close-windows.txt"

if rg -i -q 'unhandled ARM64 SIGSEGV|uncaught exception|segmentation fault|trace/bpt trap' \
	"$artifact_root/iterm2-job.out" "$artifact_root/iterm2-job.err" \
	"$artifact_root/darlingserver.err"; then
	echo "Fatal runtime diagnostic found in Silver split logs." >&2
	exit 1
fi

cat >"$artifact_root/verification.txt" <<EOF
pane1_shell_pid=$pane1_pid
pane2_shell_pid=$pane2_pid
pane1_return_shell_pid=$pane1_return_pid
pane2_return_shell_pid=$pane2_return_pid
pane1_kernel_pid=$pane1_kernel_pid
pane2_kernel_pid=$pane2_kernel_pid
surviving_shell_pid=$survivor_pid
live_shells=1
iterm2_alive=1
iterm2_sha256=$actual_hash
apple_lsd=disabled
apple_mds=disabled
EOF

echo "iTerm2 Silver splits passed: pane $pane1_pid closed; pane $pane2_pid survived"
