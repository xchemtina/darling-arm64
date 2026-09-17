#!/usr/bin/env python3
"""
DARLING-ARM64: add regression cases to the differential corpus. Idempotent.
Run from the repo root (the directory containing scripts/ and corpus/).

WHY
---
Four defects were fixed this week -- F28 (compiler-emitted constant classes), F34
(/var/tmp wiped every container start), F35 (plutil error message), F37
(abort_with_payload returning to a noreturn caller) -- and **not one of them is
covered by a test that would catch a regression**. The ladder covers F34 only
incidentally, via a service-tools rung that happens to write and then read a file.

The corpus is the right instrument: it found F28, F32, F33 and F36 directly, and
F34/F35 indirectly, which is a better return per hour than anything else here. It
also compares against ground truth captured from real macOS on the same bytes, so a
regression shows up as a divergence rather than as a judgement call.

WHAT THIS ADDS
--------------
  t08_plist.m    arm64          binary property list round-trip, in-process (F34)
  t09_vartmp.c   arm64          write/read/unlink under /private/var/tmp (F34)
  t10_boxed.m    arm64, arm64e  boxed literals, constant array AND constant
                                dictionary (F28 -- note NSConstantDictionary is
                                deliberately NOT implemented, so this also probes
                                whether clang emits it)
  t11_bridge.m   arm64, arm64e  CFStringGetCharacters on a CONSTANT CFString, i.e.
                                exactly the CF<->ObjC path that recursed in F33.
                                This is the test F33 currently lacks (STATE.md
                                trap 17: a fix cannot be credited while the failing
                                path is unexercised).

SCOPE NOTE, stated rather than glossed: t09 exercises read/write under
/private/var/tmp within a single process. It does **not** test survival across a
darlingserver restart, which is what F34 actually was -- a single binary cannot.
That remains covered by the service-tools rung of the ladder.

None of these take argv or stdin, so args_for()/stdin_for() need no changes and the
runner needs none either.

Revert with: git checkout -- scripts/10-make-corpus.sh
"""
import sys, pathlib

P = pathlib.Path("scripts/10-make-corpus.sh")

SOURCES = r'''
cat > "$SRC/t08_plist.m" <<'EOF'
/* Binary property list round-trip, in-process (FINDINGS.md F34).
   F34's first diagnosis blamed this reader; it was wrong, and this pins the
   reader so that if it ever does break, the corpus says so directly. */
#import <Foundation/Foundation.h>
#include <stdio.h>
int main(void){
    @autoreleasepool {
        NSDictionary *d = @{@"k": @"v", @"n": @42};
        NSData *bin = [NSPropertyListSerialization dataWithPropertyList:d
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
        const char *m = (const char *)[bin bytes];
        printf("magic:%c%c%c%c%c%c%c%c\n", m[0],m[1],m[2],m[3],m[4],m[5],m[6],m[7]);
        id back = [NSPropertyListSerialization propertyListWithData:bin
            options:NSPropertyListImmutable format:NULL error:NULL];
        printf("roundtrip:%s\n", back ? "ok" : "nil");
        printf("k:%s n:%d\n", [[back objectForKey:@"k"] UTF8String],
                              [[back objectForKey:@"n"] intValue]);
    }
    return 0;
}
EOF

cat > "$SRC/t09_vartmp.c" <<'EOF'
/* /private/var/tmp read/write (FINDINGS.md F34).
   NOTE: this covers a single process only. Survival across a darlingserver
   restart -- which is what F34 actually was -- is covered by the service-tools
   rung of the headless ladder, not here. */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main(void){
    const char *path = "/private/var/tmp/corpus-t09.txt";
    FILE *f = fopen(path, "w");
    if (!f) { printf("open_w:fail\n"); return 1; }
    fputs("payload", f);
    fclose(f);
    char buf[32] = {0};
    f = fopen(path, "r");
    if (!f) { printf("open_r:fail\n"); return 1; }
    if (!fgets(buf, sizeof(buf), f)) buf[0] = 0;
    fclose(f);
    unlink(path);
    printf("readback:%s match:%d\n", buf, strcmp(buf, "payload") == 0);
    return 0;
}
EOF

cat > "$SRC/t10_boxed.m" <<'EOF'
/* Compiler-emitted constant objects (FINDINGS.md F28).
   Recent clang statically allocates these into __objc_intobj / __objc_arrayobj,
   importing NSConstantIntegerNumber and NSConstantArray. The dictionary literal
   is deliberate: NSConstantDictionary was NOT implemented, so this also probes
   whether clang emits a constant dictionary here or builds one at runtime. */
#import <Foundation/Foundation.h>
#include <stdio.h>
int main(void){
    @autoreleasepool {
        NSArray *a = @[@1, @2, @3];
        printf("arr:%lu first:%d last:%d\n", (unsigned long)[a count],
               [[a objectAtIndex:0] intValue], [[a objectAtIndex:2] intValue]);
        NSDictionary *d = @{@"a": @10, @"b": @20};
        printf("dict:%lu a:%d\n", (unsigned long)[d count],
               [[d objectForKey:@"a"] intValue]);
        printf("bool:%d neg:%d big:%lld\n", [@YES boolValue], [@(-5) intValue],
               [@(1234567890123LL) longLongValue]);
        NSInteger sum = 0;
        for (NSNumber *n in a) sum += [n integerValue];
        printf("sum:%ld type:%s\n", (long)sum, [[a objectAtIndex:0] objCType]);
    }
    return 0;
}
EOF

cat > "$SRC/t11_bridge.m" <<'EOF'
/* CF<->ObjC bridging on a CONSTANT CFString (FINDINGS.md F33).
   This is the exact path that recursed to a stack overflow on arm64e:
       CFStringGetCharacters -> -[__NSCFString getCharacters:range:] -> ...
   broken only when _CFIsCFObject correctly recognises a CF object. F33 could not
   be credited with a fix because no test exercised this; this is that test. */
#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
int main(void){
    @autoreleasepool {
        CFStringRef cs = CFSTR("bridge-test");
        printf("cflen:%ld\n", (long)CFStringGetLength(cs));
        UniChar buf[8] = {0};
        CFStringGetCharacters(cs, CFRangeMake(0, 6), buf);
        printf("cfchars:%c%c%c%c%c%c\n", (char)buf[0], (char)buf[1], (char)buf[2],
                                         (char)buf[3], (char)buf[4], (char)buf[5]);
        NSString *ns = (__bridge NSString *)cs;
        printf("nslen:%lu\n", (unsigned long)[ns length]);
        unichar u[8] = {0};
        [ns getCharacters:u range:NSMakeRange(0, 6)];
        printf("nschars:%c%c%c%c%c%c\n", (char)u[0], (char)u[1], (char)u[2],
                                         (char)u[3], (char)u[4], (char)u[5]);
        NSString *fmt = [NSString stringWithFormat:@"f:%d", 7];
        printf("fmt:%s cls:%s\n", [fmt UTF8String], class_getName([fmt class]));
    }
    return 0;
}
EOF
'''

