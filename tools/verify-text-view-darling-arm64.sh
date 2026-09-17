#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
install_root=$workspace_root/install-arm64-stage10
image=darling-arm64-dev:latest
container=darling-arm64-text-view
artifact_root=$workspace_root/artifacts/stage14-text-view

if [[ $(uname -m) != aarch64 ]]; then
	echo "This verifier requires a native aarch64 Linux host." >&2
	exit 2
fi
if [[ ! -x $install_root/root/Applications/TextView.app/Contents/MacOS/TextView ]]; then
	echo "Missing staged TextView.app." >&2
	exit 2
fi
mkdir -p "$artifact_root"
rm -rf "$artifact_root/failure-markers"

docker rm -f "$container" >/dev/null 2>&1 || true
docker run --name "$container" --rm \
	-e DEBIAN_FRONTEND=noninteractive \
	--cap-add SYS_ADMIN --cap-add SYS_PTRACE \
	--security-opt apparmor=unconfined --security-opt seccomp=unconfined \
	--pids-limit 512 --memory 4g \
	-v "$install_root/root:/usr/local/libexec/darling:ro" \
	-v "$install_root/bin:/opt/darling/bin:ro" \
	-v "$artifact_root:/artifacts" \
	"$image" bash -lc '
		set -euo pipefail
		command -v xdotool >/dev/null 2>&1 || apt-get update -qq
		command -v xdotool >/dev/null 2>&1 || apt-get install -y -qq imagemagick xvfb openbox xdotool x11-utils \
			xclip libegl1 fonts-dejavu-core >/tmp/stage14-apt.log
		export PATH=/opt/darling/bin:$PATH DISPLAY=:93 LANG=C.UTF-8 LC_ALL=C.UTF-8
		export DARLING_NOOVERLAYFS=1 DYLD_USE_CLOSURES=0
		export DARLING_ARM64_THREAD_BRIDGE=1

		Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp \
			>/tmp/stage14-xvfb.log 2>&1 &
		xvfb_pid=$!
		wm_pid=
		server_pid=
		prefix=
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
			echo "Stage 14 verifier failed near line $LINENO (status $status)." >&2
			cat /tmp/stage14-text-view.err 2>/dev/null >&2 || true
			cp /tmp/stage14-text-view.out /tmp/stage14-text-view.err \
				/tmp/stage14-xvfb.log /tmp/stage14-openbox.log \
				/artifacts/ 2>/dev/null || true
			if [[ -n $prefix && -d $prefix/private/var/tmp ]]; then
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
			kill -0 "$xvfb_pid" 2>/dev/null || exit 1
			sleep 0.05
		done
		xdpyinfo >/dev/null
		openbox --sm-disable >/tmp/stage14-openbox.log 2>&1 &
		wm_pid=$!
		for attempt in {1..100}; do
			xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q WINDOW && break
			kill -0 "$wm_pid" 2>/dev/null || exit 1
			sleep 0.05
		done

		prefix=/tmp/darling-stage14
		mkdir -p "$prefix/dev/pts"
		cp -a /dev/null /dev/urandom "$prefix/dev/"
		mount --bind /dev/pts "$prefix/dev/pts"
		ln -s pts/ptmx "$prefix/dev/ptmx"
		export DSERVER_INIT=/Applications/TextView.app/Contents/MacOS/TextView
		exec 3>/tmp/stage14-ready-fd
		start_ms=$(date +%s%3N)
		darlingserver "$prefix" 0 0 3 0 \
			>/tmp/stage14-text-view.out 2>/tmp/stage14-text-view.err &
		server_pid=$!
		exec 3>&-

		for attempt in {1..300}; do
			[[ -f $prefix/private/var/tmp/text-view-ready ]] && break
			kill -0 "$server_pid" 2>/dev/null || exit 1
			sleep 0.1
		done
		ready_ms=$(date +%s%3N)
		launch_ms=$((ready_ms - start_ms))
		printf "%s\n" "$launch_ms" >/artifacts/launch-ms.txt
		((launch_ms < 30000))
		test "$(cat "$prefix/private/var/tmp/text-view-ready")" = ready
		grep -Fxq "org.darlinghq.north-star.text-view|/Applications/TextView.app" \
			"$prefix/private/var/tmp/text-view-bundle"
		grep -Fxq "550113|unicode|10000" "$prefix/private/var/tmp/text-view-initial"
		test "$(cat "$prefix/private/var/tmp/text-view-layout")" = 550113
		test "$(cat "$prefix/private/var/tmp/text-view-length")" = 550113
		test "$(cat "$prefix/private/var/tmp/text-view-prefix")" = "ASCII baseli"

		main=$(xdotool search --onlyvisible --name "^Darling ARM64 TextView$" |
			head -1)
		test -n "$main"
		xdotool windowactivate --sync "$main"

		sleep 0.6
		xdotool mousemove --sync --window "$main" 1 35 click 1
		for attempt in {1..30}; do
			[[ $(cat "$prefix/private/var/tmp/text-view-selection" 2>/dev/null || true) == 0:0 ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/text-view-selection")" = 0:0
		for key in e d i t; do
			xdotool keydown "$key"
			sleep 0.05
			xdotool keyup "$key"
			sleep 0.05
		done
		for attempt in {1..300}; do
			[[ $(cat "$prefix/private/var/tmp/text-view-length" 2>/dev/null || true) == 550117 ]] && break
			sleep 0.1
		done
		test "$(cat "$prefix/private/var/tmp/text-view-prefix")" = "editASCII ba"
		xdotool key ctrl+z
		for attempt in {1..60}; do
			[[ $(cat "$prefix/private/var/tmp/text-view-length" 2>/dev/null || true) == 550113 ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/text-view-prefix")" = "ASCII baseli"

		xdotool key Home
		xdotool key --repeat 5 shift+Right
		for attempt in {1..30}; do
			[[ $(cat "$prefix/private/var/tmp/text-view-selection" 2>/dev/null || true) == 0:5 ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/text-view-selection")" = 0:5
		xdotool key ctrl+c
		for attempt in {1..30}; do
			[[ $(xclip -selection clipboard -out 2>/dev/null || true) == ASCII ]] &&
				break
			sleep 0.05
		done
		test "$(xclip -selection clipboard -out)" = ASCII
		test "$(cat "$prefix/private/var/tmp/text-view-copy")" = ASCII
		grep -Fq "NSStringPboardType" \
			"$prefix/private/var/tmp/text-view-copy-types"

		xdotool key Right
		xdotool key ctrl+v
		for attempt in {1..60}; do
			[[ $(cat "$prefix/private/var/tmp/text-view-length" 2>/dev/null || true) == 550118 ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/text-view-prefix")" = "ASCIIASCII b"
		xdotool key ctrl+z
		for attempt in {1..60}; do
			[[ $(cat "$prefix/private/var/tmp/text-view-length" 2>/dev/null || true) == 550113 ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/text-view-length")" = 550113

		xdotool key Home
		xdotool key super+Right
		word_location=$(cut -d: -f1 "$prefix/private/var/tmp/text-view-selection")
		((word_location > 0 && word_location < 20))

		rm -f "$prefix/private/var/tmp/text-view-scroll"
		xdotool key ctrl+End
		for attempt in {1..100}; do
			[[ -f $prefix/private/var/tmp/text-view-scroll ]] && break
			sleep 0.05
		done
		scroll_y=$(cat "$prefix/private/var/tmp/text-view-scroll")
		[[ $scroll_y =~ ^[0-9]+$ ]]
		((scroll_y > 100000))
		printf "%s\n" "$scroll_y" >/artifacts/scroll-y.txt

		import -window "$main" /artifacts/text-view.png
		colors=$(convert /artifacts/text-view.png -format "%k" info:)
		((colors > 16))
		printf "%s\n" "$colors" >/artifacts/color-count.txt
		rss_kb=$(ps -o rss= -p "$server_pid")
		((rss_kb < 1572864))
		printf "%s\n" "$rss_kb" >/artifacts/rss-kb.txt

		xdotool key alt+F4
		timeout 10s tail --pid="$server_pid" -f /dev/null
		wait "$server_pid"
		server_pid=
		test "$(cat "$prefix/private/var/tmp/text-view-close")" = close-requested
		if ps -eo comm=,args= | awk "\$1 == \"mldr\" && \$2 == \"/Applications/TextView.app/Contents/MacOS/TextView\" {found=1} END {exit found ? 0 : 1}"; then
			echo "TextView.app left a live mldr process" >&2
			exit 1
		fi
		echo "ARM64 TextView.app milestone passed"
	'
