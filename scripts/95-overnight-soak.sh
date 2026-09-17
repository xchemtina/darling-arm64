#!/usr/bin/env bash
# DARLING-ARM64 overnight soak. Runs INSIDE the VM, detached, unattended.
#
# PRINCIPLE: measurement only. This script never edits source, never rebuilds and
# never re-stages. Everything it does is read-only with respect to the project, so a
# night that goes wrong costs nothing but time. Anything that *changes* the tree
# belongs in an interactive session where a control run can follow it.
#
# WHAT IT MEASURES, and why each is worth a night:
#
#   1. CORPUS SELF-CONSISTENCY -- never checked before. The corpus is the instrument
#      every fidelity claim rests on, and nobody has verified that it gives the same
#      answer twice. Any case that flaps between pass and fail is a defect in the
#      instrument, and until this runs, every corpus figure carries an unstated
#      assumption.
#
#   2. F27 FAILURE RATE, WITH EVIDENCE. TextEdit's Save crashes roughly two runs in
#      three. Volume yields both outcomes, and the artifacts of a PASSING run beside
#      those of a FAILING one are the most promising route into F27 that does not
#      require guessing. Artifacts are kept for a bounded number of each.
#
#   3. GRAPHICAL RELIABILITY (F29). Current claims rest on ~6 runs. Cheap now that
#      the dependencies are baked into the image (F46).
#
#   4. LADDER AS CANARY. 11 seconds, deterministic. If it ever fails overnight the
#      environment changed, and every later result that night is suspect.
#
# READING IT IN THE MORNING: ~/soak/SUMMARY, appended after every single run so a
# partial night is still useful. ~/soak/REPORT is written at the end (or run
# ~/soak/summarise.sh at any time).
#
# TRAP 27: a graphical run finishing in under 10 s is an apt/network failure, not a
# test failure. Those are counted separately -- conflating them is how nine runs of a
# previous sweep produced meaningless "flakiness" data.
set -uo pipefail

SOAK=$HOME/soak
SRC=$HOME/darling/source
export DARLING_ARM64_INSTALL_ROOT=$HOME/darling/install-arm64-stage10
export DARLING_ARM64_IMAGE=darling-arm64-dev:guideps

# Budget in MINUTES (integer). Bash cannot do float arithmetic, so an hours
# argument like "0.02" silently produced an empty END and the loop never ran.
DURATION_MIN="${1:-480}"
case "$DURATION_MIN" in
    ''|*[!0-9]*) echo "usage: $0 [minutes]  (integer, default 480 = 8h)" >&2; exit 2;;
esac
END=$(( $(date +%s) + DURATION_MIN * 60 ))

mkdir -p "$SOAK"/{corpus,textedit,gui,artifacts}
SUMMARY=$SOAK/SUMMARY
: > "$SUMMARY"

log() { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*" >> "$SUMMARY"; }

log "soak start, budget ${DURATION_MIN}min, image $DARLING_ARM64_IMAGE"
log "principle: measurement only -- no source edits, no rebuilds, no re-staging"

iter=0
te_pass=0; te_fail=0; te_pass_kept=0; te_fail_kept=0
KEEP_ARTIFACTS=4          # per outcome; enough to diff, bounded on disk

cd "$SRC" || { log "FATAL: no source tree"; exit 1; }

while [ "$(date +%s)" -lt "$END" ]; do
    iter=$((iter + 1))

    # ---- 1. ladder canary ---------------------------------------------------
    s=$(date +%s)
    timeout -s KILL 600 tools/verify-north-star-arm64.sh quick \
        > "$SOAK/ladder-last.log" 2>&1
    rc=$?; e=$(date +%s)
    rungs=$(grep -c passed "$SOAK/ladder-last.log" 2>/dev/null || echo 0)
    log "iter $iter ladder rc=$rc rungs=$rungs secs=$((e-s))"
    [ "$rc" != 0 ] && cp "$SOAK/ladder-last.log" "$SOAK/ladder-FAIL-$iter.log"

    # ---- 2. corpus self-consistency ----------------------------------------
    s=$(date +%s)
    timeout -s KILL 1800 "$HOME/91-corpus.sh" > "$SOAK/corpus/run-$iter.log" 2>&1
    rc=$?; e=$(date +%s)
    score=$(sed -n '/matched/p' "$SOAK/corpus/run-$iter.log" | tr -s ' ')
    log "iter $iter corpus rc=$rc secs=$((e-s)) ${score}"
    # keep only the per-case verdicts; the full log is large and repetitive
    sed -n '/SCOREBOARD/,$p' "$SOAK/corpus/run-$iter.log" \
        | grep -E '^\s+(ok|FAIL|skip)' > "$SOAK/corpus/cases-$iter.txt" 2>/dev/null
    rm -f "$SOAK/corpus/run-$iter.log"

    # ---- 3. F27: text-edit, with artifacts from both outcomes ---------------
    for k in 1 2 3; do
        [ "$(date +%s)" -ge "$END" ] && break
        rm -rf "$HOME/darling/artifacts/stage15-text-edit"/* 2>/dev/null
        s=$(date +%s)
        timeout -s KILL 900 tools/verify-text-edit-darling-arm64.sh \
            > "$SOAK/textedit/last.log" 2>&1
        rc=$?; e=$(date +%s); secs=$((e-s))
        # TRAP 28: only a NON-ZERO fast result is a suspected environment failure.
        # A fast rc=0 is a legitimate pass now the image needs no network (F46);
        # treating it as an env failure discards a real success.
        if [ "$secs" -lt 10 ] && [ "$rc" != 0 ]; then
            log "iter $iter textedit ENV-FAIL rc=$rc secs=$secs (apt/network, not a test result)"
            continue
        fi
        if [ "$rc" = 0 ]; then
            te_pass=$((te_pass + 1)); tag=pass
        else
            te_fail=$((te_fail + 1)); tag=fail
        fi
        log "iter $iter textedit rc=$rc secs=$secs ($tag; running pass=$te_pass fail=$te_fail)"
        # Keep a bounded number of each outcome -- the pass/fail diff is the point.
        keep=0
        if [ "$tag" = pass ] && [ "$te_pass_kept" -lt "$KEEP_ARTIFACTS" ]; then
            keep=1; te_pass_kept=$((te_pass_kept + 1))
        elif [ "$tag" = fail ] && [ "$te_fail_kept" -lt "$KEEP_ARTIFACTS" ]; then
            keep=1; te_fail_kept=$((te_fail_kept + 1))
        fi
        if [ "$keep" = 1 ]; then
            d=$SOAK/artifacts/$tag-$iter-$k; mkdir -p "$d"
            cp "$HOME/darling/artifacts/stage15-text-edit"/* "$d/" 2>/dev/null
            cp "$SOAK/textedit/last.log" "$d/verifier.log" 2>/dev/null
            gzip -q "$d"/*.err "$d"/*.out "$d/verifier.log" 2>/dev/null
        fi
    done

    # ---- 4. graphical reliability ------------------------------------------
    for v in verify-x11-backend verify-hello-window verify-controls \
             verify-text-view verify-pty-harness; do
        [ "$(date +%s)" -ge "$END" ] && break
        s=$(date +%s)
        timeout -s KILL 900 "tools/$v-darling-arm64.sh" > "$SOAK/gui/last.log" 2>&1
        rc=$?; e=$(date +%s); secs=$((e-s))
        # TRAP 28: as above -- a fast pass is a pass, not an environment failure.
        if [ "$secs" -lt 10 ] && [ "$rc" != 0 ]; then
            log "iter $iter $v ENV-FAIL rc=$rc secs=$secs (apt/network)"
        else
            log "iter $iter $v rc=$rc secs=$secs"
        fi
    done

    # ---- disk guard ---------------------------------------------------------
    used=$(du -sm "$SOAK" 2>/dev/null | cut -f1)
    if [ "${used:-0}" -gt 2048 ]; then
        log "disk guard: ${used}MB in $SOAK, stopping artifact capture"
        KEEP_ARTIFACTS=0
    fi
done

log "soak end after $iter iterations"
"$SOAK/summarise.sh" >> "$SUMMARY" 2>&1 || true
