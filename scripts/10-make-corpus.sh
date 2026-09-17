#!/usr/bin/env bash
# Runs on the macOS HOST. Builds the differential test corpus:
# arm64 / arm64e Mach-O binaries plus real Apple-signed CLT binaries,
# each executed natively to capture ground truth. The same corpus is
# later run under Darling in the VM and diffed against these results.
set -uo pipefail

ROOT="${1:-$HOME/darling/corpus}"
SRC="$ROOT/src"; BIN="$ROOT/bin"; TRUTH="$ROOT/truth"
mkdir -p "$SRC" "$BIN" "$TRUTH"

log() { printf '\n=== %s ===\n' "$*"; }

log "toolchain"
clang --version | head -2
echo "SDK: $(xcrun --show-sdk-path 2>/dev/null) ($(xcrun --show-sdk-version 2>/dev/null))"

# --------------------------------------------------------------- sources ---
cat > "$SRC/t01_hello.c" <<'EOF'
#include <stdio.h>
int main(void){ printf("hello from arm64 darwin\n"); return 0; }
EOF

cat > "$SRC/t02_exit42.c" <<'EOF'
int main(void){ return 42; }
EOF

cat > "$SRC/t03_syscalls.c" <<'EOF'
/* Direct libc syscall surface: write/getpid/uname/time/mmap. */
#include <stdio.h>
#include <unistd.h>
#include <sys/utsname.h>
#include <sys/mman.h>
#include <string.h>
int main(void){
    write(1, "w:ok\n", 5);
    printf("pid_positive:%d\n", getpid() > 0);
    struct utsname u;
    printf("uname:%d\n", uname(&u) == 0);
    printf("sysname:%s\n", u.sysname);
    void *p = mmap(0, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0);
    printf("mmap:%d\n", p != MAP_FAILED);
    if (p != MAP_FAILED) { memset(p, 7, 4096); printf("mmap_rw:%d\n", ((char*)p)[100] == 7); munmap(p, 4096); }
    return 0;
}
EOF

cat > "$SRC/t04_pthread.c" <<'EOF'
#include <stdio.h>
#include <pthread.h>
static void *fn(void *a){ *(int*)a = 99; return 0; }
int main(void){
    pthread_t th; int v = 0;
    if (pthread_create(&th, 0, fn, &v)) { printf("create_fail\n"); return 1; }
    pthread_join(th, 0);
    printf("thread_ran:%d\n", v == 99);
    return 0;
}
EOF

cat > "$SRC/t05_dispatch.c" <<'EOF'
/* libdispatch — a Darwin-specific subsystem, good tier-5 probe. */
#include <stdio.h>
#include <dispatch/dispatch.h>
int main(void){
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    __block int hit = 0;
    dispatch_async(dispatch_get_global_queue(0,0), ^{ hit = 1; dispatch_semaphore_signal(s); });
    dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER);
    printf("dispatch_ran:%d\n", hit);
    return 0;
}
EOF

cat > "$SRC/t06_objc.m" <<'EOF'
/* ObjC runtime + Foundation — the tier-5 frontier. */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
int main(void){
    @autoreleasepool {
        NSString *s = [NSString stringWithFormat:@"objc:%d", 1];
        printf("%s\n", [s UTF8String]);
        NSArray *a = @[@1, @2, @3];
        printf("count:%lu\n", (unsigned long)[a count]);
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        d[@"k"] = @"v";
        printf("dict:%s\n", [d[@"k"] UTF8String]);
        printf("class:%s\n", class_getName([s class]));
    }
    return 0;
}
EOF

cat > "$SRC/t07_cf.c" <<'EOF'
/* CoreFoundation without ObjC syntax. */
#include <stdio.h>
#include <CoreFoundation/CoreFoundation.h>
int main(void){
    CFStringRef s = CFStringCreateWithCString(NULL, "cf", kCFStringEncodingUTF8);
    printf("cf_len:%ld\n", (long)CFStringGetLength(s));
    CFRelease(s);
    return 0;
}
EOF

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
#import <objc/runtime.h>
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
        /* All four normalisation methods. Two of them had each other's constants
           (FINDINGS.md F39); the canonical pair caught it, the compatibility pair
           was found by reading and is pinned here so it cannot regress. */
        NSString *dec = [s decomposedStringWithCanonicalMapping];
        NSString *pre = [dec precomposedStringWithCanonicalMapping];
        printf("decomp_len:%lu recomp_eq:%d\n", (unsigned long)[dec length],
               [pre isEqualToString:s]);
        NSString *kdec = [s decomposedStringWithCompatibilityMapping];
        NSString *kpre = [kdec precomposedStringWithCompatibilityMapping];
        printf("kdecomp_len:%lu krecomp_eq:%d\n", (unsigned long)[kdec length],
               [kpre isEqualToString:s]);
        printf("nfd_ne_nfc:%d nfkd_len_ge:%d\n", ![dec isEqualToString:pre],
               (int)([kdec length] >= [s length]));
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

cat > "$SRC/t17_archive.m" <<'EOF'
/* NSKeyedArchiver / NSKeyedUnarchiver over a nested graph with shared references
   and a cycle -- the shape NSSavePanel's NIB decode takes (FINDINGS.md F27). */
#import <Foundation/Foundation.h>
#include <stdio.h>

@interface Cell : NSObject <NSCoding>
@property (assign) int tag;
@property (retain) NSString *label;
@property (assign) id owner;          /* weak-ish back reference -> cycle */
@end

@implementation Cell
@synthesize tag = _tag, label = _label, owner = _owner;
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeInt:_tag forKey:@"tag"];
    [c encodeObject:_label forKey:@"label"];
    [c encodeConditionalObject:_owner forKey:@"owner"];
}
- (id)initWithCoder:(NSCoder *)c {
    if ((self = [super init])) {
        _tag = [c decodeIntForKey:@"tag"];
        _label = [[c decodeObjectForKey:@"label"] retain];
        _owner = [c decodeObjectForKey:@"owner"];
    }
    return self;
}
@end

@interface Column : NSObject <NSCoding>
@property (retain) Cell *cell;
@property (retain) Cell *shared;
@property (retain) NSData *blob;
@property (assign) BOOL flag;
@end

@implementation Column
@synthesize cell = _cell, shared = _shared, blob = _blob, flag = _flag;
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:_cell forKey:@"cell"];
    [c encodeObject:_shared forKey:@"shared"];
    [c encodeObject:_blob forKey:@"blob"];
    [c encodeBool:_flag forKey:@"flag"];
}
- (id)initWithCoder:(NSCoder *)c {
    if ((self = [super init])) {
        _cell = [[c decodeObjectForKey:@"cell"] retain];
        _shared = [[c decodeObjectForKey:@"shared"] retain];
        _blob = [[c decodeObjectForKey:@"blob"] retain];
        _flag = [c decodeBoolForKey:@"flag"];
    }
    return self;
}
@end

int main(void){
    @autoreleasepool {
        Cell *shared = [[Cell new] autorelease];
        shared.tag = 99; shared.label = @"shared";

        NSMutableArray *cols = [NSMutableArray array];
        for (int i = 0; i < 3; i++) {
            Cell *cell = [[Cell new] autorelease];
            cell.tag = i; cell.label = [NSString stringWithFormat:@"cell%d", i];
            Column *col = [[Column new] autorelease];
            col.cell = cell;
            col.shared = shared;                    /* same object, 3 references */
            col.blob = [@"blob" dataUsingEncoding:NSUTF8StringEncoding];
            col.flag = (i % 2) == 0;
            cell.owner = col;                       /* cycle: col -> cell -> col */
            [cols addObject:col];
        }

        NSData *arch = [NSKeyedArchiver archivedDataWithRootObject:cols];
        printf("archived:%d magic:%c%c%c%c\n", [arch length] > 0,
               ((const char *)[arch bytes])[0], ((const char *)[arch bytes])[1],
               ((const char *)[arch bytes])[2], ((const char *)[arch bytes])[3]);

        NSArray *back = [NSKeyedUnarchiver unarchiveObjectWithData:arch];
        printf("count:%lu\n", (unsigned long)[back count]);
        if ([back count] == 3) {
            Column *c0 = [back objectAtIndex:0];
            Column *c2 = [back objectAtIndex:2];
            printf("tags:%d,%d\n", c0.cell.tag, c2.cell.tag);
            printf("labels:%s,%s\n", [c0.cell.label UTF8String],
                                     [c2.cell.label UTF8String]);
            printf("shared_tag:%d shared_identity:%d\n", c0.shared.tag,
                   c0.shared == c2.shared);
            printf("cycle:%d\n", c0.cell.owner == c0);
            printf("flags:%d,%d blob:%lu\n", c0.flag, c2.flag,
                   (unsigned long)[c0.blob length]);
        }
    }
    return 0;
}
EOF

cat > "$SRC/t18_task.m" <<'EOF'
/* NSTask + NSPipe: launching a child and reading its output. */
#import <Foundation/Foundation.h>
#include <stdio.h>
int main(void){
    @autoreleasepool {
        NSTask *t = [[NSTask new] autorelease];
        /* NOTE: /bin/echo does NOT exist in the Darling runtime (it ships a
           minimal /bin: bash, cat, sh, zsh, csh, tcsh, bzip2, launchctl), so an
           earlier version of this case reported a false NSTask defect. Use the
           shell, which is present on both sides. */
        [t setLaunchPath:@"/bin/sh"];
        [t setArguments:@[@"-c", @"printf 'hello task\n'"]];
        NSPipe *pipe = [NSPipe pipe];
        [t setStandardOutput:pipe];
        [t launch];
        NSData *out = [[pipe fileHandleForReading] readDataToEndOfFile];
        [t waitUntilExit];
        NSString *s = [[[NSString alloc] initWithData:out
            encoding:NSUTF8StringEncoding] autorelease];
        printf("status:%d running:%d\n", [t terminationStatus], [t isRunning]);
        printf("out:%s", [s UTF8String]);
        printf("len:%lu\n", (unsigned long)[out length]);
    }
    return 0;
}
EOF

cat > "$SRC/t19_url.m" <<'EOF'
/* NSURL parsing, resolution and encoding. */
#import <Foundation/Foundation.h>
#include <stdio.h>
static const char *S(NSString *s) { return s ? [s UTF8String] : "(nil)"; }
int main(void){
    @autoreleasepool {
        NSURL *u = [NSURL URLWithString:@"https://user@example.com:8080/a/b/c.txt?q=1&r=2#frag"];
        printf("scheme:%s host:%s port:%s\n", S([u scheme]), S([u host]),
               S([[u port] stringValue]));
        printf("path:%s query:%s frag:%s user:%s\n", S([u path]), S([u query]),
               S([u fragment]), S([u user]));
        printf("lastc:%s ext:%s\n", S([u lastPathComponent]), S([u pathExtension]));
        NSURL *base = [NSURL URLWithString:@"https://example.com/dir/"];
        NSURL *rel = [NSURL URLWithString:@"../up/x.html" relativeToURL:base];
        printf("abs:%s\n", S([[rel absoluteURL] absoluteString]));
        NSURL *f = [NSURL fileURLWithPath:@"/private/var/tmp/a b.txt"];
        printf("file:%s isfile:%d\n", S([f absoluteString]), [f isFileURL]);
        printf("enc:%s\n", S([@"a b&c" stringByAddingPercentEncodingWithAllowedCharacters:
               [NSCharacterSet URLQueryAllowedCharacterSet]]));
        printf("dec:%s\n", S([@"a%20b%26c" stringByRemovingPercentEncoding]));
        printf("eq:%d\n", [[NSURL URLWithString:@"https://a.com/x"]
                           isEqual:[NSURL URLWithString:@"https://a.com/x"]]);
    }
    return 0;
}
EOF

