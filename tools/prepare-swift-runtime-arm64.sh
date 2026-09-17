#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
version=6.2.4
archive=swift-${version}-RELEASE-osx.pkg
archive_sha=9c94637fda8312901a08e572a651c3a18a672689ad867f96c9257b43775159e9
download_root=${DARLING_SWIFT_DOWNLOAD_ROOT:-$workspace_root/downloads/swift/$version}
toolchain_root=$download_root/toolchain
url=https://download.swift.org/swift-${version}-release/xcode/swift-${version}-RELEASE/$archive

[[ $(uname -m) == aarch64 ]] || { echo "This tool requires native aarch64 Linux." >&2; exit 2; }
case "$download_root" in "$workspace_root"/*) ;; *) echo "Swift downloads must stay below the workspace." >&2; exit 2;; esac
mkdir -p "$download_root"

curl -fL --retry 3 --continue-at - "$url" -o "$download_root/$archive"
echo "$archive_sha  $download_root/$archive" | sha256sum -c -

package_root=$download_root/package
rm -rf "$package_root"
mkdir -p "$toolchain_root"
docker run --rm --platform linux/arm64 \
	-v "$toolchain_root:/target" \
	ubuntu:24.04 find /target -mindepth 1 -delete
python3 "$source_root/tools/extract-xar.py" "$download_root/$archive" "$package_root"
payload=$package_root/swift-${version}-RELEASE-osx-package.pkg/Payload
[[ -f $payload ]] || { echo "Swift package payload is missing." >&2; exit 1; }
docker run --rm --platform linux/arm64 \
	-v "$payload:/payload:ro" \
	-v "$toolchain_root:/output" \
	ubuntu:24.04 bash -lc '
		set -euo pipefail
		apt-get update -qq
		DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cpio >/tmp/apt.log
		cd /output
		gzip -dc /payload | cpio -idmu "./usr/lib/swift/*" 2>/tmp/cpio.log
	'

rm -rf "$package_root"
[[ -f $toolchain_root/usr/lib/swift/macosx/libswiftCore.dylib ]] || {
	echo "Darwin Swift runtime extraction failed." >&2
	exit 1
}
echo "Prepared official Swift $version Darwin runtime resources at $toolchain_root"
