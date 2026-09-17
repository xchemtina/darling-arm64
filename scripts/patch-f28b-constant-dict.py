#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F28b (NSConstantDictionary). Idempotent.
Run from ~/darling/source.

WHY THIS EXISTS NOW AND NOT BEFORE
----------------------------------
When F28 was fixed, NSConstantDictionary was deliberately left out, on the stated
grounds that no binary here referenced it and guessing a layout for a statically
allocated object reads the wrong memory silently rather than failing loudly.

A new corpus case written to pin F28 (`t10_boxed.m`, which contains a `@{...}`
literal) settles it: clang **does** emit a constant dictionary.

    $ nm -m corpus/bin/t10_boxed.arm64 | grep -i constant
      (undefined) external _OBJC_CLASS_$_NSConstantArray        (from CoreFoundation)
      (undefined) external _OBJC_CLASS_$_NSConstantDictionary   (from CoreFoundation)
      (undefined) external _OBJC_CLASS_$_NSConstantIntegerNumber (from Foundation)

So the condition for implementing it -- having a binary to read the layout out of --
is now met.

INSTANCE LAYOUT
---------------
Read out of the emitted binary, not guessed:

    $ otool -v -s __DATA_CONST __objc_dictobj corpus/bin/t10_boxed.arm64
      00000011 80300000   isa      (bind: NSConstantDictionary)
      00000001 00000000   ???      = 1
      00000002 00000000   count    = 2   (the literal has two entries)
      00004178 00100000   keys     -> __objc_arraydata + 0x18
      00004188 00000000   values   -> __objc_arraydata + 0x28

Cross-checked against __objc_arraydata: 0x4178 holds two pointers into __cfstring
(the keys @"a" and @"b"), and 0x4188 holds two pointers into __objc_intobj (the
values 10 and 20). Positions are therefore certain.

**The field at offset 8 is deliberately not interpreted.** Its position is certain
and its value here is 1, but its meaning is not established from one sample, so it
is declared and ignored rather than guessed at. If a future binary shows a different
value, that is the moment to work out what it means.

Placed in CoreFoundation beside NSConstantArray because that is where the binary
binds it from, and because NSDictionary is implemented there.

Revert with: cd src/external/corefoundation && git checkout -- NSConstantArray.m
"""
import sys, pathlib

P = pathlib.Path("src/external/corefoundation/NSConstantArray.m")

ANCHOR = """#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>

#import "NSObjectInternal.h"
"""

NEW_IMPORTS = """#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSException.h>

#import "NSObjectInternal.h"
"""

DICT = '''
#pragma mark - NSConstantDictionary

/*
 * Layout read out of an emitted binary with
 *   otool -v -s __DATA_CONST __objc_dictobj
 * (40 bytes: isa, <unnamed>=1, count, keys, values), and cross-checked against
 * __objc_arraydata, where the keys array holds pointers into __cfstring and the
 * values array pointers into __objc_intobj.
 *
 * `_reserved` is at a certain offset with an uncertain meaning -- it held 1 in the
 * only sample available. It is declared so the fields after it land correctly and
 * is otherwise untouched; do not attribute behaviour to it without a second sample.
 *
 * As with NSConstantArray, instances live in read-only __DATA_CONST in the client
 * image, so SINGLETON_RR() makes retain/release/dealloc no-ops.
 */
@interface NSConstantDictionary : NSDictionary {
@public
    NSUInteger _reserved;
    NSUInteger _count;
    const id *_keys;
    const id *_values;
}
@end

@implementation NSConstantDictionary

SINGLETON_RR()

- (NSUInteger)count
{
    return _count;
}

- (id)objectForKey:(id)key
{
    if (key == nil) {
        return nil;
    }
    for (NSUInteger i = 0; i < _count; i++) {
        // Constant dictionaries are small and unordered; a linear scan with
        // -isEqual: matches NSDictionary semantics without needing the hash
        // layout the compiler did not emit.
        if (_keys[i] == key || [(id)_keys[i] isEqual:key]) {
            return _values[i];
        }
    }
    return nil;
}

- (NSEnumerator *)keyEnumerator
{
    return [[NSArray arrayWithObjects:_keys count:_count] objectEnumerator];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])buffer
                                    count:(NSUInteger)len
{
    // Enumerating a dictionary yields its keys.
    if (state->state >= _count) {
        return 0;
    }
    state->itemsPtr = (id __unsafe_unretained *)_keys;
    state->state = _count;
    state->mutationsPtr = (unsigned long *)self;
    return _count;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

@end
'''

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
# Check for the implementation, not the name: the file's header comment already
# mentions NSConstantDictionary (it documented why the class was left out), so a
# bare substring test false-positives and silently skips the patch.
if "@implementation NSConstantDictionary" in s:
    print("already patched")
    sys.exit(0)
if s.count(ANCHOR) != 1:
    print(f"FATAL: import anchor found {s.count(ANCHOR)}x (want 1)", file=sys.stderr)
    sys.exit(1)

s = s.replace(ANCHOR, NEW_IMPORTS, 1).rstrip("\n") + "\n" + DICT
P.write_text(s)
print(f"patched {P}: NSConstantDictionary added")
