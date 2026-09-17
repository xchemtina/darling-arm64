#!/usr/bin/env bash
# Summarise an overnight soak. Safe to run at any time, including mid-run.
# Reads only ~/soak; writes ~/soak/REPORT.
set -uo pipefail
SOAK=$HOME/soak
S=$SOAK/SUMMARY
[ -f "$S" ] || { echo "no soak summary at $S"; exit 1; }

{
echo "=============================================================="
echo " DARLING ARM64 -- OVERNIGHT SOAK REPORT"
echo " generated $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=============================================================="
echo
echo "--- 1. LADDER (canary: should be invariant) ------------------"
tot=$(grep -c ' ladder rc=' "$S"); ok=$(grep -c ' ladder rc=0 ' "$S")
echo "  runs: $tot   passed: $ok"
grep ' ladder rc=' "$S" | grep -v 'rc=0 ' | head -5 | sed 's/^/  FAILURE: /'
echo "  duration: $(grep ' ladder rc=' "$S" | grep -oE 'secs=[0-9]+' | cut -d= -f2 \
      | sort -n | awk 'NR==1{min=$1} {max=$1} END{print min"-"max" s"}')"
echo
echo "--- 2. CORPUS SELF-CONSISTENCY -------------------------------"
runs=$(ls "$SOAK"/corpus/cases-*.txt 2>/dev/null | wc -l | tr -d ' ')
echo "  corpus runs: $runs"
grep ' corpus rc=' "$S" | grep -oE 'matched [0-9]+ diverged [0-9]+' | sort | uniq -c \
  | sed 's/^/  scoreboard /'
echo
echo "  cases whose verdict CHANGED between runs (instrument defects):"
python3 - "$SOAK" <<'PY' 2>/dev/null || echo "  (python3 unavailable)"
import glob, os, sys, collections
soak = sys.argv[1]
seen = collections.defaultdict(set)
files = sorted(glob.glob(os.path.join(soak, "corpus", "cases-*.txt")))
for f in files:
    for line in open(f, errors="ignore"):
        p = line.split()
        if len(p) >= 2 and p[0] in ("ok", "FAIL", "skip"):
            seen[p[1]].add(p[0])
flappers = {k: v for k, v in seen.items() if len(v) > 1}
if not files:
    print("  (no corpus runs yet)")
elif not flappers:
    print(f"  NONE -- all {len(seen)} cases gave an identical verdict across "
          f"{len(files)} runs.")
    print("  The corpus is self-consistent; its figures can be trusted.")
else:
    for k, v in sorted(flappers.items()):
        print(f"  FLAPPED  {k}: {'/'.join(sorted(v))}")
PY
echo
echo "--- 3. F27 (TextEdit Save) -----------------------------------"
p=$(grep -c 'textedit rc=0 ' "$S"); f=$(grep ' textedit rc=' "$S" | grep -vc 'rc=0 ')
envf=$(grep -c 'textedit ENV-FAIL' "$S")
tot=$((p + f))
echo "  valid runs: $tot   passed: $p   failed: $f   (env failures excluded: $envf)"
[ "$tot" -gt 0 ] && echo "  pass rate: $(awk -v a="$p" -v b="$tot" 'BEGIN{printf "%.1f%%", 100*a/b}')"
echo "  artifacts retained for diffing:"
ls -d "$SOAK"/artifacts/pass-* 2>/dev/null | sed 's/^/    PASS /' | head -5
ls -d "$SOAK"/artifacts/fail-* 2>/dev/null | sed 's/^/    FAIL /' | head -5
echo
echo "  NEXT STEP: diff a passing run against a failing one, e.g."
echo "    zdiff \$SOAK/artifacts/pass-*/stage15-save.out.gz \\"
echo "          \$SOAK/artifacts/fail-*/stage15-save.out.gz"
echo
echo "--- 4. GRAPHICAL RELIABILITY ---------------------------------"
# TRAP 28: the soak tags any run under 10 s as ENV-FAIL, a rule written when the only
# way to finish fast was for apt to fail. With the GUI dependencies baked in (F46)
# there is no network step, so a fast *success* now trips it -- the soak logged
# `verify-hello-window ENV-FAIL rc=0 secs=5`, a pass, discarded as an environment
# failure. Re-derive from rc here rather than trusting the tag: a pass is rc=0
# whatever its duration, and only a NON-ZERO fast result is a suspected env failure.
for v in verify-x11-backend verify-hello-window verify-controls \
         verify-text-view verify-pty-harness; do
  all=$(grep " $v " "$S" | grep -oE 'rc=[0-9]+ secs=[0-9]+')
  t=$(printf '%s\n' "$all" | grep -c 'rc=')
  o=$(printf '%s\n' "$all" | grep -c '^rc=0 ')
  # suspected environment failure: non-zero AND under 10 s
  e=$(printf '%s\n' "$all" | awk -F'[= ]' '$2!=0 && $4<10' | wc -l | tr -d ' ')
  if [ "$t" -gt 0 ]; then
    rng=$(printf '%s\n' "$all" | grep -oE 'secs=[0-9]+' | cut -d= -f2 | sort -n \
          | awk 'NR==1{min=$1} {max=$1} END{print min"-"max"s"}')
    printf "  %-22s %2d/%-2d passed   %-12s env-fail:%d\n" "$v" "$o" "$t" "$rng" "$e"
  fi
done
echo "  (passes counted by rc=0 regardless of duration -- see trap 28; the soak's own"
echo "   ENV-FAIL tag undercounts passes now that the image needs no network)"
echo
echo "--- 5. ENVIRONMENT -------------------------------------------"
echo "  env failures total: $(grep -c 'ENV-FAIL' "$S")  (should be 0 now the"
echo "    GUI dependencies are baked into the image -- any here means the"
echo "    apt guard is not taking effect somewhere)"
echo "  soak disk: $(du -sh "$SOAK" 2>/dev/null | cut -f1)"
echo
echo "=============================================================="
} > "$SOAK/REPORT"
cat "$SOAK/REPORT"