cat > "$SRC/t20_regex.m" <<'EOF'
/* NSRegularExpression: matching, groups, replacement. */
#import <Foundation/Foundation.h>
#include <stdio.h>
int main(void){
    @autoreleasepool {
        NSString *subject = @"cat=1, dog=22, bird=333";
        NSError *err = nil;
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:@"([a-z]+)=([0-9]+)" options:0 error:&err];
        printf("compiled:%d err:%d\n", re != nil, err != nil);
        NSRange all = NSMakeRange(0, [subject length]);
        printf("count:%lu\n", (unsigned long)[re numberOfMatchesInString:subject
               options:0 range:all]);
        NSTextCheckingResult *m = [re firstMatchInString:subject options:0 range:all];
        printf("groups:%lu\n", (unsigned long)[m numberOfRanges]);
        printf("g1:%s g2:%s\n",
               [[subject substringWithRange:[m rangeAtIndex:1]] UTF8String],
               [[subject substringWithRange:[m rangeAtIndex:2]] UTF8String]);
        NSString *rep = [re stringByReplacingMatchesInString:subject options:0
                            range:all withTemplate:@"$2:$1"];
        printf("replaced:%s\n", [rep UTF8String]);
        NSRegularExpression *ci = [NSRegularExpression regularExpressionWithPattern:@"CAT"
            options:NSRegularExpressionCaseInsensitive error:NULL];
        printf("ci:%lu\n", (unsigned long)[ci numberOfMatchesInString:subject
               options:0 range:all]);
        NSRegularExpression *bad = [NSRegularExpression
            regularExpressionWithPattern:@"([" options:0 error:&err];
        printf("badpattern:%d haserr:%d\n", bad == nil, err != nil);
    }
    return 0;
}
EOF

cat > "$SRC/t21_secure.m" <<'EOF'
/* NSSecureCoding: allowed classes, and the rejection path. */
#import <Foundation/Foundation.h>
#include <stdio.h>

@interface Item : NSObject <NSSecureCoding>
@property (assign) int n;
@property (retain) NSString *name;
@end
@implementation Item
@synthesize n = _n, name = _name;
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeInt:_n forKey:@"n"];
    [c encodeObject:_name forKey:@"name"];
}
- (id)initWithCoder:(NSCoder *)c {
    if ((self = [super init])) {
        _n = [c decodeIntForKey:@"n"];
        _name = [[c decodeObjectOfClass:[NSString class] forKey:@"name"] retain];
    }
    return self;
}
@end

int main(void){
    @autoreleasepool {
        Item *it = [[Item new] autorelease];
        it.n = 7; it.name = @"secure";

        NSMutableData *d = [NSMutableData data];
        NSKeyedArchiver *a = [[[NSKeyedArchiver alloc]
            initForWritingWithMutableData:d] autorelease];
        [a setRequiresSecureCoding:YES];
        [a encodeObject:it forKey:@"root"];
        [a finishEncoding];
        printf("encoded:%d secure:%d\n", [d length] > 0, [a requiresSecureCoding]);

        NSKeyedUnarchiver *u = [[[NSKeyedUnarchiver alloc]
            initForReadingWithData:d] autorelease];
        [u setRequiresSecureCoding:YES];
        Item *back = [u decodeObjectOfClass:[Item class] forKey:@"root"];
        printf("decoded:%d n:%d name:%s\n", back != nil, back.n,
               [back.name UTF8String]);
        printf("supports:%d\n", [Item supportsSecureCoding]);

        /* Wrong expected class must be refused, not silently accepted. */
        NSKeyedUnarchiver *u2 = [[[NSKeyedUnarchiver alloc]
            initForReadingWithData:d] autorelease];
        [u2 setRequiresSecureCoding:YES];
        id wrong = nil;
        @try { wrong = [u2 decodeObjectOfClass:[NSArray class] forKey:@"root"]; }
        @catch (NSException *e) { printf("rejected:1\n"); wrong = nil; }
        if (wrong != nil) printf("rejected:0\n");
    }
    return 0;
}
EOF

cat > "$SRC/t22_error.m" <<'EOF'
/* NSError and NSException. */
#import <Foundation/Foundation.h>
#include <stdio.h>
int main(void){
    @autoreleasepool {
        NSError *e = [NSError errorWithDomain:@"corpus.domain" code:42
            userInfo:@{NSLocalizedDescriptionKey: @"a failure"}];
        printf("domain:%s code:%ld\n", [[e domain] UTF8String], (long)[e code]);
        printf("desc:%s\n", [[e localizedDescription] UTF8String]);
        printf("uicount:%lu\n", (unsigned long)[[e userInfo] count]);

        NSError *out = nil;
        NSString *missing = [NSString stringWithContentsOfFile:@"/nonexistent/xyz"
            encoding:NSUTF8StringEncoding error:&out];
        printf("read:%d gaveerr:%d cocoa:%d\n", missing != nil, out != nil,
               [[out domain] isEqualToString:NSCocoaErrorDomain]);

        int caught = 0; const char *nm = "none";
        @try {
            @throw [NSException exceptionWithName:@"CorpusException"
                    reason:@"deliberate" userInfo:nil];
        } @catch (NSException *ex) {
            caught = 1; nm = [[ex name] UTF8String];
            printf("reason:%s\n", [[ex reason] UTF8String]);
        } @finally {
            printf("finally:1\n");
        }
        printf("caught:%d name:%s\n", caught, nm);

        int idx = 0;
        @try { [@[@1, @2] objectAtIndex:9]; }
        @catch (NSException *ex) { idx = 1; }
        printf("rangecheck:%d\n", idx);
    }
    return 0;
}
EOF

cat > "$SRC/t23_kvc.m" <<'EOF'
/* Key-value coding and key-value observing: -valueForKey:/-setValue:forKey:,
   nested key paths, -dictionaryWithValuesForKeys:, the @count/@sum/@max/@avg/
   @distinctUnionOfObjects collection operators, and a KVO observer that counts
   notifications and inspects the old/new values. KVC/KVO are implemented on top
   of the ObjC runtime (accessor lookup, ivar access, dynamic isa-swizzled
   notifying subclasses), so they exercise a lot of Darling's runtime at once.
   The undefined-key and nil-scalar paths are included because the exception
   behaviour is the part most likely to diverge. */
#import <Foundation/Foundation.h>
#include <stdio.h>

@interface Address : NSObject
@property (nonatomic, copy) NSString *city;
@property (nonatomic, assign) NSInteger zip;
@end
@implementation Address
@end

@interface Person : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *nickname;
@property (nonatomic, assign) NSInteger age;
@property (nonatomic, retain) Address *address;
@end
@implementation Person
@end

@interface Watcher : NSObject {
    int _fires;
    id _lastOld;
    id _lastNew;
    NSUInteger _lastKind;
}
- (int)fires;
- (id)lastOld;
- (id)lastNew;
- (NSUInteger)lastKind;
@end
@implementation Watcher
- (int)fires { return _fires; }
- (id)lastOld { return _lastOld; }
- (id)lastNew { return _lastNew; }
- (NSUInteger)lastKind { return _lastKind; }
- (void)observeValueForKeyPath:(NSString *)kp ofObject:(id)obj
                        change:(NSDictionary *)change context:(void *)ctx {
    (void)kp; (void)obj; (void)ctx;
    _fires++;
    [_lastOld release];
    [_lastNew release];
    _lastOld = [[change objectForKey:NSKeyValueChangeOldKey] retain];
    _lastNew = [[change objectForKey:NSKeyValueChangeNewKey] retain];
    _lastKind = [[change objectForKey:NSKeyValueChangeKindKey] unsignedIntegerValue];
}
@end

static Person *mkperson(NSString *n, NSInteger a) {
    Person *p = [[[Person alloc] init] autorelease];
    [p setName:n];
    [p setAge:a];
    return p;
}

static const char *joined(NSArray *a) {
    return [[[a sortedArrayUsingSelector:@selector(compare:)]
             componentsJoinedByString:@","] UTF8String];
}

int main(void){
    @autoreleasepool {
        Address *addr = [[[Address alloc] init] autorelease];
        [addr setCity:@"Quito"];
        [addr setZip:1701];

        Person *p = mkperson(@"ana", 30);
        [p setAddress:addr];

        printf("get name:%s age:%ld\n", [[p valueForKey:@"name"] UTF8String],
               (long)[[p valueForKey:@"age"] longValue]);

        [p setValue:@"bo" forKey:@"name"];
        [p setValue:[NSNumber numberWithInteger:31] forKey:@"age"];
        printf("set name:%s age:%ld\n", [[p name] UTF8String], (long)[p age]);

        printf("path city:%s zip:%ld\n",
               [[p valueForKeyPath:@"address.city"] UTF8String],
               (long)[[p valueForKeyPath:@"address.zip"] longValue]);

        [p setValue:@"Lima" forKeyPath:@"address.city"];
        printf("setpath city:%s same:%d\n", [[addr city] UTF8String],
               [[addr city] isEqualToString:@"Lima"]);

        NSDictionary *d = [p dictionaryWithValuesForKeys:
                           [NSArray arrayWithObjects:@"name", @"age", @"nickname", nil]];
        printf("dict count:%lu keys:%s\n", (unsigned long)[d count],
               joined([d allKeys]));
        printf("dict null:%d name:%s\n",
               [[d objectForKey:@"nickname"] isKindOfClass:[NSNull class]],
               [[d objectForKey:@"name"] UTF8String]);

        [p setValuesForKeysWithDictionary:
         [NSDictionary dictionaryWithObjectsAndKeys:
          @"cy", @"name", [NSNumber numberWithInteger:33], @"age", nil]];
        printf("bulk name:%s age:%ld\n", [[p name] UTF8String], (long)[p age]);

        NSArray *people = [NSArray arrayWithObjects:
                           mkperson(@"ana", 30), mkperson(@"bo", 40),
                           mkperson(@"ana", 50), nil];
        printf("op count:%ld sum:%ld\n",
               (long)[[people valueForKeyPath:@"@count"] longValue],
               (long)[[people valueForKeyPath:@"@sum.age"] longValue]);
        printf("op max:%ld min:%ld avg:%.1f\n",
               (long)[[people valueForKeyPath:@"@max.age"] longValue],
               (long)[[people valueForKeyPath:@"@min.age"] longValue],
               [[people valueForKeyPath:@"@avg.age"] doubleValue]);
        printf("op names:%s distinct:%s\n",
               joined([people valueForKey:@"name"]),
               joined([people valueForKeyPath:@"@distinctUnionOfObjects.name"]));

        Watcher *w = [[Watcher alloc] init];
        [p addObserver:w forKeyPath:@"age"
               options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
               context:NULL];
        [p setValue:[NSNumber numberWithInteger:34] forKey:@"age"];
        [p setAge:35];
        printf("kvo fires:%d old:%ld new:%ld kind:%lu\n", [w fires],
               (long)[[w lastOld] longValue], (long)[[w lastNew] longValue],
               (unsigned long)[w lastKind]);
        [p removeObserver:w forKeyPath:@"age"];
        [p setAge:36];
        printf("kvo afterremove fires:%d age:%ld\n", [w fires], (long)[p age]);

        Watcher *w2 = [[Watcher alloc] init];
        [p addObserver:w2 forKeyPath:@"address.city"
               options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
               context:NULL];
        [addr setCity:@"Cusco"];
        printf("kvo nested fires:%d old:%s new:%s\n", [w2 fires],
               [[[w2 lastOld] description] UTF8String],
               [[[w2 lastNew] description] UTF8String]);
        [p removeObserver:w2 forKeyPath:@"address.city"];

        int undef = 0; const char *uname = "none";
        @try { (void)[p valueForKey:@"noSuchKey"]; }
        @catch (NSException *ex) { undef = 1; uname = [[ex name] UTF8String]; }
        printf("undefined caught:%d name:%s\n", undef, uname);

        int setundef = 0;
        @try { [p setValue:@"x" forKey:@"noSuchKey"]; }
        @catch (NSException *ex) { setundef = 1; }
        printf("setundefined caught:%d\n", setundef);

        int nilscalar = 0;
        @try { [p setValue:nil forKey:@"age"]; }
        @catch (NSException *ex) { nilscalar = 1; }
        printf("nilscalar caught:%d age:%ld\n", nilscalar, (long)[p age]);

        [w release];
        [w2 release];
    }
    return 0;
}
EOF

