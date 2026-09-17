#!/usr/bin/env bash
set -euo pipefail

tools_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
runner="$tools_dir/run-staged-darling-arm64.sh"

run_case() {
	local label=$1
	local program=$2
	local expected_status=$3
	local expected_marker=$4
	local container=$5
	local thread_bridge=${6:-0}
	local loopback_server=${7:-0}
	local output
	local status

	echo "== $label =="
	set +e
	output=$(DARLING_ARM64_CONTAINER="$container" DARLING_ARM64_THREAD_BRIDGE="$thread_bridge" \
		DARLING_ARM64_LOOPBACK_SERVER="$loopback_server" "$runner" "$program" 2>&1)
	status=$?
	set -e
	printf '%s\n' "$output"
	if (( status != expected_status )); then
		echo "Expected status $expected_status, observed $status." >&2
		exit 1
	fi
	if [[ $output != *"$expected_marker"* ]]; then
		echo "Missing expected output marker: $expected_marker" >&2
		exit 1
	fi
	printf 'observed_exit_status=%d\n' "$status"
}

run_case \
	"staged libSystem write + return 0" \
	/hello-libsystem-arm64-0 \
	0 \
	"hello from native Darling arm64" \
	darling-arm64-staged-0
run_case \
	"staged libSystem write + return 42" \
	/hello-libsystem-arm64-42 \
	42 \
	"hello from native Darling arm64" \
	darling-arm64-staged-42
run_case \
	"staged core POSIX APIs" \
	/posix-darling-arm64 \
	0 \
	"Darling ARM64 POSIX smoke passed" \
	darling-arm64-staged-posix
run_case \
	"staged process environment" \
	/process-darling-arm64 \
	0 \
	"Darling ARM64 process smoke passed" \
	darling-arm64-staged-process
run_case \
	"staged pthread environment" \
	/pthread-darling-arm64 \
	0 \
	"Darling ARM64 pthread smoke passed" \
	darling-arm64-staged-pthread \
	1
run_case \
	"staged dispatch queues and sources" \
	/dispatch-darling-arm64 \
	0 \
	"Darling ARM64 dispatch smoke passed" \
	darling-arm64-staged-dispatch \
	1
run_case \
	"staged CFRunLoop dispatch integration" \
	/cfrunloop-dispatch-arm64 \
	0 \
	"Darling ARM64 CFRunLoop dispatch integration passed" \
	darling-arm64-staged-cfrunloop-dispatch \
	1
run_case \
	"staged real Darwin userland" \
	/userland-darling-arm64 \
	0 \
	"Darling ARM64 userland smoke passed" \
	darling-arm64-staged-userland
run_case \
	"staged Objective-C runtime" \
	/objc-darling-arm64 \
	0 \
	"Darling ARM64 Objective-C smoke passed" \
	darling-arm64-staged-objc \
	1

install_root=${DARLING_ARM64_INSTALL_ROOT:-$(cd "$tools_dir/../.." && pwd)/install-arm64}
if [[ -x $install_root/root/foundation-darling-arm64 ]]; then
	run_case \
		"staged Foundation APIs and invocation forwarding" \
		/foundation-darling-arm64 \
		0 \
		"Darling ARM64 Foundation smoke passed" \
		darling-arm64-staged-foundation \
		1
	run_case \
		"staged Foundation NSTask, pipe, and termination handler" \
		/foundation-task-darling-arm64 \
		0 \
		"Darling ARM64 Foundation task smoke passed" \
		darling-arm64-staged-foundation-task \
		1
fi

if [[ -x $install_root/root/runloop-network-darling-arm64 ]]; then
	run_case \
		"staged run-loop, DNS, socket, HTTP, timer, and notification" \
		/runloop-network-darling-arm64 \
		0 \
		"Darling ARM64 run-loop network smoke passed" \
		darling-arm64-staged-runloop-network \
		1 \
		1
fi

if [[ -x $install_root/root/usr/bin/defaults ]]; then
	"$tools_dir/verify-service-tools-darling-arm64.sh"
fi
