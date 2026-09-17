#!/usr/bin/env python3
"""
DARLING-ARM64 DIAGNOSTIC for FINDINGS.md F33. Idempotent. Run from ~/darling/source.

ESTABLISHED SO FAR (backtrace, symbolised against CoreFoundation @ 0x300660000):

    pc   = _CFStringGetCharacters + 0x10
    lr A = -[__NSCFString getCharacters:range:] + 0x64
    lr B = _CFStringGetCharacters + 0x168

repeating as a two-frame cycle until the stack hits its guard page. The loop is:

    CFStringGetCharacters (CFString.c:2026)
        -> CF_OBJC_FUNCDISPATCHV(...)              [dispatches only if CF_IS_OBJC]
        -> -[__NSCFString getCharacters:range:]    (NSString.m:327)
        -> CFStringGetCharacters                   ... and around again

The loop exists in the source unconditionally; what normally breaks it is
`CF_IS_OBJC(typeID, obj)` == `!_CFIsCFObject(obj)` returning false, so CF handles a
CF object itself instead of dispatching to ObjC. It does break on arm64 -- the same
program runs to completion. It does not break on arm64e.

HYPOTHESIS TO TEST (not assumed): _CFIsCFObject (CFInternal.h:592) compares class
pointers --

    Class cls = object_getClass((id)obj);
    if (cls == __CFConstantStringClassReferencePtr) return 1;
    ...
    return typeID < __CFRuntimeClassTableSize && cls == (Class)__CFRuntimeObjCClassTable[typeID];

and the faulting object (x0) is the client binary's constant CFString. In an arm64e
image the isa in __cfstring is PAC-signed, and Darling emulates PAC by faulting and
fixing up (see strip_unsupported_ptrauth_* in sigexc.c) rather than in hardware, so
signature bits may still be present in the pointer that comes back. If so, every
comparison above fails, _CFIsCFObject returns 0, CF dispatches to ObjC, and the loop
never terminates.

This prints the actual values so the hypothesis is confirmed or killed by data.
Gated on DARLING_ARM64_CF_TRACE and limited to the first 4 calls, because the
recursion would otherwise produce output until the stack dies.

NOTE (STATE.md trap 16): CFString.c is in CoreFoundation.dylib only, so
~/rebuild-cf.sh is sufficient here -- unlike sigexc.c, which is also linked
statically into mldr and /usr/lib/dyld.

Revert with: cd src/external/corefoundation && git checkout -- CFString.c
"""
import sys, pathlib

P = pathlib.Path("src/external/corefoundation/CFString.c")

OLD = """void CFStringGetCharacters(CFStringRef str, CFRange range, UniChar *buffer) {
    CF_OBJC_FUNCDISPATCHV(__kCFStringTypeID, void, (NSString *)str, getCharacters:(unichar *)buffer range:NSMakeRange(range.location, range.length));
"""

NEW = """/* DARLING-ARM64 DIAGNOSTIC (FINDINGS.md F33) */
static void __darling_f33_trace(CFStringRef str) {
    static int seen = 0;
    if (seen >= 4 || !getenv("DARLING_ARM64_CF_TRACE")) return;
    seen++;
    uintptr_t raw_isa = ((CFRuntimeBase *)str)->_cfisa;
    Class cls = object_getClass((id)str);
    uint32_t cfinfo = *(uint32_t *)&(((CFRuntimeBase *)str)->_cfinfo);
    CFTypeID typeID = (cfinfo >> 8) & 0x03FF;
    fprintf(stderr,
        "[F33] obj=%p raw_isa=%p object_getClass=%p constStrCls=%p "
        "cfinfo=0x%08x typeID=%lu tableSize=%lu tableCls=%p isCF=%d\\n",
        (void *)str, (void *)raw_isa, (void *)cls,
        (void *)__CFConstantStringClassReferencePtr,
        cfinfo, (unsigned long)typeID,
        (unsigned long)__CFRuntimeClassTableSize,
        (typeID < __CFRuntimeClassTableSize)
            ? (void *)__CFRuntimeObjCClassTable[typeID] : NULL,
        (int)_CFIsCFObject(str));
    fflush(stderr);
}

void CFStringGetCharacters(CFStringRef str, CFRange range, UniChar *buffer) {
    __darling_f33_trace(str);
    CF_OBJC_FUNCDISPATCHV(__kCFStringTypeID, void, (NSString *)str, getCharacters:(unichar *)buffer range:NSMakeRange(range.location, range.length));
"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "__darling_f33_trace" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: anchor found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: CFStringGetCharacters now dumps the _CFIsCFObject inputs")
