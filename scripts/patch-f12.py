#!/usr/bin/env python3
"""
DARLING-ARM64 LOCAL PATCH for FINDINGS.md F12. Run from ~/darling. Idempotent.

src/external/ruby/ruby/ext/fiddle/closure.c

fiddle picks its libffi closure API with a platform heuristic:

    #if defined(USE_FFI_CLOSURE_ALLOC)
    #elif defined(__OpenBSD__) || defined(__APPLE__) || defined(__linux__)
    # define USE_FFI_CLOSURE_ALLOC 0        <-- taken, because Darling is __APPLE__
    ...

USE_FFI_CLOSURE_ALLOC 0 selects the legacy ffi_prep_closure() + mprotect() path.
That assumption held on x86 macOS, but Apple's ffitarget_arm64.h sets
FFI_LEGACY_CLOSURE_API 0 (x86 sets it to 1), so on arm64 ffi_prep_closure is not
even declared -- the legacy API writes inline executable trampolines, which is
incompatible with W^X and pointer authentication.

The modern pair (ffi_closure_alloc / ffi_prep_closure_loc) IS declared
unconditionally in the SDK header, and fiddle already implements that path. So
select it explicitly on arm64 Apple, before the stale heuristic runs.
"""
import sys, pathlib

P = pathlib.Path("src/external/ruby/ruby/ext/fiddle/closure.c")
ANCHOR = "#if defined(USE_FFI_CLOSURE_ALLOC)"
ADD = (
    "/* DARLING-ARM64 LOCAL PATCH (FINDINGS.md F12): the __APPLE__ branch below\n"
    "   assumes the legacy closure API exists -- true only on x86 macOS. Apple's\n"
    "   ffitarget_arm64.h sets FFI_LEGACY_CLOSURE_API 0, so ffi_prep_closure is not\n"
    "   declared on arm64. Select the modern ffi_closure_alloc/ffi_prep_closure_loc\n"
    "   path, which fiddle already implements, before that heuristic runs. */\n"
    "#if !defined(USE_FFI_CLOSURE_ALLOC) && defined(__APPLE__) && \\\n"
    "    (defined(__arm64__) || defined(__aarch64__))\n"
    "# define USE_FFI_CLOSURE_ALLOC 1\n"
    "#endif\n"
    "\n" + ANCHOR
)

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "FINDINGS.md F12" in s:
    print("already patched"); sys.exit(0)
if ANCHOR not in s:
    print("FATAL: anchor not found", file=sys.stderr); sys.exit(1)
P.write_text(s.replace(ANCHOR, ADD, 1))
print(f"patched {P}")
