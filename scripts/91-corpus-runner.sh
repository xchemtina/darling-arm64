#!/usr/bin/env bash
# Runs INSIDE the Ubuntu VM. Self-contained differential-corpus runner.
#
# Mirrors tools/run-staged-darling-arm64.sh, with three differences:
#   * the corpus is bind-mounted and copied INTO the darling prefix, because
#     DSERVER_INIT resolves inside the darling filesystem view and the prefix is
#     the writable half of it;
#   * every binary is run in one container invocation instead of one container
#     per binary, which is far quicker for 17 cases;
#   * ARGUMENT-TAKING CASES ARE NOW RUN (see below) instead of being skipped.
#
# ARGV SUPPORT (added for the three previously-skipped cases)
#   tools/run-staged-darling-arm64.sh drives a program purely through DSERVER_INIT,
#   which carries no argv, so host_echo / host_basename / host_wc were reported as
#   skips from the first corpus run onward -- three of seventeen cases never
#   executed.
#
#   The mechanism to fix that already ships in the staged runtime:
#   /exec-arguments-darling-arm64 reads DARLING_EXEC_PATH and DARLING_EXEC_ARG1..8
#   and execs the target with them. verify-service-tools-darling-arm64.sh drives
#   every one of its steps this way; this is the same pattern.
#
#   host_wc additionally needs stdin, which darlingserver inherits from this shell,
#   so it is piped in.
#
#   The argument values are duplicated from scripts/10-make-corpus.sh args_for() /
#   stdin_for() and MUST stay identical to them -- ground truth in
#   corpus/truth/native.tsv was captured on macOS with exactly these arguments, so
#   any divergence here silently compares different invocations.
#
# Their tree is left untouched.
set -uo pipefail

STAGE="${DARLING_ARM64_INSTALL_ROOT:-$HOME/darling/install-arm64-stage10}"
CORPUS="$HOME/corpus"
IMAGE="${DARLING_ARM64_IMAGE:-darling-arm64-dev:latest}"
OUT="$CORPUS/truth/darling-northstar.tsv"

[ -d "$STAGE/root" ] || { echo "FATAL: no staged runtime at $STAGE/root"; exit 1; }

docker rm -f darling-corpus >/dev/null 2>&1 || true
docker run --name darling-corpus --rm \
    -e DARLING_ARM64_THREAD_BRIDGE=1 \
    --cap-add SYS_ADMIN --cap-add SYS_PTRACE \
    --security-opt apparmor=unconfined --security-opt seccomp=unconfined \
    -v "$STAGE/root:/usr/local/libexec/darling:ro" \
    -v "$STAGE/bin:/opt/darling/bin:ro" \
    -v "$CORPUS/bin:/corpus-in:ro" \
    "$IMAGE" bash -lc '
        set -u
        prefix=/tmp/darling-prefix
        mkdir -p "$prefix/dev/pts" "$prefix/corpus"
        cp -a /dev/null /dev/urandom "$prefix/dev/" 2>/dev/null || true
        mount --bind /dev/pts "$prefix/dev/pts" 2>/dev/null || true
        ln -sf pts/ptmx "$prefix/dev/ptmx" 2>/dev/null || true
        cp /corpus-in/* "$prefix/corpus/" 2>/dev/null || true
        chmod -R a+rx "$prefix/corpus"

        export PATH=/opt/darling/bin:$PATH
        export DARLING_NOOVERLAYFS=1
        export DYLD_USE_CLOSURES=0

        # Keep identical to scripts/10-make-corpus.sh args_for()/stdin_for().
        args_for() {
            case "$1" in
                host_echo)     printf "hi" ;;
                host_basename) printf "/a/b/c" ;;
                host_wc)       printf -- "-w" ;;
                *)             printf "" ;;
            esac
        }
        stdin_for() {
            case "$1" in
                host_wc) printf "a b\n" ;;
                *)       printf "" ;;
            esac
        }

        for f in "$prefix"/corpus/*; do
            case "$f" in *.err) continue;; esac
            [ -f "$f" ] || continue
            n=$(basename "$f")
            a=$(args_for "$n")

            if [ -z "$a" ]; then
                out=$(stdin_for "$n" | DSERVER_INIT="/corpus/$n" \
                      timeout -s KILL 90 darlingserver "$prefix" 0 0 3 0 2>&1)
                rc=$?
            else
                # argv path via the staged exec-arguments helper
                out=$(stdin_for "$n" | \
                      DSERVER_INIT=/exec-arguments-darling-arm64 \
                      DARLING_EXEC_PATH="/corpus/$n" \
                      DARLING_EXEC_ARG1="$a" \
                      timeout -s KILL 90 darlingserver "$prefix" 0 0 3 0 2>&1)
                rc=$?
            fi

            clean=$(printf "%s" "$out" \
                | grep -avE "^objc\[|Class NS|Class UI|libEGL|^Warning: failed to increase|^dyld:|^darlingserver" \
                | tr "\n" "~" | sed "s/~$//")
            printf "%s\t%s\t%s\n" "$n" "$rc" "$clean"
        done
    ' 2>/dev/null | grep -aE $'^[A-Za-z0-9_.]+\t' > "$OUT"

echo "=== raw results ==="
cat "$OUT"

echo
echo "=== SCOREBOARD: Darling arm64 vs macOS native ==="
python3 - "$CORPUS/truth/native.tsv" "$OUT" <<'PY'
import sys
def load(p):
    d = {}
    for line in open(p):
        parts = line.rstrip('\n').split('\t')
        if len(parts) >= 2:
            d[parts[0]] = (parts[1], parts[2] if len(parts) > 2 else '')
    return d
native, darling = load(sys.argv[1]), load(sys.argv[2])
CWD_DEPENDENT = {'host_pwd'}
rows = []; ok_n = fail_n = skip_n = 0
for name in sorted(native):
    nrc, nout = native[name]
    if name not in darling:
        rows.append((' MISS ', name, 'not run')); continue
    drc, dout = darling[name]
    if drc == 'SKIP':
        rows.append((' skip ', name, dout)); skip_n += 1; continue
    if name in CWD_DEPENDENT:
        ok = (nrc == drc); detail = f'rc {nrc} vs {drc} (output not compared)'
    else:
        ok = (nrc == drc and nout == dout)
        detail = 'exact match' if ok else \
                 f'native[rc={nrc}] {nout[:40]!r} | darling[rc={drc}] {dout[:40]!r}'
    rows.append(('  ok  ' if ok else ' FAIL ', name, detail))
    ok_n += ok; fail_n += (not ok)
w = max((len(r[1]) for r in rows), default=10)
for mark, name, detail in rows:
    print(f'{mark} {name:<{w}}  {detail}')
print(f'\n  matched {ok_n}   diverged {fail_n}   skipped {skip_n}')
PY
