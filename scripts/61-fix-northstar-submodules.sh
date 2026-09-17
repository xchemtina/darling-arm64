#!/usr/bin/env bash
# Runs INSIDE the Ubuntu VM, after configure-private-submodules.sh.
#
# GAP IN THE UPSTREAM GUIDE (worth reporting to deepai-org):
# north-star's .gitmodules uses RELATIVE urls (`../darling-Heimdal.git`). Git
# resolves those against the superproject's remote, which for a fresh clone is
# `deepai-org/darling-aarch64-north-star`. So every submodule NOT in the 32-entry
# mirrors map in configure-private-submodules.sh resolves to
# `deepai-org/darling-<X>` — which does not exist (404) — instead of
# `darlinghq/darling-<X>`.
#
# Symptom: "could not read Username for 'https://github.com'" on Heimdal,
# IOKitTools, DirectoryService, AvailabilityVersions, IONetworkingFamily,
# IOStorageFamily, and friends, even with gh fully authenticated.
#
# Fix: any submodule url pointing at deepai-org that is NOT one of the
# darling-aarch64-* private mirrors is redirected to darlinghq.
set -euo pipefail

SRC="${DARLING_SOURCE_ROOT:-$HOME/darling/source}"
cd "$SRC"

log() { printf '\n=== %s ===\n' "$*"; }

log "rewriting non-mirrored submodule urls to darlinghq"
fixed=0; kept=0
while read -r key url; do
    name="${key#submodule.}"; name="${name%.url}"
    case "$url" in
        *github.com/deepai-org/darling-aarch64-*)
            kept=$((kept+1)) ;;                     # genuine private ARM64 mirror
        *github.com/deepai-org/*)
            new="${url/github.com\/deepai-org\//github.com/darlinghq/}"
            git config "submodule.$name.url" "$new"
            fixed=$((fixed+1)) ;;
    esac
done < <(git config --get-regexp '^submodule\..*\.url$' || true)
echo "  private aarch64 mirrors kept: $kept"
echo "  redirected to darlinghq:      $fixed"

log "fetching submodules (this takes a while)"
git submodule update --init --recursive --jobs "$(nproc)" 2>&1 \
    | grep -vE "^Cloning into|^Submodule path .* checked out" | tail -30 || true

log "submodule health"
total=$(git submodule status --recursive 2>/dev/null | wc -l)
missing=$(git submodule status --recursive 2>/dev/null | grep -c '^-' || true)
mismatch=$(git submodule status --recursive 2>/dev/null | grep -c '^+' || true)
echo "  total: $total   uninitialised: $missing   wrong-commit: $mismatch"
[ "$missing" != "0" ] && { echo "  --- still missing ---"; git submodule status --recursive | grep '^-' | head -15; }

# Empty-worktree check: a submodule can sit at the right SHA with no files if a
# clone was interrupted. git submodule status reports it clean; only the build
# notices. (Hit this on libcxx/libcxxabi in the earlier kkHAIKE tree.)
log "empty-worktree scan"
empty=0
for s in $(git submodule status --recursive 2>/dev/null | awk '{print $2}'); do
    n=$(ls -A "$s" 2>/dev/null | grep -v '^\.git$' | wc -l)
    if [ "$n" -eq 0 ]; then echo "  EMPTY: $s"; empty=$((empty+1)); fi
done
echo "  empty worktrees: $empty"
