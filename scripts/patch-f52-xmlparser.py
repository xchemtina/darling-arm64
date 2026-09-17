#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F52. Idempotent. Run from ~/darling/source.

DIAGNOSIS (read from source; no guessing)
-----------------------------------------
`NSXMLParser.m` is a hand-written state machine, 594 lines. Reading it end to end
turns "malformed XML parses successfully" into six concrete gaps:

 1. `-parse` ends with an unconditional `return YES;` (line ~568). **It can never
    report failure**, whatever the input.
 2. `_parserError` (declared NSXMLParser.h:98) is only ever *read*, at line 575.
    Nothing anywhere assigns it, so `-parserError` is permanently nil.
 3. `parserDidStartDocument:` and `parserDidEndDocument:` are **never sent** -- the
    strings do not appear in the file. Every other delegate callback is dispatched
    with a `respondsToSelector:` guard; these two were simply not implemented.
 4. `-unexpectedIn:` -- the one error path -- raises an NSException with an **empty
    name** (`@""`) instead of recording an error, so even when it does fire the
    caller gets an unnamed exception rather than `parse` returning NO.
 5. `-eTag:` carries the comment `// FIX, maybe double check name here` and does
    exactly that: **it never checks the closing tag matches the open one**, so
    `<a></b>` is accepted.
 6. `-abortParsing` is `NSUnimplementedMethod()`.

Consequence: code that validates input by checking whether parsing succeeded
silently accepts garbage. That is worse than rejecting valid input, because nothing
downstream has any signal that something went wrong.

THE FIX
-------
 * send the two document callbacks, guarded like every sibling;
 * give the parser a real failure mode: record an NSError, tell the delegate via
   `parser:parseErrorOccurred:`, and return NO;
 * catch `-unexpectedIn:`'s exception at the `-parse` boundary and route it into
   that failure mode rather than letting it escape;
 * check the closing tag against the element stack in `-eTag:`;
 * treat a non-empty element stack at end of input as unclosed-element, which is
   what catches the common malformed cases the state machine tolerates;
 * add the missing `respondsToSelector:` guard in `-didEndElement`, which messages
   the delegate unguarded unlike every other callback -- a latent crash for any
   delegate that does not implement it.

NOTE ON ERROR CODES: this tree declares no `NSXMLParserError` enum (the header has
the delegate methods but not the codes), so Apple's documented numeric values are
used with a comment. That absence is itself a small gap -- code switching on parser
error codes cannot compile here.

Revert with: cd src/external/foundation && git checkout -- src/NSXMLParser.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSXMLParser.m")

# ---------------------------------------------------------------- helper ----
HELPER = '''
/* DARLING-ARM64 FIX (FINDINGS.md F52): the parser had no failure mode at all --
 * -parse ended in an unconditional `return YES`, _parserError was never assigned,
 * and the sole error path raised an unnamed exception. This records a real error,
 * notifies the delegate as Foundation does, and lets -parse return NO.
 *
 * Codes are Apple's documented values; this tree declares no NSXMLParserError enum. */
enum {
    DarlingNSXMLParserInternalError            = 1,
    DarlingNSXMLParserNotWellBalancedError     = 105,
    DarlingNSXMLParserPrematureDocumentEndError = 204,
};

@interface NSXMLParser (DarlingARM64Errors)
- (void) _darlingFailWithCode: (NSInteger) code reason: (NSString *) reason;
@end

@implementation NSXMLParser (DarlingARM64Errors)

- (void) _darlingFailWithCode: (NSInteger) code reason: (NSString *) reason {
    if (_parserError != nil) {
        return;                 /* keep the first error, as Foundation does */
    }
    _parserError = [[NSError alloc]
        initWithDomain: NSXMLParserErrorDomain
                  code: code
              userInfo: @{ NSLocalizedDescriptionKey: reason ?: @"parse error" }];

    if ([_delegate respondsToSelector: @selector(parser:parseErrorOccurred:)]) {
        [_delegate parser: self parseErrorOccurred: _parserError];
    }
}

@end

'''

EDITS = []

# 0. imports. NSXMLParser.m imports six headers and NSError.h is not among them, so
#    NSError and NSLocalizedDescriptionKey are undeclared in this translation unit --
#    the first build of this patch failed on exactly that. NSString.h is added for
#    +stringWithFormat:, which currently arrives only indirectly.
EDITS.append((
    "#import <Foundation/NSXMLParser.h>\n",
    "#import <Foundation/NSXMLParser.h>\n"
    "#import <Foundation/NSError.h>      /* DARLING-ARM64 (F52): NSError, NSLocalizedDescriptionKey */\n"
    "#import <Foundation/NSString.h>     /* DARLING-ARM64 (F52): +stringWithFormat: */\n",
    "error headers",
))

