#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
install_root=${DARLING_ARM64_INSTALL_ROOT:-$workspace_root/install-arm64-stage10}
image=${DARLING_ARM64_IMAGE:-darling-arm64-dev:latest}
container=${DARLING_ARM64_CONTROLS_CONTAINER:-darling-arm64-controls}
artifact_root=$workspace_root/artifacts/stage13-controls
bundle=Applications/Controls.app

if [[ $(uname -m) != aarch64 ]]; then
	echo "This verifier requires a native aarch64 Linux host." >&2
	exit 2
fi
case "$install_root" in
	"$workspace_root"/*) ;;
	*) echo "Install root must remain below $workspace_root." >&2; exit 2 ;;
esac
if [[ ! -x $install_root/root/$bundle/Contents/MacOS/Controls ||
	! -f $install_root/root/$bundle/Contents/Info.plist ]]; then
	echo "Missing staged Controls.app." >&2
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
		command -v xdotool >/dev/null 2>&1 || apt-get install -y -qq xvfb openbox xdotool x11-utils \
			libegl1 fonts-dejavu-core >/tmp/stage13-apt.log

		export PATH=/opt/darling/bin:$PATH
		export DISPLAY=:94
		export LANG=C.UTF-8
		export LC_ALL=C.UTF-8
		export DARLING_NOOVERLAYFS=1
		export DYLD_USE_CLOSURES=0
		export DARLING_ARM64_THREAD_BRIDGE=1

		Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp \
			>/tmp/stage13-xvfb.log 2>&1 &
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
			echo "Stage 13 verifier failed near line ${BASH_LINENO[0]} (status $status)." >&2
			cat /tmp/stage13-controls.err 2>/dev/null >&2 || true
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
				cat /tmp/stage13-xvfb.log >&2
				exit 1
			}
			sleep 0.05
		done
		xdpyinfo >/dev/null
		openbox --sm-disable >/tmp/stage13-openbox.log 2>&1 &
		wm_pid=$!
		for attempt in {1..100}; do
			xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q WINDOW && break
			kill -0 "$wm_pid" 2>/dev/null || {
				cat /tmp/stage13-openbox.log >&2
				exit 1
			}
			sleep 0.05
		done

		prefix=/tmp/darling-stage13
		mkdir -p "$prefix/dev/pts"
		cp -a /dev/null /dev/urandom "$prefix/dev/"
		mount --bind /dev/pts "$prefix/dev/pts"
		ln -s pts/ptmx "$prefix/dev/ptmx"

		export DSERVER_INIT=/Applications/Controls.app/Contents/MacOS/Controls
		exec 3>/tmp/stage13-ready-fd
		darlingserver "$prefix" 0 0 3 0 \
			>/tmp/stage13-controls.out 2>/tmp/stage13-controls.err &
		server_pid=$!
		exec 3>&-

		for attempt in {1..150}; do
			[[ -f $prefix/private/var/tmp/controls-ready ]] && break
			kill -0 "$server_pid" 2>/dev/null || {
				cat /tmp/stage13-controls.err >&2
				exit 1
			}
			sleep 0.1
		done
		test "$(cat "$prefix/private/var/tmp/controls-ready")" = ready
		grep -Fxq "org.darlinghq.north-star.controls|/Applications/Controls.app" \
			"$prefix/private/var/tmp/controls-bundle"

		mapfile -t windows < <(xdotool search --onlyvisible \
			--name "^Darling ARM64 Controls$")
		test ${#windows[@]} -eq 1
		main=${windows[0]}
		test "$(xdotool getwindowname "$main")" = "Darling ARM64 Controls"
		xprop -id "$main" _NET_WM_WINDOW_TYPE | grep -q _NET_WM_WINDOW_TYPE_NORMAL
		xdotool windowactivate --sync "$main"

		xdotool key alt+k
		for attempt in {1..30}; do
			[[ -f $prefix/private/var/tmp/controls-menu ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/controls-menu")" = option-k

		xdotool mousemove --sync --window "$main" 90 85 click 1
		for attempt in {1..30}; do
			[[ -f $prefix/private/var/tmp/controls-button ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/controls-button")" = mouse

		xdotool mousemove --sync --window "$main" 230 87 click 1
		for attempt in {1..30}; do
			[[ -f $prefix/private/var/tmp/controls-checkbox ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/controls-checkbox")" = on

		xdotool mousemove --sync --window "$main" 140 155
		xdotool mousedown 1
		sleep 0.1
		xdotool mouseup 1
		xdotool type --delay 50 "north-star-controls"
		for attempt in {1..30}; do
			[[ -f $prefix/private/var/tmp/controls-focus ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/controls-focus")" = NSTextView

		rm -f "$prefix/private/var/tmp/controls-button"
		xdotool key Tab
		for attempt in {1..30}; do
			[[ -f $prefix/private/var/tmp/controls-text ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/controls-text")" = north-star-controls
		xdotool key space
		for attempt in {1..30}; do
			[[ -f $prefix/private/var/tmp/controls-button ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/controls-button")" = keyboard

		sleep 0.6
		xdotool mousemove --sync --window "$main" 110 270 click 1
		for attempt in {1..30}; do
			[[ -f $prefix/private/var/tmp/controls-list ]] && break
			sleep 0.05
		done
		grep -Eq "^[0-9]+$" "$prefix/private/var/tmp/controls-list"

		xdotool mousemove --sync --window "$main" 110 270
		xdotool mousedown 1
		xdotool mousemove --sync --window "$main" 110 310
		sleep 0.1
		xdotool mouseup 1
		for attempt in {1..30}; do
			[[ -f $prefix/private/var/tmp/controls-drop ]] && break
			sleep 0.05
		done
		source_row=$(cat "$prefix/private/var/tmp/controls-drag-source")
		drop=$(cat "$prefix/private/var/tmp/controls-drop")
		[[ $drop == "$source_row-to-"* ]]

		rm -f "$prefix/private/var/tmp/controls-scroll"
		xdotool mousemove --sync --window "$main" 110 280 click --repeat 5 5
		for attempt in {1..30}; do
			[[ -f $prefix/private/var/tmp/controls-scroll ]] && break
			sleep 0.05
		done
		scroll_y=$(cat "$prefix/private/var/tmp/controls-scroll")
		[[ $scroll_y =~ ^[0-9]+$ ]]
		((scroll_y > 0))

		xdotool mousemove --sync --window "$main" 90 215 click 1
		for attempt in {1..30}; do
			[[ -f $prefix/private/var/tmp/controls-sheet ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/controls-sheet")" = shown
		sheet=$(xdotool search --onlyvisible --name "^Darling Controls Sheet$" | head -1)
		test -n "$sheet"
		xprop -id "$sheet" _NET_WM_WINDOW_TYPE | grep -q _NET_WM_WINDOW_TYPE_DIALOG
		xprop -id "$sheet" _NET_WM_STATE | grep -q _NET_WM_STATE_MODAL
		transient=$(xprop -id "$sheet" WM_TRANSIENT_FOR)
		grep -qi "0x$(printf "%x" "$main")" <<<"$transient"

		rm -f "$prefix/private/var/tmp/controls-button"
		xdotool mousemove --sync --window "$main" 90 85 click 1
		sleep 0.2
		test ! -f "$prefix/private/var/tmp/controls-button"

		xdotool mousemove --sync --window "$sheet" 140 90 click 1
		for attempt in {1..30}; do
			[[ $(cat "$prefix/private/var/tmp/controls-sheet") == dismissed ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/controls-sheet")" = dismissed
		! xdotool search --onlyvisible --name "^Darling Controls Sheet$" >/dev/null 2>&1

		xdotool mousemove --sync --window "$main" 270 215 click 1
		for attempt in {1..30}; do
			[[ -f $prefix/private/var/tmp/controls-auxiliary ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/controls-auxiliary")" = shown
		aux=$(xdotool search --onlyvisible --name "^Darling Controls Auxiliary$" | head -1)
		test -n "$aux"
		xprop -id "$aux" _NET_WM_WINDOW_TYPE | grep -q _NET_WM_WINDOW_TYPE_NORMAL

		xdotool windowactivate --sync "$aux"
		xdotool key alt+F4
		for attempt in {1..30}; do
			! xdotool search --onlyvisible --name "^Darling Controls Auxiliary$" \
				>/dev/null 2>&1 && break
			sleep 0.05
		done
		kill -0 "$server_pid"
		test -n "$(xdotool search --onlyvisible --name "^Darling ARM64 Controls$" | head -1)"

		xdotool windowactivate --sync "$main"
		xdotool key alt+F4
		if ! timeout 10s tail --pid="$server_pid" -f /dev/null; then
			cat /tmp/stage13-controls.err >&2
			exit 1
		fi
		wait "$server_pid"
		server_pid=
		test "$(cat "$prefix/private/var/tmp/controls-close")" = close-requested
		if ps -eo comm=,args= | awk "\$1 == \"mldr\" && \$2 == \"/Applications/Controls.app/Contents/MacOS/Controls\" {found=1} END {exit found ? 0 : 1}"; then
			echo "Controls.app left a live mldr process" >&2
			exit 1
		fi

		echo "ARM64 Controls.app milestone passed"
	'
