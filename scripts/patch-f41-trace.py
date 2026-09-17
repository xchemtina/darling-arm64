#!/usr/bin/env python3
"""
DARLING-ARM64 DIAGNOSTIC for FINDINGS.md F41. Idempotent. Run from ~/darling/source.

`t15_invoke.arm64e` dies with `_objc_fatal("cls is not an instance of metacls")`
(objc-runtime-new.mm:2245) while the identical arm64 binary passes. The obvious
reading is the F33 mechanism -- PAC signature bits surviving in isa pointers, so
`cls->ISA() == metacls` never matches -- and masking `isa_t::getClass()` was the
obvious fix.

**It did not work**, and the point of this trace is to stop guessing why. Masking
ISA() only helps if the *left* side is the signed one; if `metacls` carries the
signature instead, or if the mismatch has nothing to do with PAC, the fix was aimed
at the wrong operand.

Prints both operands at each step of the superclass walk, so the answer is read off
rather than inferred:
  * if `cls->ISA()` still shows high bits -> the mask is not in the running binary
    (STATE.md trap 16);
  * if `cls->ISA()` is clean but `metacls` carries high bits -> mask the other side;
  * if both are clean and simply differ -> not a PAC problem at all, and F41 needs a
    different explanation.

Gated on DARLING_ARM64_OBJC_TRACE and bounded to 8 lines, since this sits in a walk
that can iterate.

Revert with: cd src/external/objc4 && git checkout -- runtime/objc-runtime-new.mm
"""
import sys, pathlib

P = pathlib.Path("src/external/objc4/runtime/objc-runtime-new.mm")

OLD = """    // use inst if available
    if (inst) {
        Class cls = remapClass((Class)inst);
        // cls may be a subclass - find the real class for metacls
        // fixme this probably stops working once Swift starts
        // reallocating classes if cls is unrealized.
        while (cls) {
            if (cls->ISA() == metacls) {
"""

NEW = """    // use inst if available
    if (inst) {
        Class cls = remapClass((Class)inst);
        // cls may be a subclass - find the real class for metacls
        // fixme this probably stops working once Swift starts
        // reallocating classes if cls is unrealized.
        while (cls) {
            /* DARLING-ARM64 DIAGNOSTIC (FINDINGS.md F41) */
            {
                static int _f41_seen = 0;
                if (_f41_seen < 8 && getenv("DARLING_ARM64_OBJC_TRACE")) {
                    _f41_seen++;
                    _objc_inform("[F41] cls=%p cls->ISA()=%p metacls=%p match=%d",
                                 (void *)cls, (void *)cls->ISA(), (void *)metacls,
                                 (int)(cls->ISA() == metacls));
                }
            }
            if (cls->ISA() == metacls) {
"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "[F41] cls=" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: anchor found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: metaclass comparison now dumps both operands")
