#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
version=7.0.7
download_root=${COTEDITOR_DOWNLOAD_ROOT:-$workspace_root/downloads/coteditor/$version}
dmg=$download_root/CotEditor_${version}.dmg
reference=$download_root/reference/CotEditor.app
url=https://github.com/coteditor/CotEditor/releases/download/$version/CotEditor_${version}.dmg
dmg_sha=353997fdf989085a7a02e67fe5e3517c2b594c44c9a93102d4c017fcfc4b84b0
executable_sha=02955bf975f59016dfab7d1e39a3aa7626c96f997bfdc79d05262dda12b4cec6

case "$download_root" in
"$workspace_root"/*) ;;
*) echo "CotEditor artifacts must stay below the workspace." >&2; exit 2 ;;
esac
command -v 7z >/dev/null || {
	echo "7z 23 or newer is required to extract the APFS disk image." >&2
	exit 2
}

mkdir -p "$download_root"
curl -fL --retry 3 --continue-at - "$url" -o "$dmg"
echo "$dmg_sha  $dmg" | sha256sum -c -

if [[ -d $download_root/reference ]]; then
	chmod -R u+w "$download_root/reference"
	rm -rf "$download_root/reference"
fi
mkdir -p "$download_root/reference"
7z x -snl -o"$download_root/reference" "$dmg" 'CotEditor.app/*' >/dev/null
echo "$executable_sha  $reference/Contents/MacOS/CotEditor" | sha256sum -c -
chmod -R a-w "$reference"

echo "Prepared unchanged CotEditor $version at $reference"
