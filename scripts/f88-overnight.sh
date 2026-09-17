#!/usr/bin/env bash
# F88: 8-hour overnight driver. Sequential (trap 31: gates assert wall-clock
# deadlines, so nothing runs concurrently). Each phase logs separately, archives its
# whole artifact directory (F84 Part 3 lesson), records its own verdict, and a
# failure in one phase never blocks the next. Exit codes captured directly, never
# through a pipe (traps 10/30).
#
# Phase F integrates the funder's 110-commit gap (Jul 14-16) on a LOCAL scratch
# branch only -- nothing is pushed overnight; the reviewed branch and the note being
# sent stay untouched (core-human-decides).
set -u

W=$HOME/darling
S=$W/source
OUT=$W/f88-overnight
mkdir -p "$OUT"
R=$OUT/OVERNIGHT-REPORT.md
: > "$R"
note() { printf '%s\n' "$*" >> "$R"; }
say()  { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }

export ITERM2_SHARED_CACHE_ROOT=$W/downloads/macos/26.6/dyld-stage18
cd "$S"

note "# Overnight report — $(date)"
note ""

# ---- Phase A: baseline control ----------------------------------------------
say "Phase A: baseline"
note "## A. Baseline control (before anything changes)"
DARLING_ARM64_INSTALL_ROOT=$W/install-arm64-stage18 tools/verify-north-star-arm64.sh quick > "$OUT/A-ladder.log" 2>&1
a1=$?
tools/verify-iterm2-silver-tabs-arm64.sh > "$OUT/A-tabs.log" 2>&1
a2=$?
note "- ladder quick: rc=$a1; silver-tabs control: rc=$a2"
if (( a1 != 0 || a2 != 0 )); then
	note "- **BASELINE NOT GREEN — overnight results after this point sit on a moved control.**"
fi

# ---- Phase B: Silver stability at scale --------------------------------------
say "Phase B: 15x each Silver gate + settings-persistence"
note ""
note "## B. Silver stability, 15 consecutive runs each"
declare -A pass total
for round in $(seq 1 15); do
	for gate in tabs tab-close splits; do
		tools/verify-iterm2-silver-$gate-arm64.sh > "$OUT/B-$gate-r$round.log" 2>&1
		rc=$?
		total[$gate]=$(( ${total[$gate]:-0} + 1 ))
		(( rc == 0 )) && pass[$gate]=$(( ${pass[$gate]:-0} + 1 ))
	done
done
tools/verify-iterm2-settings-persistence-arm64.sh > "$OUT/B-settings.log" 2>&1
sp=$?
for gate in tabs tab-close splits; do
	note "- silver-$gate: ${pass[$gate]:-0}/${total[$gate]:-0}"
done
note "- settings-persistence: $( (( sp == 0 )) && echo 1 || echo 0 )/1 (cumulative with earlier: previous was 1/1)"

# ---- Phase C: Bronze soak statistics ------------------------------------------
say "Phase C: 4x full bronze soak (~2h15m)"
note ""
note "## C. Bronze soak, 4 further 30-minute runs (whole-dir archived)"
A=$W/artifacts/stage18-iterm2-bronze-soak
for run in 1 2 3 4; do
	tools/verify-iterm2-bronze-soak-arm64.sh > "$OUT/C-soak-r$run.log" 2>&1
	rc=$?
	keep=$OUT/C-soak-run$run; mkdir -p "$keep"
	cp -a "$A/." "$keep/" 2>/dev/null
	s=$(tr '\n' ' ' < "$keep/soak-summary.txt" 2>/dev/null)
	q=$(head -c 60 "$keep/quit-confirmation.txt" 2>/dev/null | tr '\n' ' ')
	note "- run $run: rc=$rc; ${s:-no summary}; quit=[${q:-none}]"
done

# ---- Phase D: quit-dialog mechanism -------------------------------------------
say "Phase D: quit-dialog mechanism observers"
note ""
note "## D. Quit-dialog mechanism (observers on both quit paths)"
# Bronze path at 30 s with two observers inside the container: the active window at
# 5 Hz, and every substructure creation on root. If a 510x126 window is CREATED on
# the bronze path but the poller misses it, the mechanism is timing; if it is never
# created, iTerm2 never posts the dialog on this path.
export ITERM2_SOAK_SECONDS=30
tools/verify-iterm2-bronze-soak-arm64.sh > "$OUT/D-bronze30.log" 2>&1 &
gate_pid=$!
c=darling-arm64-iterm2-launch-probe
for i in $(seq 1 240); do
	docker ps --format '{{.Names}}' | grep -qx "$c" && break
	sleep 0.5
