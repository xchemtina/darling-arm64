#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F60. Idempotent. Run from ~/darling/source.

DIAGNOSIS
---------
    native : ...appended:XYdefghij!! finallen:11~coalesced_len:9
    darling: ...appended:XYdefghij!! finallen:11~coalesced_len:11

After `setAttributes:{z:1}` over the whole string and then appending an attributed
string carrying **the same** attributes, macOS keeps the two runs separate (effective
range at index 0 is 9); Darling merges them (11).

The real class is the toll-free bridge `__NSCFAttributedString`, so the storage is
`CFAttributedString.c`: a per-character array of `__CFRunArrayItem *`, where a run
boundary exists only where two adjacent slots hold different pointers.

`CFAttributedStringReplaceAttributedString` does two things in order:

  1. `CFAttributedStringReplaceString(aStr, range, replaceString)` -- and for an
     append this lands in the `range.location == oldLength` branch, which grows the
     LAST EXISTING RUN in place:

         ptr->_attributes[oldLength - 1]->_range.length += adding;
         for (i = oldLength; i < _runArrayCount; i++)
             ptr->_attributes[i] = ptr->_attributes[oldLength - 1];

     The appended characters are fused into the preceding run **before their own
     attributes have been looked at**.

  2. `_CFRunArrayInsert(...)` for each attribute run of the replacement -- which
     short-circuits at `:188-192` when the target already carries an equal
     dictionary, so it never re-creates the boundary.

That is exactly why the divergence appears **only when the attributes match**: with
unequal attributes the short-circuit fails, the split logic runs, and two runs come
out correctly.

Merging here is EAGER (at mutation). The query path `_CFRunArrayObjectAtIndex`
returns the stored `_range` verbatim with no scanning, so the wrong number really is
in storage.

WHY THE FIX IS IN THE ATTRIBUTED PATH ONLY
------------------------------------------
The same `range.location == oldLength` branch is also reached by plain
`-replaceCharactersInRange:withString:` at the tail and by
`[[m mutableString] appendString:]`. Those carry **no attributes of their own** --
the appended text simply inherits the last character's -- and a single extended run
is the natural, and almost certainly correct, representation there. macOS behaviour
for that case is *not* established by this evidence, so it is left untouched.

What distinguishes the failing case is provenance: `appendAttributedString:` brings
its own attribute dictionary, and macOS keeps that a separate run even when the
dictionary happens to be equal. So the boundary is forced in
`CFAttributedStringReplaceAttributedString`, not in `CFAttributedStringReplaceString`.

WHAT THIS DOES NOT BREAK
------------------------
`run0_len:5`, `run1_loc:5 run1_len:5` and `runs:2` in the same test all route through
`longestEffectiveRange`, which **re-coalesces at query time** by scanning while
CFEqual holds. An extra storage boundary is invisible to them. The lazy merge is
correct Apple semantics and is deliberately left alone; only the eager one is wrong.

MEMORY: `_CFRunArrayDestroyAttributesOfString` walks the slot array stepping by
`inp->_range.length` and destroys each unique item once. Splitting one run into two
adjacent runs whose lengths still tile the array preserves that invariant exactly --
no leak, no double free. `_CFRunArrayItemInit` takes its own copy of the dictionary.

RISK TO RE-CHECK AFTER BUILDING: `_CFRunArrayIsEqual` compares run *structure*, not
per-character attributes, so adding a seam can change which strings compare equal.
`eq_same:1 / eq_diff:0` in the same corpus case must still hold.

Revert with: cd src/external/corefoundation && git checkout -- CFAttributedString.c
"""
import sys, pathlib

P = pathlib.Path("src/external/corefoundation/CFAttributedString.c")

HELPER_ANCHOR = "static void _CFRunArrayInsert(__CFAttributedString *attrStr, CFDictionaryRef dict, CFRange range, Boolean clearOther, CFStringRef subtractValue)"

HELPER = '''/* DARLING-ARM64 FIX (FINDINGS.md F60): force a run boundary at `loc`.
 *
 * CFAttributedStringReplaceString fuses appended characters into the preceding run
 * before their own attributes are consulted, and _CFRunArrayInsert then declines to
 * re-split because the dictionaries compare equal. macOS keeps an appended
 * attributed string as its own run even when its attributes match the preceding
 * text, so the seam has to be re-created explicitly.
 *
 * No-op when `loc` is out of range or already a boundary. The two resulting runs
 * still tile the slot array, which is what _CFRunArrayDestroyAttributesOfString
 * relies on when it walks by run length. */
static void _CFRunArrayForceBoundaryAt(__CFAttributedString *aStr, CFIndex loc)
{
    if (aStr == NULL || aStr->_attributes == NULL)
    {
        return;
    }
    if (loc <= 0 || loc >= aStr->_runArrayCount)
    {
        return;
    }

    __CFRunArrayItem *run = aStr->_attributes[loc];
    if (run == NULL || run != aStr->_attributes[loc - 1])
    {
        return;                 /* already a boundary here */
    }

    CFIndex runEnd = run->_range.location + run->_range.length;
    if (runEnd <= loc)
    {
        return;
    }

    __CFRunArrayItem *tail = _CFRunArrayItemInit(CFRangeMake(loc, runEnd - loc),
                                                 run->_dictionary);
    run->_range.length = loc - run->_range.location;
    for (CFIndex i = loc; i < runEnd; i++)
    {
        aStr->_attributes[i] = tail;
    }
}

'''

OLD_REPLACE = """    // Replace string
    CFStringRef replaceString = CFAttributedStringGetString(replacement);
    CFAttributedStringReplaceString(aStr, range, replaceString);

    // Update attributes"""

NEW_REPLACE = """    // Replace string
    CFStringRef replaceString = CFAttributedStringGetString(replacement);

    /* DARLING-ARM64 FIX (FINDINGS.md F60): when the replacement is appended at the
     * very end, CFAttributedStringReplaceString grows the last existing run in place
     * to swallow the new characters, and the _CFRunArrayInsert loop below then
     * short-circuits whenever the dictionaries compare equal -- so the boundary is
     * never re-created and `effectiveRange` reports one fused run where macOS
     * reports two.
     *
     * Forcing the seam here, rather than in CFAttributedStringReplaceString, keeps
     * plain -replaceCharactersInRange:withString: and -[mutableString appendString:]
     * untouched: that text carries no attributes of its own and a single extended
     * run is the right representation for it. */
    CFIndex _darlingOldLength = CFStringGetLength(CFAttributedStringGetString(aStr));

    CFAttributedStringReplaceString(aStr, range, replaceString);

    if (range.location == _darlingOldLength && CFStringGetLength(replaceString) > 0)
    {
        _CFRunArrayForceBoundaryAt((__CFAttributedString *)aStr, range.location);
    }

    // Update attributes"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F60" in s:
    print("already patched")
    sys.exit(0)

for old, new, what in ((HELPER_ANCHOR, HELPER + HELPER_ANCHOR, "boundary helper"),
                       (OLD_REPLACE, NEW_REPLACE, "ReplaceAttributedString seam")):
    if s.count(old) != 1:
        print(f"FATAL: {what} anchor found {s.count(old)}x (want 1)", file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)

P.write_text(s)
print(f"patched {P}: appended attributed strings keep their own run")
