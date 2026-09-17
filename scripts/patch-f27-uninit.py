#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F27 (candidate). Idempotent.
Run from ~/darling/source.

THE LEAD
--------
F27 crashes in `objc_msgSend` called from `_decodeObjectBinary`, with `x0` holding a
small value that **varies between runs** (`0x7`, `0x22`). It is also
**intermittent**: on the same build, one run got all the way through the save and on
to the reopen phase, and the next crashed.

Varying-garbage plus intermittency is the signature of an uninitialised read, and
there are three in this file:

    NSKeyedUnarchiver.m:366   CFPropertyListRef string;      <- uninitialised
    NSKeyedUnarchiver.m:486   CFPropertyListRef string;      <- uninitialised
    NSKeyedUnarchiver.m:534   CFPropertyListRef className;   <- uninitialised

(line 500 does it correctly: `CFPropertyListRef obj = NULL;`)

Both `string` declarations feed:

    if (!__CFBinaryPlistCreateObject(..., &string) || string == nil) { return nil; }
    if (CFEqual(@"$null", string))                    <- messages it

If `__CFBinaryPlistCreateObject` ever returns true without writing through its out
parameter, `string` holds whatever was on the stack, the `== nil` guard does not
catch it, and `CFEqual` messages stack garbage -- which is exactly a crash in
`objc_msgSend` with a small, run-varying receiver.

STATUS: **candidate, not confirmed.** Initialising these is correct regardless --
reading an uninitialised variable is undefined behaviour and the guard immediately
below is written as though it were NULL-initialised. Whether it cures F27 needs
repeated runs, because F27 is intermittent and a single pass proves nothing.

Revert with: cd src/external/foundation && git checkout -- src/NSKeyedUnarchiver.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSKeyedUnarchiver.m")

COMMENT = ("        /* DARLING-ARM64 FIX (FINDINGS.md F27): was uninitialised. The guard below\n"
           "         * tests `== nil`, so it assumes NULL-initialisation; without it a failure\n"
           "         * that leaves the out parameter untouched passes stack garbage to CFEqual,\n"
           "         * which messages it. Matches F27's symptoms: a small, run-varying receiver\n"
           "         * in objc_msgSend, and intermittency. */\n")

EDITS = [
    ("        CFPropertyListRef string;\n",
     COMMENT + "        CFPropertyListRef string = NULL;\n"),
    ("            CFPropertyListRef string;\n",
     COMMENT.replace("        ", "            ") + "            CFPropertyListRef string = NULL;\n"),
    ("        CFPropertyListRef className;\n",
     "        /* DARLING-ARM64 FIX (FINDINGS.md F27): was uninitialised, same class of bug. */\n"
     "        CFPropertyListRef className = NULL;\n"),
]

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F27" in s:
    print("already patched")
    sys.exit(0)

for i, (old, new) in enumerate(EDITS, 1):
    if s.count(old) != 1:
        print(f"FATAL: declaration {i} found {s.count(old)}x (want 1)", file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)

P.write_text(s)
print(f"patched {P}: three uninitialised CFPropertyListRef declarations now NULL")
