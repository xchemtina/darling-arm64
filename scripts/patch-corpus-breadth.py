#!/usr/bin/env python3
"""
DARLING-ARM64: widen the differential corpus into new capability areas. Idempotent.
Run from the repo root.

WHY THESE FIVE
--------------
The corpus already covers process start, syscalls, pthreads, dispatch, the ObjC
runtime, CoreFoundation, property lists, the filesystem basics and CF<->ObjC
bridging. It has been the highest-yield instrument in the project -- F28, F28b, F32,
F33 and F36 all came from it -- so the cheapest way to find the next defect is to
point it at capability areas nothing currently exercises.

  t12_strings.m      encodings, UTF-8/UTF-16 round-trips, composed vs decomposed,
                     case mapping, substring search
  t13_number.m       NSNumber across the integer/float boundary, NSDecimalNumber
                     arithmetic, and -description of each
  t14_fileman.m      NSFileManager: create, attributes, enumerate, move, remove
  t15_invoke.m       NSInvocation, message forwarding, method swizzling
  t16_collections.m  NSArray / NSSet / NSDictionary operations with deterministic
                     ordering

DETERMINISM IS THE WHOLE POINT. Ground truth is captured by running these on real
macOS, so anything that varies run-to-run or host-to-host produces a false
divergence and burns time. Deliberately avoided:

  * dates, times, timezones and anything locale- or ICU-dependent -- ICU versions
    differ between macOS 26 and Darling's bundle, so a divergence there would say
    nothing about Darling;
  * unordered enumeration of sets and dictionaries (sorted before printing);
  * paths, pids, addresses and sizes that depend on the environment.

Everything printed is either a fixed string, a count, or a comparison result.

Built for **both arm64 and arm64e**. arm64e is the least independently verified part
of the stack, so a divergence found only there is worth more than an arm64 one.

Revert with: git checkout -- scripts/10-make-corpus.sh
"""
import sys, pathlib

P = pathlib.Path("scripts/10-make-corpus.sh")

