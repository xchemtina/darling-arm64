#!/usr/bin/env bash
# f103-stage18-ab.sh <N> — the honest real-world A/B for the F101 wait-timer fix, on a
# COPY of the reviewed stage18 runtime (install-arm64-stage18 is never modified).
# Arm 1 = unpatched control, Arm 2 = patched. No debug amplifier. Same root, one variable.
set -u
W=$HOME/darling
S=$W/source
N=${1:-15}
IROOT=$W/install-arm64-f103
BROOT=$W/build-arm64-f103
out=$W/f103-stage18-ab-n${N}; rm -rf "$out"; mkdir -p "$out"
cd "$S"

# ---------- phase 0: faithful copies of the reviewed pair ----------
if [[ ! -d $IROOT ]]; then
	echo "[copy] install-arm64-stage18 -> $(basename "$IROOT") ($(date +%H:%M:%S))"
	sudo -n rm -rf "$IROOT" 2>/dev/null
	sudo -n cp -a "$W/install-arm64-stage18" "$IROOT" || { echo "install copy FAILED"; exit 1; }
fi
if [[ ! -d $BROOT ]]; then
	echo "[copy] build-arm64-stage18 -> $(basename "$BROOT") (6.1G, be patient) ($(date +%H:%M:%S))"
	sudo -n cp -a "$W/build-arm64-stage18" "$BROOT" || { echo "build copy FAILED"; exit 1; }
	sudo -n chown -R "$(id -u):$(id -g)" "$BROOT"
fi
echo "[copy] done $(date +%H:%M:%S); install=$(sudo -n du -sh "$IROOT" | cut -f1) build=$(du -sh "$BROOT" | cut -f1)"

build_ds() {   # rebuild darlingserver from CURRENT source into the f103 pair
	docker run --rm --platform linux/arm64 \
		-v "$S:/work/source:ro" -v "$BROOT:/work/build" \
		darling-arm64-dev:24.04 bash -lc "cd /work/build && ninja darlingserver" >"$out/build-$1.log" 2>&1 \
		|| { echo "  BUILD FAILED ($1); tail:"; tail -5 "$out/build-$1.log"; return 1; }
	sudo -n cp -a "$BROOT/src/external/darlingserver/darlingserver" "$IROOT/bin/darlingserver"
	echo "  built+staged ($1): mtime $(stat -c %y "$IROOT/bin/darlingserver" | cut -d. -f1)"
}

run_arm() {    # $1 label — N no-debug full-gate runs on the f103 root
	local label=$1 pass=0 fail=0 i rc
	local A=$W/artifacts/stage19-iterm2-silver-tab-close
	mkdir -p "$out/$label"
	export ITERM2_SHARED_CACHE_ROOT=$W/downloads/macos/26.6/dyld-stage18
	export DARLING_STAGE18_ROOT=$IROOT DARLING_STAGE18_BUILD_ROOT=$BROOT
	unset ITERM2_PROBE_LIFECYCLE_DEBUG
	echo "[arm:$label] START $(date +%H:%M:%S) N=$N (no debug amplifier)"
	for ((i=1;i<=N;i++)); do
		sudo -n rm -rf "$A" 2>/dev/null
		docker rm -f darling-arm64-iterm2-launch-probe >/dev/null 2>&1
		tools/verify-iterm2-silver-tab-close-arm64.sh > "$out/$label/run$i.log" 2>&1; rc=$?
		if (( rc==0 )); then pass=$((pass+1)); st=pass; else fail=$((fail+1)); st=FAIL; fi
		# F108: preserve evidence of a failing run BEFORE the next iteration destroys it.
		# The gate overwrites /tmp/iterm2-silver-tab-close.log every run and this loop
		# rm -rf's $A; until now iterm2-job.err (~34 KB) died seconds after every failure.
		if (( rc!=0 )); then
			cp /tmp/iterm2-silver-tab-close.log "$out/$label/run$i-probe.log" 2>/dev/null || true
			sudo -n mv "$A" "$out/$label/run$i-artifacts" 2>/dev/null \
				&& sudo -n chown -R "$(id -u):$(id -g)" "$out/$label/run$i-artifacts" || true
		fi
		echo "$i $st rc=$rc $( (( rc!=0 )) && tail -1 "$out/$label/run$i.log" | sed 's/.*evidence: //')" >> "$out/$label/log.txt"
		printf "\r  [%s] %d/%d pass=%d fail=%d   " "$label" "$i" "$N" "$pass" "$fail"
	done
	echo
	python3 - "$pass" "$fail" "$N" "$label" <<'PY'
import sys,math
p,f,n,label=int(sys.argv[1]),int(sys.argv[2]),int(sys.argv[3]),sys.argv[4]
rate=f/n; z=1.96; den=1+z*z/n
c=(rate+z*z/(2*n))/den; h=(z*math.sqrt(rate*(1-rate)/n+z*z/(4*n*n)))/den
print(f"  RESULT [{label}] n={n} pass={p} fail={f} fail-rate={rate*100:.0f}% 95% CI [{max(0,c-h)*100:.0f}%, {min(1,c+h)*100:.0f}%]")
PY
}

# ---------- arm 1: unpatched control ----------
python3 ~/fix-stale-wait-timer.py --revert >/dev/null 2>&1
echo "[arm:control] fix present in source: $(grep -c 'F101 stale wait timer' src/external/darlingserver/duct-tape/src/thread.c)  (expect 0)"
build_ds control || exit 1
run_arm control

# ---------- arm 2: patched ----------
python3 ~/fix-stale-wait-timer.py >/dev/null 2>&1
echo "[arm:patched] fix present in source: $(grep -c 'F101 stale wait timer' src/external/darlingserver/duct-tape/src/thread.c)  (expect 1)"
build_ds patched || exit 1
run_arm patched

echo
echo "===== F103 SUMMARY (reviewed-runtime copy, no debug amplifier) ====="
for a in control patched; do
	printf "  %-8s pass=%s fail=%s | modes: tab1=%s tab2=%s close=%s\n" "$a" \
		"$(grep -c ' pass ' "$out/$a/log.txt")" "$(grep -c FAIL "$out/$a/log.txt")" \
		"$(grep -c tab1-pid "$out/$a/log.txt")" "$(grep -c tab2-pid "$out/$a/log.txt")" \
		"$(grep -c survivor-pid "$out/$a/log.txt")"
done
echo "F103 COMPLETE $(date +%H:%M:%S)"
