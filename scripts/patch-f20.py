#!/usr/bin/env python3
"""
DARLING-ARM64 LOCAL PATCH for FINDINGS.md F20. Run from ~/darling/source. Idempotent.

src/external/liblzma/config.h is a CHECKED-IN autoconf output captured on an x86
host, so it hardcodes:
    #define HAVE_IMMINTRIN_H 1

memcmplen.h then does `#ifdef HAVE_IMMINTRIN_H -> #include <immintrin.h>`, pulling
x86 SIMD intrinsics into an arm64 compile:
    immintrin.h:14:2: error: "This header is only meant to be used on x86 and x64"
    mmintrin.h: invalid conversion between vector type '__m64' and integer type
    hresetintrin.h:42:27: invalid input constraint 'a' in asm

Make the definition architecture-conditional instead of removing it, so x86 builds
keep the SSE2 fast path in memcmplen.h.
"""
import sys, pathlib

P = pathlib.Path("src/external/liblzma/config.h")
OLD = "#define HAVE_IMMINTRIN_H 1"
NEW = (
    "/* DARLING-ARM64 LOCAL PATCH (FINDINGS.md F20): this config.h is a checked-in\n"
    " * autoconf result from an x86 host. <immintrin.h> is x86-only and is a hard\n"
    " * error on arm64, so gate it on the actual target architecture. */\n"
    "#if defined(__i386__) || defined(__x86_64__)\n"
    "#define HAVE_IMMINTRIN_H 1\n"
    "#endif"
)

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "FINDINGS.md F20" in s:
    print("already patched"); sys.exit(0)
if OLD not in s:
    print("FATAL: anchor not found", file=sys.stderr); sys.exit(1)
P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}")