SOURCES = r'''
cat > "$SRC/t12_strings.m" <<'EOF'
/* String encodings and Unicode handling. */
#import <Foundation/Foundation.h>
#include <stdio.h>
int main(void){
    @autoreleasepool {
        NSString *s = @"café 中文";           /* precomposed e-acute */
        printf("len:%lu\n", (unsigned long)[s length]);
        printf("utf8len:%lu\n", (unsigned long)[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
        NSData *u8 = [s dataUsingEncoding:NSUTF8StringEncoding];
        NSString *back = [[NSString alloc] initWithData:u8 encoding:NSUTF8StringEncoding];
        printf("roundtrip:%d\n", [back isEqualToString:s]);
        NSString *dec = [s decomposedStringWithCanonicalMapping];
        NSString *pre = [dec precomposedStringWithCanonicalMapping];
        printf("decomp_len:%lu recomp_eq:%d\n", (unsigned long)[dec length],
               [pre isEqualToString:s]);
        printf("upper:%s\n", [[@"straße-abc" uppercaseString] UTF8String]);
        printf("find:%lu\n", (unsigned long)[s rangeOfString:@"中"].location);
        printf("prefix:%d suffix:%d\n", [s hasPrefix:@"caf"], [s hasSuffix:@"文"]);
        unichar c = [s characterAtIndex:3];
        printf("ch3:%04x\n", (unsigned)c);
        printf("cmp:%ld\n", (long)[@"abc" compare:@"abd"]);
    }
    return 0;
}
EOF

cat > "$SRC/t13_number.m" <<'EOF'
/* NSNumber across type boundaries, and NSDecimalNumber arithmetic. */
#import <Foundation/Foundation.h>
#include <stdio.h>
int main(void){
    @autoreleasepool {
        NSNumber *i = [NSNumber numberWithInt:-42];
        NSNumber *u = [NSNumber numberWithUnsignedLongLong:18446744073709551615ULL];
        NSNumber *d = [NSNumber numberWithDouble:0.5];
        printf("i:%d u:%llu d:%.1f\n", [i intValue], [u unsignedLongLongValue],
               [d doubleValue]);
        printf("desc:%s %s %s\n", [[i description] UTF8String],
               [[u description] UTF8String], [[d description] UTF8String]);
        printf("types:%s %s\n", [i objCType], [d objCType]);
        printf("cmp:%ld eq:%d\n", (long)[i compare:d], [i isEqualToNumber:[NSNumber numberWithInt:-42]]);
        NSDecimalNumber *a = [NSDecimalNumber decimalNumberWithString:@"10.25"];
        NSDecimalNumber *b = [NSDecimalNumber decimalNumberWithString:@"3"];
        printf("add:%s\n", [[[a decimalNumberByAdding:b] stringValue] UTF8String]);
        printf("mul:%s\n", [[[a decimalNumberByMultiplyingBy:b] stringValue] UTF8String]);
        printf("bool:%d %d\n", [[NSNumber numberWithBool:YES] boolValue],
               [[NSNumber numberWithBool:NO] boolValue]);
    }
    return 0;
}
EOF

cat > "$SRC/t14_fileman.m" <<'EOF'
/* NSFileManager: create, attributes, enumerate, move, remove. */
#import <Foundation/Foundation.h>
#include <stdio.h>
int main(void){
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = @"/private/var/tmp/corpus-t14";
        [fm removeItemAtPath:dir error:NULL];
        printf("mkdir:%d\n", [fm createDirectoryAtPath:dir
            withIntermediateDirectories:YES attributes:nil error:NULL]);
        NSString *f1 = [dir stringByAppendingPathComponent:@"one.txt"];
        printf("write:%d\n", [@"hello" writeToFile:f1 atomically:YES
            encoding:NSUTF8StringEncoding error:NULL]);
        NSDictionary *at = [fm attributesOfItemAtPath:f1 error:NULL];
        printf("size:%llu\n", [[at objectForKey:NSFileSize] unsignedLongLongValue]);
        printf("exists:%d isdir:%d\n", [fm fileExistsAtPath:f1], [fm fileExistsAtPath:dir]);
        NSString *f2 = [dir stringByAppendingPathComponent:@"two.txt"];
        printf("move:%d\n", [fm moveItemAtPath:f1 toPath:f2 error:NULL]);
        NSArray *kids = [[fm contentsOfDirectoryAtPath:dir error:NULL]
            sortedArrayUsingSelector:@selector(compare:)];
        printf("count:%lu first:%s\n", (unsigned long)[kids count],
               [[kids objectAtIndex:0] UTF8String]);
        printf("read:%s\n", [[NSString stringWithContentsOfFile:f2
            encoding:NSUTF8StringEncoding error:NULL] UTF8String]);
        printf("rm:%d\n", [fm removeItemAtPath:dir error:NULL]);
        printf("gone:%d\n", ![fm fileExistsAtPath:dir]);
    }
    return 0;
}
EOF

cat > "$SRC/t15_invoke.m" <<'EOF'
/* NSInvocation, message forwarding, and swizzling. */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdio.h>

@interface Target : NSObject
- (int)doubleIt:(int)x;
@end
@implementation Target
- (int)doubleIt:(int)x { return x * 2; }
- (NSString *)swizzled { return @"orig"; }
@end

@interface Proxy : NSObject { Target *_t; }
@end
@implementation Proxy
- (id)init { if ((self = [super init])) _t = [Target new]; return self; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s {
    return [_t methodSignatureForSelector:s] ?: [super methodSignatureForSelector:s];
}
- (void)forwardInvocation:(NSInvocation *)inv { [inv invokeWithTarget:_t]; }
@end

static NSString *replacement(id self, SEL _cmd) { return @"swapped"; }

int main(void){
    @autoreleasepool {
        Target *t = [Target new];
        NSMethodSignature *sig = [t methodSignatureForSelector:@selector(doubleIt:)];
        printf("args:%lu ret:%s\n", (unsigned long)[sig numberOfArguments],
               [sig methodReturnType]);
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:t]; [inv setSelector:@selector(doubleIt:)];
        int arg = 21; [inv setArgument:&arg atIndex:2];
        [inv invoke];
        int out = 0; [inv getReturnValue:&out];
        printf("invoke:%d\n", out);
        Proxy *p = [Proxy new];
        printf("forward:%d\n", (int)[(Target *)p doubleIt:5]);
        printf("respond:%d\n", [t respondsToSelector:@selector(doubleIt:)]);
        Method m = class_getInstanceMethod([Target class], @selector(swizzled));
        printf("before:%s\n", [[t swizzled] UTF8String]);
        method_setImplementation(m, (IMP)replacement);
        printf("after:%s\n", [[t swizzled] UTF8String]);
        printf("class:%s super:%s\n", class_getName([t class]),
               class_getName(class_getSuperclass([t class])));
    }
    return 0;
}
EOF

cat > "$SRC/t16_collections.m" <<'EOF'
/* Collection behaviour with deterministic ordering. */
#import <Foundation/Foundation.h>
#include <stdio.h>
int main(void){
    @autoreleasepool {
        NSMutableArray *a = [NSMutableArray array];
        for (int i = 5; i > 0; i--) [a addObject:[NSNumber numberWithInt:i]];
        NSArray *sorted = [a sortedArrayUsingComparator:^(id x, id y){
            return [(NSNumber *)x compare:(NSNumber *)y]; }];
        printf("sorted:");
        for (NSNumber *n in sorted) printf("%d", [n intValue]);
        printf("\n");
        printf("idx:%lu contains:%d\n",
               (unsigned long)[sorted indexOfObject:[NSNumber numberWithInt:3]],
               [sorted containsObject:[NSNumber numberWithInt:9]]);
        NSSet *s = [NSSet setWithArray:a];
        printf("setcount:%lu member:%d\n", (unsigned long)[s count],
               [s containsObject:[NSNumber numberWithInt:4]]);
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        [d setObject:@"x" forKey:@"k1"]; [d setObject:@"y" forKey:@"k2"];
        NSArray *keys = [[d allKeys] sortedArrayUsingSelector:@selector(compare:)];
        printf("keys:%s,%s vals:%s,%s\n",
               [[keys objectAtIndex:0] UTF8String], [[keys objectAtIndex:1] UTF8String],
               [[d objectForKey:@"k1"] UTF8String], [[d objectForKey:@"k2"] UTF8String]);
        [d removeObjectForKey:@"k1"];
        printf("after_rm:%lu\n", (unsigned long)[d count]);
        NSArray *joined = [@"a,b,c" componentsSeparatedByString:@","];
        printf("split:%lu joined:%s\n", (unsigned long)[joined count],
               [[joined componentsJoinedByString:@"-"] UTF8String]);
    }
    return 0;
}
EOF
'''

