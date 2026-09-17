#!/usr/bin/env bash
# f101-core-capture.sh <N> — zero-perturbation crash capture. No tracing: enable core
# dumps in the probe container (--ulimit core=-1 + core_pattern into /artifacts). On the
# ~93% debug-amplified fail, sigexc's SIG_DFL re-raise produces a core whose NT_SIGINFO
# note carries si_code/si_addr and whose NT_FILE note maps the address to a module.
# Restores the VM core_pattern on exit.
set -u
cd ~/darling/source
N=${1:-3}

orig_pattern=$(cat /proc/sys/kernel/core_pattern)
restore() { printf '%s' "$orig_pattern" | sudo -n tee /proc/sys/kernel/core_pattern >/dev/null; echo "[core_pattern restored]"; }
trap restore EXIT
echo "/artifacts/core.%e.%p" | sudo -n tee /proc/sys/kernel/core_pattern >/dev/null
echo "[core_pattern -> /artifacts/core.%e.%p (was apport pipe)]"

sed -E 's|--name "\$container" --rm|--name "$container" --rm --ulimit core=-1|' \
	tools/probe-iterm2-launch-arm64.sh > tools/f101-tmp-probe2.sh && chmod +x tools/f101-tmp-probe2.sh
grep -q 'ulimit core' tools/f101-tmp-probe2.sh || { echo "probe sed failed"; exit 1; }
sed -E 's|"\$source_root/tools/probe-iterm2-launch-arm64.sh"|"$source_root/tools/f101-tmp-probe2.sh"|' \
	tools/verify-iterm2-silver-tab-close-arm64.sh > tools/f101-tmp-gate2.sh && chmod +x tools/f101-tmp-gate2.sh
grep -q 'f101-tmp-probe2' tools/f101-tmp-gate2.sh || { echo "gate sed failed"; exit 1; }

export ITERM2_SHARED_CACHE_ROOT=~/darling/downloads/macos/26.6/dyld-stage18
export DARLING_STAGE18_ROOT=~/darling/install-arm64-id26
export DARLING_STAGE18_BUILD_ROOT=~/darling/build-arm64-id26
export ITERM2_PROBE_LIFECYCLE_DEBUG=1
A=~/darling/artifacts/stage19-iterm2-silver-tab-close
out=~/darling/f101-core; rm -rf "$out"; mkdir -p "$out"

for ((i=1;i<=N;i++)); do
	sudo -n rm -rf "$A" 2>/dev/null
	docker rm -f darling-arm64-iterm2-launch-probe >/dev/null 2>&1
	echo "[run $i] $(date +%H:%M:%S)"
	tools/f101-tmp-gate2.sh > "$out/run$i.log" 2>&1; rc=$?
	k="$out/run$i"; mkdir -p "$k"
	cp -a "$A/dserver.log" "$k/" 2>/dev/null
	sg=$(grep -c "emulating default signal effects" "$k/dserver.log" 2>/dev/null); sg=${sg:-0}
	ipid=$(grep -oE '\[P:[0-9]+\(13\)\]' "$k/dserver.log" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
	ncores=$(ls "$A"/core.* 2>/dev/null | wc -l); ncores=${ncores:-0}
	sudo -n cp -a "$A"/core.* "$k/" 2>/dev/null; sudo -n chown -R $(id -u):$(id -g) "$k" 2>/dev/null
	echo "  rc=$rc sigexc=$sg iterm2_pid=${ipid:-?} cores=$ncores: $(ls "$A"/core.* 2>/dev/null | xargs -rn1 basename | tr '\n' ' ')"
done
restore; trap - EXIT
echo "CORE CAPTURE COMPLETE"
ls -la "$out"/run*/core.* 2>/dev/null | awk '{print $5, $9}'