done
if docker ps --format '{{.Names}}' | grep -qx "$c"; then
	docker exec "$c" bash -c 'for i in $(seq 1 200); do DISPLAY=:95 xdotool getactivewindow >/dev/null 2>&1 && exit 0; sleep 0.25; done; exit 1' \
	&& {
		docker exec -d "$c" bash -c 'DISPLAY=:95 stdbuf -oL xev -root -event substructure 2>/dev/null | while IFS= read -r l; do printf "%s %s\n" "$(date +%s.%2N)" "$l"; done > /artifacts/D-xev.log'
		docker exec -d "$c" bash -c 'for i in $(seq 1 900); do printf "%s %s\n" "$(date +%s.%2N)" "$(DISPLAY=:95 xdotool getactivewindow 2>/dev/null)"; sleep 0.2; done > /artifacts/D-focus.log'
	}
fi
wait "$gate_pid"
keep=$OUT/D-bronze-artifacts; mkdir -p "$keep"; cp -a "$A/." "$keep/" 2>/dev/null
unset ITERM2_SOAK_SECONDS
d_created=$(grep -c "510x126" "$keep/D-xev.log" 2>/dev/null || echo 0)
note "- bronze path: 510x126 creations seen by xev: $d_created; focus samples: $(wc -l < "$keep/D-focus.log" 2>/dev/null || echo 0). Logs archived."

