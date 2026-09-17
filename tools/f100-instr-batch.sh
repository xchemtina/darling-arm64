#!/usr/bin/env bash
# f100-instr-batch.sh — instrumented confirmation campaign. tab1+tab2 spawns for exposure,
# NO debug spam (PSYNCH_INSTR is error-level, always captured). Aggregates mint / claim-REJECT
# (the stranded-grant smoking gun) and pass/fail. Archives any run with a mint/reject/fail.
set -u
cd ~/darling/source
export ITERM2_SHARED_CACHE_ROOT=~/darling/downloads/macos/26.6/dyld-stage18
export DARLING_STAGE18_ROOT=~/darling/install-arm64-id26
export DARLING_STAGE18_BUILD_ROOT=~/darling/build-arm64-id26
N=${1:-50}
A=~/darling/artifacts/f100-instr
out=~/darling/f100-instr; rm -rf "$out"; mkdir -p "$out"
pass=0; fail=0; mint=0; reject=0
for ((i=1;i<=N;i++)); do
	sudo -n rm -rf "$A" 2>/dev/null; mkdir -p "$A"
	docker rm -f darling-arm64-iterm2-launch-probe >/dev/null 2>&1
	env ITERM2_PROBE_ARTIFACTS="$A" ITERM2_PROBE_WAIT_SECONDS=30 ITERM2_PROBE_SHARED_CACHE=1 \
		ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1 ITERM2_PROBE_FULL_LAUNCHD=1 ITERM2_PROBE_APPKIT_BOOTSTRAP=1 \
		ITERM2_PROBE_APPKIT_REOPEN=1 ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY=1 ITERM2_PROBE_DIRECT_PTY=1 \
		ITERM2_PROBE_STABLE_KEYBOARD_SOURCE=1 ITERM2_PROBE_OPAQUE_TEXT=1 ITERM2_PROBE_DISABLE_METAL=1 \
		ITERM2_PROBE_TAB_WORKFLOW=1 ITERM2_PROBE_TAB_CLOSE_WORKFLOW=1 \
		ITERM2_PROBE_TYPE_TEXT='printf %s $$ >/artifacts/silver-tab1-pid.txt;printf ready >/artifacts/silver-tab1-ready.txt' \
		ITERM2_PROBE_QUIT_DIALOG=0 ITERM2_PROBE_APPLE_LSD=0 ITERM2_PROBE_APPLE_MDS=0 \
		tools/probe-iterm2-launch-arm64.sh > "$A/probe.log" 2>&1
	rc=$?
	m=$(grep -c "PSYNCH_INSTR mint" "$A/dserver.log" 2>/dev/null); m=${m:-0}
	rj=$(grep -c "PSYNCH_INSTR claim-REJECT" "$A/dserver.log" 2>/dev/null); rj=${rj:-0}
	if [[ -s "$A/shell-ready.txt" && $rc -eq 0 ]]; then st=pass; pass=$((pass+1)); else st=FAIL; fail=$((fail+1)); fi
	mint=$((mint+m)); reject=$((reject+rj))
	echo "$i $st rc=$rc mint=$m reject=$rj" >> "$out/log.txt"
	if [[ $m -gt 0 || $rj -gt 0 || $st == FAIL ]]; then
		k=$out/$st-$i-m${m}-r${rj}; mkdir -p "$k"; cp -a "$A/dserver.log" "$A/probe.log" "$k/" 2>/dev/null
	fi
	printf "\r[instr] %d/%d pass=%d fail=%d MINT=%d REJECT=%d   " "$i" "$N" "$pass" "$fail" "$mint" "$reject"
done
echo
echo "instr batch: pass=$pass fail=$fail total-mints=$mint total-rejects=$reject in $N runs"
echo "== any mint/claim lines captured =="
grep -h "PSYNCH_INSTR mint\|PSYNCH_INSTR claim" "$out"/*/dserver.log 2>/dev/null | sort | uniq -c | head -20
