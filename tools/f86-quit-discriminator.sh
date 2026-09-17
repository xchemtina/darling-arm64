#!/usr/bin/env bash
# F86: why does the bronze quit path never find the confirmation dialog, when the
# settings path finds it every time?
#
# F84 established the facts and explicitly refused to guess the mechanism:
#   bronze  (super+q to the terminal window, after the soak workload): 0/5 finds
#   settings(super+q to the Settings window):                          2/2 finds
# Both poll the same /510x126/ geometry. Two families of explanation remain, and
# they are separable by one cheap variable: DURATION.
#
#   (a) it is the workload -- something the soak does (resizes, typed text, or just
#       elapsed iterations) breaks the dialog by the time quit is attempted
#   (b) it is the path -- the bronze quit never produces a dialog at all, at any
#       duration, because of which window is activated or what state it is in
#
# The shortest bronze soak yet run with a LIVE window was 300 s / 28 iterations.
# This runs the gate at ITERM2_SOAK_SECONDS=30 (2-3 iterations), three times:
#
#   dialog FOUND at 30 s  -> (a): the workload breaks it; bisect on duration next
#   dialog MISSING at 30 s -> (b): the bronze quit path never produces one, and the
#                             duration story is dead for good
#
# The gate is unmodified; only its documented duration knob is set. A run whose
# window vanishes mid-soak is discarded from the tally, not counted as a dialog
# failure -- F84 run 3 showed that a lost window makes super+q meaningless.
set -uo pipefail

cd "$HOME/darling/source"
export ITERM2_SHARED_CACHE_ROOT=$HOME/darling/downloads/macos/26.6/dyld-stage18
export ITERM2_SOAK_SECONDS=30
A=$HOME/darling/artifacts/stage18-iterm2-bronze-soak
out=$HOME/darling/f86-quit-discriminator
rm -rf "$out"; mkdir -p "$out"

for run in 1 2 3; do
	tools/verify-iterm2-bronze-soak-arm64.sh > "$out/soak30-r$run.log" 2>&1
	rc=$?
	keep=$out/run$run; mkdir -p "$keep"
	cp -a "$A/." "$keep/" 2>/dev/null          # whole directory (F84 Part 3 lesson)

	summary=$(tr '\n' ' ' < "$keep/soak-summary.txt" 2>/dev/null)
	quit=$(head -c 100 "$keep/quit-confirmation.txt" 2>/dev/null | tr '\n' ' ')
	iters=$(grep -oE "iterations=[0-9]+" <<<"$summary" | cut -d= -f2)
	fail=$(grep -oE "failure=[a-z-]+" <<<"$summary" | cut -d= -f2)
	printf "run %s: rc=%s iterations=%s failure=%s\n         quit=[%s]\n" \
		"$run" "$rc" "${iters:-?}" "${fail:-?}" "$quit"
done

echo
echo "== F86 verdict =="
found=0; usable=0
for run in 1 2 3; do
	q=$(cat "$out/run$run/quit-confirmation.txt" 2>/dev/null)
	f=$(grep -oE "failure=[a-z-]+" "$out/run$run/soak-summary.txt" 2>/dev/null | cut -d= -f2)
	# only runs that still had a window at quit time can speak to the dialog question
	if [[ $f == none ]]; then
		usable=$((usable+1))
		grep -q "dialog=" <<<"$q" && found=$((found+1))
	fi
done
echo "usable runs (workload completed, window alive at quit): $usable/3"
echo "quit dialog found in: $found/$usable"
if (( usable > 0 && found > 0 )); then
	echo "=> (a) DURATION-DEPENDENT: the dialog appears at 30 s but not at 300 s+."
elif (( usable > 0 )); then
	echo "=> (b) PATH-DEPENDENT: no dialog at 30 s either. Duration is not the variable."
else
	echo "=> INCONCLUSIVE: no run kept its window to the quit stage."
fi