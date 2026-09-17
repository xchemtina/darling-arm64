#!/usr/bin/env bash
# Runs INSIDE the Ubuntu VM. Robust submodule resolution for the north-star tree.
#
# Two gaps in deepai-org's configure-private-submodules.sh, both only visible on a
# genuinely fresh system:
#
# 1. NESTED submodules. .gitmodules uses relative urls at every level. Git resolves
#    them against the *parent repo's* remote, so nested modules under a private
#    mirror (e.g. IOKitUser -> IOGraphics, IOHIDFamily) resolve to
#    deepai-org/darling-IOGraphics — 404. Per-submodule `git config` only fixes the
#    top level. `url.<x>.insteadOf` is applied at transport time, so it works at
#    every depth. Git picks the LONGEST matching insteadOf, so an identity rule on
#    the darling-aarch64- prefix protects the genuine private mirrors from the
#    generic deepai-org -> darlinghq redirect.
#
# 2. MISSING MIRRORS. Four private ARM64 repos exist but are absent from the
#    32-entry map, so their pinned commits cannot be found anywhere:
#    configd, libnotify, metal, swift-crypto. configd fails loudly with
#    "upload-pack: not our ref".
set -euo pipefail

SRC="${DARLING_SOURCE_ROOT:-$HOME/darling/source}"
cd "$SRC"
log() { printf '\n=== %s ===\n' "$*"; }

log "installing transport-level url rules (apply at every nesting depth)"
# Generic: any deepai-org/darling-* that is not an aarch64 mirror -> darlinghq.
git config --global \
    "url.https://github.com/darlinghq/darling-.insteadOf" \
    "https://github.com/deepai-org/darling-"
# Identity guard: longer prefix wins, keeping real private mirrors on deepai-org.
git config --global \
    "url.https://github.com/deepai-org/darling-aarch64-.insteadOf" \
    "https://github.com/deepai-org/darling-aarch64-"
git config --global --get-regexp '^url\.' | sed 's/^/  /'

log "adding the four mirrors missing from the upstream map"
declare -A EXTRA=(
    [src/external/configd]=darling-aarch64-configd
    [src/external/libnotify]=darling-aarch64-libnotify
    [src/external/metal]=darling-aarch64-metal
    [src/external/swift-crypto]=darling-aarch64-swift-crypto
)
for path in "${!EXTRA[@]}"; do
    name=$(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' |
        awk -v p="$path" '$2 == p { k=$1; sub(/^submodule\./,"",k); sub(/\.path$/,"",k); print k }')
    if [ -n "$name" ]; then
        git config "submodule.$name.url" "https://github.com/deepai-org/${EXTRA[$path]}.git"
        echo "  $path -> ${EXTRA[$path]}"
    else
        echo "  (no submodule declared at $path — skipping)"
    fi
done

log "fetching submodules recursively"
for attempt in 1 2 3; do
    echo "--- attempt $attempt ---"
    if git submodule update --init --recursive --jobs "$(nproc)" 2>&1 \
        | grep -vE "^Cloning into|checked out" | tail -12; then
        break
    fi
done

log "health"
total=$(git submodule status --recursive 2>/dev/null | wc -l)
missing=$(git submodule status --recursive 2>/dev/null | grep -c '^-' || true)
mismatch=$(git submodule status --recursive 2>/dev/null | grep -c '^+' || true)
echo "  total: $total   uninitialised: $missing   wrong-commit: $mismatch"
[ "$missing" != "0" ] && { echo "  --- missing ---"; git submodule status --recursive | grep '^-' | head -20; }
[ "$mismatch" != "0" ] && { echo "  --- wrong commit ---"; git submodule status --recursive | grep '^+' | head -20; }

log "empty-worktree scan (right SHA, no files — status reports these as clean)"
empty=0
for s in $(git submodule status --recursive 2>/dev/null | awk '{print $2}'); do
    n=$(ls -A "$s" 2>/dev/null | grep -v '^\.git$' | wc -l)
    if [ "$n" -eq 0 ]; then echo "  EMPTY: $s"; empty=$((empty+1)); fi
done
echo "  empty worktrees: $empty"