cat > "$SRC/t24_predicate.m" <<'EOF'
// t24_predicate.m
// Probes NSPredicate (format parsing, comparison, compound AND/OR, BEGINSWITH,
// BEGINSWITH[c], IN, %K/%@ substitution, $variable substitution, direct
// evaluateWithObject:) and NSSortDescriptor (single key, two-key tie-break,
// custom selector). These sit on top of KVC, the predicate parser and the
// NSExpression machinery -- a large surface that Darling reimplements, and one
// whose error paths (unknown key, unbound variable, malformed format) are the
// most likely places to diverge from Foundation.

#import <Foundation/Foundation.h>
#include <stdio.h>

@interface T24Item : NSObject
@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSString *team;
@property (nonatomic, assign) NSInteger score;
@end

@implementation T24Item
@synthesize name, team, score;
- (void)dealloc {
    [name release];
    [team release];
    [super dealloc];
}
@end

static T24Item *T24Make(NSString *n, NSString *t, NSInteger s) {
    T24Item *i = [[[T24Item alloc] init] autorelease];
    i.name = n;
    i.team = t;
    i.score = s;
    return i;
}

static const char *T24Names(NSArray *items) {
    NSArray *names = [items valueForKey:@"name"];
    return [[names componentsJoinedByString:@","] UTF8String];
}

int main(void) {
    @autoreleasepool {
        NSArray *items = [NSArray arrayWithObjects:
            T24Make(@"alpha",   @"red",   10),
            T24Make(@"beta",    @"blue",  25),
            T24Make(@"alfredo", @"red",    5),
            T24Make(@"gamma",   @"green", 40),
            T24Make(@"alpine",  @"blue",  26),
            T24Make(@"delta",   @"green", 15),
            nil];
        printf("total:%lu\n", (unsigned long)[items count]);

        NSPredicate *pGt = [NSPredicate predicateWithFormat:@"score > 20"];
        NSArray *rGt = [items filteredArrayUsingPredicate:pGt];
        printf("gt20:%lu names:%s\n", (unsigned long)[rGt count], T24Names(rGt));

        NSPredicate *pAnd = [NSPredicate predicateWithFormat:@"score > 10 AND team == 'blue'"];
        NSArray *rAnd = [items filteredArrayUsingPredicate:pAnd];
        printf("and:%lu names:%s\n", (unsigned long)[rAnd count], T24Names(rAnd));

        NSPredicate *pOr = [NSPredicate predicateWithFormat:@"team == 'red' OR score >= 40"];
        NSArray *rOr = [items filteredArrayUsingPredicate:pOr];
        printf("or:%lu names:%s\n", (unsigned long)[rOr count], T24Names(rOr));

        NSPredicate *pBw = [NSPredicate predicateWithFormat:@"name BEGINSWITH 'al'"];
        NSArray *rBw = [items filteredArrayUsingPredicate:pBw];
        printf("beginswith:%lu names:%s\n", (unsigned long)[rBw count], T24Names(rBw));

        NSPredicate *pBwc = [NSPredicate predicateWithFormat:@"name BEGINSWITH[c] 'AL'"];
        printf("beginswith_c:%lu\n", (unsigned long)[[items filteredArrayUsingPredicate:pBwc] count]);

        NSPredicate *pIn = [NSPredicate predicateWithFormat:@"team IN %@",
                            [NSArray arrayWithObjects:@"red", @"green", nil]];
        NSArray *rIn = [items filteredArrayUsingPredicate:pIn];
        printf("in_team:%lu names:%s\n", (unsigned long)[rIn count], T24Names(rIn));

        NSPredicate *pKey = [NSPredicate predicateWithFormat:@"%K == %@", @"team", @"red"];
        printf("kvc_fmt:%lu\n", (unsigned long)[[items filteredArrayUsingPredicate:pKey] count]);

        NSPredicate *pNone = [NSPredicate predicateWithFormat:@"name BEGINSWITH 'zz'"];
        printf("nomatch:%lu\n", (unsigned long)[[items filteredArrayUsingPredicate:pNone] count]);

        T24Item *one = [items objectAtIndex:3];
        int evTrue = [pGt evaluateWithObject:one] ? 1 : 0;
        int evFalse = [pAnd evaluateWithObject:one] ? 1 : 0;
        printf("eval_true:%d eval_false:%d\n", evTrue, evFalse);

        NSPredicate *pTmpl = [NSPredicate predicateWithFormat:@"score >= $MIN AND team == $TEAM"];
        NSDictionary *subs = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithInteger:15], @"MIN",
                              @"green", @"TEAM", nil];
        NSPredicate *pSub = [pTmpl predicateWithSubstitutionVariables:subs];
        NSArray *rSub = [items filteredArrayUsingPredicate:pSub];
        printf("subst:%lu names:%s\n", (unsigned long)[rSub count], T24Names(rSub));

        NSSortDescriptor *byScore = [[[NSSortDescriptor alloc] initWithKey:@"score" ascending:YES] autorelease];
        NSArray *s1 = [items sortedArrayUsingDescriptors:[NSArray arrayWithObject:byScore]];
        printf("sort1:%s\n", T24Names(s1));

        NSSortDescriptor *byTeam = [[[NSSortDescriptor alloc] initWithKey:@"team" ascending:YES] autorelease];
        NSSortDescriptor *byScoreDesc = [[[NSSortDescriptor alloc] initWithKey:@"score" ascending:NO] autorelease];
        NSArray *s2 = [items sortedArrayUsingDescriptors:[NSArray arrayWithObjects:byTeam, byScoreDesc, nil]];
        printf("sort2:%s\n", T24Names(s2));

        NSSortDescriptor *byNameCI = [[[NSSortDescriptor alloc] initWithKey:@"name"
                                                                 ascending:NO
                                                                  selector:@selector(caseInsensitiveCompare:)] autorelease];
        NSArray *s3 = [items sortedArrayUsingDescriptors:[NSArray arrayWithObject:byNameCI]];
        printf("sort3:%s\n", T24Names(s3));

        int caughtKey = 0, keyNameMatch = 0;
        @try {
            NSPredicate *pBad = [NSPredicate predicateWithFormat:@"bogusKey == 5"];
            NSArray *r = [items filteredArrayUsingPredicate:pBad];
            printf("unexpected_key_ok:%lu\n", (unsigned long)[r count]);
        } @catch (NSException *e) {
            caughtKey = 1;
            keyNameMatch = [[e name] isEqualToString:@"NSUnknownKeyException"] ? 1 : 0;
        }
        printf("unknownkey_caught:%d name_match:%d\n", caughtKey, keyNameMatch);

        int caughtVar = 0;
        @try {
            NSPredicate *pUnbound = [NSPredicate predicateWithFormat:@"score > $LIMIT"];
            BOOL v = [pUnbound evaluateWithObject:one];
            printf("unexpected_unbound_ok:%d\n", v ? 1 : 0);
        } @catch (NSException *e) {
            caughtVar = 1;
        }
        printf("unbound_caught:%d\n", caughtVar);

        int caughtParse = 0;
        @try {
            NSPredicate *pMalformed = [NSPredicate predicateWithFormat:@"name BEGINSWITH"];
            printf("unexpected_parse_ok:%d\n", pMalformed != nil ? 1 : 0);
        } @catch (NSException *e) {
            caughtParse = 1;
        }
        printf("parse_caught:%d\n", caughtParse);
    }
    return 0;
}
EOF

cat > "$SRC/t25_notify.m" <<'EOF'
/* NSNotificationCenter: synchronous delivery to a target/selector observer and
   to a block observer, userInfo transport, name and sender filtering, duplicate
   registration, and observer removal.  The notification centre is the backbone
   of Foundation/AppKit event plumbing, and Darling reimplements it in its own
   Foundation, so a missed, duplicated or wrongly filtered delivery here breaks
   almost every real application. */
#import <Foundation/Foundation.h>
#include <stdio.h>

@interface CorpusObserver : NSObject {
@public
    int aHits, bHits;
    int lastUICount, lastUINil, lastK1, lastK2, lastName, lastObjNil;
}
- (void)gotA:(NSNotification *)n;
- (void)gotB:(NSNotification *)n;
@end

@implementation CorpusObserver
- (void)gotA:(NSNotification *)n {
    NSDictionary *ui = [n userInfo];
    aHits++;
    lastUICount = (int)[ui count];
    lastUINil   = (ui == nil);
    lastK1      = [[ui objectForKey:@"k1"] isEqualToString:@"v1"];
    lastK2      = ([[ui objectForKey:@"k2"] intValue] == 7);
    lastName    = [[n name] isEqualToString:@"CorpusNoteA"];
    lastObjNil  = ([n object] == nil);
}
- (void)gotB:(NSNotification *)n { (void)n; bHits++; }
@end

