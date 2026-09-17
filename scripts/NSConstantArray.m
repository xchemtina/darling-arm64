//
//  NSConstantArray.m
//  CoreFoundation
//
//  DARLING-ARM64: compiler-emitted constant NSArray (FINDINGS.md F28).
//
//  Recent clang (verified with Apple clang 21 / SDK 26.5) statically allocates the
//  objects behind collection and boxed-number literals instead of building them at
//  runtime. A trivial program containing `@[@1, @2, @3]` emits three __DATA_CONST
//  sections -- __objc_intobj, __objc_arraydata, __objc_arrayobj -- and imports:
//
//      _OBJC_CLASS_$_NSConstantArray           (from CoreFoundation)  <- here
//      _OBJC_CLASS_$_NSConstantIntegerNumber   (from Foundation)      <- NSConstantNumber.m
//
//  That split is not arbitrary: NSArray is implemented in CoreFoundation and
//  NSNumber in Foundation, so each constant subclass has to live beside its
//  superclass. Trying to define both here fails to link with
//  "_OBJC_CLASS_$_NSNumber, referenced from: NSConstantObjects.m.o".
//
//  Darling implemented neither, so any binary built against a modern macOS SDK that
//  uses @1-style literals failed to launch:
//
//      abort_with_payload: Symbol not found: _OBJC_CLASS_$_NSConstantIntegerNumber
//        Referenced from: /corpus/t06_objc.arm64 (built for Mac OS X 26.0)
//        Expected in: /System/Library/Frameworks/Foundation.framework/.../Foundation
//
//  Not architecture-specific -- a Foundation completeness gap -- but invisible to
//  gates built from applications compiled against older SDKs.
//
//  INSTANCE LAYOUT
//  ---------------
//  Read out of an emitted binary with `otool -v -s __DATA_CONST __objc_arrayobj`,
//  not guessed: one 24-byte record, count 3, pointing into __objc_arraydata.
//
//      { isa, NSUInteger count, const id *objects }
//
//  Those offsets are only correct because NSArray declares zero ivars, so
//  instanceSize is 8 (isa alone) and the first ivar below sits at offset 8. Checked
//  in Foundation/NSArray.h before writing this. If NSArray ever gains an ivar, the
//  non-fragile ABI silently shifts these fields away from what the compiler baked
//  into every client binary.
//
//  The instances live in read-only __DATA_CONST in the client image, so they must
//  never be mutated or freed: SINGLETON_RR() makes retain/release/dealloc no-ops,
//  matching how __NSCFConstantString is handled in NSConstantString.m.
//
//  NOT IMPLEMENTED, DELIBERATELY: NSConstantDictionary. Apple's Foundation has one,
//  but no binary here references it, so its layout is unverified. Guessing a layout
//  for a statically allocated object reads the wrong memory silently rather than
//  failing loudly -- worse than the current clean "symbol not found". Add it when
//  there is a binary to read the layout out of.
//

#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>

#import "NSObjectInternal.h"

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
    // The backing store is a contiguous id array that outlives the enumeration, so
    // hand it out directly instead of copying into the caller's buffer.
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
