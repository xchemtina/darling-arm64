#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
build_root=${DARLING_STAGE18_BUILD_ROOT:-$workspace_root/build-arm64-stage18}
swift_root=${DARLING_SWIFT_ROOT:-$workspace_root/downloads/swift/6.2.4/toolchain}
artifact_root=${DARLING_SWIFT_PROBE_ARTIFACTS:-$workspace_root/artifacts/stage18-swift-cross-compile}
image=swift:6.2-noble@sha256:dd349c6dfc3cd3040910a84ab3e5bd5d08efdd547e5fb9f77b765abed16fe5ff
ld64=$build_root/src/external/cctools-port/cctools/ld64/src/arm64-apple-darwin20-ld
sdk=$source_root/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk

[[ $(uname -m) == aarch64 ]] || { echo "This verifier requires native aarch64 Linux." >&2; exit 2; }
[[ -x $ld64 ]] || { echo "Missing Stage 18 ARM64 ld64." >&2; exit 2; }
[[ -f $swift_root/usr/lib/swift/macosx/libswiftCore.dylib ]] || { echo "Run tools/prepare-swift-runtime-arm64.sh first." >&2; exit 2; }
case "$artifact_root" in "$workspace_root"/*) ;; *) echo "Artifacts must stay below the workspace." >&2; exit 2;; esac
mkdir -p "$artifact_root"
rm -f "$artifact_root"/{empty.c,probe.swift,empty.o,libSystem.dylib,libDarlingSwiftProbe.dylib}

cat >"$artifact_root/empty.c" <<'EOF'
void darling_linker_stub(void) {}
EOF
cat >"$artifact_root/probe.swift" <<'EOF'
@_cdecl("darling_swift_probe")
public func darlingSwiftProbe() -> Int32 { 42 }
EOF

docker run --rm --platform linux/arm64 \
	-v "$source_root:/work/source:ro" \
	-v "$swift_root/usr/lib/swift:/work/swift:ro" \
	-v "$ld64:/work/ld:ro" \
	-v "$artifact_root:/work/output" \
	"$image" bash -lc '
		set -euo pipefail
		clang -target arm64-apple-macosx12.4 -c /work/output/empty.c -o /work/output/empty.o
		/work/ld -dylib -arch arm64 -platform_version macos 12.4 26.0 \
			-install_name /usr/lib/libSystem.B.dylib \
			-o /work/output/libSystem.dylib /work/output/empty.o
		swiftc -resource-dir /work/swift -use-ld=/work/ld \
			-target arm64-apple-macosx12.4 \
			-sdk /work/source/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
			-emit-library -module-name DarlingSwiftProbe \
			-L /work/output -Xlinker -undefined -Xlinker dynamic_lookup \
			/work/output/probe.swift -o /work/output/libDarlingSwiftProbe.dylib
	'

description=$(file "$artifact_root/libDarlingSwiftProbe.dylib")
[[ $description == *"Mach-O 64-bit arm64 dynamically linked shared library"* ]] || {
	echo "$description" >&2
	exit 1
}
echo "ARM64 Swift Mach-O cross-compile probe passed"