int main(void){
    @autoreleasepool {
        NSString *kA = @"CorpusNoteA";
        NSString *kB = @"CorpusNoteB";
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        CorpusObserver *obs = [[CorpusObserver alloc] init];
        NSDictionary *ui = @{@"k1": @"v1", @"k2": @7};
        NSObject *sender = [[NSObject alloc] init];
        NSObject *other  = [[NSObject alloc] init];
        __block int blkA = 0, blkUI = 0, blkName = 0, filt = 0;

        [nc addObserver:obs selector:@selector(gotA:) name:kA object:nil];
        [nc addObserver:obs selector:@selector(gotB:) name:kB object:nil];
        id tok = [nc addObserverForName:kA object:nil queue:nil
                             usingBlock:^(NSNotification *n){
            blkA++;
            blkUI = (int)[[n userInfo] count];
            blkName = [[n name] isEqualToString:kA];
        }];

        [nc postNotificationName:kA object:nil userInfo:ui];
        printf("p1 sel:%d blk:%d other:%d\n", obs->aHits, blkA, obs->bHits);
        printf("p1 uicount:%d k1:%d k2:%d\n", obs->lastUICount, obs->lastK1, obs->lastK2);
        printf("p1 name:%d objnil:%d blkname:%d blkui:%d\n",
               obs->lastName, obs->lastObjNil, blkName, blkUI);

        /* a different name must not reach the A observers */
        [nc postNotificationName:kB object:nil userInfo:nil];
        printf("p2 sel:%d blk:%d other:%d\n", obs->aHits, blkA, obs->bHits);

        /* posting a name nobody observes is legal and fires nothing */
        [nc postNotificationName:@"CorpusNoteUnobserved" object:nil userInfo:ui];
        printf("p3 sel:%d blk:%d other:%d\n", obs->aHits, blkA, obs->bHits);

        /* sender filtering: this block only wants notifications from `sender` */
        id tok2 = [nc addObserverForName:kA object:sender queue:nil
                              usingBlock:^(NSNotification *n){
            filt += ([n object] == sender);
        }];
        [nc postNotificationName:kA object:other userInfo:nil];
        printf("p4 filt:%d sel:%d blk:%d\n", filt, obs->aHits, blkA);
        [nc postNotificationName:kA object:sender userInfo:nil];
        printf("p5 filt:%d sel:%d uinil:%d\n", filt, obs->aHits, obs->lastUINil);

        /* removing one registration must leave the others intact */
        [nc removeObserver:obs name:kA object:nil];
        [nc postNotificationName:kA object:nil userInfo:ui];
        printf("p6 sel:%d blk:%d filt:%d\n", obs->aHits, blkA, filt);
        [nc removeObserver:tok];
        [nc removeObserver:tok2];
        [nc postNotificationName:kA object:sender userInfo:ui];
        printf("p7 sel:%d blk:%d filt:%d\n", obs->aHits, blkA, filt);

        /* the kB registration survived the targeted removal above */
        [nc postNotificationName:kB object:nil userInfo:nil];
        printf("p8 other:%d\n", obs->bHits);
        [nc removeObserver:obs];
        [nc postNotificationName:kB object:nil userInfo:nil];
        printf("p9 other:%d\n", obs->bHits);

        /* the centre does not de-duplicate: two identical registrations
           deliver twice; also exercise postNotification: with a prebuilt note */
        CorpusObserver *dup = [[CorpusObserver alloc] init];
        [nc addObserver:dup selector:@selector(gotA:) name:kA object:nil];
        [nc addObserver:dup selector:@selector(gotA:) name:kA object:nil];
        NSNotification *note = [NSNotification notificationWithName:kA object:nil userInfo:ui];
        printf("note name:%d uicount:%lu\n", [[note name] isEqualToString:kA],
               (unsigned long)[[note userInfo] count]);
        [nc postNotification:note];
        printf("dup hits:%d k1:%d\n", dup->aHits, dup->lastK1);
        [nc removeObserver:dup];
        [nc postNotification:note];
        printf("dup after-remove:%d\n", dup->aHits);

        [dup release];
        [obs release];
        [sender release];
        [other release];
    }
    return 0;
}
EOF

cat > "$SRC/t26_operation.m" <<'EOF'
// t26_operation.m
// Probes NSOperationQueue / NSBlockOperation: serialised execution with
// maxConcurrentOperationCount == 1, explicit addDependency: ordering,
// waitUntilAllOperationsAreFinished, completion blocks, multiple execution
// blocks, and the cancellation path (cancel before the block ever runs).
// This matters because Darling reimplements the NSOperation state machine on
// top of its own libdispatch port; readiness gating by dependencies and the
// cancelled -> finished transition are exactly where it tends to diverge.
// Ordering is forced by dependencies, so every printed value is deterministic.

#import <Foundation/Foundation.h>
#include <stdio.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSLock *lock = [[NSLock alloc] init];
        NSMutableArray *order = [[NSMutableArray alloc] init];
        __block int ranD = 0;
        __block int ranS = 0;
        __block int multi = 0;

        NSOperationQueue *q = [[NSOperationQueue alloc] init];
        [q setMaxConcurrentOperationCount:1];
        [q setName:@"corpus.queue"];
        printf("queue:%d max:%ld qname:%d\n",
               (q != nil),
               (long)[q maxConcurrentOperationCount],
               (int)[[q name] isEqualToString:@"corpus.queue"]);

        NSBlockOperation *opA = [NSBlockOperation blockOperationWithBlock:^{
            [lock lock]; [order addObject:@"A"]; [lock unlock];
        }];
        [opA setName:@"A"];
        NSBlockOperation *opB = [NSBlockOperation blockOperationWithBlock:^{
            [lock lock]; [order addObject:@"B"]; [lock unlock];
        }];
        NSBlockOperation *opC = [NSBlockOperation blockOperationWithBlock:^{
            [lock lock]; [order addObject:@"C"]; [lock unlock];
        }];
        NSBlockOperation *opD = [NSBlockOperation blockOperationWithBlock:^{
            ranD = 1;
        }];

        [opB addDependency:opA];
        [opC addDependency:opB];
        [opB setQueuePriority:NSOperationQueuePriorityHigh];

        printf("depsB:%lu depsC:%lu readyA:%d readyC:%d\n",
               (unsigned long)[[opB dependencies] count],
               (unsigned long)[[opC dependencies] count],
               (int)[opA isReady], (int)[opC isReady]);
        printf("prio:%ld oname:%d\n",
               (long)[opB queuePriority],
               (int)[[opA name] isEqualToString:@"A"]);

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [opC setCompletionBlock:^{ dispatch_semaphore_signal(sem); }];

        /* error/edge path: cancel before the operation is ever scheduled */
        [opD cancel];
        printf("dpre_can:%d dpre_fin:%d\n", (int)[opD isCancelled], (int)[opD isFinished]);

        /* added out of order on purpose: dependencies must reorder them */
        [q addOperations:[NSArray arrayWithObjects:opC, opB, opA, opD, nil] waitUntilFinished:NO];
        [q waitUntilAllOperationsAreFinished];

        long crc = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC));
        printf("completion:%d\n", (crc == 0));

        NSString *joined = [order componentsJoinedByString:@","];
        printf("order:%s match:%d n:%lu\n",
               [joined UTF8String],
               (int)[joined isEqualToString:@"A,B,C"],
               (unsigned long)[order count]);
        printf("finA:%d finB:%d finC:%d\n",
               (int)[opA isFinished], (int)[opB isFinished], (int)[opC isFinished]);
        printf("canA:%d canB:%d canC:%d\n",
               (int)[opA isCancelled], (int)[opB isCancelled], (int)[opC isCancelled]);
        printf("dcan:%d dfin:%d dran:%d dexec:%d\n",
               (int)[opD isCancelled], (int)[opD isFinished], ranD, (int)[opD isExecuting]);
        printf("qcount:%lu readyC2:%d execC:%d\n",
               (unsigned long)[q operationCount], (int)[opC isReady], (int)[opC isExecuting]);

        /* one operation carrying three execution blocks */
        NSBlockOperation *opM = [NSBlockOperation blockOperationWithBlock:^{
            [lock lock]; multi++; [lock unlock];
        }];
        [opM addExecutionBlock:^{ [lock lock]; multi++; [lock unlock]; }];
        [opM addExecutionBlock:^{ [lock lock]; multi++; [lock unlock]; }];
        [q addOperation:opM];
        [q waitUntilAllOperationsAreFinished];
        printf("multi:%d blocks:%lu mfin:%d mcan:%d\n",
               multi, (unsigned long)[[opM executionBlocks] count],
               (int)[opM isFinished], (int)[opM isCancelled]);

        /* error path: cancelAllOperations on a suspended queue, nothing may run */
        NSOperationQueue *q2 = [[NSOperationQueue alloc] init];
        [q2 setMaxConcurrentOperationCount:1];
        [q2 setSuspended:YES];
        NSBlockOperation *opS = [NSBlockOperation blockOperationWithBlock:^{ ranS = 1; }];
        [q2 addOperation:opS];
        printf("susp:%d scount:%lu sfin:%d\n",
               (int)[q2 isSuspended], (unsigned long)[q2 operationCount], (int)[opS isFinished]);
        [q2 cancelAllOperations];
        [q2 setSuspended:NO];
        [q2 waitUntilAllOperationsAreFinished];
        printf("scan:%d sfin2:%d sran:%d scount2:%lu\n",
               (int)[opS isCancelled], (int)[opS isFinished], ranS,
               (unsigned long)[q2 operationCount]);

        /* dependency bookkeeping without ever scheduling the operations */
        NSBlockOperation *opX = [NSBlockOperation blockOperationWithBlock:^{ }];
        NSBlockOperation *opY = [NSBlockOperation blockOperationWithBlock:^{ }];
        [opY addDependency:opX];
        unsigned long added = (unsigned long)[[opY dependencies] count];
        [opY removeDependency:opX];
        printf("depadd:%lu deprm:%lu\n", added, (unsigned long)[[opY dependencies] count]);

        /* edge: cancel an operation that already finished */
        [opA cancel];
        printf("postcan:%d postfin:%d\n", (int)[opA isCancelled], (int)[opA isFinished]);

        /* edge: waiting on an already-drained queue must return immediately */
        [q waitUntilAllOperationsAreFinished];
        printf("empty:%lu ops:%lu\n",
               (unsigned long)[q operationCount], (unsigned long)[[q operations] count]);

        dispatch_release(sem);
        [q2 release];
        [q release];
        [order release];
        [lock release];
    }
    return 0;
}
EOF

cat > "$SRC/t27_xml.m" <<'EOF'
/* NSXMLParser: SAX-style parse of an in-memory document, attribute lookup,
   character accumulation, and the malformed-document error path. Darling
   backs NSXMLParser with libxml2, so callback ordering, attribute
   dictionaries and parse-failure reporting can all diverge from Apple's. */
#import <Foundation/Foundation.h>
#include <stdio.h>

@interface CorpusXMLDelegate : NSObject <NSXMLParserDelegate> {
@public
    NSUInteger startCount;
    NSUInteger endCount;
    NSUInteger firstItemAttrCount;
    NSMutableString *text;
    NSMutableArray *names;
    NSString *firstItemID;
    int sawNoMissingAttr;
    int sawError;
    int sawDocStart;
    int sawDocEnd;
}
@end

@implementation CorpusXMLDelegate
- (id)init {
    self = [super init];
    if (self) {
        text = [[NSMutableString alloc] init];
        names = [[NSMutableArray alloc] init];
    }
    return self;
}
- (void)dealloc {
    [text release];
    [names release];
    [firstItemID release];
    [super dealloc];
}
- (void)parserDidStartDocument:(NSXMLParser *)p { sawDocStart = 1; }
- (void)parserDidEndDocument:(NSXMLParser *)p { sawDocEnd = 1; }
- (void)parser:(NSXMLParser *)p didStartElement:(NSString *)el
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn
    attributes:(NSDictionary *)attrs {
    startCount++;
    [names addObject:el];
    if ([el isEqualToString:@"item"] && firstItemID == nil) {
        firstItemID = [[attrs objectForKey:@"id"] copy];
        firstItemAttrCount = [attrs count];
        if ([attrs objectForKey:@"missing"] == nil) sawNoMissingAttr = 1;
    }
}
- (void)parser:(NSXMLParser *)p didEndElement:(NSString *)el
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn { endCount++; }
- (void)parser:(NSXMLParser *)p foundCharacters:(NSString *)s { [text appendString:s]; }
- (void)parser:(NSXMLParser *)p parseErrorOccurred:(NSError *)e { sawError = 1; }
@end

