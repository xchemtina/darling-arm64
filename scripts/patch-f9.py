#!/usr/bin/env python3
"""
DARLING-ARM64 LOCAL PATCH for FINDINGS.md F9. Run from ~/darling. Idempotent.

src/external/xnu/.../bsd/helper/misc/sysctl_machdep.c

Inside an `#if defined(__aarch64__) || defined(__arm64__)` block -- code added by
kkHAIKE in "Add ARM64 (aarch64) build support for Darling on Linux" (eebaed0) --
the CPU-count helper calls strncmp() to scan /proc/cpuinfo, but the block only
declares strncpy(). strncmp() has no declaration in scope, which is a hard error
on clang >= 16 (implicit function declarations removed in C99).

aarch64-only: on x86_64 this whole block is preprocessed away, so the defect is
invisible there. Same class as F1.
"""
import sys, pathlib

P = pathlib.Path("src/external/xnu/darling/src/libsystem_kernel/emulation/"
                 "src/xnu_syscall/bsd/helper/misc/sysctl_machdep.c")
ANCHOR = "extern char *strncpy(char *dest, const char *src, __SIZE_TYPE__ n);"
ADD = (ANCHOR + "\n"
       "/* DARLING-ARM64 LOCAL PATCH (FINDINGS.md F9): strncmp() is used below to\n"
       "   scan /proc/cpuinfo but was never declared in this aarch64-only block. */\n"
       "extern int strncmp(const char *s1, const char *s2, __SIZE_TYPE__ n);")

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "FINDINGS.md F9" in s:
    print("already patched"); sys.exit(0)
if ANCHOR not in s:
    print("FATAL: anchor not found", file=sys.stderr); sys.exit(1)
P.write_text(s.replace(ANCHOR, ADD, 1))
print(f"patched {P}")
