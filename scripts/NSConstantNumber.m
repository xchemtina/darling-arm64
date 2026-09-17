//
//  NSConstantNumber.m
//  Foundation
//
//  DARLING-ARM64: compiler-emitted constant boxed numbers (FINDINGS.md F28).
//
//  Companion to src/external/corefoundation/NSConstantArray.m -- read that file's
//  header for the full background. In short: recent clang (Apple clang 21 /
//  SDK 26.5) statically allocates the objects behind boxed literals, so `@[@1, @2,
//  @3]` emits __objc_intobj / __objc_arraydata / __objc_arrayobj and imports two
//  classes that Darling did not implement. The split between the two files follows
//  Apple's own: the binary binds NSConstantIntegerNumber from Foundation and
//  NSConstantArray from CoreFoundation, matching where NSNumber and NSArray live.
//  Defining this class in CoreFoundation fails to link -- NSNumber is not there.
//
//  INSTANCE LAYOUT
//  ---------------
//  Read out of an emitted binary with `otool -v -s __DATA_CONST __objc_intobj`,
//  not guessed: three 24-byte records holding 1, 2, 3.
//
//      { isa, const char *encoding, int64_t value }
//
//  Those offsets are only correct because NSValue and NSNumber both declare zero
//  ivars, so instanceSize is 8 (isa alone) and the first ivar below sits at offset
//  8. Checked in Foundation/NSValue.h before writing this. If either superclass ever
//  gains an ivar, the non-fragile ABI silently shifts these fields away from what
//  the compiler baked into every client binary.
//
//  The instances live in read-only __DATA_CONST in the client image, so they must
//  never be mutated or freed: SINGLETON_RR() makes retain/release/dealloc no-ops.
//
//  NOT IMPLEMENTED, DELIBERATELY: NSConstantDoubleNumber and NSConstantFloatNumber.
//  Apple's Foundation has them, but no binary here references them, so their
//  layouts are unverified. Guessing a layout for a statically allocated object
//  reads the wrong memory silently rather than failing loudly -- worse than the
//  current clean "symbol not found". Add them when there is a binary to read the
//  layout out of.
//

#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#import "NSObjectInternal.h"

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

- (char)charValue                            { return (char)_value; }
- (unsigned char)unsignedCharValue           { return (unsigned char)_value; }
- (short)shortValue                          { return (short)_value; }
- (unsigned short)unsignedShortValue         { return (unsigned short)_value; }
- (int)intValue                              { return (int)_value; }
- (unsigned int)unsignedIntValue             { return (unsigned int)_value; }
- (long)longValue                            { return (long)_value; }
- (unsigned long)unsignedLongValue           { return (unsigned long)_value; }
- (long long)longLongValue                   { return _value; }
- (unsigned long long)unsignedLongLongValue  { return (unsigned long long)_value; }
- (float)floatValue                          { return (float)_value; }
- (double)doubleValue                        { return (double)_value; }
- (BOOL)boolValue                            { return _value != 0; }
- (NSInteger)integerValue                    { return (NSInteger)_value; }
- (NSUInteger)unsignedIntegerValue           { return (NSUInteger)_value; }

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
