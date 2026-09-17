#!/usr/bin/env bash
# Runs INSIDE the Ubuntu VM (host side is fine — it only makes symlinks).
#
# GAP IN THE NORTH-STAR TOOLING:
#   tools/stage-darling-arm64.sh uses  -Wl,-syslibroot,$BUILD/stage-link  (line 52)
#   and later  cp -aL $BUILD/stage-link/usr/lib/.  (line 123)
#   ...but NOTHING in the repo creates stage-link. Not a ninja target
#   (grep build.ninja -> 0 hits), not a cmake rule, not a script.
#   darling-aarch64-port-report.md calls it "a temporary symlink-only link stage",
#   i.e. it was built by hand during development and never automated.
#
#   Consequence on a clean machine: build-headless.sh completes every ninja step
#   and then dies at the first smoke-binary link with
#     ld: file not found: /usr/lib/system/libsystem_sandbox.dylib for architecture arm64
#   which looks like a missing library but is really a missing sysroot.
#
# This reconstructs stage-link deterministically. cmake/use_ld64.cmake already
# encodes the complete mapping as -dylib_file <install_name>:<build_path>, which
# is precisely "where Darwin thinks this library lives" -> "where we built it".
# We mirror that into a sysroot tree of symlinks.
set -euo pipefail

BUILD="${1:-$HOME/darling/build-arm64}"
STAGE="$BUILD/stage-link"

[ -f "$BUILD/build.ninja" ] || { echo "FATAL: no build.ninja under $BUILD" >&2; exit 1; }

echo "=== extracting dylib_file mappings from build.ninja ==="
mappings=$(grep -oE '\-dylib_file,[^,[:space:]]+:[^,[:space:]]+' "$BUILD/build.ninja" \
           | sed 's/^-dylib_file,//' | sort -u)
total=$(printf '%s\n' "$mappings" | grep -c . || echo 0)
echo "  distinct mappings: $total"

rm -rf "$STAGE"
linked=0; absent=0
while IFS= read -r m; do
    [ -n "$m" ] || continue
    install_name=${m%%:*}
    build_path=${m#*:}
    # build.ninja records container paths (/work/build-arm64/...). Rewrite to the
    # real location so the symlinks resolve on either side of the mount.
    real_path=${build_path/\/work\/build-arm64/$BUILD}

    # PREFER THE FINAL LIBRARY OVER THE FIRSTPASS STUB.
    # use_ld64.cmake's mappings deliberately point at *_firstpass.dylib — bootstrap
    # stubs that permit undefined symbols to break circular dependencies at link
    # time. But stage-darling-arm64.sh also does `cp -aL stage-link/usr/lib/.` into
    # the RUNTIME root, so staging a firstpass stub yields a runtime library with
    # unresolved symbols. Observed symptom:
    #   dyld: Symbol not found: _libsimple_lock_lock
    #     Referenced from: .../libsystem_kernel.dylib   (libsimple is a STATIC lib
    #     linked into the final dylib but absent from the firstpass stub)
    # The rename is not a simple suffix strip (libplatform_firstpass.dylib ->
    # libsystem_platform.dylib), so match on the INSTALL NAME's basename, which is
    # by definition what the file should be called at runtime.
    final_path="$(dirname "$real_path")/$(basename "$install_name")"
    final_cpath="$(dirname "$build_path")/$(basename "$install_name")"
    if [ -e "$final_path" ]; then
        real_path="$final_path"; build_path="$final_cpath"
    fi

    if [ ! -e "$real_path" ]; then
        absent=$((absent+1)); continue
    fi
    dest="$STAGE${install_name}"
    mkdir -p "$(dirname "$dest")"
    ln -sfn "$build_path" "$dest"     # keep CONTAINER path: consumed inside docker
    linked=$((linked+1))
done <<< "$mappings"

echo "  linked:      $linked"
echo "  not built:   $absent  (expected: GUI/optional components in a core build)"

echo "=== sanity ==="
for probe in /usr/lib/system/libsystem_sandbox.dylib /usr/lib/libSystem.B.dylib \
             /usr/lib/system/libsystem_kernel.dylib /usr/lib/libobjc.A.dylib; do
    if [ -L "$STAGE$probe" ]; then
        echo "  OK   $probe -> $(readlink "$STAGE$probe")"
    else
        echo "  MISS $probe"
    fi
done
echo "  total symlinks: $(find "$STAGE" -type l | wc -l)"
