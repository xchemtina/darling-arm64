#!/usr/bin/env bash
# f101-realworld.sh <N> <label> — the REAL-WORLD check: the Silver tab-close gate with
# NO debug amplifier, on id26. Compares against the historical ~13% no-debug flake rate.
set -u
cd ~/darling/source
export ITERM2_SHARED_CACHE_ROOT=~/darling/downloads/macos/26.6/dyld-stage18
export DARLING_STAGE18_ROOT=~/darling/install-arm64-id26
export DARLING_STAGE18_BUILD_ROOT=~/darling/build-arm64-id26
unset ITERM2_PROBE_LIFECYCLE_DEBUG
N=${1:-15}; LABEL=${2:-realworld}
A=~/darling/artifacts/stage19-iterm2-silver-tab-close
out=~/darling/f101-realworld/$LABEL; rm -rf "$out"; mkdir -p "$out"
pass=0; fail=0
echo "REALWORLD [$LABEL] START $(date +%H:%M:%S) N=$N (no debug amplifier)"
for ((i=1;i<=N;i++)); do
	sudo -n rm -rf "$A" 2>/dev/null
	docker rm -f darling-arm64-iterm2-launch-probe >/dev/null 2>&1
	tools/verify-iterm2-silver-tab-close-arm64.sh > "$out/run$i.log" 2>&1; rc=$?
	if (( rc==0 )); then pass=$((pass+1)); st=pass; else fail=$((fail+1)); st=FAIL; fi
	# F108: preserve evidence of a failing run BEFORE the next iteration destroys it.
	# The gate overwrites /tmp/iterm2-silver-tab-close.log every run and this loop
	# rm -rf's $A; until now iterm2-job.err (~34 KB) died seconds after every failure.
	if (( rc!=0 )); then
		cp /tmp/iterm2-silver-tab-close.log "$out/run$i-probe.log" 2>/dev/null || true
		sudo -n mv "$A" "$out/run$i-artifacts" 2>/dev/null \
		&& sudo -n chown -R "$(id -u):$(id -g)" "$out/run$i-artifacts" || true
	fi
	echo "$i $st rc=$rc $( (( rc!=0 )) && tail -1 "$out/run$i.log" | sed 's/.*evidence: //')" >> "$out/log.txt"
	printf "\r[%s] %d/%d pass=%d fail=%d   " "$LABEL" "$i" "$N" "$pass" "$fail"
done
echo
python3 - "$pass" "$fail" "$N" "$LABEL" <<'PY'
import sys,math
p,f,n,label=int(sys.argv[1]),int(sys.argv[2]),int(sys.argv[3]),sys.argv[4]
rate=f/n if n else 0; z=1.96; den=1+z*z/n
c=(rate+z*z/(2*n))/den; h=(z*math.sqrt(rate*(1-rate)/n+z*z/(4*n*n)))/den
print(f"REALWORLD [{label}] n={n} pass={p} fail={f} fail-rate={rate*100:.0f}% 95% CI [{max(0,c-h)*100:.0f}%, {min(1,c+h)*100:.0f}%]")
PY
echo "[$LABEL] DONE $(date +%H:%M:%S)"
