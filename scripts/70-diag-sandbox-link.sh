#!/usr/bin/env bash
# Runs INSIDE the darling-arm64-dev container. Diagnoses why ld64 reports
# "file not found: /usr/lib/system/libsystem_sandbox.dylib" when the mapped
# file demonstrably exists and the -dylib_file mapping is in the link command.
set -uo pipefail
cd /work/build-arm64

CCT=/work/build-arm64/src/external/cctools-port/cctools
OTOOL=$(ls "$CCT"/otool/*otool 2>/dev/null | head -1)

echo "=== mapped file present? ==="
ls -la src/sandbox/libsystem_sandbox.dylib 2>&1

echo "=== its Mach-O identity ==="
if [ -n "$OTOOL" ]; then
    "$OTOOL" -h src/sandbox/libsystem_sandbox.dylib 2>&1 | head -6
    echo "--- its install name ---"
    "$OTOOL" -D src/sandbox/libsystem_sandbox.dylib 2>&1 | head -4
else
    echo "  (no otool built)"
fi

echo "=== who references libsystem_sandbox? ==="
for lib in src/external/libsystem/libSystem.B.dylib \
           src/external/foundation/Foundation \
           src/external/corefoundation/CoreFoundation; do
    [ -f "$lib" ] || continue
    if [ -n "$OTOOL" ]; then
        hits=$("$OTOOL" -L "$lib" 2>/dev/null | grep -ci sandbox)
        echo "  $lib -> $hits sandbox refs"
    fi
done

echo "=== exact ld64 command for defaults (last line) ==="
ninja -v src/external/foundation/defaults > /tmp/nv.txt 2>&1 || true
tail -2 /tmp/nv.txt | head -1 > /tmp/linkcmd.txt
wc -c < /tmp/linkcmd.txt

echo "=== does that command contain the sandbox mapping? ==="
grep -c 'libsystem_sandbox' /tmp/linkcmd.txt

echo "=== the mapping as it appears ==="
tr ' ' '\n' < /tmp/linkcmd.txt | grep 'libsystem_sandbox' | head -3

echo "=== does the mapped path in the command actually exist? ==="
tr ' ' '\n' < /tmp/linkcmd.txt | grep -o 'dylib_file,[^:]*:[^ ]*sandbox[^ ]*' | head -1 \
  | sed 's/.*://' | while read -r p; do
      echo "  path: $p"
      [ -f "$p" ] && echo "  EXISTS" || echo "  MISSING <-- this is the real problem"
  done
