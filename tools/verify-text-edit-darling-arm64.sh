#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
install_root=$workspace_root/install-arm64-stage10
image=darling-arm64-dev:latest
container=darling-arm64-text-edit
artifact_root=$workspace_root/artifacts/stage15-text-edit

if [[ $(uname -m) != aarch64 ]]; then
	echo "This verifier requires a native aarch64 Linux host." >&2
	exit 2
fi
if [[ ! -x $install_root/root/Applications/TextEdit.app/Contents/MacOS/TextEdit ]]; then
	echo "Missing staged TextEdit.app." >&2
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
		command -v xdotool >/dev/null 2>&1 || apt-get install -y -qq imagemagick xvfb openbox xdotool x11-utils \
			libegl1 fonts-dejavu-core >/tmp/stage15-apt.log
		export PATH=/opt/darling/bin:$PATH DISPLAY=:94 LANG=C.UTF-8 LC_ALL=C.UTF-8
		export DARLING_NOOVERLAYFS=1 DYLD_USE_CLOSURES=0
		export DARLING_ARM64_THREAD_BRIDGE=1

		Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp >/tmp/stage15-xvfb.log 2>&1 &
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
			echo "Stage 15 verifier failed (status $status)." >&2
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
		openbox --sm-disable >/tmp/stage15-openbox.log 2>&1 &
		openbox_pid=$!

		prepare_prefix() {
			local prefix=$1
			rm -rf "$prefix"
			mkdir -p "$prefix/dev/pts" "$prefix/private/var/tmp"
			cp -a /dev/null /dev/urandom "$prefix/dev/"
			mount --bind /dev/pts "$prefix/dev/pts"
			ln -s pts/ptmx "$prefix/dev/ptmx"
		}
		wait_for_exit() {
			for attempt in {1..100}; do
				kill -0 "$server_pid" 2>/dev/null || break
				sleep 0.1
			done
			! kill -0 "$server_pid" 2>/dev/null
			wait "$server_pid"
			server_pid=
		}

		first=/tmp/darling-stage15-save
		prepare_prefix "$first"
		export DSERVER_INIT=/Applications/TextEdit.app/Contents/MacOS/TextEdit
		unset DARLING_EXEC_PATH DARLING_EXEC_ARG1 DARLING_EXEC_ARG2
		exec 3>/tmp/stage15-save-ready
		start_ms=$(date +%s%3N)
		darlingserver "$first" 0 0 3 0 >/tmp/stage15-save.out 2>/tmp/stage15-save.err &
		server_pid=$!
		exec 3>&-
		main=
		for attempt in {1..300}; do
			main=$(xdotool search --onlyvisible --name "TextEdit$" 2>/dev/null | head -1 || true)
			[[ -n $main ]] && break
			kill -0 "$server_pid" 2>/dev/null || exit 1
			sleep 0.1
		done
		test -n "$main"
		printf "%s\n" "$(( $(date +%s%3N) - start_ms ))" >/artifacts/save-launch-ms.txt
		xdotool windowactivate --sync "$main"
		xdotool click --window "$main" 1
		xdotool type --delay 35 "North star "
		xdotool key Multi_key apostrophe e
		xdotool key super+s
		sleep 1
		xdotool mousemove 600 579 click 1
		xdotool key ctrl+a
		xdotool type --delay 15 /private/var/tmp/stage15.txt
		xdotool mousemove 825 577 click 1
		for attempt in {1..100}; do
			[[ -f $first/private/var/tmp/stage15.txt ]] && break
			sleep 0.1
		done
		printf "North star \303\251" >/tmp/expected-stage15.txt
		cmp /tmp/expected-stage15.txt "$first/private/var/tmp/stage15.txt"
		cp "$first/private/var/tmp/stage15.txt" /tmp/stage15.txt
		xdotool key super+q
		wait_for_exit

		second=/tmp/darling-stage15-reopen
		prepare_prefix "$second"
		cp /tmp/stage15.txt "$second/private/var/tmp/stage15.txt"
		export DSERVER_INIT=/exec-arguments-darling-arm64
		export DARLING_EXEC_PATH=/Applications/TextEdit.app/Contents/MacOS/TextEdit
		export DARLING_EXEC_ARG1=-NSOpen
		export DARLING_EXEC_ARG2=/private/var/tmp/stage15.txt
		exec 3>/tmp/stage15-reopen-ready
		start_ms=$(date +%s%3N)
		darlingserver "$second" 0 0 3 0 >/tmp/stage15-reopen.out 2>/tmp/stage15-reopen.err &
		server_pid=$!
		exec 3>&-
		main=
		for attempt in {1..300}; do
			main=$(xdotool search --onlyvisible --name "^stage15.txt - TextEdit$" 2>/dev/null | head -1 || true)
			[[ -n $main ]] && break
			kill -0 "$server_pid" 2>/dev/null || exit 1
			sleep 0.1
		done
		test -n "$main"
		printf "%s\n" "$(( $(date +%s%3N) - start_ms ))" >/artifacts/reopen-launch-ms.txt
		test "$(cat "$second/private/var/tmp/textedit-read-content")" = "North star é"
		test "$(cat "$second/private/var/tmp/textedit-window-step")" = ready
		import -window "$main" /artifacts/text-edit-reopen.png
		colors=$(convert /artifacts/text-edit-reopen.png -format "%k" info:)
		((colors > 16))
		printf "%s\n" "$colors" >/artifacts/color-count.txt
		rss_kb=$(ps -o rss= -p "$server_pid")
		((rss_kb < 1572864))
		printf "%s\n" "$rss_kb" >/artifacts/rss-kb.txt
		xdotool windowactivate --sync "$main" key super+q
		wait_for_exit
		echo "ARM64 TextEdit.app milestone passed"
	'
