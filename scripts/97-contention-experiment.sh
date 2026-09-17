#!/usr/bin/env bash
# Does machine contention alone explain the graphical verifiers' pass rate?
#
# WHY THIS EXISTS
# ---------------
# Two soaks measured `verify-text-view` very differently: 2/7 on the first, 15/15 on
# the second. Between them TWO variables moved -- the build changed (F44/F45/F52) and
# the machine went from heavily contended (I was running greps, docker builds and
# diagnosis on the same VM) to idle. Reporting "text-view improved" without separating
# those two would be exactly the mistake this project's method section warns about.
#
# A mechanism was found by reading the harness. verify-text-view is built from bounded
# WALL-CLOCK wait loops:
#
#     for attempt in {1..30};  do ... sleep 0.05; done   #  1.5 s budget
#     for attempt in {1..300}; do ... sleep 0.1;  done   # 30 s budget
#
# A 1.5-second budget for a UI to settle is blown by any real CPU contention. And
# hello-window shows the signature this predicts: passes take 2-3 s, failures 11-12 s
# -- a wait loop burning its full budget and then falling through.
#
# THE TEST: run text-view N times on ONE unchanged build, alternating idle and loaded.
# Alternating rather than blocking (all-idle then all-loaded) guards against drift in
# machine state over the run.
#
# READING THE RESULT
#   loaded pass rate collapses  -> contention confirmed; the earlier 2/7 measured my
#                                  own working practice, not Darling.
#   loaded pass rate holds      -> the build change explains it, i.e. one of the three
#                                  fixes also repaired text-view. Surprising; chase it.
#
# CAVEAT, to state either way: last night's contention was docker and I/O as much as
# CPU. If a pure CPU load does not reproduce it, that NARROWS the cause -- it does not
# exonerate contention.
set -uo pipefail

SRC=$HOME/darling/source
export DARLING_ARM64_INSTALL_ROOT=$HOME/darling/install-arm64-stage10
export DARLING_ARM64_IMAGE=darling-arm64-dev:guideps

ROUNDS="${1:-3}"                 # pairs; each pair = one idle run + one loaded run
NCPU=$(nproc)
OUT=$HOME/contention.log
: > "$OUT"

log() { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$OUT"; }

log "contention experiment: $ROUNDS idle/loaded pairs, ${NCPU} cores"
log "build is UNCHANGED throughout -- the only variable is machine load"

burners=()
start_load() {
    # One busy loop per core. Crude but portable and, unlike stress-ng, needs no
    # package install inside the VM (F46: keep the network off the critical path).
    for _ in $(seq 1 "$NCPU"); do
        ( while :; do :; done ) & burners+=($!)
    done
}
stop_load() {
    for p in "${burners[@]:-}"; do kill -9 "$p" 2>/dev/null; done
    burners=()
    wait 2>/dev/null
}
trap stop_load EXIT

cd "$SRC" || exit 1
idle_pass=0; idle_tot=0; load_pass=0; load_tot=0

for r in $(seq 1 "$ROUNDS"); do
    for mode in idle loaded; do
        [ "$mode" = loaded ] && start_load
        s=$(date +%s)
        timeout -s KILL 600 tools/verify-text-view-darling-arm64.sh \
            > "$HOME/contention-last.log" 2>&1
        rc=$?
        e=$(date +%s)
        [ "$mode" = loaded ] && stop_load
        if [ "$mode" = idle ]; then
            idle_tot=$((idle_tot+1)); [ "$rc" = 0 ] && idle_pass=$((idle_pass+1))
        else
            load_tot=$((load_tot+1)); [ "$rc" = 0 ] && load_pass=$((load_pass+1))
        fi
        log "round $r $mode rc=$rc secs=$((e-s))"
    done
done

log "RESULT  idle: $idle_pass/$idle_tot passed   loaded: $load_pass/$load_tot passed"
if [ "$load_tot" -gt 0 ] && [ "$load_pass" -lt "$load_tot" ] && [ "$idle_pass" = "$idle_tot" ]; then
    log "READING: contention reproduces the failure on an unchanged build."
elif [ "$load_pass" = "$load_tot" ] && [ "$idle_pass" = "$idle_tot" ]; then
    log "READING: CPU load alone does NOT reproduce it. Narrows to docker/IO"
    log "         contention or the build change; does not exonerate contention."
else
    log "READING: mixed -- report both rates and the unresolved confound."
fi
