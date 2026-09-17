#!/usr/bin/env bash
# Runs INSIDE the VM. Configures and builds the arm64 Darling tree.
# Staged so we get early signal from the loader/server before committing to
# the full multi-hour framework build.
set -uo pipefail

SRC="$HOME/darling"
BUILD="$SRC/build"
JOBS="${JOBS:-$(nproc)}"
STAGE="${1:-all}"   # configure | core | all

log() { printf '\n=== %s ===\n' "$*"; }

cd "$SRC" || { echo "FATAL: $SRC missing"; exit 1; }

log "tree state"
git --no-pager log --oneline -1
echo "submodules checked out: $(git submodule status --recursive 2>/dev/null | grep -vc '^-' || echo '?')"
echo "uninitialised:          $(git submodule status --recursive 2>/dev/null | grep -c '^-' || echo 0)"

# ------------------------------------------------------------- configure ---
mkdir -p "$BUILD"
cd "$BUILD"
# kkHAIKE developed PR #1753 against clang-19; Fedora 44 ships clang 22, where
# several diagnostics that were warnings became hard errors (clang 16+). These
# relaxations restore the older behaviour for exactly the classes we've triaged.
# They are DELIBERATE and each one is a real upstream defect worth reporting:
#   implicit-function-declaration -> xnu epoll_create.c calls epoll_create1()
#       with no declaration in scope. aarch64-ONLY path: x86_64 has
#       __NR_epoll_create so the #else branch never compiles there.
#   incompatible-pointer-types    -> libkqueue timer.c passes kevent_internal_s*
#       where kevent64_s* is expected (pre-existing, not arm64-specific).
RELAX="-Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=incompatible-function-pointer-types"

if [ ! -f CMakeCache.txt ]; then
    log "configuring (aarch64 host => TARGET_ARM64 should default ON)"
    cmake .. -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$RELAX" -DCMAKE_CXX_FLAGS="$RELAX" 2>&1 | tail -30
else
    log "already configured (delete $BUILD/CMakeCache.txt to redo)"
fi

log "architecture configuration"
for v in CMAKE_SYSTEM_PROCESSOR TARGET_ARM64 TARGET_x86_64 TARGET_i386 CMAKE_BUILD_TYPE; do
    printf '  %-22s %s\n' "$v" "$(grep -E "^${v}:" CMakeCache.txt 2>/dev/null | cut -d= -f2- || echo '<unset>')"
done

[ "$STAGE" = "configure" ] && { echo "stopping after configure"; exit 0; }

# ------------------------------------------------------------------ core ---
# The loader + server are the arm64 critical path: if these don't build,
# nothing else matters. Build them first for fast feedback.
log "building core targets (mldr, darlingserver) with -j$JOBS"
CORE_OK=1
for t in mldr darlingserver; do
    if make help 2>/dev/null | grep -qx "... $t"; then
        echo "--- $t ---"
        if ! make "$t" -j"$JOBS" 2>&1 | tail -25; then CORE_OK=0; echo "CORE TARGET FAILED: $t"; fi
    else
        echo "  (target '$t' not exposed; will build as part of the full tree)"
    fi
done
[ "$CORE_OK" = 1 ] || echo "WARNING: a core target failed — full build will likely fail too"

[ "$STAGE" = "core" ] && { echo "stopping after core"; exit 0; }

# ------------------------------------------------------------------- all ---
log "full build with -j$JOBS (long)"
make -j"$JOBS" 2>&1 | tail -60
rc=${PIPESTATUS[0]}

log "build result"
if [ "$rc" = 0 ]; then
    echo "BUILD OK"
    log "installing"
    sudo make install 2>&1 | tail -15
    command -v darling && darling --version 2>&1 | head -3
else
    echo "BUILD FAILED (rc=$rc) — see above"
fi
exit "$rc"
