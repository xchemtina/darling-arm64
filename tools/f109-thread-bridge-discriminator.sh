#!/usr/bin/env bash
# f109-thread-bridge-discriminator.sh <N> [label] — F102's ZERO-BUILD discriminator.
# A/B/A over ONE variable: DARLING_ARM64_THREAD_BRIDGE (1 = the probe's default, broker
# created in the fork child; 0 = no broker). F102 predicts mode B (the forked session
# child aborting in sigexc_handler on the broker thread) must vanish at 0.
# The flag is flipped at ALL EIGHT sites (probe:463 + the seven generated launchd plists) in
# a TEMPORARY COPY of the probe, called by a TEMPORARY COPY of the gate — Kevin's files are
# never edited. Cores are captured into the artifact dir (f101/f104 trick) because cores are
# how F102 identified mode B. Every run's artifacts are kept (F108).
set -u
W=$HOME/darling
S=$W/source
cd "$S"
N=${1:-2}
LABEL=${2:-disc}
out=$W/f109-thread-bridge/$LABEL; mkdir -p "$out"
A=$W/artifacts/stage19-iterm2-silver-tab-close
export ITERM2_SHARED_CACHE_ROOT=$W/downloads/macos/26.6/dyld-stage18
export DARLING_STAGE18_ROOT=$W/install-arm64-f103 DARLING_STAGE18_BUILD_ROOT=$W/build-arm64-f103
unset ITERM2_PROBE_LIFECYCLE_DEBUG

orig_pattern=$(cat /proc/sys/kernel/core_pattern)
restore() {
	printf '%s' "$orig_pattern" | sudo -n tee /proc/sys/kernel/core_pattern >/dev/null
	rm -f tools/f109-tmp-probe.sh tools/f109-tmp-gate.sh
}
trap restore EXIT
echo "/artifacts/core.%e.%p" | sudo -n tee /proc/sys/kernel/core_pattern >/dev/null

make_probe() {   # $1 = bridge value (1|0); writes tools/f109-tmp-probe.sh + tools/f109-tmp-gate.sh
	local v=$1 n1 n0 p1 p0
	sed -E -e 's|--name "\$container" --rm|--name "$container" --rm --ulimit core=-1|' \
		-e "s|DARLING_ARM64_THREAD_BRIDGE=1|DARLING_ARM64_THREAD_BRIDGE=$v|" \
		-e "s|\"DARLING_ARM64_THREAD_BRIDGE\": \"1\"|\"DARLING_ARM64_THREAD_BRIDGE\": \"$v\"|" \
		tools/probe-iterm2-launch-arm64.sh > tools/f109-tmp-probe.sh
	chmod +x tools/f109-tmp-probe.sh
	n1=$(grep -c 'DARLING_ARM64_THREAD_BRIDGE=1' tools/f109-tmp-probe.sh)
	n0=$(grep -c 'DARLING_ARM64_THREAD_BRIDGE=0' tools/f109-tmp-probe.sh)
	p1=$(grep -c '"DARLING_ARM64_THREAD_BRIDGE": "1"' tools/f109-tmp-probe.sh)
	p0=$(grep -c '"DARLING_ARM64_THREAD_BRIDGE": "0"' tools/f109-tmp-probe.sh)
	echo "  probe copy for bridge=$v: export sites 1/0 = $n1/$n0, plist sites 1/0 = $p1/$p0 (must be 1 export + 7 plists on the '$v' side)"
	if [[ $v == 1 ]]; then (( n1==1 && p1==7 && n0==0 && p0==0 )) || { echo "  FLIP INCOMPLETE — refusing to run a contaminated arm"; exit 1; }
	else                   (( n0==1 && p0==7 && n1==0 && p1==0 )) || { echo "  FLIP INCOMPLETE — refusing to run a contaminated arm"; exit 1; }; fi
	grep -q 'ulimit core' tools/f109-tmp-probe.sh || { echo "ulimit sed failed"; exit 1; }
	sed -e 's|tools/probe-iterm2-launch-arm64.sh|tools/f109-tmp-probe.sh|' \
		tools/verify-iterm2-silver-tab-close-arm64.sh > tools/f109-tmp-gate.sh
	chmod +x tools/f109-tmp-gate.sh
	grep -q 'f109-tmp-probe' tools/f109-tmp-gate.sh || { echo "gate sed failed"; exit 1; }
}

run_arm() {   # $1 arm label, $2 bridge value
	local arm=$1 v=$2 pass=0 fail=0 i rc k cores st
	make_probe "$v"
	mkdir -p "$out/$arm"
	echo "[arm $arm] THREAD_BRIDGE=$v N=$N $(date +%H:%M:%S)"
	for ((i=1;i<=N;i++)); do
		sudo -n rm -rf "$A" 2>/dev/null
		docker rm -f darling-arm64-iterm2-launch-probe >/dev/null 2>&1
		tools/f109-tmp-gate.sh > "$out/$arm/run$i.log" 2>&1; rc=$?
		if (( rc==0 )); then pass=$((pass+1)); st=pass; else fail=$((fail+1)); st=FAIL; fi
		k="$out/$arm/run$i-artifacts"; mkdir -p "$k"
		sudo -n cp -a "$A/." "$k/" 2>/dev/null; sudo -n chown -R "$(id -u):$(id -g)" "$k" 2>/dev/null
		cp /tmp/iterm2-silver-tab-close.log "$out/$arm/run$i-probe.log" 2>/dev/null || true
		cores=$(ls "$k"/core.* 2>/dev/null | wc -l)
		echo "$i $st rc=$rc cores=$cores $(ls "$k"/core.* 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ') $( (( rc!=0 )) && tail -1 "$out/$arm/run$i.log" | sed 's/.*evidence: //')" >> "$out/$arm/log.txt"
		printf "\r  [%s] %d/%d pass=%d fail=%d cores=%s   " "$arm" "$i" "$N" "$pass" "$fail" "$cores"
	done
	echo
}

run_arm A1 1
run_arm B  0
run_arm A2 1

echo
echo "===== F109 SUMMARY (label=$LABEL, N=$N per arm) — artifacts in $out ====="
for arm in A1 B A2; do
	printf "  %-3s pass=%-3s fail=%-3s runs-with-cores=%-3s mldr-cores=%-3s | fail modes: %s\n" "$arm" \
		"$(grep -c ' pass ' "$out/$arm/log.txt")" "$(grep -c FAIL "$out/$arm/log.txt")" \
		"$(grep -c 'cores=[1-9]' "$out/$arm/log.txt")" "$(grep -o 'core\.mldr\.[0-9]*' "$out/$arm/log.txt" | wc -l)" \
		"$(grep FAIL "$out/$arm/log.txt" | grep -oE 'silver-[a-z0-9-]+\.txt' | sort | uniq -c | tr '\n' ' ')"
done
echo "F109 COMPLETE $(date +%H:%M:%S)"
