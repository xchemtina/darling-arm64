#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F43, second half. Idempotent.
Run from ~/darling/source.

F43 turned out to be two missing APIs, not one. Adding the six URL character sets to
NSCharacterSet moved the failure on to:

    -[NSString stringByAddingPercentEncodingWithAllowedCharacters:]:
        unrecognized selector

`-stringByRemovingPercentEncoding` already exists (NSString.m:2490), as does the
deprecated `-stringByAddingPercentEscapesUsingEncoding:`. Only the modern encoding
method -- the one all current code calls -- is absent.

SEMANTICS, matching Foundation:
  * a character in the allowed set is passed through unchanged;
  * anything else is encoded as UTF-8 and each byte written as %XX in UPPER case;
  * iteration is by composed character sequence, so a surrogate pair or a combining
    sequence is encoded as one unit rather than being split;
  * a nil character set returns nil.

Uppercase hex is not cosmetic here: the corpus compares output byte-for-byte against
real macOS, which emits uppercase.

Revert with: cd src/external/foundation && git checkout -- src/NSString.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSString.m")

ANCHOR = "- (NSString *) stringByRemovingPercentEncoding\n"

NEW = """/* DARLING-ARM64 FIX (FINDINGS.md F43): this was missing entirely, so any code
 * building a URL from user input threw "unrecognized selector". Its counterpart
 * -stringByRemovingPercentEncoding was already present.
 *
 * Foundation's semantics: pass through characters in the allowed set; encode
 * everything else as UTF-8 with each byte as %XX in UPPER case. Iterating by
 * composed character sequence keeps surrogate pairs and combining marks intact.
 * Uppercase matters -- the differential corpus compares this byte-for-byte against
 * real macOS. */
- (NSString *)stringByAddingPercentEncodingWithAllowedCharacters:(NSCharacterSet *)allowed
{
    if (allowed == nil)
    {
        return nil;
    }

    NSUInteger len = [self length];
    NSMutableString *out = [NSMutableString stringWithCapacity:len];
    NSUInteger i = 0;

    while (i < len)
    {
        NSRange r = [self rangeOfComposedCharacterSequenceAtIndex:i];
        NSString *chunk = [self substringWithRange:r];

        if (r.length == 1 && [allowed characterIsMember:[chunk characterAtIndex:0]])
        {
            [out appendString:chunk];
        }
        else
        {
            NSData *utf8 = [chunk dataUsingEncoding:NSUTF8StringEncoding];
            const unsigned char *bytes = (const unsigned char *)[utf8 bytes];
            NSUInteger n = [utf8 length];
            for (NSUInteger k = 0; k < n; k++)
            {
                [out appendFormat:@"%%%02X", (unsigned)bytes[k]];
            }
        }
        i = NSMaxRange(r);
    }

    return out;
}

- (NSString *) stringByRemovingPercentEncoding
"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "stringByAddingPercentEncodingWithAllowedCharacters" in s:
    print("already patched")
    sys.exit(0)
if s.count(ANCHOR) != 1:
    print(f"FATAL: anchor found {s.count(ANCHOR)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(ANCHOR, NEW, 1))
print(f"patched {P}: stringByAddingPercentEncodingWithAllowedCharacters: added")
