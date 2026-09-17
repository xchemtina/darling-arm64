#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
install_root=${DARLING_ARM64_INSTALL_ROOT:-$workspace_root/install-arm64-stage10}
image=${DARLING_ARM64_IMAGE:-darling-arm64-dev:latest}
container=${DARLING_ARM64_HELLO_WINDOW_CONTAINER:-darling-arm64-hello-window}
artifact_root=$workspace_root/artifacts/stage12-hello-window
bundle=Applications/HelloWindow.app

if [[ $(uname -m) != aarch64 ]]; then
	echo "This verifier requires a native aarch64 Linux host." >&2
	exit 2
fi
case "$install_root" in
	"$workspace_root"/*) ;;
	*) echo "Install root must remain below $workspace_root." >&2; exit 2 ;;
esac
if [[ ! -x $install_root/root/$bundle/Contents/MacOS/HelloWindow ||
	! -f $install_root/root/$bundle/Contents/Info.plist ]]; then
	echo "Missing staged HelloWindow.app." >&2
	exit 2
fi
mkdir -p "$artifact_root"
rm -rf "$artifact_root/failure-markers"

docker rm -f "$container" >/dev/null 2>&1 || true
docker run --name "$container" --rm \
	-e DEBIAN_FRONTEND=noninteractive \
	--cap-add SYS_ADMIN \
	--cap-add SYS_PTRACE \
	--security-opt apparmor=unconfined \
	--security-opt seccomp=unconfined \
	--pids-limit 512 \
	--memory 4g \
	-v "$install_root/root:/usr/local/libexec/darling:ro" \
	-v "$install_root/bin:/opt/darling/bin:ro" \
	-v "$artifact_root:/artifacts" \
	"$image" bash -lc '
		set -euo pipefail
		command -v xdotool >/dev/null 2>&1 || apt-get update -qq
		command -v xdotool >/dev/null 2>&1 || apt-get install -y -qq xvfb openbox xdotool x11-utils imagemagick \
			libegl1 fonts-dejavu-core >/tmp/stage12-apt.log

		export PATH=/opt/darling/bin:$PATH
		export DISPLAY=:93
		export LANG=C.UTF-8
		export LC_ALL=C.UTF-8
		export DARLING_NOOVERLAYFS=1
		export DYLD_USE_CLOSURES=0
		export DARLING_ARM64_THREAD_BRIDGE=1

		Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp \
			>/tmp/stage12-xvfb.log 2>&1 &
		xvfb_pid=$!
		wm_pid=
		server_pid=
		cleanup() {
			# DARLING-ARM64 LOCAL DIAGNOSTIC: preserve application output.
			# /artifacts is bind-mounted and survives the container; /tmp is not.
			# Done from the EXIT trap so logs survive timeouts as well as failures.
			for _f in /tmp/stage*.err /tmp/stage*.out; do
				[ -s "$_f" ] && cp "$_f" /artifacts/ 2>/dev/null || true
			done
			[[ -z $server_pid ]] || kill "$server_pid" 2>/dev/null || true
			[[ -z $wm_pid ]] || kill "$wm_pid" 2>/dev/null || true
			kill "$xvfb_pid" 2>/dev/null || true
		}
		failure() {
			local status=$?
			echo "Stage 12 verifier failed near line ${BASH_LINENO[0]} (status $status)." >&2
			cat /tmp/stage12-hello-window.err 2>/dev/null >&2 || true
			if [[ -n ${prefix:-} && -d $prefix/private/var/tmp ]]; then
				rm -rf /artifacts/failure-markers
				mkdir -p /artifacts/failure-markers
				cp -a "$prefix/private/var/tmp/." /artifacts/failure-markers/
			fi
			return "$status"
		}
		trap cleanup EXIT
		trap failure ERR

		for attempt in {1..100}; do
			xdpyinfo >/dev/null 2>&1 && break
			kill -0 "$xvfb_pid" 2>/dev/null || {
				cat /tmp/stage12-xvfb.log >&2
				exit 1
			}
			sleep 0.05
		done
		xdpyinfo >/dev/null
		openbox --sm-disable >/tmp/stage12-openbox.log 2>&1 &
		wm_pid=$!
		for attempt in {1..100}; do
			xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q WINDOW && break
			kill -0 "$wm_pid" 2>/dev/null || {
				cat /tmp/stage12-openbox.log >&2
				exit 1
			}
			sleep 0.05
		done

		prefix=/tmp/darling-stage12
		mkdir -p "$prefix/dev/pts"
		cp -a /dev/null /dev/urandom "$prefix/dev/"
		mount --bind /dev/pts "$prefix/dev/pts"
		ln -s pts/ptmx "$prefix/dev/ptmx"

		export DSERVER_INIT=/Applications/HelloWindow.app/Contents/MacOS/HelloWindow
		exec 3>/tmp/stage12-ready-fd
		darlingserver "$prefix" 0 0 3 0 \
			>/tmp/stage12-hello-window.out 2>/tmp/stage12-hello-window.err &
		server_pid=$!
		exec 3>&-

		for attempt in {1..150}; do
			[[ -f $prefix/private/var/tmp/hello-window-ready ]] && break
			kill -0 "$server_pid" 2>/dev/null || {
				cat /tmp/stage12-hello-window.err >&2
				exit 1
			}
			sleep 0.1
		done
		test "$(cat "$prefix/private/var/tmp/hello-window-ready")" = ready
		grep -Fxq "org.darlinghq.north-star.hello-window|/Applications/HelloWindow.app" \
			"$prefix/private/var/tmp/hello-window-bundle"
		test "$(cat "$prefix/private/var/tmp/hello-window-resources")" = discovered

		window=$(xdotool search --onlyvisible \
			--name "^Darling ARM64 HelloWindow$" | head -1)
		test -n "$window"
		test "$(xdotool getwindowname "$window")" = "Darling ARM64 HelloWindow"
		xprop -id "$window" _NET_WM_WINDOW_TYPE | grep -q _NET_WM_WINDOW_TYPE_NORMAL
		xdotool windowactivate --sync "$window"
		for attempt in {1..50}; do
			[[ -f $prefix/private/var/tmp/hello-window-focus ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/hello-window-focus")" = focused

		import -window "$window" /artifacts/hello-window.png
		read -r image_width image_height < <(identify -format "%w %h\n" \
			/artifacts/hello-window.png)
		test "$image_width" -eq 400
		test "$image_height" -ge 240
		test "$image_height" -le 280
		test "$(convert /artifacts/hello-window.png \
			-format "%[fx:p{60,175}.g>0.55&&p{60,175}.b>0.55&&p{60,175}.r<0.2]" info:)" = 1
		test "$(convert /artifacts/hello-window.png \
			-format "%[fx:p{190,175}.r>0.6&&p{190,175}.b>0.5&&p{190,175}.g<0.3]" info:)" = 1
		test "$(convert /artifacts/hello-window.png \
			-format "%[fx:p{320,175}.r>0.7&&p{320,175}.g>0.55&&p{320,175}.b<0.25]" info:)" = 1
		test "$(cat "$prefix/private/var/tmp/hello-window-draw")" = painted

		xdotool mousemove --window "$window" 200 120 click 1
		for attempt in {1..50}; do
			[[ -f $prefix/private/var/tmp/hello-window-mouse ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/hello-window-mouse")" = clicked

		rm -f "$prefix/private/var/tmp/hello-window-draw"
		xdotool windowsize --sync "$window" 540 340
		for attempt in {1..50}; do
			[[ -f $prefix/private/var/tmp/hello-window-resize && \
			   -f $prefix/private/var/tmp/hello-window-draw ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/hello-window-resize")" = resized
		test "$(cat "$prefix/private/var/tmp/hello-window-draw")" = painted

		xdotool windowactivate --sync "$window"
		xdotool key alt+F4
		if ! timeout 10s tail --pid="$server_pid" -f /dev/null; then
			cat /tmp/stage12-hello-window.err >&2
			exit 1
		fi
		wait "$server_pid"
		server_pid=
		test "$(cat "$prefix/private/var/tmp/hello-window-close")" = close-requested
		if ps -eo comm=,args= | awk "\$1 == \"mldr\" && \$2 == \"/Applications/HelloWindow.app/Contents/MacOS/HelloWindow\" {found=1} END {exit found ? 0 : 1}"; then
			echo "HelloWindow.app left a live mldr process" >&2
			exit 1
		fi

		echo "ARM64 HelloWindow.app passed"
	'