int main(void){
    @autoreleasepool {
        NSString *doc = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                        @"<catalog kind=\"books\">"
                        @"<item id=\"a1\" qty=\"3\">Alpha</item>"
                        @"<item id=\"b2\" qty=\"7\">Beta</item>"
                        @"<note>ok</note></catalog>";
        NSData *data = [doc dataUsingEncoding:NSUTF8StringEncoding];
        printf("bytes:%lu\n", (unsigned long)[data length]);

        CorpusXMLDelegate *d = [[CorpusXMLDelegate alloc] init];
        NSXMLParser *p = [[NSXMLParser alloc] initWithData:data];
        [p setDelegate:d];
        int ok = [p parse] ? 1 : 0;
        printf("parse:%d err:%d\n", ok, [p parserError] != nil);
        printf("docstart:%d docend:%d\n", d->sawDocStart, d->sawDocEnd);
        printf("start:%lu end:%lu\n", (unsigned long)d->startCount,
               (unsigned long)d->endCount);
        printf("root:%s\n", [[d->names objectAtIndex:0] UTF8String]);
        printf("names:%s\n", [[d->names componentsJoinedByString:@","] UTF8String]);
        printf("id:%s attrs:%lu nomissing:%d\n", [d->firstItemID UTF8String],
               (unsigned long)d->firstItemAttrCount, d->sawNoMissingAttr);
        printf("text:%s len:%lu\n", [d->text UTF8String],
               (unsigned long)[d->text length]);
        printf("textmatch:%d\n", [d->text isEqualToString:@"AlphaBetaok"]);
        printf("errcb:%d\n", d->sawError);
        [p release];
        [d release];

        NSString *badDoc = @"<root><a>unclosed</root>";
        CorpusXMLDelegate *d2 = [[CorpusXMLDelegate alloc] init];
        NSXMLParser *p2 = [[NSXMLParser alloc]
            initWithData:[badDoc dataUsingEncoding:NSUTF8StringEncoding]];
        [p2 setDelegate:d2];
        int ok2 = [p2 parse] ? 1 : 0;
        NSError *e2 = [p2 parserError];
        printf("badparse:%d haserr:%d errcb:%d\n", ok2, e2 != nil, d2->sawError);
        printf("baddomain:%d\n", [[e2 domain] isEqualToString:NSXMLParserErrorDomain]);
        printf("badstarts:%lu badends:%lu\n", (unsigned long)d2->startCount,
               (unsigned long)d2->endCount);
        [p2 release];
        [d2 release];

        NSXMLParser *p3 = [[NSXMLParser alloc] initWithData:[NSData data]];
        int ok3 = [p3 parse] ? 1 : 0;
        printf("emptyparse:%d haserr:%d\n", ok3, [p3 parserError] != nil);
        [p3 release];
    }
    return 0;
}
EOF

cat > "$SRC/t28_valuebox.m" <<'EOF'
/* NSValue struct boxing: geometry structs, arbitrary bytes, and @encode strings.
   Matters because NSValue is the bridge between Objective-C objects and raw C
   structs -- Darling must reproduce Apple's type-encoding strings byte for byte
   and byte-compare buffers in isEqualToValue:, or NSArray lookups silently fail. */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>

struct TS { double d; int a; int b; };

int main(void){
    @autoreleasepool {
        NSValue *rv = [NSValue valueWithRange:NSMakeRange(7, 12)];
        NSRange r = [rv rangeValue];
        printf("range_loc:%lu range_len:%lu eq:%d\n", (unsigned long)r.location,
               (unsigned long)r.length, NSEqualRanges(r, NSMakeRange(7, 12)));
        printf("range_eqsame:%d range_eqdiff:%d\n",
               [rv isEqualToValue:[NSValue valueWithRange:NSMakeRange(7, 12)]],
               [rv isEqualToValue:[NSValue valueWithRange:NSMakeRange(7, 13)]]);

        NSValue *pv = [NSValue valueWithPoint:NSMakePoint(3.5, -2.25)];
        NSPoint p = [pv pointValue];
        printf("point_x:%.2f point_y:%.2f eq:%d\n", p.x, p.y,
               NSEqualPoints(p, NSMakePoint(3.5, -2.25)));
        NSValue *sv = [NSValue valueWithSize:NSMakeSize(12.5, 7.25)];
        NSSize sz = [sv sizeValue];
        printf("size_w:%.2f size_h:%.2f eq:%d\n", sz.width, sz.height,
               NSEqualSizes(sz, NSMakeSize(12.5, 7.25)));
        NSValue *qv = [NSValue valueWithRect:NSMakeRect(1.0, 2.0, 30.0, 40.0)];
        NSRect q = [qv rectValue];
        printf("rect_x:%.2f rect_y:%.2f rect_w:%.2f rect_h:%.2f eq:%d\n",
               q.origin.x, q.origin.y, q.size.width, q.size.height,
               NSEqualRects(q, NSMakeRect(1.0, 2.0, 30.0, 40.0)));

        printf("type_range:%s type_point:%s\n", [rv objCType], [pv objCType]);
        printf("type_size:%s type_rect:%s\n", [sv objCType], [qv objCType]);
        printf("cross_eq:%d nonvalue_eq:%d\n", [rv isEqualToValue:pv],
               [rv isEqual:@"not a value"]);

        struct TS in; memset(&in, 0, sizeof(in));
        in.d = 6.25; in.a = -3; in.b = 99;
        NSValue *bv = [NSValue valueWithBytes:&in objCType:@encode(struct TS)];
        struct TS out; memset(&out, 0, sizeof(out));
        [bv getValue:&out];
        printf("struct_d:%.2f struct_a:%d struct_b:%d\n", out.d, out.a, out.b);
        printf("struct_type:%s enc_match:%d\n", [bv objCType],
               strcmp([bv objCType], @encode(struct TS)) == 0);
        struct TS same = in, diff = in; diff.b = 100;
        printf("struct_eqsame:%d struct_eqdiff:%d\n",
               [bv isEqualToValue:[NSValue valueWithBytes:&same
                                   objCType:@encode(struct TS)]],
               [bv isEqualToValue:[NSValue valueWithBytes:&diff
                                   objCType:@encode(struct TS)]]);

        int anchor = 5;
        NSValue *ptr = [NSValue valueWithPointer:&anchor];
        printf("ptr_roundtrip:%d ptr_type:%s\n", [ptr pointerValue] == &anchor,
               [ptr objCType]);

        NSArray *arr = @[rv, pv, sv, qv];
        NSUInteger found = [arr indexOfObject:[NSValue valueWithSize:NSMakeSize(12.5, 7.25)]];
        NSUInteger gone = [arr indexOfObject:[NSValue valueWithRange:NSMakeRange(0, 1)]];
        printf("array_count:%lu found:%lu missing:%d\n", (unsigned long)[arr count],
               (unsigned long)found, gone == NSNotFound);
        printf("contains:%d identical:%lu\n",
               [arr containsObject:[NSValue valueWithRange:NSMakeRange(7, 12)]],
               (unsigned long)[arr indexOfObjectIdenticalTo:qv]);

        NSRange zr = [[NSValue valueWithRange:NSMakeRange(0, 0)] rangeValue];
        printf("nullptr:%d zero_loc:%lu zero_len:%lu\n",
               [[NSValue valueWithPointer:NULL] pointerValue] == NULL,
               (unsigned long)zr.location, (unsigned long)zr.length);
    }
    return 0;
}
EOF

cat > "$SRC/t29_cache.m" <<'EOF'
/* NSCache: storage, lookup, cost accounting and limits.
   DETERMINISM NOTE: NSCache's eviction policy is documented as unspecified, so this
   case deliberately asserts nothing about what gets evicted under pressure -- an
   expectation there would be a defect in the test, not the implementation. What is
   specified, and therefore tested, is the storage/lookup contract and the limit
   accessors. */
#import <Foundation/Foundation.h>
#include <stdio.h>

static const char *S(NSString *s) { return s ? [s UTF8String] : "(nil)"; }

int main(void){
    @autoreleasepool {
        NSCache *c = [[NSCache alloc] init];
        [c setName:@"corpus-cache"];
        printf("name:%s\n", S([c name]));

        [c setObject:@"alpha" forKey:@"k1"];
        [c setObject:@"beta"  forKey:@"k2" cost:10];
        printf("get1:%s get2:%s missing:%d\n",
               S([c objectForKey:@"k1"]), S([c objectForKey:@"k2"]),
               [c objectForKey:@"nope"] == nil);

        /* keys are matched with isEqual:, not by identity */
        NSMutableString *eq = [NSMutableString stringWithString:@"k"];
        [eq appendString:@"1"];
        printf("equalkey:%s\n", S([c objectForKey:eq]));

        [c removeObjectForKey:@"k1"];
        printf("removed1:%d kept2:%s\n",
               [c objectForKey:@"k1"] == nil, S([c objectForKey:@"k2"]));

        [c setCountLimit:5];
        [c setTotalCostLimit:1024];
        printf("countlimit:%lu costlimit:%lu\n",
               (unsigned long)[c countLimit], (unsigned long)[c totalCostLimit]);
        [c setEvictsObjectsWithDiscardedContent:NO];
        printf("evicts:%d\n", [c evictsObjectsWithDiscardedContent] ? 1 : 0);

        /* overwrite in place */
        [c setObject:@"beta2" forKey:@"k2"];
        printf("overwrite:%s\n", S([c objectForKey:@"k2"]));

        [c removeAllObjects];
        printf("cleared:%d %d\n",
               [c objectForKey:@"k1"] == nil, [c objectForKey:@"k2"] == nil);

        /* bulk insert past the count limit must not crash; what survives is
           unspecified and so is not printed */
        NSCache *c2 = [[NSCache alloc] init];
        [c2 setCountLimit:8];
        for (int i = 0; i < 200; i++)
            [c2 setObject:[NSString stringWithFormat:@"v%d", i]
                   forKey:[NSString stringWithFormat:@"bk%d", i] cost:1];
        printf("bulk_survived:1\n");
    }
    return 0;
}
EOF

cat > "$SRC/t30_scanner.m" <<'EOF'
/* NSScanner: the tokeniser behind a great deal of text handling. Fully
   deterministic -- no locale, no clock, no ordering. Deliberately uses the
   non-localized scanner: -localizedScannerWithString: would make output depend on
   the host's locale and produce divergences that say nothing about Darling. */
#import <Foundation/Foundation.h>
#include <stdio.h>

static const char *S(NSString *s) { return s ? [s UTF8String] : "(nil)"; }

