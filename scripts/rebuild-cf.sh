#!/usr/bin/env bash
# Incremental CoreFoundation + Foundation rebuild and re-stage.
#
# TWO DEFECTS FIXED HERE 2026-08-11, both of which had been silently corrupting
# results. Recorded because the failure mode was invisible:
#
#   1. TRAP 10 -- the old version ran `ninja ... | tail -25` and then read `rc=$?`.
#      `$?` after a pipeline is the status of the LAST command, i.e. `tail`, which
#      succeeds whatever ninja does. So a failed build reported rc=0 and the script
#      went on to stage. This is the same trap that once produced a bogus
#      "11/11 gates pass". Fixed by testing ninja's own status directly.
#
#   2. The `tail -25` also violated the project rule to capture the FIRST error:
#      ninja prints the root cause early and hundreds of follow-on lines after it,
#      so the tail showed warnings from an unrelated translation unit while the
#      actual error had scrolled away. Full output now goes to a file, and the
#      first error is printed on failure.
#
# Consequence of (1) while it was live: on any failed build this script staged
# nothing new and said "staged", leaving the PREVIOUS binary in place -- so the
# verifiers then measured stale code that did not contain the change under test
# (trap 16). Always confirm the staged timestamp moved.
set -uo pipefail

SRC=$HOME/darling/source
B=$HOME/darling/build-arm64-gui
S=$HOME/darling/install-arm64-stage10
LOG=${REBUILD_LOG:-$HOME/rebuild-full.log}

before=$(stat -c %Y "$S/root/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation" 2>/dev/null || echo 0)

docker run --rm --platform linux/arm64 \
    -v "$SRC:/work/source:ro" -v "$B:/work/build" \
    darling-arm64-dev:latest \
    bash -lc "cd /work/build && ninja CoreFoundation_arm64 Foundation_arm64" \
    > "$LOG" 2>&1
rc=$?          # no pipe: this really is ninja's (well, docker's) status

if [ "$rc" != 0 ]; then
    echo "BUILD FAILED rc=$rc  (full log: $LOG)"
    echo "--- first error ---"
    grep -nE "error:|FAILED:" "$LOG" | head -5
    echo "--- context around it ---"
    n=$(grep -nE "error:|FAILED:" "$LOG" | head -1 | cut -d: -f1)
    [ -n "${n:-}" ] && sed -n "$((n>4 ? n-4 : 1)),$((n+18))p" "$LOG"
    exit "$rc"
fi

echo "build ok ($(wc -l < "$LOG") lines, $(grep -c 'warning:' "$LOG") warnings)"

docker run --rm --platform linux/arm64 \
    -v "$SRC:/work/source:ro" -v "$B:/work/build" -v "$S:/work/stage" \
    darling-arm64-dev:latest bash -lc "
    rm -rf /tmp/cf-dest
    DESTDIR=/tmp/cf-dest cmake --install /work/build --component cli_gui_common >/tmp/i.log 2>&1
    DESTDIR=/tmp/cf-dest cmake --install /work/build --component core >>/tmp/i.log 2>&1
    cp -a /tmp/cf-dest/usr/local/libexec/darling/. /work/stage/root/ 2>/dev/null
    echo staged"
srt=$?
[ "$srt" = 0 ] || { echo "STAGING FAILED rc=$srt"; exit "$srt"; }

# TRAP 16: prove the binary that will actually run was replaced.
after=$(stat -c %Y "$S/root/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation" 2>/dev/null || echo 0)
if [ "$after" = "$before" ]; then
    echo "WARNING: staged Foundation timestamp did not change ($after) -- the"
    echo "         verifiers would measure the OLD binary. Treat any result as void."
    exit 3
fi
echo "staged ok: Foundation mtime $before -> $after"
