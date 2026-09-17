#!/usr/bin/env bash
# reproduce.sh — turnkey verification of the core claims. Runs the capability ladder,
# one Silver gate, and the leak-ABA short cycle against a staged Stage 18 runtime,
# and prints a pass/fail summary. Full per-claim map: REPRODUCE.md.
#
# Prerequisites (checked below, with actionable errors):
#   - native aarch64 Linux + docker
#   - a staged Stage 18 runtime (DARLING_STAGE18_ROOT, default install-arm64-stage18)
#   - an Apple dyld shared cache (ITERM2_SHARED_CACHE_ROOT) -- see
#     tools/prepare-macos-shared-cache.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
src_root=$(cd "$here/.." && pwd)          # tools/ -> source root
ws=$(cd "$src_root/.." && pwd)
cd "$src_root"

pass=0; fail=0
line() { printf '  %-42s %s\n' "$1" "$2"; }
run()  {  # $1 label  $2... command
	local label=$1; shift
	if "$@" >/tmp/reproduce-step.log 2>&1; then line "$label" "PASS"; pass=$((pass+1))
	else line "$label" "FAIL (rc=$?; see /tmp/reproduce-step.log)"; fail=$((fail+1)); fi
}

echo "== prerequisites =="
[[ $(uname -m) == aarch64 ]] || { echo "  need native aarch64 (this is $(uname -m)); Darling is a translation layer, not an emulator."; exit 2; }
command -v docker >/dev/null || { echo "  docker not found."; exit 2; }
: "${ITERM2_SHARED_CACHE_ROOT:?set ITERM2_SHARED_CACHE_ROOT (see tools/prepare-macos-shared-cache.sh)}"
export DARLING_STAGE18_ROOT=${DARLING_STAGE18_ROOT:-$ws/install-arm64-stage18}
export DARLING_STAGE18_BUILD_ROOT=${DARLING_STAGE18_BUILD_ROOT:-$ws/build-arm64-stage18}
export DARLING_ARM64_INSTALL_ROOT=$DARLING_STAGE18_ROOT
[[ -d $DARLING_STAGE18_ROOT/root ]] || { echo "  no staged runtime at $DARLING_STAGE18_ROOT; run tools/bootstrap-iterm2-stage18.sh first."; exit 2; }
[[ -f $DARLING_STAGE18_ROOT/root/usr/bin/login ]] || echo "  WARNING: /usr/bin/login absent -- Silver will stall at session start (F79)."
line "aarch64 + docker + cache + runtime" "ok"

echo
echo "== core claims =="
run "capability ladder (12/12)"      tools/verify-north-star-arm64.sh quick
run "Silver: independent tabs"        tools/verify-iterm2-silver-tabs-arm64.sh
run "per-resize leak measurable (F85)" bash -c 'tools/f85-resize-leak.sh >/dev/null 2>&1; test -s "$0/artifacts/f85-resize-leak/f85-samples.txt"' "$ws"

echo
echo "== summary =="
echo "  $pass passed, $fail failed"
echo "  (leak FIX validation is the full ABA: tools/f92-leak-aba.sh; see REPRODUCE.md for the rest)"
exit $(( fail > 0 ))