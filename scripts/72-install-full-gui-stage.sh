#!/usr/bin/env bash
# Runs INSIDE the darling-arm64-dev container, with:
#   /work/source (ro), /work/build (gui build tree), /work/stage (stage root)
#
# WHY: deepai-org's build-gui.sh installs only `--component gui`. That leaves the
# staged runtime without the transitive dylibs Foundation needs at load time:
#   dyld: Library not loaded: .../CFNetwork   (component cli_gui_common)
#   dyld: Library not loaded: /usr/lib/libbz2.1.0.dylib  (referenced by Security)
# Installing with no --component filter runs every `NOT CMAKE_INSTALL_COMPONENT`
# branch, giving full dependency closure in one pass instead of chasing each
# missing dylib through a separate gate run.
set -uo pipefail

DEST=/tmp/full-install
ROOT="$DEST/usr/local/libexec/darling"

rm -rf "$DEST"
echo "=== installing ALL components ==="
DESTDIR="$DEST" cmake --install /work/build > /tmp/install-all.log 2>&1
rc=$?
echo "install rc=$rc"
[ "$rc" = 0 ] || { tail -5 /tmp/install-all.log; exit "$rc"; }
du -sh "$ROOT"

# The install tree models the Darwin layout, where /etc, /tmp and /var are
# symlinks into /private. The staging script created them as real directories,
# so `cp -a` refuses to replace a directory with a symlink. Remove the empty
# placeholders first; never touch a non-empty one.
echo "=== reconciling dir-vs-symlink layout ==="
for p in etc tmp var; do
    if [ -L "$ROOT/$p" ] && [ -d "/work/stage/root/$p" ] && [ ! -L "/work/stage/root/$p" ]; then
        if [ -z "$(ls -A "/work/stage/root/$p" 2>/dev/null)" ]; then
            rmdir "/work/stage/root/$p" && echo "  replaced empty dir: $p"
        else
            echo "  KEEPING non-empty dir (not replacing with symlink): $p"
        fi
    fi
done

echo "=== copying into stage ==="
cp -a "$ROOT/." /work/stage/root/ && echo "COPIED"
du -sh /work/stage/root

echo "=== key libraries now present? ==="
for f in System/Library/Frameworks/CFNetwork.framework/Versions/A/CFNetwork \
         System/Library/Frameworks/Security.framework/Versions/A/Security \
         System/Library/Frameworks/AppKit.framework/Versions/C/AppKit \
         usr/lib/libbz2.1.0.dylib; do
    [ -e "/work/stage/root/$f" ] && echo "  OK   $f" || echo "  MISS $f"
done
