#!/usr/bin/env bash
# F95: the identity experiment. Build the reviewed tree + f89 leak fix with
# DARLING_EMULATED_OS_PRODUCT_VERSION=26.5 (matching the author's environment,
# F93), in ISOLATED roots, then run the full tier and one 30-minute soak.
#
# Hypotheses under test (F93's consequences):
#   H1  the ~13% Silver flake is legacy-path-specific -> shrinks or vanishes on 26.5
#   H2  the mid-soak window vanish (6/12) is legacy-path-specific
#   H3  the quit dialog IS created on 26.5 (his workload logs show it working)
#   H4  with f89, soak RSS growth stays far under the 512 MB ceiling
# Two variables deliberately combined (identity + leak fix): the fix is
# ABA-cleared for no-regression, and this is the candidate "matches-his-world"
# configuration. Any weird result falls back to isolating.
set -u
W=$HOME/darling
S=$W/source
OUT=$W/f95-identity
mkdir -p "$OUT"
R=$OUT/F95-REPORT.md
: > "$R"
note() { printf '%s\n' "$*" >> "$R"; }
say()  { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }

note "# F95 — 26.5 identity + f89 fix — $(date)"

say "phase 0: source state"
cd "$S"
git checkout -q north-star/arm64-verified-fixes
git -C src/external/cocotron checkout -q f89-leak-fix
note "- source: reviewed branch $(git rev-parse --short=9 HEAD); cocotron f89-leak-fix $(git -C src/external/cocotron rev-parse --short=9 HEAD)"

say "phase 1: seed isolated roots"
sudo -n rm -rf "$W/install-arm64-id26" "$W/build-arm64-id26"
cp -a "$W/install-arm64-stage10" "$W/install-arm64-id26"
cp -a "$W/build-arm64-gui" "$W/build-arm64-id26"

say "phase 2: configure (26.5 identity) + build"
docker run --rm --platform linux/arm64 \
	-v "$S:/work/source:ro" -v "$W/build-arm64-id26:/work/build" \
	darling-arm64-dev:24.04 bash -lc "cd /work/build && cmake -S /work/source -B /work/build -G Ninja \
		-DDARLING_ARM64_NORTH_STAR_STAGE18=ON -DCOMPONENTS=gui,jsc -DCOMPONENT_gui=ON \
		-DTARGET_arm64=ON -DTARGET_x86_64=OFF -DTARGET_i386=OFF -DCMAKE_BUILD_TYPE= \
		-DDARLING_EMULATED_OS_PRODUCT_VERSION=26.5 && ninja -j8" \
	> "$OUT/build.log" 2>&1
rc=$?
note "- configure+build (26.5): rc=$rc"
(( rc == 0 )) || { note "ABORT: build failed"; grep -m3 -E "error:|FAILED:" "$OUT/build.log" >> "$R"; exit 1; }

say "phase 3: stage (components + login)"
docker run --rm --platform linux/arm64 \
	-v "$S:/work/source:ro" -v "$W/build-arm64-id26:/work/build" -v "$W/install-arm64-id26:/work/stage" \
	darling-arm64-dev:24.04 bash -lc '
		set -u; rm -rf /tmp/s
		for c in cli_gui_common core gui stage18 jsc Unspecified; do
			DESTDIR=/tmp/s cmake --install /work/build --component "$c" >>/tmp/i.log 2>&1 || true
		done
		DESTDIR=/tmp/cli cmake --install /work/build --component cli >>/tmp/i.log 2>&1 || true
		cp /tmp/cli/usr/local/libexec/darling/usr/bin/login /tmp/s/usr/local/libexec/darling/usr/bin/login 2>/dev/null
		src=/tmp/s/usr/local/libexec/darling; dst=/work/stage/root
		for e in "$src"/*; do b=${e##*/}
			if [ -L "$e" ] && [ -d "$dst/$b" ] && [ ! -L "$dst/$b" ]; then continue
			elif [ -d "$e" ] && [ ! -L "$e" ]; then mkdir -p "$dst/$b" && cp -a "$e/." "$dst/$b/"
			else cp -a "$e" "$dst/"; fi
		done' > "$OUT/stage.log" 2>&1
note "- staged; login present: $( [ -f "$W/install-arm64-id26/root/usr/bin/login" ] && echo yes || echo NO )"
grep -m1 "EMULATED_OS" "$W/build-arm64-id26/CMakeCache.txt" >> "$R"

say "phase 4: ladder"
export ITERM2_SHARED_CACHE_ROOT=$W/downloads/macos/26.6/dyld-stage18
export DARLING_STAGE18_ROOT=$W/install-arm64-id26 DARLING_STAGE18_BUILD_ROOT=$W/build-arm64-id26
DARLING_ARM64_INSTALL_ROOT=$W/install-arm64-id26 tools/verify-north-star-arm64.sh quick > "$OUT/ladder.log" 2>&1
note "- ladder: rc=$?"

say "phase 5: Silver tier x3 each"
declare -A pass
for round in 1 2 3; do
	for g in tabs tab-close splits; do
		tools/verify-iterm2-silver-$g-arm64.sh > "$OUT/silver-$g-r$round.log" 2>&1
		rc=$?
		(( rc == 0 )) && pass[$g]=$(( ${pass[$g]:-0} + 1 ))
	done
done
note "- Silver on 26.5+fix: tabs ${pass[tabs]:-0}/3, tab-close ${pass[tab-close]:-0}/3, splits ${pass[splits]:-0}/3"

say "phase 6: leak cycle on 26.5 runtime"
EA=$W/artifacts/f95-leak-check; rm -rf "$EA"
env ITERM2_PROBE_ARTIFACTS="$EA" "$HOME/f85.sh" > "$OUT/leak-cycle.log" 2>&1
cp "$W/artifacts/f85-resize-leak/f85-samples.txt" "$OUT/leak-samples.txt" 2>/dev/null
note "- leak cycle samples: $(grep -c "^[0-9]" "$OUT/leak-samples.txt" 2>/dev/null || echo 0)"

say "phase 7: one 30-minute soak (quit dialog + RSS + vanish, all at once)"
A=$W/artifacts/stage18-iterm2-bronze-soak
tools/verify-iterm2-bronze-soak-arm64.sh > "$OUT/soak.log" 2>&1
src_rc=$?
keep=$OUT/soak-artifacts; mkdir -p "$keep"; cp -a "$A/." "$keep/" 2>/dev/null
note "- soak rc=$src_rc; summary: $(tr '\n' ' ' < "$keep/soak-summary.txt" 2>/dev/null)"
note "- quit: $(head -c 100 "$keep/quit-confirmation.txt" 2>/dev/null | tr '\n' ' ')"
first=$(grep -m1 -oE "[0-9]+" <(grep Rss "$keep/soak-smaps-0001.txt" 2>/dev/null))
lastf=$(ls "$keep"/soak-smaps-*.txt 2>/dev/null | sort | tail -1)
last=$(grep -m1 -oE "[0-9]+" <(grep Rss "$lastf" 2>/dev/null))
note "- soak RSS: ${first:-?} -> ${last:-?} KiB (growth $(( ${last:-0} - ${first:-0} )) KiB; ceiling 524288)"

note ""
note "*(finished $(date))*"
echo "F95 COMPLETE"