#!/usr/bin/env bash
# Runs INSIDE the Ubuntu VM. Generates a complete, sync-proof set of git url
# rules for the north-star submodule graph.
#
# WHY THIS EXISTS
# ---------------
# deepai-org's configure-private-submodules.sh sets `git config submodule.<n>.url`
# for 32 components. Three problems on a fresh system:
#
#   1. `git submodule sync` (which the same script runs, and which git runs
#      internally) RE-DERIVES every url from .gitmodules and overwrites that
#      config. Per-submodule url settings are therefore not durable.
#   2. .gitmodules uses RELATIVE urls, so they resolve against the superproject
#      remote — deepai-org/darling-aarch64-north-star — producing
#      deepai-org/darling-<Component>, which mostly does not exist.
#   3. Component names differ in case and spelling from the mirror names
#      (darling-Libnotify vs darling-aarch64-libnotify, darling-IOKitUser vs
#      darling-aarch64-iokituser), so a naive mapping misses some.
#
# `url.<real>.insteadOf <wrong>` is applied at TRANSPORT time, survives sync, and
# works at every nesting depth. Git resolves by LONGEST matching prefix, so a
# full-url rule always beats the generic prefix redirect.
#
# Strategy: for every distinct deepai-org/* url in the tree, match the component
# name case-insensitively against the real darling-aarch64-* mirror list. Match
# -> point at the private mirror. No match -> point at darlinghq upstream.
set -euo pipefail

MIRROR_LIST="${1:-$HOME/darling/aarch64-mirrors.txt}"
SRC="${DARLING_SOURCE_ROOT:-$HOME/darling/source}"
cd "$SRC"

[ -f "$MIRROR_LIST" ] || { echo "FATAL: mirror list $MIRROR_LIST missing" >&2; exit 1; }

log() { printf '\n=== %s ===\n' "$*"; }

log "clearing previous url rules"
git config --global --get-regexp '^url\.' | awk '{print $1}' | sed 's/\.insteadof$//i' \
  | sort -u | while read -r k; do git config --global --unset-all "${k}.insteadOf" 2>/dev/null || true; done

log "collecting deepai-org urls referenced by the tree"
git submodule sync --recursive >/dev/null 2>&1 || true
urls=$( { git config --get-regexp '^submodule\..*\.url$' | awk '{print $2}'
          git submodule foreach --recursive --quiet \
            'git config --get-regexp "^submodule\..*\.url$" | awk "{print \$2}"' 2>/dev/null
        } | grep 'github.com/deepai-org/' | sort -u || true )
echo "  distinct deepai-org urls: $(echo "$urls" | grep -c . || echo 0)"

mirrored=0; upstream=0
while read -r url; do
    [ -n "$url" ] || continue
    base=${url##*/}; base=${base%.git}          # darling-Libnotify
    comp=${base#darling-}                        # Libnotify
    case "$base" in darling-aarch64-*) continue;; esac   # already a mirror

    lc=$(printf '%s' "$comp" | tr '[:upper:]' '[:lower:]')
    mirror=$(grep -ix "darling-aarch64-${lc}" "$MIRROR_LIST" || true)
    # a few components differ beyond case (bootstrap_cmds -> bootstrap-cmds)
    [ -z "$mirror" ] && mirror=$(grep -ix "darling-aarch64-${lc//_/-}" "$MIRROR_LIST" || true)

    if [ -n "$mirror" ]; then
        git config --global "url.https://github.com/deepai-org/${mirror}.git.insteadOf" "$url"
        mirrored=$((mirrored+1))
    else
        git config --global "url.https://github.com/darlinghq/${base}.git.insteadOf" "$url"
        upstream=$((upstream+1))
    fi
done <<< "$urls"

echo "  -> private aarch64 mirror: $mirrored"
echo "  -> darlinghq upstream:     $upstream"

log "fetching"
for attempt in 1 2 3 4; do
    echo "--- attempt $attempt ---"
    if git submodule update --init --recursive --jobs "$(nproc)" 2>&1 \
        | grep -vE "^Cloning into|checked out|^From |^ \* branch" | tail -6; then :; fi
    bad=$(git submodule status --recursive | grep -c '^+' || true)
    miss=$(git submodule status --recursive | grep -c '^-' || true)
    echo "  wrong-commit=$bad missing=$miss"
    [ "$bad" = 0 ] && [ "$miss" = 0 ] && break
done

log "final health"
echo "  total: $(git submodule status --recursive | wc -l)"
echo "  missing: $(git submodule status --recursive | grep -c '^-' || true)"
echo "  wrong-commit: $(git submodule status --recursive | grep -c '^+' || true)"
git submodule status --recursive | grep '^+' | head -10 || true
