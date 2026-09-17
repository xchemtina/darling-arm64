#!/usr/bin/env bash
# F84: bracket the Bronze soak's two open failures with three short soaks.
#
# F83 left two things open: (a) the post-soak quit-confirmation dialog fails to
# appear after a 30-minute session while the identical dialog works in a fresh one
# (settings gate) -- where between ~1 and ~30 minutes does it break?; (b) the
# terminal window vanished at iteration 20 in one of two runs -- what is the rate?
#
# Three consecutive soaks at ITERM2_SOAK_SECONDS=300 (~24-27 iterations each at the
# measured ~11-12 s/iteration) cover the iteration-20 window three more times AND
# test the quit chain at the 5-minute mark. If the quit chain works at 5 minutes,
# the degradation lies between 5 and 30 minutes; if the gate passes end-to-end at
# 300 s, that is the first full Bronze-soak-gate pass at any duration.
#
# The gate overwrites its artifact directory on every run (F83's caveat, learned
# the hard way), so each run's key evidence is archived before the next starts.
set -u

cd "$HOME/darling/source"
export ITERM2_SHARED_CACHE_ROOT=$HOME/darling/downloads/macos/26.6/dyld-stage18
export ITERM2_SOAK_SECONDS=300
A=$HOME/darling/artifacts/stage18-iterm2-bronze-soak
out=$HOME/darling/f84-short-soaks
rm -rf "$out"; mkdir -p "$out"

for run in 1 2 3; do
	log=$out/soak300-r$run.log
	start=$(date +%s)
	tools/verify-iterm2-bronze-soak-arm64.sh > "$log" 2>&1
	rc=$?
	secs=$(( $(date +%s) - start ))

	# Archive the WHOLE directory before the next run clobbers it. Copying a
	# hand-picked four files lost the evidence for run 2's launch-stage failure the
	# first time this ran (FINDINGS.md F84 Part 3) -- when a run fails in an
	# unexpected way, the file you did not think to copy is the one you needed.
	keep=$out/run$run
	mkdir -p "$keep"
	cp -a "$A/." "$keep/" 2>/dev/null
	ls "$A"/soak-status-*.txt 2>/dev/null | wc -l > "$keep/status-file-count.txt"
	# full RSS list for the leak curve at n>1
	for f in "$A"/soak-smaps-*.txt; do
		[ -f "$f" ] || continue
		printf "%s %s\n" "$(basename "$f" .txt | grep -oE "[0-9]+$")" \
			"$(grep -m1 "^Rss:" "$f" | grep -oE "[0-9]+")"
	done > "$keep/rss-curve.txt"

	echo "run $run: rc=$rc ${secs}s  summary=[$(tr "\n" " " < "$keep/soak-summary.txt" 2>/dev/null)]"
	echo "         quit=[$(head -c 120 "$keep/quit-confirmation.txt" 2>/dev/null | tr "\n" " ")]  status=[$(cat "$keep/status.txt" 2>/dev/null)]"
done

echo
echo "== F84 summary =="
for run in 1 2 3; do
	s=$out/run$run/soak-summary.txt
	echo "run $run: $(grep -E "iterations|completed|failure" "$s" 2>/dev/null | tr "\n" " ")  quit_ok=$(grep -c "app_exited=1" "$out/run$run/quit-confirmation.txt" 2>/dev/null)"
done