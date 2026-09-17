#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
version=3.6.11
expected_sha256=36e78c5049560eaa8e122224f6652eb4b229c61cd5e7332d6d25b5c36f7398e7
archive=${ITERM2_ARCHIVE:-$workspace_root/downloads/iterm2/$version/iTerm2-3_6_11.zip}
artifact_root=$workspace_root/artifacts/stage18-iterm2-artifact
extract_root=$artifact_root/fresh-extraction

case "$archive" in
	"$workspace_root"/*) ;;
	*) echo "The iTerm2 archive must be below $workspace_root." >&2; exit 2 ;;
esac
[[ -f $archive ]] || { echo "Missing official iTerm2 archive: $archive" >&2; exit 2; }
mkdir -p "$artifact_root"
case "$extract_root" in
	"$workspace_root"/*) rm -rf -- "$extract_root" ;;
	*) echo "Unsafe extraction path." >&2; exit 2 ;;
esac

printf '%s  %s\n' "$expected_sha256" "$archive" | sha256sum --check
unzip -Z1 "$archive" | awk '
	BEGIN { bad = 0 }
	/^\// || /(^|\/)\.\.($|\/)/ {
		print "Unsafe archive path: " $0 > "/dev/stderr"
		bad = 1
	}
	END { exit bad }
'
mkdir -p "$extract_root"
unzip -q "$archive" -d "$extract_root"

bundle=$extract_root/iTerm.app
plist=$bundle/Contents/Info.plist
executable=$bundle/Contents/MacOS/iTerm2
[[ -f $plist && -x $executable ]]
grep -A1 -F '<key>CFBundleIdentifier</key>' "$plist" | grep -Fq '<string>com.googlecode.iterm2</string>'
grep -A1 -F '<key>CFBundleShortVersionString</key>' "$plist" | grep -Fq "<string>$version</string>"
grep -A1 -F '<key>LSMinimumSystemVersion</key>' "$plist" | grep -Fq '<string>12.4</string>'
file "$executable" | grep -Fq 'arm64'

(
	cd "$bundle"
	find . -type f -print0 | sort -z | xargs -0 sha256sum
) >"$artifact_root/bundle-files.sha256"
(
	cd "$bundle"
	find . -type l -printf '%p -> %l\n' | LC_ALL=C sort
) >"$artifact_root/bundle-symlinks.txt"
sha256sum "$archive" >"$artifact_root/archive.sha256"
file "$executable" >"$artifact_root/main-executable.txt"

echo "Official unmodified iTerm2 $version artifact passed"
