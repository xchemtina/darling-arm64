#!/usr/bin/env bash
# f100-gate-aba.sh <N> <label> — run the real Silver tab-close gate under DSERVER debug
# on id26 (debug logging is the reliable flake amplifier), report fail rate + Wilson CI.
# One phase of the A/B/A: baseline / patched / restore.
set -u
cd ~/darling/source
export ITERM2_SHARED_CACHE_ROOT=~/darling/downloads/macos/26.6/dyld-stage18
export DARLING_STAGE18_ROOT=~/darling/install-arm64-id26
export DARLING_STAGE18_BUILD_ROOT=~/darling/build-arm64-id26
export ITERM2_PROBE_LIFECYCLE_DEBUG=1
N=${1:-14}; LABEL=${2:-baseline}
A=~/darling/artifacts/stage19-iterm2-silver-tab-close
out=~/darling/f100-gate-aba/$LABEL; rm -rf "$out"; mkdir -p "$out"
pass=0; fail=0
echo "GATE-ABA [$LABEL] START $(date +%H:%M:%S) N=$N binary-mtime=$(stat -c %y "$DARLING_STAGE18_ROOT/bin/darlingserver" | cut -d. -f1)"
for ((i=1;i<=N;i++)); do
	sudo -n rm -rf "$A" 2>/dev/null
	docker rm -f darling-arm64-iterm2-launch-probe >/dev/null 2>&1
	tools/verify-iterm2-silver-tab-close-arm64.sh > "$out/run$i.log" 2>&1
	rc=$?
	if (( rc==0 )); then pass=$((pass+1)); st=pass; else fail=$((fail+1)); st=FAIL; fi
	echo "$i $st rc=$rc $( (( rc!=0 )) && tail -1 "$out/run$i.log" | sed 's/.*evidence: //')" >> "$out/log.txt"
	printf "\r[%s] %d/%d pass=%d fail=%d failrate=%.0f%%   " "$LABEL" "$i" "$N" "$pass" "$fail" "$(awk "BEGIN{print ($fail/$i)*100}")"
done
echo
python3 - "$pass" "$fail" "$N" "$LABEL" <<'PY'
import sys,math
p,f,n,label=int(sys.argv[1]),int(sys.argv[2]),int(sys.argv[3]),sys.argv[4]
rate=f/n if n else 0; z=1.96; den=1+z*z/n
c=(rate+z*z/(2*n))/den; h=(z*math.sqrt(rate*(1-rate)/n+z*z/(4*n*n)))/den
print(f"GATE-ABA [{label}] n={n} fail={f} fail-rate={rate*100:.0f}% 95% Wilson CI [{max(0,c-h)*100:.0f}%, {min(1,c+h)*100:.0f}%]")
PY
echo "[$LABEL] DONE $(date +%H:%M:%S)"
