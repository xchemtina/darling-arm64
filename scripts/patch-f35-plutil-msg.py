#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F35. Idempotent. Run from ~/darling/source.

`plutil -convert` reports an unreadable file and a malformed file with the same
message:

    NSData* input = [NSData dataWithContentsOfFile:… error:&error];
    id plist = input ? [NSPropertyListSerialization propertyListWithData:…] : nil;
    if (!plist || error)
        return fail("plutil: input is not a property list\\n", 1);

A missing file yields `input == nil`, hence `plist == nil`, hence "input is not a
property list" -- a claim about the file's *contents*, made about a file that was
never read.

That message cost a full session: it sent the F34 investigation into
`CFBinaryPList.c` looking for a binary-plist parser defect, when in fact
`/private/var/tmp` was being wiped between the two `darlingserver` invocations and
the file simply was not there. The parser was fine all along.

`dataWithContentsOfFile:` already populates `error`, so distinguishing the two costs
nothing. This also splits the parse failure out from the read failure so each says
what actually happened.

Revert with: cd src/external/foundation && git checkout -- tools/plutil.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/tools/plutil.m")

OLD = """		NSError* error = nil;
		NSData* input = [NSData dataWithContentsOfFile:string_argument(input_path)
			options:0 error:&error];
		id plist = input ? [NSPropertyListSerialization propertyListWithData:input
			options:NSPropertyListImmutable format:NULL error:&error] : nil;
		if (!plist || error)
			return fail("plutil: input is not a property list\\n", 1);
"""

NEW = """		NSError* error = nil;
		NSData* input = [NSData dataWithContentsOfFile:string_argument(input_path)
			options:0 error:&error];
		/* DARLING-ARM64 FIX (FINDINGS.md F35): report an unreadable file as an
		 * unreadable file. Collapsing this into "input is not a property list"
		 * asserts something about contents that were never examined, and sent the
		 * F34 investigation into the binary-plist parser for a full session when
		 * the file had simply been deleted between two darlingserver runs. */
		if (!input)
			return fail("plutil: could not read input file\\n", 1);

		id plist = [NSPropertyListSerialization propertyListWithData:input
			options:NSPropertyListImmutable format:NULL error:&error];
		if (!plist || error)
			return fail("plutil: input is not a property list\\n", 1);
"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "could not read input file" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: anchor found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: unreadable input now reported distinctly from malformed input")
