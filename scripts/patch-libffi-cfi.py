#!/usr/bin/env python3
"""
DARLING-ARM64 LOCAL PATCH.

clang's integrated Mach-O aarch64 assembler rejects the CFI directive forms
libffi emits from src/aarch64/sysv.S when targeting aarch64-apple-darwin20:

    .cfi_def_cfa x1, 40;
    .cfi_adjust_cfa_offset (8*2 + (8 * 16 + 8 * 8) + 64)
        -> error: invalid CFI advance_loc expression

libffi's include/ffi_cfi.h degrades every cfi_* macro to a no-op when
HAVE_AS_CFI_PSEUDO_OP is undefined -- exactly the escape hatch this situation
calls for. darwin/include/fficonfig_arm64.h asserts it unconditionally.

Tradeoff: no DWARF unwind info through ffi trampolines. Acceptable for a
measurement build. A proper upstream fix should correct the directives (drop the
trailing semicolon, avoid parenthesised arithmetic in CFI operands) rather than
disable CFI wholesale.
"""
import sys, pathlib

p = pathlib.Path(sys.argv[1] if len(sys.argv) > 1
                 else "darwin/include/fficonfig_arm64.h")
src = p.read_text()
gate = "#define HAVE_AS_CFI_PSEUDO_OP 1"

if "DARLING-ARM64 LOCAL PATCH" in src:
    print("already patched")
    sys.exit(0)
if gate not in src:
    print(f"FATAL: gate not found in {p}", file=sys.stderr)
    sys.exit(1)

p.write_text(src.replace(gate, (
    "/* DARLING-ARM64 LOCAL PATCH: clang's integrated Mach-O aarch64 assembler\n"
    "   rejects the CFI forms libffi emits from src/aarch64/sysv.S. ffi_cfi.h\n"
    "   degrades cfi_* to no-ops when this is undefined. See FINDINGS.md F6. */\n"
    "#undef HAVE_AS_CFI_PSEUDO_OP"
)))
print(f"patched {p}")
