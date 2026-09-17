#!/usr/bin/env python3
"""
DARLING-ARM64 LOCAL PATCH for FINDINGS.md F19. Run from ~/darling/source. Idempotent.

src/external/liblzma/CMakeLists.txt:10 sets, unconditionally:
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -msse -msse2 -msse3 -w -nostdinc")

-msse/-msse2/-msse3 are x86-only. clang <= 11 ignored them silently on aarch64;
clang >= 16 makes them a hard error:
    error: unsupported option '-msse' for target 'arm64-apple-darwin20'

kkHAIKE fixed this class upstream (darling-liblzma#2, "-msse* gated by target
arch"), but deepai-org's configure-private-submodules.sh mirror map does NOT
include liblzma, so on a clean north-star checkout this submodule resolves to
unpatched darlinghq/darling-liblzma and the GUI build dies on ~6 objects.
"""
import sys, pathlib

P = pathlib.Path("src/external/liblzma/CMakeLists.txt")
OLD = 'set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -msse -msse2 -msse3 -w -nostdinc")'
NEW = (
    "# DARLING-ARM64 LOCAL PATCH (FINDINGS.md F19): -msse* are x86-only and are a\n"
    "# hard error on clang >= 16 for an arm64 target. Gate them on the target arch.\n"
    "if (TARGET_x86_64 OR TARGET_i386)\n"
    '\tset(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -msse -msse2 -msse3")\n'
    "endif()\n"
    'set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -w -nostdinc")'
)

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "FINDINGS.md F19" in s:
    print("already patched"); sys.exit(0)
if OLD not in s:
    print("FATAL: anchor not found", file=sys.stderr); sys.exit(1)
P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}")