int main(void){
    @autoreleasepool {
        NSScanner *s = [NSScanner scannerWithString:@"  42 -17 3.5 0x1f rest here"];
        int i = 0; double d = 0; unsigned u = 0; long long ll = 0;
        printf("int:%d val:%d loc:%lu\n", [s scanInt:&i], i,
               (unsigned long)[s scanLocation]);
        printf("neg:%d val:%d\n", [s scanInt:&i], i);
        printf("dbl:%d val:%.2f\n", [s scanDouble:&d], d);
        printf("hex:%d val:%u\n", [s scanHexInt:&u], u);
        NSString *word = nil;
        printf("upto:%d word:%s\n",
               [s scanUpToString:@"here" intoString:&word], S(word));
        /* NOTE: each scan is sequenced into a local before printing. C leaves the
           evaluation order of function arguments unspecified, so a printf taking
           both a scan and a query of the scanner's resulting state would print
           whichever the compiler happened to evaluate first. The differential
           comparison would still be sound -- both sides run the identical binary --
           but the labels would not mean what they say. */
        BOOL lit = [s scanString:@"here" intoString:NULL];
        BOOL atEnd = [s isAtEnd];
        printf("lit:%d atend_after:%d\n", lit, atEnd);

        /* failure must not advance the location */
        NSScanner *f = [NSScanner scannerWithString:@"abc"];
        NSUInteger before = [f scanLocation];
        BOOL failint = [f scanInt:&i];
        printf("failint:%d unmoved:%d\n", failint, (int)([f scanLocation] == before));

        /* character sets */
        NSScanner *cs = [NSScanner scannerWithString:@"aaabbbccc"];
        NSString *got = nil;
        BOOL okset = [cs scanCharactersFromSet:
                         [NSCharacterSet characterSetWithCharactersInString:@"a"]
                                    intoString:&got];
        printf("charset:%d got:%s\n", okset, S(got));
        BOOL okupto = [cs scanUpToCharactersFromSet:
                          [NSCharacterSet characterSetWithCharactersInString:@"c"]
                                         intoString:&got];
        printf("upto_set:%d got:%s\n", okupto, S(got));

        /* case sensitivity is off by default */
        NSScanner *ci = [NSScanner scannerWithString:@"HELLO"];
        BOOL defcs = [ci caseSensitive];
        printf("default_casesens:%d ciscan:%d\n",
               defcs, [ci scanString:@"hello" intoString:NULL]);
        NSScanner *cse = [NSScanner scannerWithString:@"HELLO"];
        [cse setCaseSensitive:YES];
        printf("cs_scan:%d\n", [cse scanString:@"hello" intoString:NULL]);

        /* charactersToBeSkipped */
        NSScanner *sk = [NSScanner scannerWithString:@"xxx7"];
        [sk setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@"x"]];
        printf("skipped:%d val:%d\n", [sk scanInt:&i], i);

        /* explicit repositioning */
        NSScanner *rp = [NSScanner scannerWithString:@"12345"];
        [rp setScanLocation:3];
        printf("reposition:%d val:%d\n", [rp scanInt:&i], i);

        NSScanner *big = [NSScanner scannerWithString:@"9223372036854775807"];
        printf("longlong:%d val:%lld\n", [big scanLongLong:&ll], ll);

        printf("string_roundtrip:%s\n", S([[NSScanner scannerWithString:@"abc"] string]));
    }
    return 0;
}
EOF

cat > "$SRC/t31_attrstr.m" <<'EOF'
/* NSAttributedString / NSMutableAttributedString.
   Uses plain string attribute keys rather than the NSFontAttributeName family: those
   live in AppKit, and this case is about Foundation's attribute-run bookkeeping, not
   about text rendering. Attribute runs are where implementations usually diverge --
   splitting, merging and coalescing ranges after an edit. */
#import <Foundation/Foundation.h>
#include <stdio.h>

static const char *S(NSString *s) { return s ? [s UTF8String] : "(nil)"; }

int main(void){
    @autoreleasepool {
        NSAttributedString *a =
            [[NSAttributedString alloc] initWithString:@"Hello world"
                                            attributes:@{@"k1": @"v1"}];
        printf("len:%lu str:%s\n", (unsigned long)[a length], S([a string]));

        NSRange eff = NSMakeRange(0, 0);
        NSString *v = [a attribute:@"k1" atIndex:0 effectiveRange:&eff];
        printf("attr:%s eff_loc:%lu eff_len:%lu\n", S(v),
               (unsigned long)eff.location, (unsigned long)eff.length);
        printf("absent:%d\n", [a attribute:@"nope" atIndex:0 effectiveRange:NULL] == nil);

        NSDictionary *all = [a attributesAtIndex:3 effectiveRange:&eff];
        printf("dict_count:%lu dict_v:%s\n", (unsigned long)[all count],
               S([all objectForKey:@"k1"]));

        NSAttributedString *sub =
            [a attributedSubstringFromRange:NSMakeRange(6, 5)];
        printf("sub:%s sublen:%lu\n", S([sub string]), (unsigned long)[sub length]);

        printf("eq_same:%d eq_diff:%d\n",
               [a isEqualToAttributedString:
                   [[NSAttributedString alloc] initWithString:@"Hello world"
                                                   attributes:@{@"k1": @"v1"}]],
               [a isEqualToAttributedString:
                   [[NSAttributedString alloc] initWithString:@"Hello world"
                                                   attributes:@{@"k1": @"v2"}]]);

        /* mutation: this is where run bookkeeping gets interesting */
        NSMutableAttributedString *m =
            [[NSMutableAttributedString alloc] initWithString:@"abcdefghij"];
        [m addAttribute:@"k" value:@"A" range:NSMakeRange(0, 5)];
        [m addAttribute:@"k" value:@"B" range:NSMakeRange(5, 5)];
        [m attribute:@"k" atIndex:0 effectiveRange:&eff];
        printf("run0_len:%lu\n", (unsigned long)eff.length);
        [m attribute:@"k" atIndex:7 effectiveRange:&eff];
        printf("run1_loc:%lu run1_len:%lu\n",
               (unsigned long)eff.location, (unsigned long)eff.length);

        __block int runs = 0;
        [m enumerateAttribute:@"k" inRange:NSMakeRange(0, [m length])
                      options:0
                   usingBlock:^(id value, NSRange range, BOOL *stop) {
            runs++;
            printf("  run %d: %s loc:%lu len:%lu\n", runs, S(value),
                   (unsigned long)range.location, (unsigned long)range.length);
        }];
        printf("runs:%d\n", runs);

        [m removeAttribute:@"k" range:NSMakeRange(0, 5)];
        printf("afterremove:%d\n",
               [m attribute:@"k" atIndex:0 effectiveRange:NULL] == nil);

        [m replaceCharactersInRange:NSMakeRange(0, 3) withString:@"XY"];
        printf("replaced:%s len:%lu\n", S([m string]), (unsigned long)[m length]);

        [m insertAttributedString:
            [[NSAttributedString alloc] initWithString:@"##"] atIndex:0];
        printf("inserted:%s\n", S([m string]));

        [m deleteCharactersInRange:NSMakeRange(0, 2)];
        printf("deleted:%s\n", S([m string]));

        [m setAttributes:@{@"z": @"1"} range:NSMakeRange(0, [m length])];
        printf("setattrs:%s\n",
               S([m attribute:@"z" atIndex:0 effectiveRange:NULL]));

        [m appendAttributedString:
            [[NSAttributedString alloc] initWithString:@"!!"
                                            attributes:@{@"z": @"1"}]];
        printf("appended:%s finallen:%lu\n", S([m string]),
               (unsigned long)[m length]);
        /* Run boundaries after appending a string carrying identical attributes.
           macOS does NOT merge the appended run with the preceding one -- the
           effective range at index 0 stays at the pre-append length. (An earlier
           version of this comment asserted the opposite; ground truth says
           otherwise, and ground truth is what a translation layer must match.) */
        [m attribute:@"z" atIndex:0 effectiveRange:&eff];
        printf("coalesced_len:%lu\n", (unsigned long)eff.length);
    }
    return 0;
}
EOF

cat > "$SRC/t32_filehandle.m" <<'EOF'
/* NSFileHandle: positional file I/O.
   Writes its own input inside the run -- /private/var/tmp does not survive between
   invocations under Darling (FINDINGS.md F34), so nothing may be assumed to persist
   from an earlier test. */
#import <Foundation/Foundation.h>
#include <stdio.h>

static const char *S(NSString *s) { return s ? [s UTF8String] : "(nil)"; }
static NSString *asStr(NSData *d) {
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
}

int main(void){
    @autoreleasepool {
        NSString *path = @"/private/var/tmp/corpus-t32.txt";
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        BOOL made = [@"ABCDEFGHIJ" writeToFile:path atomically:YES
                                      encoding:NSUTF8StringEncoding error:NULL];
        printf("created:%d\n", made);

        NSFileHandle *r = [NSFileHandle fileHandleForReadingAtPath:path];
        printf("opened:%d\n", r != nil);
        printf("head:%s off:%llu\n", S(asStr([r readDataOfLength:4])),
               [r offsetInFile]);
        [r seekToFileOffset:6];
        printf("seek:%s off:%llu\n", S(asStr([r readDataOfLength:2])),
               [r offsetInFile]);
        [r seekToFileOffset:0];
        printf("all:%s\n", S(asStr([r readDataToEndOfFile])));
        unsigned long long end = [r seekToEndOfFile];
        printf("end:%llu\n", end);
        [r closeFile];

        NSFileHandle *w = [NSFileHandle fileHandleForWritingAtPath:path];
        [w seekToEndOfFile];
        [w writeData:[@"KLM" dataUsingEncoding:NSUTF8StringEncoding]];
        [w closeFile];
        printf("appended:%s\n",
               S([NSString stringWithContentsOfFile:path
                                           encoding:NSUTF8StringEncoding error:NULL]));

        NSFileHandle *t = [NSFileHandle fileHandleForWritingAtPath:path];
        [t truncateFileAtOffset:5];
        [t closeFile];
        printf("truncated:%s\n",
               S([NSString stringWithContentsOfFile:path
                                           encoding:NSUTF8StringEncoding error:NULL]));

        NSFileHandle *u = [NSFileHandle fileHandleForUpdatingAtPath:path];
        printf("updating:%d\n", u != nil);
        [u seekToFileOffset:1];
        [u writeData:[@"zz" dataUsingEncoding:NSUTF8StringEncoding]];
        [u closeFile];
        printf("updated:%s\n",
               S([NSString stringWithContentsOfFile:path
                                           encoding:NSUTF8StringEncoding error:NULL]));

        /* error paths */
        printf("missing_read:%d missing_write:%d\n",
               [NSFileHandle fileHandleForReadingAtPath:@"/private/var/tmp/corpus-t32-absent"] == nil,
               [NSFileHandle fileHandleForWritingAtPath:@"/private/var/tmp/corpus-t32-absent"] == nil);

        /* reading past EOF yields empty data, not an error */
        NSFileHandle *e = [NSFileHandle fileHandleForReadingAtPath:path];
        [e seekToEndOfFile];
        printf("pasteof_len:%lu\n", (unsigned long)[[e readDataToEndOfFile] length]);
        [e closeFile];

        /* URL-based opener and the null device */
        NSFileHandle *nu = [NSFileHandle fileHandleWithNullDevice];
        printf("nulldev:%d nulldev_read:%lu\n", nu != nil,
               (unsigned long)[[nu readDataToEndOfFile] length]);

        /* FINDINGS.md F64: -truncateFileAtOffset: must seek to the offset
           (SEEK_SET), not relative to the current position (SEEK_CUR). The block
           above cannot tell the two apart, because a freshly opened handle sits at
           position 0 where both give the same answer. Writing first moves the
           position, which separates them: from position 3, SEEK_SET 5 lands at 5
           and SEEK_CUR 5 lands at 8. Kept on its own file so it disturbs none of
           the assertions above. */
        NSString *p2 = @"/private/var/tmp/corpus-t32b.txt";
        [[NSFileManager defaultManager] removeItemAtPath:p2 error:NULL];
        [@"ABCDEFGHIJ" writeToFile:p2 atomically:YES
                          encoding:NSUTF8StringEncoding error:NULL];
        NSFileHandle *tw = [NSFileHandle fileHandleForWritingAtPath:p2];
        [tw writeData:[@"xyz" dataUsingEncoding:NSUTF8StringEncoding]];
        unsigned long long preOff = [tw offsetInFile];
        [tw truncateFileAtOffset:5];
        printf("pre_trunc_off:%llu post_trunc_off:%llu\n", preOff, [tw offsetInFile]);
        [tw closeFile];
        printf("trunc_len:%lu\n", (unsigned long)
               [[NSString stringWithContentsOfFile:p2
                                          encoding:NSUTF8StringEncoding
                                             error:NULL] length]);
        [[NSFileManager defaultManager] removeItemAtPath:p2 error:NULL];

        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        printf("cleaned:%d\n",
               ![[NSFileManager defaultManager] fileExistsAtPath:path]);
    }
    return 0;
}
EOF