# 1. helper before @implementation NSXMLParser
EDITS.append((
    "@implementation NSXMLParser\n",
    HELPER + "@implementation NSXMLParser\n",
    "error helper",
))

# 2. -eTag: verify the closing tag matches
EDITS.append((
    """- (void) eTag: (NSString *) eTag {
    // FIX, maybe double check name here
    [self didEndElement];
}""",
    """- (void) eTag: (NSString *) eTag {
    /* DARLING-ARM64 FIX (FINDINGS.md F52): the original comment here read
     * "FIX, maybe double check name here" and it did not -- so <a></b> was
     * accepted. A mismatched closing tag is the textbook not-well-balanced case. */
    NSString *open = [_elementNameStack lastObject];
    if (open != nil && eTag != nil && ![open isEqualToString: eTag]) {
        [self _darlingFailWithCode: DarlingNSXMLParserNotWellBalancedError
                            reason: [NSString stringWithFormat:
                                     @"Closing tag </%@> does not match <%@>",
                                     eTag, open]];
        return;
    }
    [self didEndElement];
}""",
    "eTag mismatch check",
))

# 3. -didEndElement: add the guard its siblings all have
EDITS.append((
    """- (void) didEndElement {
    NSString *elementName = [_elementNameStack lastObject];
    [_delegate parser: self
            didEndElement: elementName
             namespaceURI: nil
            qualifiedName: nil];
    [_elementNameStack removeLastObject];
}""",
    """- (void) didEndElement {
    NSString *elementName = [_elementNameStack lastObject];
    /* DARLING-ARM64 FIX (FINDINGS.md F52): this messaged the delegate with no
     * respondsToSelector: guard, unlike every other callback in this file -- a
     * latent crash for any delegate not implementing it. */
    if ([_delegate respondsToSelector: @selector
                   (parser:didEndElement:namespaceURI:qualifiedName:)]) {
        [_delegate parser: self
                didEndElement: elementName
                 namespaceURI: nil
                qualifiedName: nil];
    }
    [_elementNameStack removeLastObject];
}""",
    "didEndElement guard",
))

# 4. -parse: document callbacks, exception routing, well-formedness, real return
EDITS.append((
    """- (BOOL) parse {
    int createNewPool = 0;
    NSAutoreleasePool *pool = nil;

    while (NSMaxRange(_range) < _length) {""",
    """- (BOOL) parse {
    int createNewPool = 0;
    NSAutoreleasePool *pool = nil;

    /* DARLING-ARM64 FIX (FINDINGS.md F52): neither document callback was ever
     * sent. */
    [_parserError release];
    _parserError = nil;
    if ([_delegate respondsToSelector: @selector(parserDidStartDocument:)]) {
        [_delegate parserDidStartDocument: self];
    }

    @try {

    while (NSMaxRange(_range) < _length) {""",
    "parse prologue",
))

EDITS.append((
    """        createNewPool++;

        if ((createNewPool % 1000) == 0) {
            [pool release];
            pool = nil;
        }
    }
    return YES;
}""",
    """        createNewPool++;

        if ((createNewPool % 1000) == 0) {
            [pool release];
            pool = nil;
        }

        if (_parserError != nil) {
            break;              /* a callback recorded a well-formedness error */
        }
    }

    }
    @catch (NSException *exception) {
        /* -unexpectedIn: raises rather than recording. Route it into the real
         * failure path instead of letting an unnamed exception escape -parse. */
        [self _darlingFailWithCode: DarlingNSXMLParserInternalError
                            reason: [exception reason]];
    }

    /* Anything still open at end of input is an unclosed element. This is what
     * catches the malformed documents the state machine otherwise tolerates. */
    if (_parserError == nil && [_elementNameStack count] > 0) {
        [self _darlingFailWithCode: DarlingNSXMLParserPrematureDocumentEndError
                            reason: [NSString stringWithFormat:
                                     @"Element <%@> was never closed",
                                     [_elementNameStack lastObject]]];
    }

    if (_parserError != nil) {
        [pool release];
        return NO;
    }

    if ([_delegate respondsToSelector: @selector(parserDidEndDocument:)]) {
        [_delegate parserDidEndDocument: self];
    }
    return YES;
}""",
    "parse epilogue",
))

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F52" in s:
    print("already patched")
    sys.exit(0)

for old, new, what in EDITS:
    if s.count(old) != 1:
        print(f"FATAL: {what} anchor found {s.count(old)}x (want 1)", file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)

P.write_text(s)
print(f"patched {P}: document callbacks, real failure mode, tag matching, "
      f"unclosed-element detection, delegate guard")
