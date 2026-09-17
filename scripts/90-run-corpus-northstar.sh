#!/usr/bin/env bash
# Runs INSIDE the Ubuntu VM. Executes the differential corpus under the staged
# north-star ARM64 runtime and scores each binary against macOS-native ground truth.
#
# WHY THIS EXISTS
#   deepai-org's gates are application-level: they prove iTerm2/TextEdit/MiniTerm
#   behave. They would not notice a subtly wrong `uname` string, a divergent errno,
#   or a pthread that silently no-ops. This corpus was compiled on the host Mac with
#   Apple clang 21 / SDK 26.5 and each binary's exact output+status was captured by
#   running it natively on macOS -- so any divergence here is a real behavioural
#   difference between Darling arm64 and the real system, on identical bytes.
#
#   It is also the first exercise of the arm64e (PAC-signed) binaries, which are the
#   least independently verified part of the stack.
#
# MECHANISM
#   tools/run-staged-darling-arm64.sh takes a single program path rooted at the
#   staged runtime and sets DSERVER_INIT to it. It accepts no arguments, so the
#   three arg-taking cases (host_echo, host_basename, host_wc) are skipped and
#   reported as such rather than silently dropped.
set -uo pipefail

SRC="$HOME/darling/source"
STAGE="${DARLING_ARM64_INSTALL_ROOT:-$HOME/darling/install-arm64-stage10}"
CORPUS="$HOME/corpus"
RUNNER="$SRC/tools/run-staged-darling-arm64.sh"
TRUTH="$CORPUS/truth/native.tsv"
OUT="$CORPUS/truth/darling-northstar.tsv"

[ -f "$TRUTH" ]   || { echo "FATAL: no ground truth at $TRUTH"; exit 1; }
[ -x "$RUNNER" ]  || { echo "FATAL: runner missing at $RUNNER"; exit 1; }
[ -d "$STAGE/root" ] || { echo "FATAL: no staged runtime at $STAGE/root"; exit 1; }

# Cases needing argv; the runner cannot supply them.
needs_args() { case "$1" in host_echo|host_basename|host_wc) return 0;; *) return 1;; esac; }

echo "=== staging corpus into the runtime root ==="
sudo mkdir -p "$STAGE/root/corpus"
for f in "$CORPUS"/bin/*; do
    case "$f" in *.err) continue;; esac
    [ -f "$f" ] || continue
    sudo cp "$f" "$STAGE/root/corpus/$(basename "$f")"
done
sudo chmod -R a+rx "$STAGE/root/corpus"
echo "  staged: $(ls "$STAGE/root/corpus" | wc -l) binaries"

echo "=== running under Darling ==="
: > "$OUT"
skipped=0
for f in "$CORPUS"/bin/*; do
    case "$f" in *.err) continue;; esac
    [ -f "$f" ] || continue
    n=$(basename "$f")
    if needs_args "$n"; then
        printf '%s\tSKIP\t(runner takes no argv)\n' "$n" >> "$OUT"
        skipped=$((skipped+1)); continue
    fi
    out=$(DARLING_ARM64_CONTAINER="corpus-$n" DARLING_ARM64_THREAD_BRIDGE=1 \
          timeout -s KILL 120 "$RUNNER" "/corpus/$n" 2>&1)
    rc=$?
    # Keep only the program's own output: drop loader/objc/EGL noise so the
    # comparison is against what the binary actually printed.
    clean=$(printf '%s' "$out" \
        | grep -avE '^objc\[|Class NS|Class UI|libEGL|^Warning: failed to increase|^dyld:' \
        | tr '\n' '~' | sed 's/~$//')
    printf '%s\t%s\t%s\n' "$n" "$rc" "$clean" >> "$OUT"
    printf '  %-22s rc=%-4s %s\n' "$n" "$rc" "$(printf '%s' "$clean" | cut -c1-60)"
done
echo "  skipped (need argv): $skipped"

echo
echo "=== SCOREBOARD: Darling arm64 vs macOS native ==="
python3 - "$TRUTH" "$OUT" <<'PY'
import sys
def load(p):
    d = {}
    for line in open(p):
        parts = line.rstrip('\n').split('\t')
        if len(parts) >= 2:
            d[parts[0]] = (parts[1], parts[2] if len(parts) > 2 else '')
    return d
native, darling = load(sys.argv[1]), load(sys.argv[2])
CWD_DEPENDENT = {'host_pwd'}          # cwd differs by construction
rows, p = [], 0; f = 0; s = 0
for name in sorted(native):
    nrc, nout = native[name]
    if name not in darling:
        rows.append((' MISS ', name, 'not run')); continue
    drc, dout = darling[name]
    if drc == 'SKIP':
        rows.append((' skip ', name, dout)); s += 1; continue
    if name in CWD_DEPENDENT:
        ok = (nrc == drc); detail = f'rc {nrc} vs {drc} (output not compared)'
    else:
        ok = (nrc == drc and nout == dout)
        detail = 'exact match' if ok else f'native[rc={nrc}] {nout[:44]!r}  darling[rc={drc}] {dout[:44]!r}'
    rows.append(('  ok  ' if ok else ' FAIL ', name, detail))
    p += ok; f += (not ok)
w = max((len(r[1]) for r in rows), default=10)
for mark, name, detail in rows:
    print(f'{mark} {name:<{w}}  {detail}')
print(f'\n  matched {p}   diverged {f}   skipped {s}')
PY
