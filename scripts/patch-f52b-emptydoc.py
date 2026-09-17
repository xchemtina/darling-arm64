#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F52, part 2. Idempotent. Run from ~/darling/source.

WHAT PART 1 LEFT
----------------
After `patch-f52-xmlparser.py`, `t27_xml` went from many divergences to exactly one:

    native : …badstarts:2 badends:0~emptyparse:0 haserr:1
    darling: …badstarts:2 badends:0~emptyparse:1 haserr:0

Parsing an EMPTY document still "succeeds". Part 1 detects unclosed elements by
finding a non-empty `_elementNameStack` at end of input, and for empty input the
stack is empty too -- so nothing fires and `-parse` returns YES.

A document with no root element is not well-formed XML, so macOS returns NO and sets
an error. This adds that case.

SCOPE, STATED HONESTLY
----------------------
This detects the unambiguous case: **zero-length input**. A non-empty document that
still contains no root element (whitespace only, or nothing but a comment or an XML
declaration) is *also* an empty-document error on macOS, and is *not* caught here --
detecting it needs a "did we ever see a root element" flag, which means adding an
ivar to NSXMLParser and touching the header. That is a larger change than the
evidence currently justifies, and no corpus case exercises it. Recorded in
FINDINGS.md as a known remaining gap rather than fixed blind.

A NOTE ON THE ERROR CODES IN PART 1
-----------------------------------
Part 1's comment described its numeric codes as "Apple's documented values". That
is overstated -- they were taken from libxml2's error numbering, which is what
Foundation reports for some cases but not a verified match. The corpus compares the
error *domain* and whether an error exists, not the code, so nothing measured here
depends on them. The comment is corrected by this patch so the source does not
assert something unverified.

Revert with: cd src/external/foundation && git checkout -- src/NSXMLParser.m
  -- WARNING (trap 29): that also reverts the F50 fix, which lives in the same file.
     Re-apply patch-f47-f50.py afterwards.
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSXMLParser.m")

OLD_EMPTY = """    /* Anything still open at end of input is an unclosed element. This is what
     * catches the malformed documents the state machine otherwise tolerates. */
    if (_parserError == nil && [_elementNameStack count] > 0) {"""

NEW_EMPTY = """    /* DARLING-ARM64 FIX (FINDINGS.md F52 part 2): a zero-length document has no
     * root element and so is not well-formed; macOS returns NO and sets an error,
     * whereas this parser returned YES. The unclosed-element check below cannot
     * catch it, because an empty document leaves an empty stack too.
     *
     * SCOPE: only zero-length input is detected. A non-empty document that still
     * has no root element (whitespace, a bare comment, an XML declaration alone) is
     * also an empty-document error on macOS and is NOT caught here -- that needs a
     * "saw a root element" flag, i.e. a new ivar and a header change. Left undone
     * deliberately rather than guessed at. */
    if (_parserError == nil && _length == 0) {
        [self _darlingFailWithCode: DarlingNSXMLParserEmptyDocumentError
                            reason: @"Document is empty"];
    }

    /* Anything still open at end of input is an unclosed element. This is what
     * catches the malformed documents the state machine otherwise tolerates. */
    if (_parserError == nil && [_elementNameStack count] > 0) {"""

OLD_ENUM = """ * Codes are Apple's documented values; this tree declares no NSXMLParserError enum. */
enum {
    DarlingNSXMLParserInternalError            = 1,
    DarlingNSXMLParserNotWellBalancedError     = 105,
    DarlingNSXMLParserPrematureDocumentEndError = 204,
};"""

NEW_ENUM = """ * (Error-code provenance is described below.) */

/* This tree declares no NSXMLParserError enum, so the codes below are spelled out.
 * They follow libxml2's numbering, which is what Foundation surfaces for some cases
 * -- they are NOT a verified match for Apple's values, and are named here so the
 * source does not claim more than has been checked. Nothing measured depends on
 * them: the corpus compares the error domain and whether an error exists, not the
 * code. If a future case does compare codes, verify these against macOS first. */
enum {
    DarlingNSXMLParserInternalError             = 1,
    DarlingNSXMLParserEmptyDocumentError        = 4,
    DarlingNSXMLParserNotWellBalancedError      = 105,
    DarlingNSXMLParserPrematureDocumentEndError = 204,
};"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "F52 part 2" in s:
    print("already patched")
    sys.exit(0)
if "FINDINGS.md F52" not in s:
    print("FATAL: part 1 (patch-f52-xmlparser.py) has not been applied", file=sys.stderr)
    sys.exit(1)

for old, new, what in ((OLD_ENUM, NEW_ENUM, "error-code enum"),
                       (OLD_EMPTY, NEW_EMPTY, "empty-document check")):
    if s.count(old) != 1:
        print(f"FATAL: {what} anchor found {s.count(old)}x (want 1)", file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)

P.write_text(s)
print(f"patched {P}: empty document now reports a parse error; "
      f"error-code provenance comment corrected")
