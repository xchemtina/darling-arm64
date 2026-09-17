#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F43. Idempotent. Run from ~/darling/source.

THE DEFECT
----------
    +[NSCharacterSet URLQueryAllowedCharacterSet]: unrecognized selector

The six URL character sets are missing from NSCharacterSet, so
`-stringByAddingPercentEncodingWithAllowedCharacters:` -- the standard way to build a
URL from user input -- throws. Everything else about NSURL matches macOS exactly
(scheme/host/port/path/query/fragment/user extraction, relative resolution against a
base, file URLs), so this is a single missing API rather than a broken subsystem.

WHERE THE DEFINITIONS COME FROM
-------------------------------
Not invented. They are copied verbatim from Apple's own source, vendored in this very
tree at

    corefoundation/submodules/swift-corelibs-foundation/
        CoreFoundation/URL.subproj/CFURLComponents_URIParser.c:22-28

That file is **not compiled** here (the URL subproject is absent from CoreFoundation's
CMakeLists), which is why neither the CF functions nor the ObjC methods exist. The
`Darwin/shims/NSCharacterSetShims.h` header in the same submodule calls
`NSCharacterSet.URLQueryAllowedCharacterSet` -- i.e. it expects exactly the methods
added here.

Being byte-exact matters: the corpus compares percent-encoded output against real
macOS, so a set that is close but not identical fails just as loudly as a missing one
-- which is the point of taking them from Apple's source rather than from RFC 3986 by
hand.

Note `+URLHostAllowedCharacterSet` includes `[` and `]` for IPv6 literals, and
`+URLPathAllowedCharacterSet` deliberately excludes `;` -- both quirks are Apple's,
preserved here with their original comments.

Revert with: cd src/external/corefoundation && git checkout -- NSCharacterSet.m
"""
import sys, pathlib

P = pathlib.Path("src/external/corefoundation/NSCharacterSet.m")

SETS = [
    ("URLUserAllowedCharacterSet",
     "!$&'()*+,-.0123456789;=ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~", ""),
    ("URLPasswordAllowedCharacterSet",
     "!$&'()*+,-.0123456789;=ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~", ""),
    ("URLHostAllowedCharacterSet",
     "!$&'()*+,-.0123456789:;=ABCDEFGHIJKLMNOPQRSTUVWXYZ[]_abcdefghijklmnopqrstuvwxyz~",
     "  /* '[' and ']' are permitted for IPv6 literals. */"),
    ("URLPathAllowedCharacterSet",
     "!$&'()*+,-./0123456789:=@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~",
     "  /* ';' is deliberately excluded, for compatibility with rfc1808 parsing\n     * where it separated path from param. Apple's quirk, preserved. */"),
    ("URLQueryAllowedCharacterSet",
     "!$&'()*+,-./0123456789:;=?@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~", ""),
    ("URLFragmentAllowedCharacterSet",
     "!$&'()*+,-./0123456789:;=?@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~", ""),
]


def method(name, chars, note):
    esc = chars.replace("\\", "\\\\").replace('"', '\\"')
    return (f"+ (NSCharacterSet *)%s\n{{\n{note}\n" % name if note else
            f"+ (NSCharacterSet *)%s\n{{\n" % name) + (
        f'    static NSCharacterSet *set = nil;\n'
        f'    static dispatch_once_t once;\n'
        f'    dispatch_once(&once, ^{{\n'
        f'        set = [[NSCharacterSet characterSetWithCharactersInString:\n'
        f'                @"{esc}"] retain];\n'
        f'    }});\n'
        f'    return set;\n'
        f'}}\n\n')


BLOCK = ("""
/*
 * DARLING-ARM64 FIX (FINDINGS.md F43): the six URL character sets were missing, so
 * -stringByAddingPercentEncodingWithAllowedCharacters: threw
 * "unrecognized selector". These are the standard way to build a URL from user
 * input.
 *
 * The character strings are copied verbatim from Apple's own source, vendored in
 * this tree at corefoundation/submodules/swift-corelibs-foundation/CoreFoundation/
 * URL.subproj/CFURLComponents_URIParser.c:22-28. That file is not compiled here,
 * which is why neither the CF functions nor these methods existed -- and
 * Darwin/shims/NSCharacterSetShims.h in the same submodule calls exactly these
 * methods, so it was written expecting them.
 *
 * Byte-exactness matters: the differential corpus compares percent-encoded output
 * against real macOS, so a nearly-right set fails as loudly as a missing one.
 */
@implementation NSCharacterSet (DarlingARM64URLCharacterSets)

""" + "".join(method(n, c, note) for n, c, note in SETS) + "@end\n")

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "DarlingARM64URLCharacterSets" in s:
    print("already patched")
    sys.exit(0)

if "#import <dispatch/dispatch.h>" not in s:
    # dispatch_once is used above; make sure it is declared.
    first_import = s.index("#import")
    s = s[:first_import] + "#import <dispatch/dispatch.h>\n" + s[first_import:]

P.write_text(s.rstrip("\n") + "\n" + BLOCK)
print(f"patched {P}: six URL character sets added")
