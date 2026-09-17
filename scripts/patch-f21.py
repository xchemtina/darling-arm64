#!/usr/bin/env python3
"""
DARLING-ARM64 LOCAL PATCH for FINDINGS.md F21. Run from ~/darling/source. Idempotent.

src/external/bash/bash-3.2/conftypes.h picks HOSTTYPE by architecture:

    #  elif __ppc__
    #    define HOSTTYPE "powerpc"
    #  elif __x86_64__
    #    define HOSTTYPE "x86_64"
    #  elif defined(__i386__)
    #    define HOSTTYPE "i386"
    #  elif defined(__arm__)
    #    define HOSTTYPE "arm"
    #  else
    #    define HOSTTYPE CONF_HOSTTYPE      <-- arm64 lands here
    #  endif

There is no __arm64__/__aarch64__ branch (32-bit __arm__ only), so an arm64 build
falls through to CONF_HOSTTYPE, which nothing defines:

    shell.c:1799:74: error: use of undeclared identifier 'CONF_HOSTTYPE'
      (expanded from MACHTYPE -> HOSTTYPE)

"arm64" matches what macOS reports for `uname -m` on Apple Silicon, so MACHTYPE
becomes arm64-apple-darwin<N>, consistent with the rest of the toolchain.
"""
import sys, pathlib

P = pathlib.Path("src/external/bash/bash-3.2/conftypes.h")
OLD = """#  elif defined(__arm__)
#    define HOSTTYPE "arm"
#  else"""
NEW = """#  elif defined(__arm__)
#    define HOSTTYPE "arm"
/* DARLING-ARM64 LOCAL PATCH (FINDINGS.md F21): no arm64 branch existed, so an
 * arm64 build fell through to the undefined CONF_HOSTTYPE. "arm64" is what
 * macOS reports for uname -m on Apple Silicon. */
#  elif defined(__arm64__) || defined(__aarch64__)
#    define HOSTTYPE "arm64"
#  else"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "FINDINGS.md F21" in s:
    print("already patched"); sys.exit(0)
if OLD not in s:
    print("FATAL: anchor not found", file=sys.stderr); sys.exit(1)
P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}")
