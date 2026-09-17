#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F39. Idempotent. Run from ~/darling/source.

Two of the four Unicode normalisation methods in NSString have each other's
constants:

    method                                      should pass   actually passes
    decomposedStringWithCanonicalMapping        FormD         FormD      ok
    precomposedStringWithCanonicalMapping       FormC         FormKD     WRONG
    decomposedStringWithCompatibilityMapping    FormKD        FormC      WRONG
    precomposedStringWithCompatibilityMapping   FormKC        FormKC     ok

So `-precomposedStringWithCanonicalMapping` applies **compatibility decomposition**
where it should apply canonical composition -- it decomposes further instead of
recomposing. That is exactly what the corpus measured:

    native : ... decomp_len:8 recomp_eq:1 ...
    darling: ... decomp_len:8 recomp_eq:0 ...

Decomposition was correct all along (`decomp_len:8` matches macOS), which is what
narrowed this to the composition side rather than to Unicode handling generally.

`-decomposedStringWithCompatibilityMapping` is wrong in the mirror-image way and
returns *composed* output. The corpus did not cover it, so it was found by reading
rather than by measurement -- `t12_strings.m` is extended in the same change so both
halves are pinned from now on.

Revert with: cd src/external/foundation && git checkout -- src/NSString.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSString.m")

# Each method body is identical apart from the constant, so anchor on the whole
# method to avoid matching the wrong one.
PRE_CANON_OLD = """- (NSString *)precomposedStringWithCanonicalMapping
{
    CFMutableStringRef str = CFStringCreateMutable(kCFAllocatorDefault, 0);
    CFStringReplaceAll(str, (CFStringRef)self);
    CFStringNormalize(str, kCFStringNormalizationFormKD);
    return [(NSString *)str autorelease];
}"""

PRE_CANON_NEW = """- (NSString *)precomposedStringWithCanonicalMapping
{
    /* DARLING-ARM64 FIX (FINDINGS.md F39): this passed FormKD -- compatibility
     * DEcomposition -- so "precomposed" decomposed further instead of recomposing,
     * and NFD -> NFC did not round-trip. Canonical composition is FormC. */
    CFMutableStringRef str = CFStringCreateMutable(kCFAllocatorDefault, 0);
    CFStringReplaceAll(str, (CFStringRef)self);
    CFStringNormalize(str, kCFStringNormalizationFormC);
    return [(NSString *)str autorelease];
}"""

DEC_COMPAT_OLD = """- (NSString *)decomposedStringWithCompatibilityMapping
{
    CFMutableStringRef str = CFStringCreateMutable(kCFAllocatorDefault, 0);
    CFStringReplaceAll(str, (CFStringRef)self);
    CFStringNormalize(str, kCFStringNormalizationFormC);
    return [(NSString *)str autorelease];
}"""

DEC_COMPAT_NEW = """- (NSString *)decomposedStringWithCompatibilityMapping
{
    /* DARLING-ARM64 FIX (FINDINGS.md F39): the mirror image of the bug above --
     * this passed FormC (canonical COMPOSITION), so "decomposed" returned composed
     * output. Compatibility decomposition is FormKD. */
    CFMutableStringRef str = CFStringCreateMutable(kCFAllocatorDefault, 0);
    CFStringReplaceAll(str, (CFStringRef)self);
    CFStringNormalize(str, kCFStringNormalizationFormKD);
    return [(NSString *)str autorelease];
}"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F39" in s:
    print("already patched")
    sys.exit(0)

for old, new, what in ((PRE_CANON_OLD, PRE_CANON_NEW, "precomposedStringWithCanonicalMapping"),
                       (DEC_COMPAT_OLD, DEC_COMPAT_NEW, "decomposedStringWithCompatibilityMapping")):
    if s.count(old) != 1:
        print(f"FATAL: {what} anchor found {s.count(old)}x (want 1)", file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)

P.write_text(s)
print(f"patched {P}: FormKD/FormC swapped back into the correct methods")
