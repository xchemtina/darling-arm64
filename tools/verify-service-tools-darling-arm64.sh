#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
install_root=${DARLING_ARM64_INSTALL_ROOT:-$workspace_root/install-arm64}
image=${DARLING_ARM64_IMAGE:-darling-arm64-dev:latest}
container=${DARLING_ARM64_SERVICE_CONTAINER:-darling-arm64-service-tools}

if [[ $(uname -m) != aarch64 ]]; then
	echo "This verifier requires a native aarch64 Linux host." >&2
	exit 2
fi
case "$install_root" in
	"$workspace_root"/*) ;;
	*) echo "Install root must remain below $workspace_root." >&2; exit 2 ;;
esac
for path in defaults plutil; do
	if [[ ! -x $install_root/root/usr/bin/$path ]]; then
		echo "Missing staged service tool: $path" >&2
		exit 2
	fi
done

docker rm -f "$container" >/dev/null 2>&1 || true
docker run --name "$container" --rm \
	-e DARLING_ARM64_THREAD_BRIDGE=1 \
	--cap-add SYS_ADMIN \
	--cap-add SYS_PTRACE \
	--security-opt apparmor=unconfined \
	--security-opt seccomp=unconfined \
	-v "$install_root/root:/usr/local/libexec/darling:ro" \
	-v "$install_root/bin:/opt/darling/bin:ro" \
	"$image" bash -lc '
		set -e
		prefix=/tmp/darling-prefix
		mkdir -p "$prefix/dev/pts"
		cp -a /dev/null /dev/urandom "$prefix/dev/"
		mount --bind /dev/pts "$prefix/dev/pts"
		ln -s pts/ptmx "$prefix/dev/ptmx"
		export PATH=/opt/darling/bin:$PATH
		export DARLING_NOOVERLAYFS=1
		export DYLD_USE_CLOSURES=0
		export DSERVER_INIT=/exec-arguments-darling-arm64

		run_tool() {
			timeout 15s darlingserver "$prefix" 0 0 1 0
		}
		clear_args() {
			unset DARLING_EXEC_ARG1 DARLING_EXEC_ARG2 DARLING_EXEC_ARG3 DARLING_EXEC_ARG4
			unset DARLING_EXEC_ARG5 DARLING_EXEC_ARG6 DARLING_EXEC_ARG7 DARLING_EXEC_ARG8
		}

		clear_args
		export DARLING_EXEC_PATH=/usr/bin/defaults
		export DARLING_EXEC_ARG1=write
		export DARLING_EXEC_ARG2=org.darlinghq.north-star.stage10
		export DARLING_EXEC_ARG3=Greeting
		export DARLING_EXEC_ARG4=stage10-persisted
		run_tool
		prefs=$prefix/root/Library/Preferences/org.darlinghq.north-star.stage10.plist
		grep -q "<string>stage10-persisted</string>" "$prefs"

		clear_args
		export DARLING_EXEC_PATH=/usr/bin/defaults
		export DARLING_EXEC_ARG1=read
		export DARLING_EXEC_ARG2=org.darlinghq.north-star.stage10
		export DARLING_EXEC_ARG3=Greeting
		run_tool

		clear_args
		export DARLING_EXEC_PATH=/usr/bin/plutil
		export DARLING_EXEC_ARG1=-lint
		export DARLING_EXEC_ARG2=/root/Library/Preferences/org.darlinghq.north-star.stage10.plist
		run_tool

		clear_args
		export DARLING_EXEC_PATH=/usr/bin/plutil
		export DARLING_EXEC_ARG1=-convert
		export DARLING_EXEC_ARG2=binary1
		export DARLING_EXEC_ARG3=-o
		export DARLING_EXEC_ARG4=/private/var/tmp/stage10.binary.plist
		export DARLING_EXEC_ARG5=/root/Library/Preferences/org.darlinghq.north-star.stage10.plist
		run_tool
		test "$(head -c 8 "$prefix/private/var/tmp/stage10.binary.plist")" = bplist00

		clear_args
		export DARLING_EXEC_PATH=/usr/bin/plutil
		export DARLING_EXEC_ARG1=-convert
		export DARLING_EXEC_ARG2=xml1
		export DARLING_EXEC_ARG3=-o
		export DARLING_EXEC_ARG4=/private/var/tmp/stage10.roundtrip.plist
		export DARLING_EXEC_ARG5=/private/var/tmp/stage10.binary.plist
		run_tool
		grep -q "<string>stage10-persisted</string>" "$prefix/private/var/tmp/stage10.roundtrip.plist"

		clear_args
		export DARLING_EXEC_PATH=/usr/bin/defaults
		export DARLING_EXEC_ARG1=delete
		export DARLING_EXEC_ARG2=org.darlinghq.north-star.stage10
		export DARLING_EXEC_ARG3=Greeting
		run_tool

		clear_args
		export DARLING_EXEC_PATH=/usr/bin/defaults
		export DARLING_EXEC_ARG1=read
		export DARLING_EXEC_ARG2=org.darlinghq.north-star.stage10
		export DARLING_EXEC_ARG3=Greeting
		set +e
		run_tool
		status=$?
		set -e
		test "$status" -eq 2

		echo "Darling ARM64 defaults/plutil persistence smoke passed"
	'
