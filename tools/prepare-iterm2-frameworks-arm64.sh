#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
build_root=${DARLING_STAGE18_BUILD_ROOT:-$workspace_root/build-arm64-stage18}
install_root=${DARLING_STAGE18_ROOT:-$workspace_root/install-arm64-stage18}
image=${DARLING_ARM64_BUILDER_IMAGE:-darling-arm64-dev:24.04}

[[ $(uname -m) == aarch64 ]] || { echo "This builder requires native aarch64 Linux." >&2; exit 2; }
case "$build_root" in "$workspace_root"/*) ;; *) echo "Build root must stay below the workspace." >&2; exit 2;; esac
case "$install_root" in "$workspace_root"/*) ;; *) echo "Install root must stay below the workspace." >&2; exit 2;; esac
[[ -d $build_root && -d $install_root/root ]] || { echo "Missing Stage 18 build or install root." >&2; exit 2; }

docker run --rm --platform linux/arm64 \
	-v "$source_root:/work/source:ro" \
	-v "$build_root:/work/build" \
	"$image" bash -lc '
		set -euo pipefail
		cmake -S /work/source -B /work/build \
			-DCOMPONENTS=gui,jsc -DCOMPONENT_gui=ON \
			-DDARLING_ARM64_NORTH_STAR_STAGE18=ON \
			-DTARGET_arm64=ON -DTARGET_x86_64=OFF -DTARGET_i386=OFF
		ninja -C /work/build Metal MetalKit QuickLookUI Quartz ScreenCaptureKit
	'

docker run --rm --platform linux/arm64 \
	-v "$build_root:/work/build:ro" \
	-v "$install_root:/work/install" \
	"$image" bash -lc '
		set -euo pipefail
		stage_framework() {
			name=$1
			source=$2
			destination=/work/install/root/System/Library/Frameworks/$name.framework/Versions/A
			mkdir -p "$destination"
			install -m 0755 "$source" "$destination/$name"
		}
		stage_framework Metal /work/build/src/external/metal/Metal
		stage_framework MetalKit /work/build/src/external/metal/MetalKit
		stage_framework QuickLookUI /work/build/src/frameworks/Quartz/QuickLookUI/QuickLookUI
		stage_framework Quartz /work/build/src/frameworks/Quartz/Quartz
		stage_framework ScreenCaptureKit /work/build/src/frameworks/ScreenCaptureKit/ScreenCaptureKit
	'

for framework in Metal MetalKit QuickLookUI Quartz ScreenCaptureKit; do
	binary=$install_root/root/System/Library/Frameworks/$framework.framework/Versions/A/$framework
	description=$(file "$binary")
	[[ $description == *"Mach-O 64-bit arm64 dynamically linked shared library"* && $description == *"NOUNDEFS"* ]] || {
		echo "$description" >&2
		exit 1
	}
done
echo "ARM64 iTerm2 framework slice staged"
