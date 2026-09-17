#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
build_root=${DARLING_ARM64_BUILD_ROOT:-$workspace_root/build-arm64}
install_root=${DARLING_ARM64_INSTALL_ROOT:-$workspace_root/install-arm64}
image=${DARLING_ARM64_IMAGE:-darling-arm64-dev:latest}

case "$install_root" in
	"$workspace_root"/*) ;;
	*)
		echo "Install root must remain below $workspace_root." >&2
		exit 2
		;;
esac

tmp_root="$install_root.tmp.$$"
old_root="$install_root.previous.$$"
cleanup() {
	rm -rf -- "$tmp_root" "$old_root"
}
trap cleanup EXIT
mkdir -p "$tmp_root"

docker run --rm \
	-e HOST_UID="$(id -u)" \
	-e HOST_GID="$(id -g)" \
	-v "$source_root:/work/source:ro" \
	-v "$build_root:/work/build-arm64" \
	-v "$tmp_root:/work/install" \
	"$image" bash -lc '
		set -e
		ninja -C /work/build-arm64 ash cat env vim libdispatch_shared notifyd
		stage8=0
		stage9=0
		stage10=0
		if ninja -C /work/build-arm64 -t targets all | grep -q "src/external/foundation/Foundation:"; then
			stage8=1
			ninja -C /work/build-arm64 src/external/foundation/Foundation
		fi
		if grep -q "^DARLING_ARM64_NORTH_STAR_STAGE9:BOOL=ON$" /work/build-arm64/CMakeCache.txt; then
			stage9=1
			ninja -C /work/build-arm64 libsystem_info.dylib
		fi
		if grep -q "^DARLING_ARM64_NORTH_STAR_STAGE10:BOOL=ON$" /work/build-arm64/CMakeCache.txt; then
			stage10=1
			ninja -C /work/build-arm64 defaults plutil
		fi
		cc=/usr/bin/clang
		ld=/work/build-arm64/src/external/cctools-port/cctools/ld64/src/arm64-apple-darwin20-ld
		common="-target arm64-apple-darwin20 -mmacosx-version-min=11.0 -fuse-ld=$ld -B /work/build-arm64/src/external/cctools-port/cctools/ld64/src/ -B /work/build-arm64/src/external/cctools-port/cctools/misc/ -Wl,-sdk_version,11.0 -Wl,-syslibroot,/work/build-arm64/stage-link -nostdlib"
		libsystem=/work/build-arm64/src/external/libsystem/libSystem.B.dylib
		$cc $common -DDARLING_SMOKE_EXIT_CODE=0 /work/source/tools/hello-darling-arm64.c "$libsystem" -o /work/build-arm64/hello-libsystem-arm64-0
		$cc $common -DDARLING_SMOKE_EXIT_CODE=42 /work/source/tools/hello-darling-arm64.c "$libsystem" -o /work/build-arm64/hello-libsystem-arm64-42
		$cc $common /work/source/tools/posix-darling-arm64.c "$libsystem" -o /work/build-arm64/posix-darling-arm64
		$cc $common /work/source/tools/process-darling-arm64.c "$libsystem" -o /work/build-arm64/process-darling-arm64
		$cc $common /work/source/tools/pthread-darling-arm64.c "$libsystem" -o /work/build-arm64/pthread-darling-arm64
		$cc $common /work/source/tools/userland-darling-arm64.c "$libsystem" -o /work/build-arm64/userland-darling-arm64
		$cc $common -D__DARWIN_UNIX03=0 \
			-isysroot /work/source/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
			/work/source/tools/pty-harness-darling-arm64.c "$libsystem" \
			-o /work/build-arm64/pty-harness-darling-arm64
		$cc $common -isysroot /work/source/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
			-DPLATFORM_MacOSX -fobjc-exceptions -fblocks \
			/work/source/tools/objc-darling-arm64.m \
			/work/build-arm64/src/external/objc4/runtime/libobjc.A.dylib \
			/work/build-arm64/src/external/libdispatch/libdispatch.dylib \
			"$libsystem" -o /work/build-arm64/objc-darling-arm64
		if [[ $stage8 == 1 ]]; then
			foundation_libs="/work/build-arm64/src/external/foundation/Foundation \
				/work/build-arm64/src/external/corefoundation/CoreFoundation \
				/work/build-arm64/src/external/objc4/runtime/libobjc.A.dylib \
				/work/build-arm64/src/external/libdispatch/libdispatch.dylib $libsystem"
			for name in foundation foundation-task; do
				$cc $common -w \
					-isysroot /work/source/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
					-I/work/source/src/external/foundation/include \
					-DPLATFORM_MacOSX -fobjc-exceptions -fblocks \
					/work/source/tools/$name-darling-arm64.m $foundation_libs \
					-o /work/build-arm64/$name-darling-arm64
			done
		fi
		if [[ $stage9 == 1 ]]; then
			/usr/bin/clang /work/source/tools/network-loopback-server-arm64.c \
				-o /work/build-arm64/network-loopback-server-arm64
			$cc $common -w -D__DARWIN_ONLY_UNIX_CONFORMANCE=1 \
				-isysroot /work/source/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
				/work/source/tools/runloop-network-darling-arm64.c \
				/work/build-arm64/src/external/corefoundation/CoreFoundation \
				"$libsystem" -o /work/build-arm64/runloop-network-darling-arm64
		fi
		if [[ $stage10 == 1 ]]; then
			$cc $common /work/source/tools/exec-arguments-darling-arm64.c \
				"$libsystem" -o /work/build-arm64/exec-arguments-darling-arm64
		fi
		$cc $common /work/source/tools/dispatch-darling-arm64.c "$libsystem" \
			/work/build-arm64/src/external/libdispatch/libdispatch.dylib \
			-o /work/build-arm64/dispatch-darling-arm64
		$cc $common /work/source/tools/cfrunloop-dispatch-darling-arm64.c "$libsystem" \
			/work/build-arm64/src/external/libdispatch/libdispatch.dylib \
			/work/build-arm64/src/external/corefoundation/CoreFoundation \
			-o /work/build-arm64/cfrunloop-dispatch-arm64

		mkdir -p \
			/work/install/bin \
			/work/install/root/bin \
			/work/install/root/System/Library/Frameworks/CoreFoundation.framework/Versions/A \
			/work/install/root/System/Library/Frameworks/Foundation.framework/Versions/C \
			/work/install/root/etc \
			/work/install/root/usr/bin \
			/work/install/root/usr/sbin \
			/work/install/root/usr/lib/system \
			/work/install/root/usr/libexec/darling \
			/work/install/root/System/Library/LaunchDaemons \
			/work/install/root/private/var/tmp \
			/work/install/root/private/var/run \
			/work/install/root/root/Library/Preferences \
			/work/install/root/proc
		cp /work/build-arm64/src/external/darlingserver/darlingserver /work/install/bin/darlingserver
		cp /work/source/tools/xdg-user-dir-stub.sh /work/install/bin/xdg-user-dir
		chmod +x /work/install/bin/xdg-user-dir
		cp -aL /work/build-arm64/stage-link/usr/lib/. /work/install/root/usr/lib/
		cp /work/build-arm64/src/external/dyld/dyld /work/install/root/usr/lib/dyld
		cp /work/build-arm64/src/startup/mldr/mldr /work/install/root/usr/libexec/darling/mldr
		cp /work/build-arm64/src/vchroot/vchroot /work/install/root/usr/libexec/darling/vchroot
		cp /work/build-arm64/src/external/objc4/runtime/libobjc.A.dylib /work/install/root/usr/lib/libobjc.A.dylib
		cp /work/build-arm64/src/external/libcxx/libc++.1.dylib /work/install/root/usr/lib/libc++.1.dylib
		cp /work/build-arm64/src/external/libcxxabi/libc++abi.dylib /work/install/root/usr/lib/libc++abi.dylib
		cp /work/build-arm64/src/external/libresolv/libresolv.9.dylib /work/install/root/usr/lib/libresolv.9.dylib
		cp /work/build-arm64/src/external/libedit/libedit.3.dylib /work/install/root/usr/lib/libedit.3.dylib
		cp /work/build-arm64/src/external/ncurses/ncurses/ncurses/libncurses.5.4.dylib /work/install/root/usr/lib/libncurses.5.4.dylib
		cp /work/build-arm64/src/external/libiconv/libiconv.2.dylib /work/install/root/usr/lib/libiconv.2.dylib
		cp /work/build-arm64/src/external/libiconv/libcharset.1.dylib /work/install/root/usr/lib/libcharset.1.dylib
		cp /work/build-arm64/src/external/icu/icuSources/libicucore.A.dylib /work/install/root/usr/lib/libicucore.A.dylib
		cp /work/build-arm64/src/external/corefoundation/CoreFoundation \
			/work/install/root/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation
		if [[ $stage8 == 1 ]]; then
			cp /work/build-arm64/src/external/foundation/Foundation \
				/work/install/root/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
			cp /work/build-arm64/src/external/libxml2/libxml2.2.dylib /work/install/root/usr/lib/libxml2.2.dylib
			cp /work/build-arm64/src/external/zlib/libz.1.dylib /work/install/root/usr/lib/libz.1.dylib
			cp /work/build-arm64/foundation-darling-arm64 /work/install/root/foundation-darling-arm64
			cp /work/build-arm64/foundation-task-darling-arm64 /work/install/root/foundation-task-darling-arm64
		fi
		if [[ $stage9 == 1 ]]; then
			cp /work/build-arm64/network-loopback-server-arm64 /work/install/bin/network-loopback-server-arm64
			cp /work/build-arm64/runloop-network-darling-arm64 /work/install/root/runloop-network-darling-arm64
			cp /work/source/tools/hosts-darling-arm64 /work/install/root/etc/hosts
		fi
		if [[ $stage10 == 1 ]]; then
			cp /work/build-arm64/src/external/foundation/defaults /work/install/root/usr/bin/defaults
			cp /work/build-arm64/src/external/foundation/plutil /work/install/root/usr/bin/plutil
			cp /work/build-arm64/exec-arguments-darling-arm64 /work/install/root/exec-arguments-darling-arm64
		fi
		cp /work/build-arm64/hello-libsystem-arm64-0 /work/install/root/hello-libsystem-arm64-0
		cp /work/build-arm64/hello-libsystem-arm64-42 /work/install/root/hello-libsystem-arm64-42
		cp /work/build-arm64/posix-darling-arm64 /work/install/root/posix-darling-arm64
		cp /work/build-arm64/process-darling-arm64 /work/install/root/process-darling-arm64
		cp /work/build-arm64/pthread-darling-arm64 /work/install/root/pthread-darling-arm64
		cp /work/build-arm64/userland-darling-arm64 /work/install/root/userland-darling-arm64
		cp /work/build-arm64/pty-harness-darling-arm64 /work/install/root/pty-harness-darling-arm64
		cp /work/build-arm64/objc-darling-arm64 /work/install/root/objc-darling-arm64
		cp /work/build-arm64/src/external/shell_cmds/sh/ash /work/install/root/bin/sh
		cp /work/build-arm64/src/external/text_cmds/cat /work/install/root/bin/cat
		cp /work/build-arm64/src/external/shell_cmds/env /work/install/root/usr/bin/env
		cp /work/build-arm64/src/external/vim/src/vim /work/install/root/usr/bin/vim
		cp /work/build-arm64/src/external/libnotify/notifyd/notifyd /work/install/root/usr/sbin/notifyd
		cp /work/source/src/external/libnotify/notifyd/com.apple.notifyd.plist \
			/work/install/root/System/Library/LaunchDaemons/com.apple.notifyd.plist
		cp /work/build-arm64/dispatch-darling-arm64 /work/install/root/dispatch-darling-arm64
		cp /work/build-arm64/cfrunloop-dispatch-arm64 /work/install/root/cfrunloop-dispatch-arm64
		chown -R "$HOST_UID:$HOST_GID" /work/install
	'

if find "$tmp_root" -type l -print -quit | grep -q .; then
	echo "Staged installation contains a symbolic link." >&2
	exit 1
fi
if find "$tmp_root" -type f -exec file {} + | grep -Eq 'x86-64|80386|Intel 80386'; then
	echo "Staged installation contains an x86 artifact." >&2
	exit 1
fi
if ! file "$tmp_root/bin/darlingserver" | grep -q 'ARM aarch64'; then
	echo "darlingserver is not a native Linux aarch64 executable." >&2
	exit 1
fi
if [[ -e $tmp_root/bin/network-loopback-server-arm64 ]] &&
	! file "$tmp_root/bin/network-loopback-server-arm64" | grep -q 'ELF 64-bit.*ARM aarch64'; then
	echo "Stage 9 loopback server is not a native Linux aarch64 executable." >&2
	exit 1
fi
if ! file "$tmp_root/root/usr/lib/dyld" | grep -q 'Mach-O 64-bit arm64'; then
	echo "dyld is not an ARM64 Mach-O image." >&2
	exit 1
fi

{
	printf 'Darling native ARM64 Linux staging profile\n'
	printf 'source_commit=%s\n' "$(git -C "$source_root" rev-parse HEAD)"
	if [[ -n $(git -C "$source_root" status --porcelain) ]]; then
		printf 'source_worktree=dirty\n'
	else
		printf 'source_worktree=clean\n'
	fi
	printf 'host_arch=%s\n' "$(uname -m)"
	printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf 'bin/darlingserver: %s\n' "$(file -b "$tmp_root/bin/darlingserver")"
	printf 'root/usr/libexec/darling/mldr: %s\n' "$(file -b "$tmp_root/root/usr/libexec/darling/mldr")"
	printf 'root/usr/lib/dyld: %s\n' "$(file -b "$tmp_root/root/usr/lib/dyld")"
	printf 'root/hello-libsystem-arm64-0: %s\n' "$(file -b "$tmp_root/root/hello-libsystem-arm64-0")"
	printf 'root/hello-libsystem-arm64-42: %s\n' "$(file -b "$tmp_root/root/hello-libsystem-arm64-42")"
	printf 'root/posix-darling-arm64: %s\n' "$(file -b "$tmp_root/root/posix-darling-arm64")"
	printf 'root/process-darling-arm64: %s\n' "$(file -b "$tmp_root/root/process-darling-arm64")"
	printf 'root/pthread-darling-arm64: %s\n' "$(file -b "$tmp_root/root/pthread-darling-arm64")"
	printf 'root/userland-darling-arm64: %s\n' "$(file -b "$tmp_root/root/userland-darling-arm64")"
	printf 'root/objc-darling-arm64: %s\n' "$(file -b "$tmp_root/root/objc-darling-arm64")"
	printf 'root/bin/sh: %s\n' "$(file -b "$tmp_root/root/bin/sh")"
	printf 'root/bin/cat: %s\n' "$(file -b "$tmp_root/root/bin/cat")"
	printf 'root/usr/bin/env: %s\n' "$(file -b "$tmp_root/root/usr/bin/env")"
	printf 'root/usr/bin/vim: %s\n' "$(file -b "$tmp_root/root/usr/bin/vim")"
	printf 'root/dispatch-darling-arm64: %s\n' "$(file -b "$tmp_root/root/dispatch-darling-arm64")"
	printf 'root/cfrunloop-dispatch-arm64: %s\n' "$(file -b "$tmp_root/root/cfrunloop-dispatch-arm64")"
	printf 'root/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation: %s\n' \
		"$(file -b "$tmp_root/root/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation")"
	if [[ -x $tmp_root/root/foundation-darling-arm64 ]]; then
		printf 'root/foundation-darling-arm64: %s\n' "$(file -b "$tmp_root/root/foundation-darling-arm64")"
		printf 'root/foundation-task-darling-arm64: %s\n' "$(file -b "$tmp_root/root/foundation-task-darling-arm64")"
		printf 'root/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation: %s\n' \
			"$(file -b "$tmp_root/root/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation")"
	fi
	if [[ -x $tmp_root/root/runloop-network-darling-arm64 ]]; then
		printf 'bin/network-loopback-server-arm64: %s\n' "$(file -b "$tmp_root/bin/network-loopback-server-arm64")"
		printf 'root/runloop-network-darling-arm64: %s\n' "$(file -b "$tmp_root/root/runloop-network-darling-arm64")"
	fi
	if [[ -x $tmp_root/root/usr/bin/defaults ]]; then
		printf 'root/usr/bin/defaults: %s\n' "$(file -b "$tmp_root/root/usr/bin/defaults")"
		printf 'root/usr/bin/plutil: %s\n' "$(file -b "$tmp_root/root/usr/bin/plutil")"
		printf 'root/exec-arguments-darling-arm64: %s\n' "$(file -b "$tmp_root/root/exec-arguments-darling-arm64")"
	fi
} > "$tmp_root/MANIFEST.txt"

if [[ -e $install_root ]]; then
	mv -- "$install_root" "$old_root"
fi
mv -- "$tmp_root" "$install_root"
rm -rf -- "$old_root"
trap - EXIT

echo "Staged Darling ARM64 installation at $install_root"