COMPILE_ANCHOR = 'compile t07_cf       "$SRC/t07_cf.c"       arm64 -framework CoreFoundation\n'
COMPILE_NEW = COMPILE_ANCHOR + '''compile t08_plist    "$SRC/t08_plist.m"    arm64  -framework Foundation -fobjc-arc
compile t09_vartmp   "$SRC/t09_vartmp.c"   arm64
compile t10_boxed    "$SRC/t10_boxed.m"    arm64  -framework Foundation -fobjc-arc
compile t11_bridge   "$SRC/t11_bridge.m"   arm64  -framework Foundation -framework CoreFoundation -fobjc-arc
'''

ARM64E_ANCHOR = 'compile t06_objc     "$SRC/t06_objc.m"     arm64e -framework Foundation -fobjc-arc\n'
ARM64E_NEW = ARM64E_ANCHOR + '''compile t10_boxed    "$SRC/t10_boxed.m"    arm64e -framework Foundation -fobjc-arc
compile t11_bridge   "$SRC/t11_bridge.m"   arm64e -framework Foundation -framework CoreFoundation -fobjc-arc
'''

# t11 uses class_getName
OBJC_RUNTIME_FIX = ('#import <Foundation/Foundation.h>\n#include <CoreFoundation/CoreFoundation.h>\n#include <stdio.h>\nint main(void){\n    @autoreleasepool {\n        CFStringRef cs = CFSTR("bridge-test");',
                    '#import <Foundation/Foundation.h>\n#include <CoreFoundation/CoreFoundation.h>\n#import <objc/runtime.h>\n#include <stdio.h>\nint main(void){\n    @autoreleasepool {\n        CFStringRef cs = CFSTR("bridge-test");')

if not P.exists():
    print(f"FATAL: missing {P} -- run from the repo root", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "t08_plist" in s:
    print("already patched")
    sys.exit(0)

anchor_src = 'EOF\n\n# --------------------------------------------------------------- compile ---'
if s.count(anchor_src) != 1:
    print(f"FATAL: source-block anchor found {s.count(anchor_src)}x (want 1)", file=sys.stderr)
    sys.exit(1)
s = s.replace(anchor_src,
              'EOF\n' + SOURCES + '\n# --------------------------------------------------------------- compile ---',
              1)

for old, new, what in ((COMPILE_ANCHOR, COMPILE_NEW, "arm64 compiles"),
                       (ARM64E_ANCHOR, ARM64E_NEW, "arm64e compiles")):
    if s.count(old) != 1:
        print(f"FATAL: {what} anchor found {s.count(old)}x (want 1)", file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)

s = s.replace(*OBJC_RUNTIME_FIX, 1)

P.write_text(s)
print(f"patched {P}: 4 new cases (t08 plist, t09 vartmp, t10 boxed, t11 bridge);"
      " t10 and t11 also built for arm64e")