cat > "$SRC/t33_thread.m" <<'EOF'
/* NSThread.
   DETERMINISM NOTE: nothing here prints a thread number, address, stack size or
   scheduling priority -- all of those legitimately differ between runs and between
   platforms, and printing them would manufacture divergences that mean nothing. What
   is deterministic, and therefore tested, is the threading *contract*: a detached
   thread runs, it is not the main thread, its name and thread dictionary are its
   own, and the process reports itself multithreaded afterwards.
   Synchronisation is by semaphore, so the case cannot flake under load. */
#import <Foundation/Foundation.h>
#include <stdio.h>

static dispatch_semaphore_t gSem;
static int gNotMain = -1, gNamed = -1, gDict = -1, gIsolated = -1;

@interface Worker : NSObject
+ (void) run: (id) arg;
@end

@implementation Worker
+ (void) run: (id) arg {
    @autoreleasepool {
        gNotMain = ([NSThread isMainThread] == NO);
        [[NSThread currentThread] setName:@"corpus-worker"];
        gNamed = [[[NSThread currentThread] name] isEqualToString:@"corpus-worker"];
        [[[NSThread currentThread] threadDictionary] setObject:@"v" forKey:@"tk"];
        gDict = ([[[NSThread currentThread] threadDictionary]
                     objectForKey:@"tk"] != nil);
        /* the main thread's dictionary must not have been touched */
        gIsolated = ([arg isEqualToString:@"payload"]);
        dispatch_semaphore_signal(gSem);
    }
}
@end

int main(void){
    /* Unbuffered: this case dies with SIGSEGV on arm64e (FINDINGS.md F58) and a
       signal death discards a block-buffered stdout (trap 23), so without this the
       crash reports "no output" regardless of how far it actually got. Costs nothing
       on the native side -- the bytes written are identical, only the flush timing
       differs. */
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        printf("main_is_main:%d\n", [NSThread isMainThread]);
        printf("multi_before:%d\n", [NSThread isMultiThreaded]);

        [[NSThread currentThread] setName:@"corpus-main"];
        printf("main_name:%s\n", [[[NSThread currentThread] name] UTF8String]);
        [[[NSThread currentThread] threadDictionary] setObject:@"mv" forKey:@"mk"];

        gSem = dispatch_semaphore_create(0);
        [NSThread detachNewThreadSelector:@selector(run:)
                                 toTarget:[Worker class]
                               withObject:@"payload"];
        dispatch_semaphore_wait(gSem, DISPATCH_TIME_FOREVER);

        printf("worker_notmain:%d worker_named:%d worker_dict:%d arg:%d\n",
               gNotMain, gNamed, gDict, gIsolated);
        printf("multi_after:%d\n", [NSThread isMultiThreaded]);
        printf("main_name_intact:%s main_dict_intact:%s\n",
               [[[NSThread currentThread] name] UTF8String],
               [[[[NSThread currentThread] threadDictionary]
                    objectForKey:@"mk"] UTF8String]);
        printf("main_dict_clean:%d\n",
               [[[NSThread currentThread] threadDictionary]
                   objectForKey:@"tk"] == nil);

        /* explicit NSThread object lifecycle */
        gNotMain = -1; gNamed = -1; gDict = -1; gIsolated = -1;
        NSThread *t = [[NSThread alloc] initWithTarget:[Worker class]
                                              selector:@selector(run:)
                                                object:@"payload"];
        printf("pre_exec:%d pre_fin:%d pre_cancel:%d\n",
               [t isExecuting], [t isFinished], [t isCancelled]);
        [t setName:@"explicit"];
        [t start];
        dispatch_semaphore_wait(gSem, DISPATCH_TIME_FOREVER);
        /* the semaphore fires inside -run:, so allow the thread to unwind */
        for (int i = 0; i < 200 && ![t isFinished]; i++)
            [NSThread sleepForTimeInterval:0.01];
        printf("post_fin:%d post_exec:%d ran:%d\n",
               [t isFinished], [t isExecuting], gNotMain);

        /* cancellation is cooperative: setting it must be observable */
        NSThread *c = [[NSThread alloc] initWithTarget:[Worker class]
                                              selector:@selector(run:)
                                                object:@"payload"];
        [c cancel];
        printf("cancelled_flag:%d\n", [c isCancelled]);

        /* sleepForTimeInterval must actually block */
        NSDate *s = [NSDate date];
        [NSThread sleepForTimeInterval:0.05];
        printf("slept:%d\n", [[NSDate date] timeIntervalSinceDate:s] >= 0.04);

        printf("callstack_nonempty:%d\n",
               [[NSThread callStackReturnAddresses] count] > 0);
    }
    return 0;
}
EOF

cat > "$SRC/t34_progress.m" <<'EOF'
/* NSProgress: unit accounting, parent/child composition, cancel and pause.
   DETERMINISM NOTE: -localizedDescription and -localizedAdditionalDescription are
   deliberately not printed. They are locale-formatted, so they would diverge for
   reasons that say nothing about the implementation. Fractions are printed to four
   places, which is exact for the values used here. */
#import <Foundation/Foundation.h>
#include <stdio.h>

int main(void){
    @autoreleasepool {
        NSProgress *p = [NSProgress progressWithTotalUnitCount:10];
        printf("total:%lld completed:%lld frac:%.4f\n",
               [p totalUnitCount], [p completedUnitCount], [p fractionCompleted]);

        [p setCompletedUnitCount:5];
        printf("half:%.4f\n", [p fractionCompleted]);
        [p setCompletedUnitCount:10];
        printf("full:%.4f finished:%d\n", [p fractionCompleted], [p isFinished]);

        /* indeterminate when the total is unknown */
        NSProgress *ind = [NSProgress progressWithTotalUnitCount:-1];
        printf("indeterminate:%d\n", [ind isIndeterminate]);

        /* cancellation and pause are sticky flags */
        NSProgress *c = [NSProgress progressWithTotalUnitCount:4];
        printf("pre_cancel:%d pre_pause:%d cancellable:%d pausable:%d\n",
               [c isCancelled], [c isPaused],
               [c isCancellable], [c isPausable]);
        [c cancel];
        printf("post_cancel:%d\n", [c isCancelled]);
        NSProgress *pz = [NSProgress progressWithTotalUnitCount:4];
        [pz pause];
        printf("paused:%d\n", [pz isPaused]);
        [pz resume];
        printf("resumed:%d\n", [pz isPaused]);

        /* parent/child composition via the current-progress mechanism */
        NSProgress *parent = [NSProgress progressWithTotalUnitCount:2];
        [parent becomeCurrentWithPendingUnitCount:1];
        NSProgress *child = [NSProgress progressWithTotalUnitCount:100];
        [parent resignCurrent];
        [child setCompletedUnitCount:50];
        printf("parent_frac:%.4f child_frac:%.4f\n",
               [parent fractionCompleted], [child fractionCompleted]);
        [child setCompletedUnitCount:100];
        printf("parent_after_child:%.4f\n", [parent fractionCompleted]);

        /* explicit child attachment */
        NSProgress *p2 = [NSProgress progressWithTotalUnitCount:2];
        NSProgress *c2 = [NSProgress progressWithTotalUnitCount:10];
        [p2 addChild:c2 withPendingUnitCount:2];
        [c2 setCompletedUnitCount:5];
        printf("explicit_child:%.4f\n", [p2 fractionCompleted]);

        /* user-info payload */
        NSProgress *u = [NSProgress progressWithTotalUnitCount:1];
        [u setUserInfoObject:@"payload" forKey:@"corpusKey"];
        printf("userinfo:%s count:%lu\n",
               [[[u userInfo] objectForKey:@"corpusKey"] UTF8String],
               (unsigned long)[[u userInfo] count]);
        [u setKind:NSProgressKindFile];
        printf("kind_set:%d\n", [u kind] != nil);

        /* over-completion must not report a fraction above 1 */
        NSProgress *o = [NSProgress progressWithTotalUnitCount:4];
        [o setCompletedUnitCount:9];
        printf("over_frac:%.4f\n", [o fractionCompleted]);
    }
    return 0;
}
EOF

cat > "$SRC/t35_symlink.m" <<'EOF'
/* Removing a directory tree must delete symbolic links, NOT follow them and delete
   what they point at (FINDINGS.md F63).
   This is a DATA LOSS test: it builds a tree containing a link to a directory
   OUTSIDE the tree, removes the tree, and checks the outside file survived. A
   translation layer that gets this wrong destroys user data that was never named. */
#import <Foundation/Foundation.h>
#include <stdio.h>

int main(void){
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *base    = @"/private/var/tmp/corpus-t35";
        NSString *outside = @"/private/var/tmp/corpus-t35-outside";
        NSString *victim  = [outside stringByAppendingPathComponent:@"precious.txt"];
        NSString *tree    = [base stringByAppendingPathComponent:@"tree"];
        NSString *link    = [tree stringByAppendingPathComponent:@"link"];
        NSString *inner   = [tree stringByAppendingPathComponent:@"inner.txt"];

        [fm removeItemAtPath:base error:NULL];
        [fm removeItemAtPath:outside error:NULL];

        /* the bystander: a directory and file that the removal never names */
        [fm createDirectoryAtPath:outside withIntermediateDirectories:YES
                       attributes:nil error:NULL];
        [@"precious" writeToFile:victim atomically:YES
                        encoding:NSUTF8StringEncoding error:NULL];

        /* the tree to be removed, containing a link pointing out of it */
        [fm createDirectoryAtPath:tree withIntermediateDirectories:YES
                       attributes:nil error:NULL];
        [@"inner" writeToFile:inner atomically:YES
                     encoding:NSUTF8StringEncoding error:NULL];
        BOOL madeLink = [fm createSymbolicLinkAtPath:link
                                 withDestinationPath:outside error:NULL];

        printf("setup link:%d victim:%d inner:%d\n", madeLink,
               [fm fileExistsAtPath:victim], [fm fileExistsAtPath:inner]);
        printf("link_is_link:%d\n",
               [[fm attributesOfItemAtPath:link error:NULL][NSFileType]
                   isEqualToString:NSFileTypeSymbolicLink]);

        BOOL removed = [fm removeItemAtPath:base error:NULL];
        printf("removed:%d tree_gone:%d\n", removed, ![fm fileExistsAtPath:base]);

        /* the assertion that matters */
        printf("victim_survived:%d outside_survived:%d\n",
               [fm fileExistsAtPath:victim], [fm fileExistsAtPath:outside]);

        [fm removeItemAtPath:outside error:NULL];
        printf("cleanup:%d\n", ![fm fileExistsAtPath:outside]);
    }
    return 0;
}
EOF

