#!/usr/bin/env python3
"""
DARLING-ARM64 ROOT-CAUSE FIX for FINDINGS.md F33/F41. Idempotent.
Run from ~/darling/source.

THE DEFECT
----------
On arm64e, compiler-emitted constant objects carry **PAC-signed isa pointers**.
Darling has no PAC hardware -- it emulates the instructions by faulting and fixing
up (`strip_unsupported_ptrauth_*` in sigexc.c) -- so the signature bits survive in
the pointer. objc4 here is built with `SUPPORT_PACKED_ISA 0` for
`defined(DARLING) && defined(__arm64__)` (objc-config.h:94), hence
`SUPPORT_NONPOINTER_ISA 0`, and `isa_t::getClass()` reduces to:

    #if !SUPPORT_NONPOINTER_ISA
        return cls;          // raw -- no `clsbits &= ISA_MASK` anywhere

Every `ISA()` read therefore returns a pointer with signature bits still attached,
and **every class-identity comparison against a clean pointer fails**. Measured:

    object_getClass = 0x4c000300845838
    real class      = 0x000300845838

Two independent failures traced to this:

  F33  `_CFIsCFObject` (CFInternal.h:592) misjudges a CF object as a foreign ObjC
       object, so CFStringGetCharacters dispatches to
       -[__NSCFString getCharacters:range:], which calls straight back in --
       unbounded recursion to the stack guard page.
  F41  `cls->ISA() == metacls` (objc-runtime-new.mm:2228,2236) never matches, so
       NSInvocation / forwarding / swizzling dies with
       `_objc_fatal("cls is not an instance of metacls")`.

F41 is what makes this fixable with confidence: `t15_invoke.arm64e` fails and
`t15_invoke.arm64` passes, so there is finally a test that exercises the defect.
STATE.md trap 17 exists because F33's fix could not be credited without one.

THE FIX
-------
Strip the signature bits at the single site every isa read goes through. On a
runtime with no PAC hardware, bits above the virtual address range are never
meaningful in an isa.

Masking to the low 48 bits is safe here: Darling deliberately mmaps images below
2^47 to stay clear of ObjC's 47-bit FAST_DATA_MASK (STATE.md), and the measured
image bases confirm it -- 41 file-backed images all mapped in the 0x3_0000_0000
range. On a plain arm64 image the high bits are already zero, so the mask is a
no-op there.

This supersedes the containment fix in `_CFIsCFObject`, which covered CF<->ObjC
bridging only. That patch is left in place -- it is correct and cheap -- but this is
the fix that addresses the cause.

NOTE (STATE.md trap 16): rebuild every binary that links objc4, not just
libobjc.A.dylib, or the change will appear to do nothing.

Revert with: cd src/external/objc4 && git checkout -- runtime/objc-object.h
"""
import sys, pathlib

P = pathlib.Path("src/external/objc4/runtime/objc-object.h")

# NOTE: objc-object.h defines isa_t::getClass() TWICE -- once in the
# SUPPORT_NONPOINTER_ISA section (~line 234, with the ISA_MASK logic) and once in
# the `#else // not SUPPORT_NONPOINTER_ISA` section (~line 987). Darling/arm64 sets
# SUPPORT_PACKED_ISA 0, so the SECOND one is what compiles. Patching the first has
# no effect whatsoever -- verified the hard way, twice.
OLD = """inline Class
isa_t::getClass(bool authenticated __unused)
{
    return cls;
}
"""

NEW = """inline Class
isa_t::getClass(bool authenticated __unused)
{
#if defined(DARLING) && defined(__arm64__)
    /* DARLING-ARM64 FIX (FINDINGS.md F33, F41): strip pointer-authentication bits.
     *
     * In an arm64e image the isa of a compiler-emitted class or constant object is
     * PAC-signed. Darling has no PAC hardware -- it emulates the instructions by
     * faulting and fixing up (strip_unsupported_ptrauth_* in sigexc.c) -- so the
     * signature bits survive in the pointer. This is the raw-isa path (objc4 here
     * builds with SUPPORT_PACKED_ISA 0, objc-config.h:94), so nothing masks them,
     * and every class-identity comparison against a clean pointer fails:
     *
     *     [F41] FAIL inst=0x1000081f0 metacls=0x1000081c8
     *     [F41]   [0] cls=0x1000081f0 ISA=0x510001000081c8 name=Target
     *
     * 0x510001000081c8 & 0x0000FFFFFFFFFFFF == 0x1000081c8 == metacls. The high
     * bits vary run to run, which is what identifies them as a signature rather
     * than an address.
     *
     * Observed breaking `cls->ISA() == metacls` in getNonMetaClass
     * (objc-runtime-new.mm:2228), which kills NSInvocation, message forwarding and
     * swizzling for any arm64e binary, and `_CFIsCFObject` in CoreFoundation
     * (FINDINGS.md F33).
     *
     * Masking to 48 bits is safe: Darling deliberately maps images below 2^47 to
     * stay clear of ObjC's 47-bit FAST_DATA_MASK, and on a plain arm64 image the
     * high bits are already zero, so this is a no-op there. */
    return (Class)(((uintptr_t)cls) & 0x0000FFFFFFFFFFFFULL);
#else
    return cls;
#endif
}
"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F33, F41" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: raw-isa getClass anchor found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: raw-isa getClass() now strips PAC signature bits")
