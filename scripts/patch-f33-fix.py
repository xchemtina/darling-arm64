#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F33. Idempotent. Run from ~/darling/source.

THE DEFECT, ESTABLISHED WITH DATA
---------------------------------
`t06_objc.arm64e` died with SIGSEGV before printing anything. A frame-chain walk
(scripts/patch-f33-backtrace.py), symbolised against CoreFoundation at 0x300660000,
showed a perfect two-frame cycle to the stack guard page:

    _CFStringGetCharacters + 0x10                     <- pc
    -[__NSCFString getCharacters:range:] + 0x64       <- alternating
    _CFStringGetCharacters + 0x168                    <- alternating

i.e. CFString.c:2026 dispatches to ObjC, NSString.m:327 calls straight back in:

    CFStringGetCharacters -> CF_OBJC_FUNCDISPATCHV -> -[__NSCFString getCharacters:range:]
                          -> CFStringGetCharacters -> ...

That loop is meant to be broken by `CF_IS_OBJC(typeID, obj)`, i.e.
`!_CFIsCFObject(obj)` (CFInternal.h:592), which recognises a CF object and handles
it in C instead of dispatching. Instrumenting it (scripts/patch-f33-trace.py) shows
exactly why it fails on arm64e:

    obj=0x100004068
    raw_isa         = 0x4c000300845838
    object_getClass = 0x4c000300845838      <- PAC signature bits still present
    constStrCls     = 0x  300845838         <- the real class pointer
    cfinfo=0x000007c8 typeID=7 tableCls=0x300846918 isCF=0

The object is the client binary's constant CFString. In an arm64e image the isa in
`__cfstring` is PAC-signed, and **Darling has no PAC hardware** -- it emulates the
instructions by faulting and fixing up (see `strip_unsupported_ptrauth_pc` and
`strip_unsupported_ptrauth_data_address` in sigexc.c). So the signature bits survive
in the pointer, every class comparison in `_CFIsCFObject` fails, CF concludes the
object is a foreign ObjC object, and the bridge recurses forever.

The same binary built for arm64 runs to completion, and the trace never fires there
-- the contrast is what localises this to the PAC path.

WHY THE FIX GOES HERE
---------------------
The root cause is broader than CoreFoundation: `objc-config.h:94` sets
`SUPPORT_PACKED_ISA 0` for `defined(DARLING) && defined(__arm64__)`, so
`SUPPORT_NONPOINTER_ISA` is 0 and objc4's isa accessors return `isa.cls` **raw**,
with no `clsbits &= ISA_MASK` step. Every isa read from an arm64e image therefore
carries signature bits. Fixing that properly means changing objc4's isa handling or
the arm64e chained-fixup path, which is a core change with wide blast radius and
needs more verification than one session affords.

`_CFIsCFObject` is, however, the single gate for **all** CF<->ObjC bridging, so
masking here repairs the whole bridging layer for arm64e -- which is where this
class of defect actually bites -- at zero risk to the ObjC runtime.

This is deliberately a **containment fix, not the root-cause fix.** The root cause
stays open in FINDINGS.md F33 with the evidence above.

The mask keeps the low 48 bits. Darling maps images below 2^47 (it deliberately
mmaps low to avoid ObjC's 47-bit FAST_DATA_MASK), so no legitimate class pointer
loses bits, and on any non-arm64 build the code is unchanged.

Revert with: cd src/external/corefoundation && git checkout -- CFInternal.h
"""
import sys, pathlib

P = pathlib.Path("src/external/corefoundation/CFInternal.h")

OLD = """	uintptr_t isa = ((CFRuntimeBase *)obj)->_cfisa;
	if (isa == 0) return 1;
	// at this point, it's definetely a valid objc object,
	// but we'd still like to return 1 for __NSCF types
	Class cls = object_getClass((id)obj);
	if (cls == __CFConstantStringClassReferencePtr) return 1;
"""

NEW = """	uintptr_t isa = ((CFRuntimeBase *)obj)->_cfisa;
	if (isa == 0) return 1;
	// at this point, it's definetely a valid objc object,
	// but we'd still like to return 1 for __NSCF types
	Class cls = object_getClass((id)obj);

	/* DARLING-ARM64 FIX (FINDINGS.md F33): strip pointer-authentication bits.
	 *
	 * In an arm64e image the isa of a compiler-emitted constant object (e.g. the
	 * __cfstring entries behind @"..." literals) is PAC-signed. Darling has no PAC
	 * hardware -- it emulates the instructions by faulting and fixing up, see
	 * strip_unsupported_ptrauth_* in sigexc.c -- and objc4 is built here with
	 * SUPPORT_PACKED_ISA 0 for arm64 (objc-config.h:94), so its isa accessors
	 * return isa.cls raw with no ISA_MASK step. The signature bits therefore
	 * survive into object_getClass():
	 *
	 *     object_getClass = 0x4c000300845838
	 *     real class      = 0x000300845838
	 *
	 * Every comparison below then fails, CF decides a CF object is a foreign ObjC
	 * object, and CFStringGetCharacters <-> -[__NSCFString getCharacters:range:]
	 * recurse until the stack dies.
	 *
	 * Darling maps images below 2^47 (deliberately, to stay clear of ObjC's
	 * 47-bit FAST_DATA_MASK), so keeping the low 48 bits cannot truncate a real
	 * class pointer.
	 *
	 * This is containment, not the root-cause fix: the raw-isa problem is
	 * runtime-wide, and _CFIsCFObject is merely the gate for all CF<->ObjC
	 * bridging. See FINDINGS.md F33. */
#if defined(__arm64__)
	cls = (Class)(((uintptr_t)cls) & 0x0000FFFFFFFFFFFFULL);
#endif

	if (cls == __CFConstantStringClassReferencePtr) return 1;
"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F33" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: anchor found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: isa PAC bits stripped before class comparison")