# --------------------------------------------------------------- compile ---
compile() { # name, source, arch, extra...
  local name=$1 src=$2 arch=$3; shift 3
  if clang -arch "$arch" -o "$BIN/${name}.${arch}" "$src" "$@" 2>"$BIN/${name}.${arch}.cc.err"; then
      echo "  built  ${name}.${arch}"
  else
      echo "  FAILED ${name}.${arch} -- $(head -1 "$BIN/${name}.${arch}.cc.err")"
      rm -f "$BIN/${name}.${arch}"
  fi
}

log "compiling arm64"
compile t01_hello    "$SRC/t01_hello.c"    arm64
compile t02_exit42   "$SRC/t02_exit42.c"   arm64
compile t03_syscalls "$SRC/t03_syscalls.c" arm64
compile t04_pthread  "$SRC/t04_pthread.c"  arm64
compile t05_dispatch "$SRC/t05_dispatch.c" arm64
compile t06_objc     "$SRC/t06_objc.m"     arm64 -framework Foundation -fobjc-arc
compile t07_cf       "$SRC/t07_cf.c"       arm64 -framework CoreFoundation
compile t08_plist    "$SRC/t08_plist.m"    arm64  -framework Foundation -fobjc-arc
compile t09_vartmp   "$SRC/t09_vartmp.c"   arm64
compile t10_boxed    "$SRC/t10_boxed.m"    arm64  -framework Foundation -fobjc-arc
compile t11_bridge   "$SRC/t11_bridge.m"   arm64  -framework Foundation -framework CoreFoundation -fobjc-arc
compile t12_strings  "$SRC/t12_strings.m"  arm64  -framework Foundation -fobjc-arc
compile t13_number   "$SRC/t13_number.m"   arm64  -framework Foundation -fobjc-arc
compile t14_fileman  "$SRC/t14_fileman.m"  arm64  -framework Foundation -fobjc-arc
compile t15_invoke   "$SRC/t15_invoke.m"   arm64  -framework Foundation
compile t16_collect  "$SRC/t16_collections.m" arm64 -framework Foundation -fobjc-arc
compile t17_archive  "$SRC/t17_archive.m"  arm64  -framework Foundation
compile t18_task     "$SRC/t18_task.m"     arm64  -framework Foundation
compile t19_url      "$SRC/t19_url.m"      arm64  -framework Foundation
compile t20_regex    "$SRC/t20_regex.m"    arm64  -framework Foundation
compile t21_secure   "$SRC/t21_secure.m"   arm64  -framework Foundation
compile t22_error    "$SRC/t22_error.m"    arm64  -framework Foundation
compile t23_kvc      "$SRC/t23_kvc.m"         arm64  -framework Foundation
compile t24_predicate "$SRC/t24_predicate.m"   arm64  -framework Foundation
compile t25_notify   "$SRC/t25_notify.m"      arm64  -framework Foundation
compile t26_operation "$SRC/t26_operation.m"   arm64  -framework Foundation
compile t27_xml      "$SRC/t27_xml.m"         arm64  -framework Foundation
compile t28_valuebox "$SRC/t28_valuebox.m"    arm64  -framework Foundation
compile t29_cache    "$SRC/t29_cache.m"       arm64  -framework Foundation -fobjc-arc
compile t30_scanner  "$SRC/t30_scanner.m"     arm64  -framework Foundation -fobjc-arc
compile t31_attrstr  "$SRC/t31_attrstr.m"     arm64  -framework Foundation -fobjc-arc
compile t32_filehandle "$SRC/t32_filehandle.m" arm64 -framework Foundation -fobjc-arc
compile t33_thread   "$SRC/t33_thread.m"      arm64  -framework Foundation -fobjc-arc
compile t34_progress "$SRC/t34_progress.m"    arm64  -framework Foundation -fobjc-arc
compile t35_symlink  "$SRC/t35_symlink.m"     arm64  -framework Foundation -fobjc-arc

log "compiling arm64e (PAC-signed — kkHAIKE's hardest claim)"
compile t01_hello    "$SRC/t01_hello.c"    arm64e
compile t03_syscalls "$SRC/t03_syscalls.c" arm64e
compile t06_objc     "$SRC/t06_objc.m"     arm64e -framework Foundation -fobjc-arc
compile t10_boxed    "$SRC/t10_boxed.m"    arm64e -framework Foundation -fobjc-arc
compile t11_bridge   "$SRC/t11_bridge.m"   arm64e -framework Foundation -framework CoreFoundation -fobjc-arc
# arm64e breadth: PAC-signed binaries are the least independently verified part of
# the stack, so every case that can be built for arm64e is. Divergences here are
# worth far more than another arm64 case would be.
compile t02_exit42   "$SRC/t02_exit42.c"   arm64e
compile t04_pthread  "$SRC/t04_pthread.c"  arm64e
compile t05_dispatch "$SRC/t05_dispatch.c" arm64e
compile t07_cf       "$SRC/t07_cf.c"       arm64e -framework CoreFoundation
compile t08_plist    "$SRC/t08_plist.m"    arm64e -framework Foundation -fobjc-arc
compile t09_vartmp   "$SRC/t09_vartmp.c"   arm64e
compile t12_strings  "$SRC/t12_strings.m"  arm64e -framework Foundation -fobjc-arc
compile t13_number   "$SRC/t13_number.m"   arm64e -framework Foundation -fobjc-arc
compile t14_fileman  "$SRC/t14_fileman.m"  arm64e -framework Foundation -fobjc-arc
compile t15_invoke   "$SRC/t15_invoke.m"   arm64e -framework Foundation
compile t16_collect  "$SRC/t16_collections.m" arm64e -framework Foundation -fobjc-arc
compile t17_archive  "$SRC/t17_archive.m"  arm64e -framework Foundation
compile t18_task     "$SRC/t18_task.m"     arm64e -framework Foundation
compile t19_url      "$SRC/t19_url.m"      arm64e -framework Foundation
compile t20_regex    "$SRC/t20_regex.m"    arm64e -framework Foundation
compile t21_secure   "$SRC/t21_secure.m"   arm64e -framework Foundation
compile t22_error    "$SRC/t22_error.m"    arm64e -framework Foundation
compile t23_kvc      "$SRC/t23_kvc.m"         arm64e -framework Foundation
compile t24_predicate "$SRC/t24_predicate.m"   arm64e -framework Foundation
compile t25_notify   "$SRC/t25_notify.m"      arm64e -framework Foundation
compile t26_operation "$SRC/t26_operation.m"   arm64e -framework Foundation
compile t27_xml      "$SRC/t27_xml.m"         arm64e -framework Foundation
compile t28_valuebox "$SRC/t28_valuebox.m"    arm64e -framework Foundation
compile t29_cache    "$SRC/t29_cache.m"       arm64e -framework Foundation -fobjc-arc
compile t30_scanner  "$SRC/t30_scanner.m"     arm64e -framework Foundation -fobjc-arc
compile t31_attrstr  "$SRC/t31_attrstr.m"     arm64e -framework Foundation -fobjc-arc
compile t32_filehandle "$SRC/t32_filehandle.m" arm64e -framework Foundation -fobjc-arc
compile t33_thread   "$SRC/t33_thread.m"      arm64e -framework Foundation -fobjc-arc
compile t34_progress "$SRC/t34_progress.m"    arm64e -framework Foundation -fobjc-arc
compile t35_symlink  "$SRC/t35_symlink.m"     arm64e -framework Foundation -fobjc-arc

# ------------------------------------------------- real Apple CLT binaries ---
# NOTE: copying an Apple-signed binary invalidates its code signature, so the
# COPY is SIGKILLed by macOS (exit 137). The copy is still a perfectly valid
# Mach-O for Darling to load, so we keep it as a Darling input — but ground
# truth must always be taken from the ORIGINAL path.
log "copying Apple-signed host binaries"
: > "$ROOT/host_manifest.tsv"
for b in /bin/echo /usr/bin/uname /bin/pwd /usr/bin/basename /usr/bin/true /usr/bin/false /usr/bin/wc; do
    [ -f "$b" ] || continue
    n="host_$(basename "$b")"
    cp "$b" "$BIN/$n" 2>/dev/null && {
        printf '%s\t%s\n' "$n" "$b" >> "$ROOT/host_manifest.tsv"
        echo "  copied $n  <- $b"
    }
done

# ------------------------------------------------------------ ground truth ---
# args per test, kept in one place so the VM-side runner uses identical ones.
args_for() {
  case "$1" in
    host_echo|echo)          echo "hi" ;;
    host_basename|basename)  echo "/a/b/c" ;;
    host_wc|wc)              echo "-w" ;;
    *)                       echo "" ;;
  esac
}
stdin_for() { case "$1" in host_wc|wc) printf 'a b\n' ;; *) printf '' ;; esac; }

log "capturing native ground truth (originals for host_*, copies for ours)"
: > "$TRUTH/native.tsv"
for f in "$BIN"/*; do
    case "$f" in *.err) continue;; esac
    [ -x "$f" ] || continue
    n=$(basename "$f")
    # For Apple binaries run the ORIGINAL; the copy would be SIGKILLed.
    target="$f"
    if orig=$(awk -F'\t' -v k="$n" '$1==k{print $2}' "$ROOT/host_manifest.tsv" 2>/dev/null) && [ -n "$orig" ]; then
        target="$orig"
    fi
    a=$(args_for "$n")
    if [ -n "$a" ]; then
        out=$(stdin_for "$n" | "$target" $a 2>&1); rc=$?
    else
        out=$(stdin_for "$n" | "$target" 2>&1); rc=$?
    fi
    printf '%s\t%s\t%s\n' "$n" "$rc" "$(printf '%s' "$out" | tr '\n' '~')" >> "$TRUTH/native.tsv"
done

log "corpus summary"
printf 'binaries: %s\n' "$(find "$BIN" -type f ! -name '*.err' | wc -l | tr -d ' ')"
column -t -s"$(printf '\t')" "$TRUTH/native.tsv" 2>/dev/null || cat "$TRUTH/native.tsv"

log "mach-o arch check"
for f in "$BIN"/t01_hello.* "$BIN"/t06_objc.* "$BIN"/host_uname; do
    [ -f "$f" ] && printf '%-24s %s\n' "$(basename "$f")" "$(lipo -archs "$f" 2>/dev/null)"
done