COMPILE_ANCHOR = 'compile t11_bridge   "$SRC/t11_bridge.m"   arm64  -framework Foundation -framework CoreFoundation -fobjc-arc\n'
COMPILE_NEW = COMPILE_ANCHOR + '''compile t12_strings  "$SRC/t12_strings.m"  arm64  -framework Foundation -fobjc-arc
compile t13_number   "$SRC/t13_number.m"   arm64  -framework Foundation -fobjc-arc
compile t14_fileman  "$SRC/t14_fileman.m"  arm64  -framework Foundation -fobjc-arc
compile t15_invoke   "$SRC/t15_invoke.m"   arm64  -framework Foundation
compile t16_collect  "$SRC/t16_collections.m" arm64 -framework Foundation -fobjc-arc
'''

ARM64E_ANCHOR = 'compile t09_vartmp   "$SRC/t09_vartmp.c"   arm64e\n'
ARM64E_NEW = ARM64E_ANCHOR + '''compile t12_strings  "$SRC/t12_strings.m"  arm64e -framework Foundation -fobjc-arc
compile t13_number   "$SRC/t13_number.m"   arm64e -framework Foundation -fobjc-arc
compile t14_fileman  "$SRC/t14_fileman.m"  arm64e -framework Foundation -fobjc-arc
compile t15_invoke   "$SRC/t15_invoke.m"   arm64e -framework Foundation
compile t16_collect  "$SRC/t16_collections.m" arm64e -framework Foundation -fobjc-arc
'''

if not P.exists():
    print(f"FATAL: missing {P} -- run from the repo root", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "t12_strings" in s:
    print("already patched")
    sys.exit(0)

anchor_src = 'EOF\n\n# --------------------------------------------------------------- compile ---'
if s.count(anchor_src) != 1:
    print(f"FATAL: source anchor found {s.count(anchor_src)}x (want 1)", file=sys.stderr)
    sys.exit(1)
s = s.replace(anchor_src,
              'EOF\n' + SOURCES + '\n# --------------------------------------------------------------- compile ---', 1)

for old, new, what in ((COMPILE_ANCHOR, COMPILE_NEW, "arm64"),
                       (ARM64E_ANCHOR, ARM64E_NEW, "arm64e")):
    if s.count(old) != 1:
        print(f"FATAL: {what} compile anchor found {s.count(old)}x (want 1)", file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)

P.write_text(s)
print(f"patched {P}: 5 new capability areas, each built for arm64 and arm64e")
