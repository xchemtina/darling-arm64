#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F48. Idempotent. Run from ~/darling/source.

THE DEFECT
----------
    'this class does not implement the '@distinctUnionOfObjects' operation'

`@count`, `@sum`, `@max`, `@min` and `@avg` all work and match macOS exactly; the
six `@distinctUnionOf…` / `@unionOf…` operators never do. NSArray and NSSet both
*have* the dispatch cases for them (NSArray.m:317-326), so the failure is upstream in
the name lookup.

CAUSE -- a copy-paste slip in `__NSKVCOperatorTypeFromKey`
(NSKeyValueCodingInternal.m:162). It strips the leading `@`:

    NSString *operatorName = [key substringFromIndex:1];

then compares the first five against `operatorName` and **the remaining six against
`key`**:

    else if ([operatorName isEqualToString:NSSumKeyValueOperator])            // right
    else if ([key          isEqualToString:NSDistinctUnionOfObjectsKeyValueOperator])  // wrong

The constants are unprefixed (`NSKeyValueCoding.m:23-31`, e.g.
`@"distinctUnionOfObjects"`), so a comparison against the still-prefixed `key` can
never match and every union operator falls through to the "does not implement"
throw. Five comparisons were right, six were wrong.

Fix: use `operatorName` in all eleven, as the first five already do.

Verified by t23_kvc on both arm64 and arm64e.

Revert with: cd src/external/foundation && git checkout -- src/NSKeyValueCodingInternal.m
"""
import sys, pathlib, re

P = pathlib.Path("src/external/foundation/src/NSKeyValueCodingInternal.m")

OPERATORS = [
    "NSDistinctUnionOfObjectsKeyValueOperator",
    "NSUnionOfObjectsKeyValueOperator",
    "NSDistinctUnionOfArraysKeyValueOperator",
    "NSUnionOfArraysKeyValueOperator",
    "NSDistinctUnionOfSetsKeyValueOperator",
    "NSUnionOfSetsKeyValueOperator",
]

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F48" in s:
    print("already patched")
    sys.exit(0)

n = 0
for op in OPERATORS:
    old = f"[key isEqualToString:{op}]"
    new = f"[operatorName isEqualToString:{op}]"
    c = s.count(old)
    if c:
        s = s.replace(old, new)
        n += c

if n == 0:
    print("FATAL: no mis-compared operators found -- already fixed upstream?",
          file=sys.stderr)
    sys.exit(1)

# Leave a note at the function so the asymmetry is not reintroduced.
anchor = "    NSString *operatorName = [key substringFromIndex:1];\n"
if s.count(anchor) == 1:
    s = s.replace(anchor, anchor +
        "\n    /* DARLING-ARM64 FIX (FINDINGS.md F48): every comparison below must use\n"
        "     * operatorName, not key. The operator constants are unprefixed, so a\n"
        "     * comparison against the still-@-prefixed key can never match. Five of the\n"
        "     * eleven were correct and six were not, which is why @count/@sum/@max/@min/\n"
        "     * @avg worked and the whole union family did not. */\n", 1)

P.write_text(s)
print(f"patched {P}: {n} operator comparisons corrected to use operatorName")
