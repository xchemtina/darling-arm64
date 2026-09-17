#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F44. Idempotent. Run from ~/darling/source.

DIAGNOSIS
---------
Archiving with `requiresSecureCoding` set dies with SIGTRAP and no output. The cause
is the same shape as F42 -- a stub that traps -- and it sits in the encode path
(`NSKeyedArchiver.m:174`), so it fires on the **first object encoded**:

    Class class = [object classForKeyedArchiver];
    if ([archiver requiresSecureCoding])
    {
        // TODO secureCoding
        DEBUG_BREAK();
    }

That is the whole of the secure-coding support on the writing side. Any code setting
`requiresSecureCoding = YES` -- which is the modern default and mandatory for XPC --
crashes immediately.

WHAT IT SHOULD DO
-----------------
Foundation's contract when archiving with secure coding required: every class
encoded must adopt NSSecureCoding and return YES from `+supportsSecureCoding`. If it
does not, raise `NSInvalidArchiveOperationException`. There is nothing else to do on
the writing side -- the security property is enforced on *decode*, by the caller
naming the classes it expects, and that path already works
(`t21_secure` gets its rejection right once this stub stops trapping).

The check is defensive about `+supportsSecureCoding` being absent: a class that does
not implement it cannot be secure-coded, which is exactly the failure case.

ALSO NOTED, NOT FIXED HERE: `-initRequiringSecureCoding:` (line ~555) is a stub that
ignores its argument and calls plain `-init`, so it neither sets the flag nor
configures output. It is a separate entry point that no current test exercises;
recorded in FINDINGS.md rather than changed blind.

Revert with: cd src/external/foundation && git checkout -- src/NSKeyedArchiver.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSKeyedArchiver.m")

OLD = """    Class class = [object classForKeyedArchiver];
    if ([archiver requiresSecureCoding])
    {
        // TODO secureCoding
        DEBUG_BREAK();
    }"""

NEW = """    Class class = [object classForKeyedArchiver];
    if ([archiver requiresSecureCoding])
    {
        /* DARLING-ARM64 FIX (FINDINGS.md F44): this was `DEBUG_BREAK()`, so any
         * archive with requiresSecureCoding set died with SIGTRAP and no message on
         * the first object encoded -- and secure coding is the modern default and
         * mandatory for XPC.
         *
         * Foundation's contract on the writing side is a conformance check: every
         * class encoded must adopt NSSecureCoding and return YES from
         * +supportsSecureCoding, otherwise NSInvalidArchiveOperationException. The
         * security property itself is enforced on decode, by the caller naming the
         * classes it expects -- and that path already works once this stops
         * trapping.
         *
         * A class that does not implement +supportsSecureCoding at all cannot be
         * secure-coded, which is precisely the failure case, hence the
         * respondsToSelector: guard rather than an unchecked send. */
        BOOL supports = [class respondsToSelector: @selector(supportsSecureCoding)]
                        && [class supportsSecureCoding];
        if (!supports)
        {
            @throw [NSException
                exceptionWithName: NSInvalidArchiveOperationException
                           reason: [NSString stringWithFormat:
                                    @"%@ does not support secure coding",
                                    NSStringFromClass(class)]
                         userInfo: nil];
        }
    }"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F44" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: anchor found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: secure-coding conformance check replaces the DEBUG_BREAK stub")
