#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
install_root=${DARLING_ARM64_INSTALL_ROOT:-$workspace_root/install-arm64-stage10}
image=${DARLING_ARM64_IMAGE:-darling-arm64-dev:latest}
container=${DARLING_ARM64_GUI_CONTAINER:-darling-arm64-gui-service-tools}

if [[ $(uname -m) != aarch64 ]]; then
	echo "This verifier requires a native aarch64 Linux host." >&2
	exit 2
fi
case "$install_root" in
	"$workspace_root"/*) ;;
	*) echo "Install root must remain below $workspace_root." >&2; exit 2 ;;
esac
for path in pbcopy pbpaste open; do
	if [[ ! -x $install_root/root/usr/bin/$path ]]; then
		echo "Missing staged GUI service tool: $path" >&2
		exit 2
	fi
done
for path in root/exec-arguments-darling-arm64 root/bin/sh \
	root/System/Library/CoreServices/launchservicesd; do
	if [[ ! -x $install_root/$path ]]; then
		echo "Missing staged LaunchServices dependency: $path" >&2
		exit 2
	fi
done

docker rm -f "$container" >/dev/null 2>&1 || true
docker run --name "$container" --rm \
	-e DEBIAN_FRONTEND=noninteractive \
	--cap-add SYS_ADMIN \
	--cap-add SYS_PTRACE \
	--security-opt apparmor=unconfined \
	--security-opt seccomp=unconfined \
	-v "$install_root/root:/usr/local/libexec/darling:ro" \
	-v "$install_root/bin:/opt/darling/bin:ro" \
	-v "$source_root/tools/fixtures:/opt/darling-fixtures:ro" \
	"$image" bash -lc '
		set -euo pipefail
		apt-get update -qq
		apt-get install -y -qq xvfb xclip x11-utils libegl1 >/tmp/stage10-apt.log

		export PATH=/opt/darling/bin:$PATH
		export DISPLAY=:91
		export DARLING_NOOVERLAYFS=1
		export DYLD_USE_CLOSURES=0
		export DARLING_ARM64_THREAD_BRIDGE=1

		Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp \
			>/tmp/stage10-xvfb.log 2>&1 &
		xvfb_pid=$!
		copy_server=
		stop_pbcopy() {
			while read -r pid; do
				kill -9 "$pid" 2>/dev/null || true
			done < <(ps -eo pid=,comm=,args= | \
				awk '\''$2 == "mldr" && $3 == "/usr/bin/pbcopy" {print $1}'\'')
		}
		cleanup() {
			[[ -z $copy_server ]] || kill "$copy_server" 2>/dev/null || true
			stop_pbcopy
			kill "$xvfb_pid" 2>/dev/null || true
		}
		trap cleanup EXIT
		for attempt in {1..100}; do
			xdpyinfo >/dev/null 2>&1 && break
			kill -0 "$xvfb_pid" 2>/dev/null || {
				cat /tmp/stage10-xvfb.log >&2
				exit 1
			}
			sleep 0.05
		done
		xdpyinfo >/dev/null

		prepare_prefix() {
			local prefix=$1
			mkdir -p "$prefix/dev/pts"
			cp -a /dev/null /dev/urandom "$prefix/dev/"
			mount --bind /dev/pts "$prefix/dev/pts"
			ln -s pts/ptmx "$prefix/dev/ptmx"
		}

		copy_prefix=/tmp/darling-prefix-copy
		prepare_prefix "$copy_prefix"
		export DSERVER_INIT=/usr/bin/pbcopy
		exec 3>/tmp/stage10-copy-ready
		printf darling-to-linux | \
			darlingserver "$copy_prefix" 0 0 3 0 \
			>/tmp/stage10-pbcopy.out 2>/tmp/stage10-pbcopy.err &
		copy_server=$!
		exec 3>&-
		clipboard=
		for attempt in {1..100}; do
			clipboard=$(xclip -selection clipboard -out 2>/dev/null || true)
			[[ $clipboard == darling-to-linux ]] && break
			kill -0 "$copy_server" 2>/dev/null || {
				cat /tmp/stage10-pbcopy.err >&2
				exit 1
			}
			sleep 0.1
		done
		test "$clipboard" = darling-to-linux

		kill "$copy_server" 2>/dev/null || true
		wait "$copy_server" 2>/dev/null || true
		copy_server=
		stop_pbcopy

		printf linux-to-darling | xclip -selection clipboard -in \
			>/tmp/stage10-xclip.err 2>&1 &
		xclip_pid=$!
		paste_prefix=/tmp/darling-prefix-paste
		prepare_prefix "$paste_prefix"
		export DSERVER_INIT=/usr/bin/pbpaste
		exec 3>/tmp/stage10-paste-ready
		timeout 15s darlingserver "$paste_prefix" 0 0 3 0 \
			>/tmp/stage10-pbpaste.out 2>/tmp/stage10-pbpaste.err
		exec 3>&-
		kill "$xclip_pid" 2>/dev/null || true
		wait "$xclip_pid" 2>/dev/null || true
		test "$(cat /tmp/stage10-pbpaste.out)" = linux-to-darling

		launch_prefix=/tmp/darling-prefix-launchservices
		prepare_prefix "$launch_prefix"
		mkdir -p "$launch_prefix/private/var/db" \
			"$launch_prefix/private/var/tmp" \
			"$launch_prefix/Applications/NorthStarOpen.app/Contents/MacOS"
		cp /opt/darling-fixtures/NorthStarOpen.app/Contents/Info.plist \
			"$launch_prefix/Applications/NorthStarOpen.app/Contents/Info.plist"
		cp /usr/local/libexec/darling/bin/sh \
			"$launch_prefix/Applications/NorthStarOpen.app/Contents/MacOS/sh"
		cp /opt/darling-fixtures/north-star-open.northstar \
			"$launch_prefix/private/var/tmp/north-star-open.northstar"

		export DSERVER_INIT=/exec-arguments-darling-arm64
		export DARLING_ARM64_THREAD_BRIDGE=1
		export DARLING_EXEC_PATH=/System/Library/CoreServices/launchservicesd
		export DARLING_EXEC_ARG1=--register
		export DARLING_EXEC_ARG2=/Applications/NorthStarOpen.app
		exec 3>/tmp/stage10-register-ready
		timeout 15s darlingserver "$launch_prefix" 0 0 3 0 \
			>/tmp/stage10-register.out 2>/tmp/stage10-register.err
		exec 3>&-

		export DARLING_ARM64_THREAD_BRIDGE=0
		export DARLING_EXEC_PATH=/usr/bin/open
		export DARLING_EXEC_ARG1=-W
		export DARLING_EXEC_ARG2=file:///private/var/tmp/north-star-open.northstar
		exec 3>/tmp/stage10-open-ready
		timeout 15s darlingserver "$launch_prefix" 0 0 3 0 \
			>/tmp/stage10-open.out 2>/tmp/stage10-open.err
		exec 3>&-
		test "$(cat "$launch_prefix/private/var/tmp/north-star-open-marker")" = \
			launchservices-open-passed

		echo "ARM64 GUI service tools passed"
	'
