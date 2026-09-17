#!/usr/bin/env bash
# Runs INSIDE the Debian 13 aarch64 VM.
#
# The clean-foundation build: clang 19 (matching PR #1753's author exactly),
# ZERO -Wno-error relaxations, F6 reverted. The only local changes are F1 and F2,
# which are genuine bugs independent of compiler version.
#
# If this builds clean, F4/F6 are confirmed as Fedora-44 artifacts and the F7
# runtime crash can finally be investigated on a trustworthy foundation.
set -uo pipefail

SRC="$HOME/darling"
BUILD="$SRC/build"
JOBS="${JOBS:-$(nproc)}"

log() { printf '\n=== %s ===\n' "$*"; }

cd "$SRC" || { echo "FATAL: $SRC missing"; exit 1; }

log "toolchain (want clang 19.x to match the author)"
clang --version | head -1

log "deviation audit — expect F1+F2 present, F6 ABSENT"
grep -q 'DARLING-ARM64 LOCAL PATCH' \
  src/external/xnu/darling/src/libsystem_kernel/emulation/include/linux_premigration/ext/sys/epoll.h \
  && echo "  F1 epoll_create1 decl: present" || echo "  F1: MISSING (expected present)"
grep -q 'DARLING-ARM64 LOCAL PATCH' src/external/libkqueue/src/linux/timer.c \
  && echo "  F2 timer type fix:     present" || echo "  F2: MISSING (expected present)"
grep -q 'HAVE_AS_CFI_PSEUDO_OP 1' src/external/libffi/darwin/include/fficonfig_arm64.h \
  && echo "  F6 libffi CFI:         REVERTED (stock, correct)" \
  || echo "  F6: still patched — revert it, clang 19 should not need it"

mkdir -p "$BUILD"; cd "$BUILD"
if [ ! -f CMakeCache.txt ]; then
    log "configure — no CMAKE_C_FLAGS overrides at all"
    cmake .. -DCMAKE_BUILD_TYPE=Release > /tmp/cfg.log 2>&1
    echo "configure rc=$?"; tail -4 /tmp/cfg.log
fi
for v in TARGET_ARM64 TARGET_x86_64 CMAKE_C_COMPILER CMAKE_BUILD_TYPE; do
    printf '  %-20s %s\n' "$v" "$(grep -E "^${v}:" CMakeCache.txt 2>/dev/null | cut -d= -f2-)"
done

log "building with -j$JOBS (long)"
make -j"$JOBS" > "$HOME/build.log" 2>&1
rc=$?

log "result"
echo "make rc=$rc"
echo "progress: $(grep -oE '^\[ *[0-9]+%\]' "$HOME/build.log" | tail -1)"
echo "errors:   $(grep -ciE 'error:' "$HOME/build.log")"
if [ "$rc" != 0 ]; then
    echo "--- first error ---"
    n=$(grep -n -iE 'error:' "$HOME/build.log" | head -1 | cut -d: -f1)
    [ -n "$n" ] && sed -n "$((n>6?n-6:1)),$((n+14))p" "$HOME/build.log"
else
    echo "CLEAN BUILD — no relaxations needed. F4/F6 were Fedora-44 artifacts."
fi
exit "$rc"