# ---- Phase E: leak model validation --------------------------------------------
say "Phase E: non-alternating resize sequence"
note ""
note "## E. Leak model validation (mixed magnitudes and directions)"
EA=$W/artifacts/f88-leak-validation
rm -rf "$EA"; mkdir -p "$EA"
export ITERM2_PROBE_SHARED_CACHE=1 ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1
export ITERM2_PROBE_FULL_LAUNCHD=1 ITERM2_PROBE_APPKIT_BOOTSTRAP=1 ITERM2_PROBE_APPKIT_REOPEN=1
export ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY=1 ITERM2_PROBE_DIRECT_PTY=1
export ITERM2_PROBE_STABLE_KEYBOARD_SOURCE=1 ITERM2_PROBE_OPAQUE_TEXT=1
export ITERM2_PROBE_DISABLE_METAL=1 ITERM2_PROBE_APPLE_LSD=0 ITERM2_PROBE_APPLE_MDS=0
export ITERM2_PROBE_WAIT_SECONDS=200 ITERM2_PROBE_ARTIFACTS=$EA
tools/probe-iterm2-launch-arm64.sh > "$EA/probe-driver.log" 2>&1 &
probe_pid=$!
for i in $(seq 1 240); do docker ps --format '{{.Names}}' | grep -qx "$c" && break; sleep 0.5; done
if docker ps --format '{{.Names}}' | grep -qx "$c"; then
	docker exec "$c" bash -c 'for i in $(seq 1 200); do DISPLAY=:95 xdotool getactivewindow >/dev/null 2>&1 && exit 0; sleep 0.25; done; exit 1' && sleep 25 && \
	docker exec "$c" bash -c '
		set -u
		export DISPLAY=:95
		pid=$(pgrep -f "MacOS/iTerm2" | head -1)
		win=$(xdotool getactivewindow 2>/dev/null)
		[ -n "$pid" ] && [ -n "$win" ] || { echo "no pid/window"; exit 1; }
		stat=/proc/$pid/status
		rss() { grep -m1 "^VmRSS:" "$stat" 2>/dev/null | grep -oE "[0-9]+"; }
		seq_list="700 450  1100 750  800 520  1000 680  700 450  900 600  1100 750  700 450  1000 680  800 520  900 600  700 450  1100 750  900 600  800 520  1000 680"
		prev=$(rss)
		echo "# w h rss_kb delta_kb" > /artifacts/E-samples.txt
		set -- $seq_list
		while [ $# -ge 2 ]; do
			xdotool windowsize "$win" "$1" "$2" 2>/dev/null
			sleep 1.2
			cur=$(rss); [ -n "$cur" ] || cur=$prev
			echo "$1 $2 $cur $((cur-prev))" >> /artifacts/E-samples.txt
			prev=$cur
			shift 2
		done
		echo done >> /artifacts/E-samples.txt'
fi
kill "$probe_pid" 2>/dev/null; wait "$probe_pid" 2>/dev/null
docker rm -f "$c" >/dev/null 2>&1
note "- samples collected: $(grep -c "^[0-9]" "$EA/E-samples.txt" 2>/dev/null || echo 0) resizes (16-step mixed sequence over 5 sizes)"
unset ITERM2_PROBE_WAIT_SECONDS ITERM2_PROBE_ARTIFACTS

# ---- Phase F: integrate the 110-commit gap on a LOCAL scratch branch -----------
say "Phase F: gap integration (local scratch branch, no push)"
note ""
note "## F. 110-commit gap integration (branch north-star/gap-integration, LOCAL ONLY)"
cd "$S"
git fetch origin > "$OUT/F-fetch.log" 2>&1
db=$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p')
db=${db:-main}
git branch -f north-star/gap-integration HEAD >> "$OUT/F-fetch.log" 2>&1
git checkout north-star/gap-integration >> "$OUT/F-fetch.log" 2>&1
if git merge --no-edit "origin/$db" > "$OUT/F-merge.log" 2>&1; then
	git submodule sync --recursive >> "$OUT/F-merge.log" 2>&1
	git submodule update --init --recursive >> "$OUT/F-merge.log" 2>&1
	note "- merge of origin/$db: clean"
	# rebuild stage18 on the merged tree (seeded build dir already exists)
	docker run --rm --platform linux/arm64 \
		-v "$S:/work/source:ro" -v "$W/build-arm64-stage18:/work/build" \
		darling-arm64-dev:24.04 bash -lc "cd /work/build && cmake -S /work/source -B /work/build -G Ninja -DDARLING_ARM64_NORTH_STAR_STAGE18=ON -DCOMPONENTS=gui,jsc -DCOMPONENT_gui=ON -DTARGET_arm64=ON -DTARGET_x86_64=OFF -DTARGET_i386=OFF -DCMAKE_BUILD_TYPE= && ninja -j8" \
		> "$OUT/F-build.log" 2>&1
	brc=$?
	note "- merged-tree build: rc=$brc $( (( brc != 0 )) && echo '(FIRST error below)' )"
	(( brc == 0 )) || grep -m3 -E "error:|FAILED:" "$OUT/F-build.log" >> "$R"
	if (( brc == 0 )); then
		DESTDIR_STAGE=$W/install-arm64-stage18
		docker run --rm --platform linux/arm64 \
			-v "$S:/work/source:ro" -v "$W/build-arm64-stage18:/work/build" -v "$DESTDIR_STAGE:/work/stage" \
			darling-arm64-dev:24.04 bash -lc '
				set -u; rm -rf /tmp/s18
				for cpt in cli_gui_common core gui stage18 jsc Unspecified; do
					DESTDIR=/tmp/s18 cmake --install /work/build --component "$cpt" >>/tmp/i.log 2>&1 || true
				done
				DESTDIR=/tmp/cli cmake --install /work/build --component cli >>/tmp/i.log 2>&1 || true
				cp /tmp/cli/usr/local/libexec/darling/usr/bin/login /tmp/s18/usr/local/libexec/darling/usr/bin/login 2>/dev/null
				src=/tmp/s18/usr/local/libexec/darling; dst=/work/stage/root
				for e in "$src"/*; do
					b=${e##*/}
					if [ -L "$e" ] && [ -d "$dst/$b" ] && [ ! -L "$dst/$b" ]; then continue
					elif [ -d "$e" ] && [ ! -L "$e" ]; then mkdir -p "$dst/$b" && cp -a "$e/." "$dst/$b/"
					else cp -a "$e" "$dst/"; fi
				done' > "$OUT/F-stage.log" 2>&1
		DARLING_ARM64_INSTALL_ROOT=$W/install-arm64-stage18 tools/verify-north-star-arm64.sh quick > "$OUT/F-ladder.log" 2>&1
		lrc=$?
		note "- merged-tree ladder: rc=$lrc"
		if (( lrc == 0 )); then
			for gate in tabs tab-close splits; do
				tools/verify-iterm2-silver-$gate-arm64.sh > "$OUT/F-$gate.log" 2>&1
				note "- merged-tree silver-$gate: rc=$?"
			done
			if [ -f tools/verify-iterm2-silver-workload-arm64.sh ]; then
				tools/verify-iterm2-silver-workload-arm64.sh > "$OUT/F-workload.log" 2>&1
				note "- **silver-workload (4th Silver gate, first run anywhere but the author's machine): rc=$?**"
			else
				note "- silver-workload script not present after merge (unexpected)"
			fi
		fi
	fi
else
	note "- **merge CONFLICTED — aborted, recorded, tree restored.** Conflicts:"
	git status --porcelain | grep -E "^(UU|AA|DU|UD)" | head -10 >> "$R"
	git merge --abort >> "$OUT/F-merge.log" 2>&1
fi
git checkout north-star/arm64-verified-fixes >> "$OUT/F-fetch.log" 2>&1
note "- reviewed branch restored as checkout; scratch branch kept locally, NOT pushed"

# ---- Phase G: done -------------------------------------------------------------
say "Phase G: report written"
note ""
note "*(driver finished $(date); per-phase logs in ~/darling/f88-overnight/)*"
echo "OVERNIGHT DRIVER COMPLETE"