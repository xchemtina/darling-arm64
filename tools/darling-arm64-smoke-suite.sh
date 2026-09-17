#!/usr/bin/env bash
set -euo pipefail

tools_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
smoke="$tools_dir/darling-arm64-smoke.sh"

echo "== libSystem write + return 0 =="
"$smoke"

echo "== libSystem write + return 42 =="
DARLING_ARM64_EXPECTED_STATUS=42 \
	DARLING_ARM64_CONTAINER=darling-arm64-smoke-42 \
	"$smoke"

echo "== core POSIX APIs =="
DARLING_ARM64_TEST_SOURCE=tools/posix-darling-arm64.c \
	DARLING_ARM64_TEST_BINARY=posix-darling-arm64 \
	DARLING_ARM64_EXPECTED_MARKER="Darling ARM64 POSIX smoke passed" \
	DARLING_ARM64_CONTAINER=darling-arm64-posix \
	"$smoke"

echo "== process environment =="
DARLING_ARM64_TEST_SOURCE=tools/process-darling-arm64.c \
	DARLING_ARM64_TEST_BINARY=process-darling-arm64 \
	DARLING_ARM64_EXPECTED_MARKER="Darling ARM64 process smoke passed" \
	DARLING_ARM64_CONTAINER=darling-arm64-process \
	"$smoke"

echo "== pthread environment =="
DARLING_ARM64_TEST_SOURCE=tools/pthread-darling-arm64.c \
	DARLING_ARM64_TEST_BINARY=pthread-darling-arm64 \
	DARLING_ARM64_EXPECTED_MARKER="Darling ARM64 pthread smoke passed" \
	DARLING_ARM64_CONTAINER=darling-arm64-pthread \
	DARLING_ARM64_THREAD_BRIDGE=1 \
	"$smoke"

echo "== dispatch queues and sources =="
DARLING_ARM64_TEST_SOURCE=tools/dispatch-darling-arm64.c \
	DARLING_ARM64_TEST_BINARY=dispatch-darling-arm64 \
	DARLING_ARM64_EXPECTED_MARKER="Darling ARM64 dispatch smoke passed" \
	DARLING_ARM64_CONTAINER=darling-arm64-dispatch \
	DARLING_ARM64_THREAD_BRIDGE=1 \
	DARLING_ARM64_LINK_DISPATCH=1 \
	"$smoke"

echo "== CFRunLoop dispatch integration =="
DARLING_ARM64_TEST_SOURCE=tools/cfrunloop-dispatch-darling-arm64.c \
	DARLING_ARM64_TEST_BINARY=cfrunloop-dispatch-arm64 \
	DARLING_ARM64_EXPECTED_MARKER="Darling ARM64 CFRunLoop dispatch integration passed" \
	DARLING_ARM64_CONTAINER=darling-arm64-cfrunloop-dispatch \
	DARLING_ARM64_THREAD_BRIDGE=1 \
	DARLING_ARM64_LINK_DISPATCH=1 \
	DARLING_ARM64_LINK_COREFOUNDATION=1 \
	"$smoke"
