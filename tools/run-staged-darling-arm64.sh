#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
install_root=${DARLING_ARM64_INSTALL_ROOT:-$workspace_root/install-arm64}
image=${DARLING_ARM64_IMAGE:-darling-arm64-dev:latest}
container=${DARLING_ARM64_CONTAINER:-darling-arm64-staged}
program=${1:-/hello-libsystem-arm64-0}

if [[ $(uname -m) != aarch64 ]]; then
	echo "This runner requires a native aarch64 Linux host." >&2
	exit 2
fi
if [[ ! $program =~ ^/[A-Za-z0-9._/-]+$ ]] || [[ $program == *..* ]]; then
	echo "Program must be an absolute path inside the staged Darling root." >&2
	exit 2
fi
if [[ ! -x $install_root/bin/darlingserver ]] || [[ ! -d $install_root/root ]]; then
	echo "No staged installation at $install_root; run tools/stage-darling-arm64.sh first." >&2
	exit 2
fi

docker rm -f "$container" >/dev/null 2>&1 || true
set +e
	docker run --name "$container" --rm \
	-e DARLING_ARM64_THREAD_BRIDGE="${DARLING_ARM64_THREAD_BRIDGE:-0}" \
	-e DARLING_ARM64_LOOPBACK_SERVER="${DARLING_ARM64_LOOPBACK_SERVER:-0}" \
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
		if [[ $DARLING_ARM64_LOOPBACK_SERVER == 1 ]]; then
			/opt/darling/bin/network-loopback-server-arm64 >/tmp/stage9-server.log 2>&1 &
			server_pid=$!
			for attempt in {1..100}; do
				grep -q ready /tmp/stage9-server.log && break
				kill -0 "$server_pid" 2>/dev/null || {
					cat /tmp/stage9-server.log >&2
					exit 1
				}
				sleep 0.01
			done
			grep -q ready /tmp/stage9-server.log
			export DARLING_STAGE9_PORT=39091
		fi
		export DSERVER_INIT='"$program"'
		exec timeout 15s /opt/darling/bin/darlingserver "$prefix" 0 0 1 0
	'
status=$?
set -e
exit "$status"
