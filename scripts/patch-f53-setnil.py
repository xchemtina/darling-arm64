#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F53. Idempotent. Run from ~/darling/source.

    -[Person setNilValueForKey:]: unrecognized selector

Setting nil on a scalar property is a documented KVC path: the framework calls
`-setNilValueForKey:` on the object, and `NSObject`'s default implementation raises
`NSInvalidArgumentException`. Darling makes the call but provides no default, so
instead of the documented exception the program dies with an unrecognized selector.

The difference matters: application code routinely overrides `setNilValueForKey:` to
supply a default (the whole reason the hook exists), and code that does *not* override
it expects a catchable `NSInvalidArgumentException`, not a crash.

`-valueForUndefinedKey:` right above it (NSKeyValueCoding.m:188) is the same shape,
and this follows it -- including the userInfo keys, so the exception carries the same
diagnostic payload.

Found by t23_kvc once F48 let the case run that far.

Revert with: cd src/external/foundation && git checkout -- src/NSKeyValueCoding.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSKeyValueCoding.m")

ANCHOR = "- (NSDictionary *)dictionaryWithValuesForKeys:(NSArray *)keys\n"

NEW = """/* DARLING-ARM64 FIX (FINDINGS.md F53): NSObject had no default
 * -setNilValueForKey:, so assigning nil to a scalar property died with an
 * unrecognized selector instead of the documented NSInvalidArgumentException.
 * Applications override this hook to supply a default value; those that do not
 * expect a catchable exception. Mirrors -valueForUndefinedKey: above. */
- (void)setNilValueForKey:(id)key
{
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Could not set nil as the value for the key %@.", key] userInfo:@{
        NSTargetObjectUserInfoKey: [self description],
        NSUnknownUserInfoKey: key ?: @"(null)"
    }];
}

- (NSDictionary *)dictionaryWithValuesForKeys:(NSArray *)keys
"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F53" in s:
    print("already patched")
    sys.exit(0)
if s.count(ANCHOR) != 1:
    print(f"FATAL: anchor found {s.count(ANCHOR)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(ANCHOR, NEW, 1))
print(f"patched {P}: default -setNilValueForKey: added")
