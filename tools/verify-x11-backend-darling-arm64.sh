#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
install_root=${DARLING_ARM64_INSTALL_ROOT:-$workspace_root/install-arm64-stage10}
image=${DARLING_ARM64_IMAGE:-darling-arm64-dev:latest}
container=${DARLING_ARM64_X11_CONTAINER:-darling-arm64-x11-backend}
failure_container=${container}-display-failure
artifact_root=$workspace_root/artifacts/stage11-x11

if [[ $(uname -m) != aarch64 ]]; then
	echo "This verifier requires a native aarch64 Linux host." >&2
	exit 2
fi
case "$install_root" in
	"$workspace_root"/*) ;;
	*) echo "Install root must remain below $workspace_root." >&2; exit 2 ;;
esac
if [[ ! -x $install_root/root/usr/bin/x11-backend-smoke ]]; then
	echo "Missing staged x11-backend-smoke." >&2
	exit 2
fi
mkdir -p "$artifact_root"
rm -rf "$artifact_root/failure-markers"

docker rm -f "$container" >/dev/null 2>&1 || true
docker rm -f "$failure_container" >/dev/null 2>&1 || true
docker run --name "$failure_container" --rm \
	-e DEBIAN_FRONTEND=noninteractive \
	--cap-add SYS_ADMIN \
	--cap-add SYS_PTRACE \
	--security-opt apparmor=unconfined \
	--security-opt seccomp=unconfined \
	--pids-limit 512 \
	--memory 4g \
	-v "$install_root/root:/usr/local/libexec/darling:ro" \
	-v "$install_root/bin:/opt/darling/bin:ro" \
	"$image" bash -lc '
		set -euo pipefail
		command -v xdotool >/dev/null 2>&1 || apt-get update -qq
		command -v xdotool >/dev/null 2>&1 || apt-get install -y -qq libegl1 libx11-6 libxext6 libxrender1 \
			libxcursor1 libxfixes3 libxi6 >/tmp/stage11-display-apt.log
		failure() {
			local status=$?
			cat /tmp/stage11-display-failure.err 2>/dev/null >&2 || true
			exit "$status"
		}
		trap failure ERR
		export PATH=/opt/darling/bin:$PATH
		export DISPLAY=:199
		export DARLING_NOOVERLAYFS=1
		export DYLD_USE_CLOSURES=0
		export DARLING_ARM64_THREAD_BRIDGE=1
		export DSERVER_INIT=/usr/bin/x11-backend-smoke
		export NORTH_STAR_EXPECT_DISPLAY_FAILURE=1
		prefix=/tmp/darling-x11-fail
		mkdir -p "$prefix/dev/pts"
		cp -a /dev/null /dev/urandom "$prefix/dev/"
		mount --bind /dev/pts "$prefix/dev/pts"
		ln -s pts/ptmx "$prefix/dev/ptmx"
		exec 3>/tmp/stage11-display-failure-ready
		set +e
		timeout 10s darlingserver "$prefix" 0 0 3 0 \
			>/tmp/stage11-display-failure.out \
			2>/tmp/stage11-display-failure.err
		status=$?
		set -e
		if [[ $status -ne 0 ]]; then
			cat /tmp/stage11-display-failure.err >&2
			exit "$status"
		fi
		grep -Fxq "x11 display connection failed cleanly" \
			/tmp/stage11-display-failure.err
	'
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
	-v "$source_root/tools/fixtures:/opt/darling-fixtures:ro" \
	-v "$artifact_root:/artifacts" \
	"$image" bash -lc '
		set -euo pipefail
		command -v xdotool >/dev/null 2>&1 || apt-get update -qq
		command -v xdotool >/dev/null 2>&1 || apt-get install -y -qq xvfb xserver-xephyr openbox xdotool xclip x11-utils wmctrl \
			x11-xserver-utils gcc libx11-dev libxfixes-dev libxcursor-dev \
			imagemagick libegl1 fonts-dejavu-core xcursor-themes \
			>/tmp/stage11-apt.log
		gcc -O2 /opt/darling-fixtures/x11-cursor-probe.c \
			-o /tmp/x11-cursor-probe -lXcursor -lXfixes -lX11

		export PATH=/opt/darling/bin:$PATH
		export DISPLAY=:92
		export LANG=C.UTF-8
		export LC_ALL=C.UTF-8
		export XCURSOR_THEME=whiteglass
		export DARLING_NOOVERLAYFS=1
		export DYLD_USE_CLOSURES=0
		export DARLING_ARM64_THREAD_BRIDGE=1

		Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp \
			>/tmp/stage11-xvfb.log 2>&1 &
		xvfb_pid=$!
		wm_pid=
		inner_wm_pid=
		xephyr_pid=
		server_pid=
		cleanup() {
			# DARLING-ARM64 LOCAL DIAGNOSTIC: preserve application output.
			# /artifacts is bind-mounted and survives the container; /tmp is not.
			# Done from the EXIT trap so logs survive timeouts as well as failures.
			for _f in /tmp/stage*.err /tmp/stage*.out; do
				[ -s "$_f" ] && cp "$_f" /artifacts/ 2>/dev/null || true
			done
			[[ -z $server_pid ]] || kill "$server_pid" 2>/dev/null || true
			[[ -z $inner_wm_pid ]] || kill "$inner_wm_pid" 2>/dev/null || true
			[[ -z $xephyr_pid ]] || kill "$xephyr_pid" 2>/dev/null || true
			[[ -z $wm_pid ]] || kill "$wm_pid" 2>/dev/null || true
			kill "$xvfb_pid" 2>/dev/null || true
		}
		failure() {
			local status=$?
			echo "Stage 11 verifier failed near line ${BASH_LINENO[0]} (status $status)." >&2
			# DARLING-ARM64 DIAG (FINDINGS.md F24): the line number alone has
			# twice been misread. Name the command and show the markers.
			echo "  failing command: ${BASH_COMMAND}" >&2
			echo "  markers present at failure:" >&2
			ls -1 "${prefix:-/nonexistent}/private/var/tmp" 2>/dev/null \
				| sed "s/^/    /" >&2 || echo "    (none)" >&2
			cat /tmp/stage11-smoke.err 2>/dev/null >&2 || true
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
				cat /tmp/stage11-xvfb.log >&2
				exit 1
			}
			sleep 0.05
		done
		xdpyinfo >/dev/null
		setxkbmap -option compose:ralt
		openbox --sm-disable >/tmp/stage11-openbox.log 2>&1 &
		wm_pid=$!
		for attempt in {1..100}; do
			xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q WINDOW && break
			kill -0 "$wm_pid" 2>/dev/null || {
				cat /tmp/stage11-openbox.log >&2
				exit 1
			}
			sleep 0.05
		done

		prefix=/tmp/darling-prefix-stage11
		mkdir -p "$prefix/dev/pts"
		cp -a /dev/null /dev/urandom "$prefix/dev/"
		mount --bind /dev/pts "$prefix/dev/pts"
		ln -s pts/ptmx "$prefix/dev/ptmx"

		export DSERVER_INIT=/usr/bin/x11-backend-smoke
		exec 3>/tmp/stage11-ready-fd
		darlingserver "$prefix" 0 0 3 0 \
			>/tmp/stage11-smoke.out 2>/tmp/stage11-smoke.err &
		server_pid=$!
		exec 3>&-

		ready=$prefix/private/var/tmp/x11-backend-ready
		for attempt in {1..150}; do
			[[ -f $ready ]] && break
			kill -0 "$server_pid" 2>/dev/null || {
				cat /tmp/stage11-smoke.err >&2
				exit 1
			}
			sleep 0.1
		done
		test "$(cat "$ready")" = ready

		expected_title=$(printf "Darling ARM64 X11 Smoke \342\200\224 UTF-8")
		window=$(xdotool search --onlyvisible --name "^$expected_title$" | head -1)
		test -n "$window"
		test "$(xdotool getwindowname "$window")" = "$expected_title"
		xdotool windowactivate --sync "$window"

		import -window "$window" /artifacts/x11-backend-smoke.png
		read -r image_width image_height < <(identify -format "%w %h\n" \
			/artifacts/x11-backend-smoke.png)
		test "$image_width" -eq 360
		test "$image_height" -ge 220
		test "$image_height" -le 260
		test "$(convert /artifacts/x11-backend-smoke.png \
			-format "%[fx:p{60,160}.r>0.6&&p{60,160}.g<0.3]" info:)" = 1
		test "$(convert /artifacts/x11-backend-smoke.png \
			-format "%[fx:p{180,160}.g>0.45&&p{180,160}.r<0.3]" info:)" = 1
		test "$(convert /artifacts/x11-backend-smoke.png \
			-format "%[fx:p{290,160}.b>0.6&&p{290,160}.r<0.3]" info:)" = 1

		xdotool key shift+k
		for attempt in {1..50}; do
			[[ -f $prefix/private/var/tmp/x11-backend-key ]] && break
			sleep 0.05
		done
		grep -Fq "characters=K;shift=1;control=0;option=0" \
			"$prefix/private/var/tmp/x11-backend-key"
		xdotool key ctrl+alt+x
		xdotool keydown a
		sleep 0.8
		xdotool keyup a
		xdotool key Multi_key apostrophe e
		for attempt in {1..50}; do
			grep -q "control=1;option=1" \
				"$prefix/private/var/tmp/x11-backend-key" 2>/dev/null && \
			grep -q "repeat=1" "$prefix/private/var/tmp/x11-backend-key" && \
			grep -Fq "characters=é" "$prefix/private/var/tmp/x11-backend-key" && break
			sleep 0.05
		done
		grep -q "control=1;option=1" "$prefix/private/var/tmp/x11-backend-key"
		grep -q "repeat=1" "$prefix/private/var/tmp/x11-backend-key"
		grep -Fq "characters=é" "$prefix/private/var/tmp/x11-backend-key"

		xterm_signature=$(/tmp/x11-cursor-probe --reference xterm)
		xdotool mousemove --window "$window" 180 120
		test "$(/tmp/x11-cursor-probe --current)" = "$xterm_signature"
		test "$(cat "$prefix/private/var/tmp/x11-backend-cursor")" = xterm
		xdotool key g
		for attempt in {1..50}; do
			grep -q "characters=g" "$prefix/private/var/tmp/x11-backend-key" && break
			sleep 0.05
		done
		test "$(/tmp/x11-cursor-probe --grab)" = 1
		xdotool key u
		for attempt in {1..50}; do
			grep -q "characters=u" "$prefix/private/var/tmp/x11-backend-key" && break
			sleep 0.05
		done
		test "$(/tmp/x11-cursor-probe --grab)" = 0

		rm -f "$prefix/private/var/tmp/x11-backend-scroll"
		xdotool mousemove --window "$window" 180 160 click 4
		for attempt in {1..50}; do
			[[ -f $prefix/private/var/tmp/x11-backend-scroll ]] && break
			sleep 0.05
		done
		grep -Fxq "phase=0;momentum=0;precise=0;delta=1;scrollingDelta=1;moved=1" \
			"$prefix/private/var/tmp/x11-backend-scroll"

		xdotool click 1
		rm -f "$prefix/private/var/tmp/x11-backend-resize"
		xdotool windowsize --sync "$window" 520 320
		for attempt in {1..50}; do
			[[ -f $prefix/private/var/tmp/x11-backend-mouse && \
			   -f $prefix/private/var/tmp/x11-backend-resize ]] && break
			sleep 0.05
		done
		test -s "$prefix/private/var/tmp/x11-backend-mouse"
		test "$(cat "$prefix/private/var/tmp/x11-backend-resize")" = resized
		test "$(cat "$prefix/private/var/tmp/x11-backend-focus")" = focused
		test -s "$prefix/private/var/tmp/x11-backend-font"
		import -window "$window" /artifacts/x11-backend-smoke-resized.png
		read -r resized_width resized_height < <(identify -format "%w %h\n" \
			/artifacts/x11-backend-smoke-resized.png)
		test "$resized_width" -eq 520
		test "$resized_height" -eq 320
		test "$(convert /artifacts/x11-backend-smoke-resized.png \
			-format "%[fx:p{440,60}.r>0.85&&p{440,60}.g>0.85&&p{440,60}.b>0.80]" \
			info:)" = 1

		rm -f "$prefix/private/var/tmp/x11-backend-fixed-resize"
		xdotool key n
		for attempt in {1..50}; do
			[[ -f $prefix/private/var/tmp/x11-backend-fixed-resize ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/x11-backend-fixed-resize")" = requested
		for attempt in {1..50}; do
			eval "$(xdotool getwindowgeometry --shell "$window")"
			[[ $WIDTH -eq 520 && $HEIGHT -eq 292 ]] && break
			sleep 0.05
		done
		import -window "$window" /artifacts/x11-backend-smoke-fixed-resized.png
		test "$WIDTH" -eq 520
		test "$HEIGHT" -eq 292
		test "$(convert /artifacts/x11-backend-smoke-fixed-resized.png \
			-format "%[fx:p{440,60}.r>0.85&&p{440,60}.g>0.85&&p{440,60}.b>0.80]" \
			info:)" = 1

		xdotool windowactivate --sync "$window"
		xdotool key m
		for attempt in {1..100}; do
			[[ -f $prefix/private/var/tmp/x11-backend-modal-ready ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/x11-backend-modal-ready")" = ready
		modal_window=$(xdotool search --onlyvisible \
			--name "^Darling ARM64 X11 Modal$" | head -1)
		test -n "$modal_window"
		xprop -id "$modal_window" _NET_WM_WINDOW_TYPE | \
			grep -q _NET_WM_WINDOW_TYPE_DIALOG
		xprop -id "$modal_window" _NET_WM_STATE | \
			grep -q _NET_WM_STATE_MODAL
		xprop -id "$modal_window" WM_STATE | grep -q "window state: Normal"
		xprop -id "$modal_window" WM_PROTOCOLS | grep -q WM_DELETE_WINDOW
		xprop -id "$modal_window" _NET_WM_ALLOWED_ACTIONS | \
			grep -q _NET_WM_ACTION_CLOSE
		main_window_hex=$(printf "0x%x" "$window")
		xprop -id "$modal_window" WM_TRANSIENT_FOR | grep -qi "$main_window_hex"

		rm -f "$prefix/private/var/tmp/x11-backend-mouse" \
			"$prefix/private/var/tmp/x11-backend-modal-click"
		xdotool mousemove --window "$window" 40 40 click 1
		sleep 0.2
		test ! -e "$prefix/private/var/tmp/x11-backend-mouse"
		xdotool mousemove --window "$modal_window" 80 60 click 1
		for attempt in {1..50}; do
			[[ -f $prefix/private/var/tmp/x11-backend-modal-click ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/x11-backend-modal-click")" = clicked
		modal_window_hex=$(printf "0x%08x" "$modal_window")
		wmctrl -ic "$modal_window_hex"
		for attempt in {1..100}; do
			[[ -f $prefix/private/var/tmp/x11-backend-modal-close ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/x11-backend-modal-close")" = closed
		kill -0 "$server_pid"

		test "$(xclip -selection clipboard -out)" = stage11-clipboard
		test "$(xclip -selection primary -out)" = stage11-primary

		xdotool windowactivate --sync "$window"
		xdotool key alt+F4
		if ! timeout 10s tail --pid="$server_pid" -f /dev/null; then
			cat /tmp/stage11-smoke.err >&2
			exit 1
		fi
		wait "$server_pid"
		server_pid=
		test "$(cat "$prefix/private/var/tmp/x11-backend-close")" = close-requested

		DISPLAY=:92 Xephyr :93 -screen 1280x800 -resizeable -nolisten tcp \
			>/tmp/stage11-xephyr.log 2>&1 &
		xephyr_pid=$!
		for attempt in {1..100}; do
			DISPLAY=:93 xdpyinfo >/dev/null 2>&1 && break
			kill -0 "$xephyr_pid" 2>/dev/null || {
				cat /tmp/stage11-xephyr.log >&2
				exit 1
			}
			sleep 0.05
		done
		DISPLAY=:93 xdpyinfo >/dev/null
		DISPLAY=:93 openbox --sm-disable >/tmp/stage11-inner-openbox.log 2>&1 &
		inner_wm_pid=$!

		prefix=/tmp/darling-prefix-stage11-randr
		mkdir -p "$prefix/dev/pts"
		cp -a /dev/null /dev/urandom "$prefix/dev/"
		mount --bind /dev/pts "$prefix/dev/pts"
		ln -s pts/ptmx "$prefix/dev/ptmx"
		(
			export DISPLAY=:93
			exec 3>/tmp/stage11-randr-ready-fd
			darlingserver "$prefix" 0 0 3 0 \
				>/tmp/stage11-randr.out 2>/tmp/stage11-randr.err
		) &
		server_pid=$!
		exec 3>&-
		ready=$prefix/private/var/tmp/x11-backend-ready
		for attempt in {1..150}; do
			[[ -f $ready ]] && break
			kill -0 "$server_pid" 2>/dev/null || {
				cat /tmp/stage11-randr.err >&2
				exit 1
			}
			sleep 0.1
		done
		test "$(cat "$ready")" = ready
		expected_title=$(printf "Darling ARM64 X11 Smoke \342\200\224 UTF-8")
		inner_window=$(DISPLAY=:93 xdotool search --onlyvisible \
			--name "^$expected_title$" | head -1)
		xephyr_window=$(DISPLAY=:92 xdotool search --onlyvisible \
			--class Xephyr | tail -1)
		test -n "$inner_window"
		test -n "$xephyr_window"
		rm -f "$prefix/private/var/tmp/x11-backend-screen"
		DISPLAY=:92 xdotool windowsize --sync "$xephyr_window" 1024 700 \
			2>/tmp/stage11-xephyr-resize.err
		for attempt in {1..100}; do
			[[ -f $prefix/private/var/tmp/x11-backend-screen ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/x11-backend-screen")" = 1024x700@1
		rm -f "$prefix/private/var/tmp/x11-backend-screen"
		printf "Xft.dpi: 192\n" | DISPLAY=:93 xrdb -merge
		DISPLAY=:92 xdotool windowsize --sync "$xephyr_window" 1000 680 \
			2>/tmp/stage11-xephyr-scale.err
		for attempt in {1..100}; do
			[[ -f $prefix/private/var/tmp/x11-backend-screen ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/x11-backend-screen")" = 1000x680@2
		DISPLAY=:93 xdotool windowactivate --sync "$inner_window"
		DISPLAY=:93 xdotool key alt+F4
		timeout 10s tail --pid="$server_pid" -f /dev/null
		wait "$server_pid"
		server_pid=

		if ps -eo stat=,comm= | awk "\$2 == \"mldr\" && \$1 !~ /^Z/ {found=1} END {exit found ? 0 : 1}"; then
			echo "x11-backend-smoke left a live mldr process" >&2
			exit 1
		fi

		echo "ARM64 X11 backend smoke passed"
	'
