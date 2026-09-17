#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
install_root=$workspace_root/install-arm64-stage10
image=darling-arm64-dev:latest
container=darling-arm64-mini-term
artifact_root=$workspace_root/artifacts/stage17-mini-term

if [[ $(uname -m) != aarch64 ]]; then
	echo "This verifier requires a native aarch64 Linux host." >&2
	exit 2
fi
if [[ ! -x $install_root/root/Applications/MiniTerm.app/Contents/MacOS/MiniTerm ]]; then
	echo "Missing staged MiniTerm.app." >&2
	exit 2
fi
mkdir -p "$artifact_root"

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
		command -v xdotool >/dev/null 2>&1 || apt-get install -y -qq imagemagick xvfb openbox xdotool x11-utils xclip \
			libegl1 fonts-dejavu-core >/tmp/stage17-apt.log
		export PATH=/opt/darling/bin:$PATH DISPLAY=:97 LANG=C.UTF-8 LC_ALL=C.UTF-8
		export DARLING_NOOVERLAYFS=1 DYLD_USE_CLOSURES=0 DARLING_ARM64_THREAD_BRIDGE=1

		Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp >/tmp/stage17-xvfb.log 2>&1 &
		xvfb_pid=$!
		openbox_pid=
		server_pid=
		cleanup() {
			# DARLING-ARM64 LOCAL DIAGNOSTIC: preserve application output.
			# /artifacts is bind-mounted and survives the container; /tmp is not.
			# Done from the EXIT trap so logs survive timeouts as well as failures.
			for _f in /tmp/stage*.err /tmp/stage*.out; do
				[ -s "$_f" ] && cp "$_f" /artifacts/ 2>/dev/null || true
			done
			cp /tmp/stage17.err /artifacts/darlingserver.err 2>/dev/null || true
			cp /tmp/stage17.out /artifacts/darlingserver.out 2>/dev/null || true
			if [[ -n ${prefix:-} ]]; then
				cp "$prefix/private/var/tmp/mini-term-output" /artifacts/last-output.txt 2>/dev/null || true
				cp "$prefix/private/var/tmp/mini-term-copy" /artifacts/app-copy.txt 2>/dev/null || true
				cp "$prefix/private/var/tmp/mini-term-paste" /artifacts/app-paste.txt 2>/dev/null || true
			fi
			[[ -z $server_pid ]] || kill "$server_pid" 2>/dev/null || true
			[[ -z $openbox_pid ]] || kill "$openbox_pid" 2>/dev/null || true
			kill "$xvfb_pid" 2>/dev/null || true
		}
		trap cleanup EXIT
		# DARLING-ARM64 LOCAL DIAGNOSTIC: name the failing command.
		# In a bash ERR trap, ${BASH_LINENO[0]} does NOT track $BASH_COMMAND --
		# stage 11 blamed the wrong command for days (STATE.md trap 7). Print
		# the command itself. Status 124 always means a timeout expired.
		failure() {
			local status=$?
			echo "Stage 17 verifier failed (status $status)." >&2
			echo "  failing command: ${BASH_COMMAND}" >&2
			echo "  markers in the CURRENT prefix (not proof about earlier phases):" >&2
			ls -1 "${prefix:-/nonexistent}/private/var/tmp" 2>/dev/null \
				| sed "s/^/    /" >&2 || true
			return "$status"
		}
		trap failure ERR
		for attempt in {1..100}; do
			xdpyinfo >/dev/null 2>&1 && break
			sleep 0.05
		done
		xdpyinfo >/dev/null
		openbox --sm-disable >/tmp/stage17-openbox.log 2>&1 &
		openbox_pid=$!

		prefix=/tmp/darling-stage17
		rm -rf "$prefix"
		mkdir -p "$prefix/dev/pts" "$prefix/private/var/tmp"
		cp -a /dev/null /dev/urandom "$prefix/dev/"
		mount --bind /dev/pts "$prefix/dev/pts"
		ln -s pts/ptmx "$prefix/dev/ptmx"
		export DSERVER_INIT=/Applications/MiniTerm.app/Contents/MacOS/MiniTerm
		exec 3>/tmp/stage17-ready
		start_ms=$(date +%s%3N)
		darlingserver "$prefix" 0 0 3 0 >/tmp/stage17.out 2>/tmp/stage17.err &
		server_pid=$!
		exec 3>&-
		window=
		for attempt in {1..300}; do
			window=$(xdotool search --onlyvisible --name "^Darling ARM64 MiniTerm$" 2>/dev/null | head -1 || true)
			[[ -n $window ]] && break
			kill -0 "$server_pid" 2>/dev/null || exit 1
			sleep 0.05
		done
		test -n "$window"
		launch_ms=$(( $(date +%s%3N) - start_ms ))
		test "$launch_ms" -lt 10000
		printf "%s\n" "$launch_ms" >/artifacts/launch-ms.txt
		xdotool windowactivate --sync "$window"

		type_command() {
			xdotool type --delay 5 --clearmodifiers "$1"
			xdotool key Return
		}
		wait_for_output() {
			local pattern=$1
			for attempt in {1..400}; do
				[[ -f $prefix/private/var/tmp/mini-term-output ]] && \
					grep -q "$pattern" "$prefix/private/var/tmp/mini-term-output" && return 0
				kill -0 "$server_pid" 2>/dev/null || return 1
				sleep 0.05
			done
			return 1
		}

		# DARLING-ARM64 TEST (FINDINGS.md F25): wait for the shell prompt before
		# the first keystroke. Without this the first characters race the prompt
		# and corrupt line 0 of the terminal buffer.
		for attempt in {1..400}; do
			[[ -f $prefix/private/var/tmp/mini-term-output ]] && \
				grep -q "north-star\$" "$prefix/private/var/tmp/mini-term-output" && break
			sleep 0.05
		done
		type_command "echo STAGE17_COMMAND_OK"
		wait_for_output "^STAGE17_COMMAND_OK[[:space:]]*$"
		echo command >/artifacts/checkpoint.txt
		type_command "printf \"\\342\\234\\223 WIDE:\\344\\270\\255 COMB:e\\314\\201\\n\""
		unicode_pattern=$(printf "WIDE:\344\270\255 COMB:e\314\201")
		wait_for_output "$unicode_pattern"
		echo unicode >/artifacts/checkpoint.txt

		type_command "printf \"\\033[31mC16 \\033[38;5;202mC256 \\033[38;2;12;200;90mCTRUE\\033[0m\\n\""
		wait_for_output "C16 C256 CTRUE"
		echo colors-output >/artifacts/checkpoint.txt
		sleep 0.2
		import -window "$window" /artifacts/colors.png
		color_count=$(convert /artifacts/colors.png -format %c histogram:info:- | wc -l)
		test "$color_count" -ge 32
		printf "%s\n" "$color_count" >/artifacts/color-count.txt

		type_command "printf \"ABCDE\\rXY\\033[K\\nERASE_OK\\n\""
		wait_for_output "^XY[[:space:]]*$"
		! grep -q "XYCDE" "$prefix/private/var/tmp/mini-term-output"
		rm -f "$prefix/private/var/tmp/mini-term-alt-enter" \
			"$prefix/private/var/tmp/mini-term-alt-exit"
		type_command "/usr/bin/terminal-size --alternate-screen"
		wait_for_output "AFTER_ALT_OK"
		test "$(cat "$prefix/private/var/tmp/mini-term-alt-enter")" = seen
		test "$(cat "$prefix/private/var/tmp/mini-term-alt-exit")" = seen
		! grep -q "ALT_SCREEN_OK" "$prefix/private/var/tmp/mini-term-output"

		rm -f "$prefix/private/var/tmp/mini-term-size"
		xdotool windowsize "$window" 1000 650
		for attempt in {1..200}; do
			[[ -f $prefix/private/var/tmp/mini-term-size ]] && break
			sleep 0.05
		done
		size=$(cat "$prefix/private/var/tmp/mini-term-size")
		columns=${size%x*}; rows=${size#*x}
		type_command "/usr/bin/terminal-size"
		wait_for_output "^$rows $columns[[:space:]]*$"
		printf "%s\n" "$size" >/artifacts/terminal-size.txt

		xdotool key --repeat 6 shift+Right
		for attempt in {1..100}; do
			[[ $(cat "$prefix/private/var/tmp/mini-term-selection" 2>/dev/null || true) == "{0, 6}" ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/mini-term-selection")" = "{0, 6}"
		import -window "$window" /artifacts/selection.png
		rm -f "$prefix/private/var/tmp/mini-term-paste"
		xdotool windowactivate --sync "$window"
		xdotool key ctrl+v
		xdotool key Return
		for attempt in {1..100}; do
			[[ -f $prefix/private/var/tmp/mini-term-paste ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/mini-term-paste")" = paste
		wait_for_output "^north-star\\\$ Cannot[[:space:]]*$"
		for attempt in {1..100}; do
			xclip -selection clipboard -o >/artifacts/clipboard.txt 2>/dev/null || true
			grep -q "^Cannot$" /artifacts/clipboard.txt && break
			sleep 0.05
		done
		grep -q "^Cannot$" /artifacts/clipboard.txt

		mldr_pid=$(pgrep -x mldr | head -1)
		rss_before=$(awk "/VmRSS:/ { print \$2 }" "/proc/$mldr_pid/status")
		type_command "i=0; while [ \$i -lt 10000 ]; do echo SCROLL_\$i; i=\$((i+1)); done"
		wait_for_output "SCROLL_9999"
		rss_after=$(awk "/VmRSS:/ { print \$2 }" "/proc/$mldr_pid/status")
		test "$rss_after" -lt 262144
		test $((rss_after - rss_before)) -lt 131072
		printf "%s %s\n" "$rss_before" "$rss_after" >/artifacts/rss-kib.txt

		xdotool key ctrl+d
		for attempt in {1..200}; do
			[[ -f $prefix/private/var/tmp/mini-term-shell-status ]] && break
			sleep 0.05
		done
		test "$(cat "$prefix/private/var/tmp/mini-term-shell-status")" = exit:0
		for attempt in {1..200}; do
			kill -0 "$server_pid" 2>/dev/null || break
			sleep 0.05
		done
		! kill -0 "$server_pid" 2>/dev/null
		wait "$server_pid"
		server_pid=
		! pgrep -x mldr >/dev/null
		! grep -Eq "SIGSEGV|overwriting existing saved reply|terminate called|core dumped" /tmp/stage17.err
		cp /tmp/stage17.err /artifacts/darlingserver.err
		echo "ARM64 MiniTerm milestone passed"
	'
