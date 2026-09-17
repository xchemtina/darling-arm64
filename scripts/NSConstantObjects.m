//
//  NSConstantObjects.m
//  CoreFoundation
//
//  DARLING-ARM64: compiler-emitted constant ObjC objects (FINDINGS.md F28).
//
//  Recent clang (verified with Apple clang 21 / SDK 26.5) statically allocates the
//  objects behind boxed literals instead of building them at runtime. A trivial
//  program containing `@[@1, @2, @3]` emits three __DATA_CONST sections --
//  __objc_intobj, __objc_arraydata, __objc_arrayobj -- and imports two classes:
//
//      _OBJC_CLASS_$_NSConstantIntegerNumber   (from Foundation)
//      _OBJC_CLASS_$_NSConstantArray           (from CoreFoundation)
//
//  Darling implemented neither, so any binary built against a modern macOS SDK that
//  uses @1-style literals failed to launch:
//
//      abort_with_payload: Symbol not found: _OBJC_CLASS_$_NSConstantIntegerNumber
//        Referenced from: /corpus/t06_objc.arm64 (built for Mac OS X 26.0)
//        Expected in: /System/Library/Frameworks/Foundation.framework/.../Foundation
//
//  This is not architecture-specific -- it is a Foundation completeness gap -- but
//  it is invisible to gates built from applications compiled against older SDKs.
//
//  INSTANCE LAYOUTS
//  ----------------
//  Read out of the emitted binary with `otool -v -s __DATA_CONST ...`, not guessed.
//  Three 24-byte __objc_intobj entries holding 1, 2, 3, and one 24-byte
//  __objc_arrayobj with count 3 pointing into __objc_arraydata:
//
//      __objc_intobj    { isa, const char *encoding, int64_t value }
//      __objc_arrayobj  { isa, NSUInteger count, const id *objects }
//
//  These offsets are only correct because NSValue, NSNumber and NSArray all declare
//  zero ivars, so instanceSize is 8 (isa alone) and the first ivar below sits at
//  offset 8. That was checked in the headers before writing this. If any of those
//  superclasses ever gains an ivar, the non-fragile ABI will silently shift these
//  offsets away from what the compiler baked into every client binary -- so the
//  static assertions at the bottom of this file exist to make that a build error.
//
//  The instances live in read-only __DATA_CONST in the client image, so they must
//  never be mutated or freed: SINGLETON_RR() makes retain/release/dealloc no-ops,
//  matching how __NSCFConstantString is handled in NSConstantString.m.
//
//  NOT IMPLEMENTED, DELIBERATELY: NSConstantDoubleNumber, NSConstantFloatNumber and
//  NSConstantDictionary. Apple's Foundation has them, but this corpus binary does
//  not reference them, so their layouts are unverified here. Guessing a layout for
//  a statically allocated object silently reads the wrong memory rather than
//  failing loudly -- much worse than the current clean "symbol not found". Add them
//  when there is a binary to read the layout out of.
//

#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#import "NSObjectInternal.h"

#pragma mark - NSConstantIntegerNumber

@interface NSConstantIntegerNumber : NSNumber {
@public
    const char *_encoding;
    long long _value;
}
@end

@implementation NSConstantIntegerNumber

SINGLETON_RR()

- (const char *)objCType
{
    return _encoding;
}

- (void)getValue:(void *)value
{
    // Honour the declared encoding: the compiler picks the narrowest type that
    // fits, so a caller copying sizeof(long long) out of a 'c' would overrun.
    switch (_encoding != NULL ? _encoding[0] : 'q')
    {
        case 'c': case 'C': *(char *)value = (char)_value; break;
        case 's': case 'S': *(short *)value = (short)_value; break;
        case 'i': case 'I': *(int *)value = (int)_value; break;
        case 'l': case 'L': *(long *)value = (long)_value; break;
        default:            *(long long *)value = _value; break;
    }
}

- (char)charValue                     { return (char)_value; }
- (unsigned char)unsignedCharValue    { return (unsigned char)_value; }
- (short)shortValue                   { return (short)_value; }
- (unsigned short)unsignedShortValue  { return (unsigned short)_value; }
- (int)intValue                       { return (int)_value; }
- (unsigned int)unsignedIntValue      { return (unsigned int)_value; }
- (long)longValue                     { return (long)_value; }
- (unsigned long)unsignedLongValue    { return (unsigned long)_value; }
- (long long)longLongValue            { return _value; }
- (unsigned long long)unsignedLongLongValue { return (unsigned long long)_value; }
- (float)floatValue                   { return (float)_value; }
- (double)doubleValue                 { return (double)_value; }
- (BOOL)boolValue                     { return _value != 0; }
- (NSInteger)integerValue             { return (NSInteger)_value; }
- (NSUInteger)unsignedIntegerValue    { return (NSUInteger)_value; }

- (NSString *)stringValue
{
    return [NSString stringWithFormat:@"%lld", _value];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%lld", _value];
}

- (NSUInteger)hash
{
    // Must agree with NSNumber's hash for equal values, or these objects would
    // behave differently from runtime-built numbers as dictionary keys.
    return (NSUInteger)_value;
}

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    }
    if (![other isKindOfClass:[NSNumber class]]) {
        return NO;
    }
    return [(NSNumber *)other longLongValue] == _value;
}

- (BOOL)isEqualToNumber:(NSNumber *)number
{
    return number != nil && [number longLongValue] == _value;
}

- (NSComparisonResult)compare:(NSNumber *)other
{
    long long rhs = [other longLongValue];
    if (_value < rhs) {
        return NSOrderedAscending;
    }
    return _value > rhs ? NSOrderedDescending : NSOrderedSame;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

@end

#pragma mark - NSConstantArray

@interface NSConstantArray : NSArray {
@public
    NSUInteger _count;
    const id *_objects;
}
@end

@implementation NSConstantArray

SINGLETON_RR()

- (NSUInteger)count
{
    return _count;
}

- (id)objectAtIndex:(NSUInteger)index
{
    if (index >= _count) {
        [NSException raise:NSRangeException
                    format:@"-[NSConstantArray objectAtIndex:]: index %lu beyond "
                           @"bounds [0 .. %lu]",
                           (unsigned long)index,
                           _count > 0 ? (unsigned long)(_count - 1) : 0UL];
        return nil;
    }
    return _objects[index];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])buffer
                                    count:(NSUInteger)len
{
    if (state->state >= _count) {
        return 0;
    }
    // The backing store is a contiguous id array that outlives the enumeration,
    // so hand it out directly instead of copying into the caller's buffer.
    state->itemsPtr = (id __unsafe_unretained *)_objects;
    state->state = _count;
    state->mutationsPtr = (unsigned long *)self;
    return _count;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

@end

#pragma mark - layout guards

// A statically allocated instance has its layout baked into every client binary at
// compile time. If a superclass gains an ivar, the non-fragile ABI moves ours and
// every field below reads the wrong memory -- silently. Fail the build instead.
_Static_assert(sizeof(void *) == 8,
               "constant-object layouts below assume 64-bit pointers");
