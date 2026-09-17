#!/usr/bin/env python3
"""
DARLING-ARM64 DIAGNOSTIC for FINDINGS.md F34. Idempotent. Run from ~/darling/source.

F34: Darling writes a valid `bplist00` and cannot read it back.
`CFPropertyList.c:2481` tries `__CFTryParseBinaryPlist` first and silently falls
through to the XML parser on failure, which is why the user-visible symptom is the
misleading "plutil: input is not a property list" rather than a binary-parse error.

`__CFTryParseBinaryPlist` (CFBinaryPList.c:1566) has two failure points --
`__CFBinaryPlistGetTopLevelInfo` (trailer) and `__CFBinaryPlistCreateObjectFiltered`
(object graph) -- and between them the file rejects input through a single macro at
113 sites:

    CFBinaryPList.c:728   #define FAIL_FALSE  do { return false; } while (0)

Redefining that one macro instruments every rejection point at once, so a single run
names the exact check rather than requiring a bisect through Apple's parser.

Gated on DARLING_ARM64_PLIST_TRACE so the diagnostic can stay in the tree while the
fix is developed without adding output to any other gate. Uses write(2) on fd 2
rather than fprintf: this is CoreFoundation, and stdio from inside the parser risks
re-entering CF during early initialisation.

Reproduce with ~/plutil-probe2.sh (XML -> binary -> XML round trip, one container
run, no verifier needed).

Revert with: cd src/external/corefoundation && git checkout -- CFBinaryPList.c
"""
import sys, pathlib

P = pathlib.Path("src/external/corefoundation/CFBinaryPList.c")

OLD = "#define FAIL_FALSE\tdo { return false; } while (0)\n"

NEW = '''/* DARLING-ARM64 DIAGNOSTIC (FINDINGS.md F34): name the rejecting check.
 * This macro is the single rejection path for the whole binary-plist parser (113
 * sites), so logging __LINE__ here localises any parse failure in one run.
 * Gated on an env var so no other gate sees extra output. write(2) rather than
 * fprintf: this is CoreFoundation, and stdio here can re-enter CF. */
#define FAIL_FALSE\tdo { \\
    if (getenv("DARLING_ARM64_PLIST_TRACE")) { \\
        char _b[96]; \\
        int _n = snprintf(_b, sizeof(_b), "[F34] reject at CFBinaryPList.c:%d\\n", __LINE__); \\
        if (_n > 0) { ssize_t _w = write(2, _b, (size_t)_n); (void)_w; } \\
    } \\
    return false; } while (0)
'''

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "[F34] reject at" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: FAIL_FALSE definition found {s.count(OLD)}x (want 1)",
          file=sys.stderr)
    sys.exit(1)

s = s.replace(OLD, NEW, 1)

# write(2) and snprintf need declarations; CFBinaryPList.c may not pull them in.
if "#include <unistd.h>" not in s:
    anchor = "#define FAIL_FALSE"
    s = s.replace(anchor, "#include <unistd.h>\n#include <stdio.h>\n#include <stdlib.h>\n\n" + anchor, 1)

P.write_text(s)
print(f"patched {P}: FAIL_FALSE now reports its line under DARLING_ARM64_PLIST_TRACE")
