#!/usr/bin/env python3
"""
DARLING-ARM64: three small fixes found by the corpus. Idempotent.
Run from ~/darling/source.

F47 -- -[NSObject dictionaryWithValuesForKeys:] throws on a nil value
       NSKeyValueCoding.m:202 does `values[key] = [self valueForKey:key];`. Subscript
       assignment rejects nil, so any object with an unset property throws
       "Cannot set nil objects nor nil keys". Foundation's contract is to substitute
       NSNull for a nil value -- that is the documented behaviour and the whole
       reason NSNull exists in this API. One line.

F49 -- NSOperation has no name property
       `-[NSBlockOperation setName:]: unrecognized selector`. NSOperationQueue has
       `name`/`setName:` (NSOperation.m:942) but NSOperation itself does not, so no
       operation can be named. Added with KVO notifications, matching the queue's
       implementation directly above it.

F50 -- NSXMLParserErrorDomain is not defined
       `Symbol not found: _NSXMLParserErrorDomain`. NSXMLParser is implemented, but
       the error-domain constant every caller uses to classify a parse failure is
       declared in the header and defined nowhere, so any binary referencing it
       fails to launch.

Each was found by a new corpus case (t23_kvc, t26_operation, t27_xml) on its first
run.

Revert with: cd src/external/foundation && git checkout -- \\
    src/NSKeyValueCoding.m src/NSOperation.m src/NSXMLParser.m
"""
import sys, pathlib

def patch(rel, old, new, what, guard):
    p = pathlib.Path(rel)
    if not p.exists():
        print(f"FATAL: missing {p}", file=sys.stderr); sys.exit(1)
    s = p.read_text()
    if guard in s:
        print(f"  already patched: {what}"); return False
    if s.count(old) != 1:
        print(f"FATAL: {what} anchor found {s.count(old)}x (want 1)", file=sys.stderr)
        sys.exit(1)
    p.write_text(s.replace(old, new, 1))
    print(f"  patched: {what}")
    return True

# ---- F47 -------------------------------------------------------------------
patch("src/external/foundation/src/NSKeyValueCoding.m",
"""    NSMutableDictionary *values = [[NSMutableDictionary alloc] init];
    for (NSString *key in keys)
    {
        values[key] = [self valueForKey:key];
    }""",
"""    NSMutableDictionary *values = [[NSMutableDictionary alloc] init];
    for (NSString *key in keys)
    {
        /* DARLING-ARM64 FIX (FINDINGS.md F47): a nil value must become NSNull.
         * Subscript assignment rejects nil, so any object with an unset property
         * threw "Cannot set nil objects nor nil keys". Substituting NSNull is the
         * documented contract and the reason NSNull exists in this API. */
        id value = [self valueForKey:key];
        values[key] = (value != nil) ? value : (id)[NSNull null];
    }""",
"F47 dictionaryWithValuesForKeys", "FINDINGS.md F47")

# ---- F49 -------------------------------------------------------------------
patch("src/external/foundation/src/NSOperation.m",
"""@implementation NSOperationQueue""",
"""/* DARLING-ARM64 FIX (FINDINGS.md F49): NSOperation had no name property, so
 * -[NSBlockOperation setName:] was an unrecognized selector and no operation could
 * be named. NSOperationQueue already implements the same pair below; this mirrors
 * it, KVO notifications included. */
@implementation NSOperation (DarlingARM64Naming)

- (void)setName:(NSString *)aName
{
    [self willChangeValueForKey:@"name"];
    objc_setAssociatedObject(self, "__darling_operation_name",
                             [[aName copy] autorelease],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self didChangeValueForKey:@"name"];
}

- (NSString *)name
{
    NSString *n = objc_getAssociatedObject(self, "__darling_operation_name");
    return n;
}

@end

@implementation NSOperationQueue""",
"F49 NSOperation name", "FINDINGS.md F49")

# ---- F50 -------------------------------------------------------------------
p = pathlib.Path("src/external/foundation/src/NSXMLParser.m")
s = p.read_text()
if "FINDINGS.md F50" in s:
    print("  already patched: F50 NSXMLParserErrorDomain")
else:
    i = s.index("@implementation")
    s = s[:i] + ("""/* DARLING-ARM64 FIX (FINDINGS.md F50): declared in the header, defined nowhere, so
 * any binary referencing it failed to launch with
 * "Symbol not found: _NSXMLParserErrorDomain". Callers use it to classify a parse
 * failure, so NSXMLParser was effectively unusable for error handling. */
NSString * const NSXMLParserErrorDomain = @"NSXMLParserErrorDomain";

""") + s[i:]
    p.write_text(s)
    print("  patched: F50 NSXMLParserErrorDomain")

print("done")
