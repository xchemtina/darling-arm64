#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
build_root=${DARLING_STAGE18_BUILD_ROOT:-$workspace_root/build-arm64-stage18}
install_root=${DARLING_STAGE18_ROOT:-$workspace_root/install-arm64-stage18}
artifact_root=${DARLING_JSC_ARTIFACTS:-$workspace_root/artifacts/stage18-javascriptcore}
builder=${DARLING_ARM64_BUILDER_IMAGE:-darling-arm64-dev:24.04}
runtime=${DARLING_GUI_TEST_IMAGE:-darling-arm64-gui-test:latest}

[[ $(uname -m) == aarch64 ]] || { echo "This verifier requires native aarch64 Linux." >&2; exit 2; }
case "$artifact_root" in "$workspace_root"/*) ;; *) echo "Artifacts must stay below the workspace." >&2; exit 2;; esac
jsc=$install_root/root/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/JavaScriptCore
[[ -f $jsc ]] || { echo "Run tools/prepare-javascriptcore-arm64.sh first." >&2; exit 2; }
mkdir -p "$artifact_root"
rm -f "$artifact_root"/{empty.o,empty.s,JavaScriptCore.stub,libSystem.stub,probe.o,stubs.o,stubs.s,javascriptcore-darling-arm64}

docker run --rm --platform linux/arm64 \
	-v "$source_root:/work/source:ro" \
	-v "$build_root:/work/build:ro" \
	-v "$artifact_root:/work/output" \
	"$builder" bash -lc '
		set -euo pipefail
		ld=/work/build/src/external/cctools-port/cctools/ld64/src/arm64-apple-darwin20-ld
		cat >/work/output/stubs.s <<"EOF"
.p2align 2
.globl _JSGlobalContextCreate
.globl _JSGlobalContextRelease
.globl _JSStringCreateWithUTF8CString
.globl _JSStringRelease
.globl _JSEvaluateScript
.globl _JSValueToNumber
_JSGlobalContextCreate:
_JSGlobalContextRelease:
_JSStringCreateWithUTF8CString:
_JSStringRelease:
_JSEvaluateScript:
_JSValueToNumber:
  ret
EOF
		cat >/work/output/empty.s <<"EOF"
.p2align 2
.globl _darling_empty
_darling_empty:
  ret
EOF
		clang -target arm64-apple-darwin20 -c /work/output/stubs.s -o /work/output/stubs.o
		clang -target arm64-apple-darwin20 -c /work/output/empty.s -o /work/output/empty.o
		$ld -dylib -arch arm64 -platform_version macos 11.0 11.0 \
			-install_name /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/JavaScriptCore \
			-o /work/output/JavaScriptCore.stub /work/output/stubs.o
		$ld -dylib -arch arm64 -platform_version macos 11.0 11.0 \
			-install_name /usr/lib/libSystem.B.dylib \
			-o /work/output/libSystem.stub /work/output/empty.o
		clang -target arm64-apple-darwin20 -c /work/source/tools/javascriptcore-darling-arm64.c \
			-o /work/output/probe.o
		$ld -arch arm64 -platform_version macos 11.0 11.0 -pie -undefined dynamic_lookup \
			-o /work/output/javascriptcore-darling-arm64 /work/output/probe.o \
			/work/output/JavaScriptCore.stub /work/output/libSystem.stub
	'

description=$(file "$artifact_root/javascriptcore-darling-arm64")
[[ $description == *"Mach-O 64-bit arm64 executable"* && $description == *"NOUNDEFS"* ]] || { echo "$description" >&2; exit 1; }

docker run --rm --platform linux/arm64 \
	--cap-add SYS_ADMIN --cap-add SYS_PTRACE \
	--security-opt apparmor=unconfined --security-opt seccomp=unconfined \
	--pids-limit 256 --memory 2g \
	-v "$install_root/root:/usr/local/libexec/darling:ro" \
	-v "$install_root/bin:/opt/darling/bin:ro" \
	-v "$artifact_root/javascriptcore-darling-arm64:/probe:ro" \
	"$runtime" bash -lc '
		set -euo pipefail
		export PATH=/opt/darling/bin:$PATH DARLING_NOOVERLAYFS=1 DYLD_USE_CLOSURES=0 DARLING_ARM64_THREAD_BRIDGE=1
		prefix=/tmp/javascriptcore-prefix
		mkdir -p "$prefix/dev/pts" "$prefix/private/var/tmp" "$prefix/usr/bin"
		cp -a /dev/null /dev/urandom "$prefix/dev/"
		cp /probe "$prefix/usr/bin/javascriptcore-darling-arm64"
		mount --bind /dev/pts "$prefix/dev/pts"
		ln -s pts/ptmx "$prefix/dev/ptmx"
		export DSERVER_INIT=/usr/bin/javascriptcore-darling-arm64
		exec 3>/tmp/ready
		timeout 20 darlingserver "$prefix" 0 0 3 0
	'

echo "ARM64 JavaScriptCore evaluation passed"
