#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F42. Idempotent. Run from ~/darling/source.

THE DEFECT
----------
`-[NSKeyedArchiver encodeConditionalObject:forKey:]` is not implemented. It is a
stub that traps:

    static void encodeConditionalObject(NSKeyedArchiver *archiver, id object, NSString *key)
    {
    #warning TODO
        DEBUG_BREAK();
    }

So **any** attempt to archive an object graph that uses conditional encoding dies
with SIGTRAP (exit 133) and no message. Found by a new corpus case, `t17_archive`,
which archives a small graph with a parent/child cycle:

    S0 start
    S1 graph built
    <dies -- S2 never printed>

`encodeConditionalObject:` is not exotic: it is the standard way to encode a
back-reference that must not keep the target alive -- delegates, targets, an
NSCell's control view, an NSTableColumn's table view. Any AppKit-shaped graph uses
it.

THE FIX, AND ITS LIMIT
----------------------
Apple's contract: encode a reference to the object **if it is encoded
unconditionally elsewhere in the archive**, otherwise encode nil.

Doing that exactly requires knowing the whole archive before emitting -- Apple's
implementation defers conditional references and resolves them at the end. This is a
**single-pass approximation**: if the object is already in `_objRefMap` (i.e. it has
been assigned a UID by the unconditional path) emit that reference, otherwise emit
nil.

That is correct for the overwhelmingly common shape -- a child encoding a
back-reference to a parent that is already mid-encode, since encoding proceeds
depth-first from the root and the parent is assigned its UID before its contents are
written. It is **wrong** for the case where the conditional object is encoded
unconditionally only *later* in the archive: Apple emits a reference, this emits
nil.

The limit is stated rather than hidden, and the alternative today is a hard trap on
every such graph. `archiver->_conditionals` already exists and is consulted (with an
empty `// TODO`) in the unconditional path, so the infrastructure for a proper
two-pass implementation is partly present if someone wants to finish it.

Revert with: cd src/external/foundation && git checkout -- src/NSKeyedArchiver.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSKeyedArchiver.m")

OLD = """static void encodeConditionalObject(NSKeyedArchiver *archiver, id object, NSString *key)
{
#warning TODO
    DEBUG_BREAK();
}"""

NEW = """static void encodeConditionalObject(NSKeyedArchiver *archiver, id object, NSString *key)
{
    /* DARLING-ARM64 FIX (FINDINGS.md F42): this was a stub that ran DEBUG_BREAK(),
     * so archiving ANY graph using conditional encoding died with SIGTRAP and no
     * message. Conditional encoding is how every back-reference is written --
     * delegates, targets, an NSCell's control view, an NSTableColumn's table view.
     *
     * Contract: emit a reference if the object is encoded unconditionally
     * elsewhere, otherwise emit nil.
     *
     * This is a SINGLE-PASS APPROXIMATION of that. Apple defers conditional
     * references and resolves them once the archive is complete; here, if the
     * object already has a UID in _objRefMap it is referenced, and otherwise nil is
     * written. Correct for the common shape -- a child referring back to a parent
     * that is already mid-encode, since encoding is depth-first from the root and
     * the parent gets its UID before its contents are written -- and wrong when the
     * target is encoded unconditionally only later in the archive, where Apple
     * would still emit a reference.
     *
     * archiver->_conditionals exists and is already consulted (with an empty TODO)
     * in the unconditional path, so a proper two-pass implementation has somewhere
     * to start. */
    int uidIndex = 0;   /* UID 0 is the nil reference, as used for object == nil */

    if (object != nil)
    {
        id mapObject = nil;
        if (CFDictionaryGetValueIfPresent(archiver->_objRefMap, object, (const void **)&mapObject))
        {
            uidIndex = (int)mapObject;
        }
    }

    CFKeyedArchiverUIDRef cka = _NSKeyedArchiverUIDCreateCached(archiver, uidIndex);
    encodeFinalValue(archiver, (id)cka, key);
    CFRelease(cka);
}"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F42" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: stub found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: encodeConditionalObject implemented (single-pass approximation)")
