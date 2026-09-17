#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
install_root=${DARLING_ARM64_INSTALL_ROOT:-$workspace_root/install-arm64-stage10}
image=darling-arm64-dev:latest
container=darling-arm64-pty-harness
artifact_root=$workspace_root/artifacts/stage16-pty-harness

if [[ $(uname -m) != aarch64 ]]; then
	echo "This verifier requires a native aarch64 Linux host." >&2
	exit 2
fi
if [[ ! -x $install_root/root/pty-harness-darling-arm64 ]]; then
	echo "Missing staged PTYHarness." >&2
	exit 2
fi
mkdir -p "$artifact_root"

docker rm -f "$container" >/dev/null 2>&1 || true
docker run --name "$container" --rm \
	--cap-add SYS_ADMIN --cap-add SYS_PTRACE \
	--security-opt apparmor=unconfined --security-opt seccomp=unconfined \
	--pids-limit 512 --memory 2g \
	-v "$install_root/root:/usr/local/libexec/darling:ro" \
	-v "$install_root/bin:/opt/darling/bin:ro" \
	-v "$artifact_root:/artifacts" \
	"$image" bash -lc '
		set -euo pipefail
		export PATH=/opt/darling/bin:$PATH DARLING_NOOVERLAYFS=1
		export DYLD_USE_CLOSURES=0 DARLING_ARM64_THREAD_BRIDGE=0
		export DSERVER_INIT=/pty-harness-darling-arm64
		prefix=/tmp/darling-stage16
		mkdir -p "$prefix/dev/pts"
		cp -a /dev/null /dev/urandom "$prefix/dev/"
		mount --bind /dev/pts "$prefix/dev/pts"
		ln -s pts/ptmx "$prefix/dev/ptmx"
		exec 3>/tmp/stage16-ready
		start_ms=$(date +%s%3N)
		darlingserver "$prefix" 0 0 3 0 >/tmp/stage16.out 2>/tmp/stage16.err &
		server_pid=$!
		exec 3>&-
		peak_rss=0
		while kill -0 "$server_pid" 2>/dev/null; do
			rss=$(ps -o rss= -p "$server_pid" 2>/dev/null || true)
			rss=${rss//[[:space:]]/}
			[[ -z $rss ]] || ((rss <= peak_rss)) || peak_rss=$rss
			sleep 0.05
		done
		wait "$server_pid"
		elapsed_ms=$(( $(date +%s%3N) - start_ms ))
		test "$(cat /tmp/stage16.out)" = \
			"PTYHarness: interactive, resize, termios, UTF-8, multi-session EOF, and 1000 cycles passed"
		((elapsed_ms < 120000))
		((peak_rss < 1048576))
		printf "%s\n" "$elapsed_ms" >/artifacts/elapsed-ms.txt
		printf "%s\n" "$peak_rss" >/artifacts/peak-rss-kb.txt
		cp /tmp/stage16.out /tmp/stage16.err /artifacts/
		if ps -eo comm=,args= | awk '\''$1 == "mldr" {found=1} END {exit found ? 0 : 1}'\''; then
			echo "PTYHarness left a live mldr process" >&2
			exit 1
		fi
		echo "ARM64 PTYHarness milestone passed"
	'
