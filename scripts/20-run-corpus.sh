#!/usr/bin/env bash
# Runs INSIDE the VM. Executes the corpus under Darling and diffs each result
# against the macOS-native ground truth captured on the host.
#
# usage: 20-run-corpus.sh [corpus_dir] [darling_binary]
set -uo pipefail

CORPUS="${1:-$HOME/corpus}"
DARLING="${2:-$(command -v darling || echo /usr/local/bin/darling)}"
BIN="$CORPUS/bin"; TRUTH="$CORPUS/truth/native.tsv"; OUT="$CORPUS/truth/darling.tsv"

log() { printf '\n=== %s ===\n' "$*"; }

[ -f "$TRUTH" ] || { echo "FATAL: no ground truth at $TRUTH"; exit 1; }
[ -x "$DARLING" ] || { echo "FATAL: darling not found/executable at $DARLING"; exit 1; }

# Same argument table as the host script — must stay in sync.
args_for() {
  case "$1" in
    host_echo)     echo "hi" ;;
    host_basename) echo "/a/b/c" ;;
    host_wc)       echo "-w" ;;
    *)             echo "" ;;
  esac
}
stdin_for() { case "$1" in host_wc) printf 'a b\n' ;; *) printf '' ;; esac; }

# cwd-dependent or otherwise non-comparable outputs: compare exit code only.
rc_only() { case "$1" in host_pwd) return 0 ;; *) return 1 ;; esac; }

log "darling version"
"$DARLING" --version 2>&1 | head -3 || true

# Inside Darling the Linux root appears under /Volumes/SystemRoot.
INNER_PREFIX="/Volumes/SystemRoot"

log "running corpus under darling"
: > "$OUT"
for f in "$BIN"/*; do
    case "$f" in *.err) continue;; esac
    [ -f "$f" ] || continue
    n=$(basename "$f")
    inner="${INNER_PREFIX}${f}"
    a=$(args_for "$n")
    out=$(stdin_for "$n" | timeout 60 "$DARLING" shell "$inner" $a 2>&1); rc=$?
    printf '%s\t%s\t%s\n' "$n" "$rc" "$(printf '%s' "$out" | tr '\n' '~')" >> "$OUT"
    printf '  %-22s rc=%-4s %s\n' "$n" "$rc" "$(printf '%s' "$out" | tr '\n' '~' | cut -c1-70)"
done

# ------------------------------------------------------------- scoreboard ---
log "scoreboard: darling vs native"
python3 - "$TRUTH" "$OUT" <<'PY'
import sys
def load(p):
    d={}
    for line in open(p):
        parts=line.rstrip('\n').split('\t')
        if len(parts)>=2:
            d[parts[0]]=(parts[1], parts[2] if len(parts)>2 else '')
    return d
native, darling = load(sys.argv[1]), load(sys.argv[2])
RC_ONLY={'host_pwd'}
rows=[]; passed=failed=missing=0
for name in sorted(native):
    nrc,nout = native[name]
    if name not in darling:
        rows.append(('MISSING', name, f'native rc={nrc}', '')); missing+=1; continue
    drc,dout = darling[name]
    if name in RC_ONLY:
        ok = (nrc==drc); detail=f'rc {nrc} vs {drc} (output not compared)'
    else:
        ok = (nrc==drc and nout==dout)
        detail = 'exact match' if ok else f'native[rc={nrc}] {nout[:40]!r} | darling[rc={drc}] {dout[:40]!r}'
    rows.append(('PASS' if ok else 'FAIL', name, detail, ''))
    passed += ok; failed += (not ok)
w=max((len(r[1]) for r in rows), default=10)
for st,name,detail,_ in rows:
    mark={'PASS':'  ok  ','FAIL':' FAIL ','MISSING':' MISS '}[st]
    print(f'{mark} {name:<{w}}  {detail}')
total=passed+failed+missing
print(f'\n  passed {passed}/{total}   failed {failed}   missing {missing}')
PY
