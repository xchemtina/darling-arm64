#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
build_root=${DARLING_ARM64_BUILD_ROOT:-$workspace_root/build-arm64}
image=${DARLING_ARM64_IMAGE:-darling-arm64-dev:latest}
container=${DARLING_ARM64_CONTAINER:-darling-arm64-smoke}
expected_status=${DARLING_ARM64_EXPECTED_STATUS:-0}
test_source=${DARLING_ARM64_TEST_SOURCE:-tools/hello-darling-arm64.c}
test_binary=${DARLING_ARM64_TEST_BINARY:-hello-libsystem-arm64}
expected_marker=${DARLING_ARM64_EXPECTED_MARKER:-hello from native Darling arm64}
link_dispatch=${DARLING_ARM64_LINK_DISPATCH:-0}
link_corefoundation=${DARLING_ARM64_LINK_COREFOUNDATION:-0}

if [[ ! $expected_status =~ ^[0-9]+$ ]] || (( expected_status > 255 )); then
	echo "DARLING_ARM64_EXPECTED_STATUS must be an integer from 0 through 255." >&2
	exit 2
fi
if [[ ! $test_source =~ ^tools/[A-Za-z0-9._/-]+$ ]] || [[ $test_source == *..* ]]; then
	echo "DARLING_ARM64_TEST_SOURCE must be a path below tools/." >&2
	exit 2
fi
if [[ ! $test_binary =~ ^[A-Za-z0-9._-]+$ ]]; then
	echo "DARLING_ARM64_TEST_BINARY must be a filename." >&2
	exit 2
fi
if [[ $link_dispatch != 0 && $link_dispatch != 1 ]]; then
	echo "DARLING_ARM64_LINK_DISPATCH must be 0 or 1." >&2
	exit 2
fi
if [[ $link_corefoundation != 0 && $link_corefoundation != 1 ]]; then
	echo "DARLING_ARM64_LINK_COREFOUNDATION must be 0 or 1." >&2
	exit 2
fi

if [[ $(uname -m) != aarch64 ]]; then
	echo "This smoke test requires a native aarch64 Linux host." >&2
	exit 2
fi

docker run --rm \
	-e DARLING_ARM64_LINK_DISPATCH="$link_dispatch" \
	-e DARLING_ARM64_LINK_COREFOUNDATION="$link_corefoundation" \
	-v "$source_root:/work/source:ro" \
	-v "$build_root:/work/build-arm64" \
	"$image" bash -lc '
		libraries=(/work/build-arm64/src/external/libsystem/libSystem.B.dylib)
		if [[ $DARLING_ARM64_LINK_DISPATCH == 1 ]]; then
			libraries+=(/work/build-arm64/src/external/libdispatch/libdispatch.dylib)
		fi
		if [[ $DARLING_ARM64_LINK_COREFOUNDATION == 1 ]]; then
			libraries+=(/work/build-arm64/src/external/corefoundation/CoreFoundation)
		fi
		/usr/bin/clang \
			-target arm64-apple-darwin20 \
			-mmacosx-version-min=11.0 \
			-fuse-ld=/work/build-arm64/src/external/cctools-port/cctools/ld64/src/arm64-apple-darwin20-ld \
			-B /work/build-arm64/src/external/cctools-port/cctools/ld64/src/ \
			-B /work/build-arm64/src/external/cctools-port/cctools/misc/ \
			-Wl,-sdk_version,11.0 \
			-Wl,-syslibroot,/work/build-arm64/stage-link \
			-DDARLING_SMOKE_EXIT_CODE='"$expected_status"' \
			-nostdlib \
			/work/source/'"$test_source"' \
			"${libraries[@]}" \
			-o /work/build-arm64/'"$test_binary"'
	'

docker rm -f "$container" >/dev/null 2>&1 || true
set +e
output=$(docker run --name "$container" --rm \
	-e DARLING_ARM64_THREAD_BRIDGE \
	-e DARLING_ARM64_LINK_COREFOUNDATION="$link_corefoundation" \
	--cap-add SYS_ADMIN \
	--cap-add SYS_PTRACE \
	--security-opt apparmor=unconfined \
	--security-opt seccomp=unconfined \
	-v "$source_root:/work/source:ro" \
	-v "$build_root:/work/build-arm64:ro" \
	"$image" bash -lc '
		set -e
		root=/usr/local/libexec/darling
		prefix=/tmp/darling-prefix
		mkdir -p \
			"$root/usr/lib/system" \
			"$root/usr/libexec/darling" \
			"$root/proc" \
			"$root/private/var/tmp" \
			"$root/private/var/run" \
			"$prefix/dev/pts"
		cp -aL /work/build-arm64/stage-link/usr/lib/. "$root/usr/lib/"
		ln -sf /work/build-arm64/src/external/dyld/dyld "$root/usr/lib/dyld"
		ln -sf /work/build-arm64/src/startup/mldr/mldr "$root/usr/libexec/darling/mldr"
		ln -sf /work/build-arm64/src/vchroot/vchroot "$root/usr/libexec/darling/vchroot"
		cp /work/build-arm64/'"$test_binary"' "$root/'"$test_binary"'"
		cp /work/build-arm64/src/external/objc4/runtime/libobjc.A.dylib "$root/usr/lib/libobjc.A.dylib"
		cp /work/build-arm64/src/external/libcxx/libc++.1.dylib "$root/usr/lib/libc++.1.dylib"
		cp /work/build-arm64/src/external/libcxxabi/libc++abi.dylib "$root/usr/lib/libc++abi.dylib"
		cp /work/build-arm64/src/external/libresolv/libresolv.9.dylib "$root/usr/lib/libresolv.9.dylib"
		if [[ $DARLING_ARM64_LINK_COREFOUNDATION == 1 ]]; then
			mkdir -p "$root/System/Library/Frameworks/CoreFoundation.framework/Versions/A"
			cp /work/build-arm64/src/external/corefoundation/CoreFoundation \
				"$root/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation"
			cp /work/build-arm64/src/external/icu/icuSources/libicucore.A.dylib \
				"$root/usr/lib/libicucore.A.dylib"
		fi
		cp -a /dev/null /dev/urandom "$prefix/dev/"
		mount --bind /dev/pts "$prefix/dev/pts"
		ln -s pts/ptmx "$prefix/dev/ptmx"
		export DARLING_NOOVERLAYFS=1
		export DYLD_USE_CLOSURES=0
		export DSERVER_INIT=/'"$test_binary"'
		exec timeout 15s /work/build-arm64/src/external/darlingserver/darlingserver "$prefix" 0 0 1 0
	' 2>&1)
status=$?
set -e

printf '%s\n' "$output"
if [[ $output == *"$expected_marker"* ]] && (( status == expected_status )); then
	printf 'observed_exit_status=%d\n' "$status"
	exit 0
fi
printf 'expected_exit_status=%d observed_exit_status=%d\n' "$expected_status" "$status" >&2
exit "$status"
