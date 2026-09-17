#!/usr/bin/env python3
"""
DARLING-ARM64: five more capability areas for the differential corpus. Idempotent.
Run from the repo root.

WHY THESE FIVE
--------------
Every new capability area added to the corpus has found a defect on its first run --
F28b, F39, F40, F41 and F42 all arrived that way. These are the highest-value areas
nothing currently exercises, chosen for real-application relevance:

  t18_task.m    NSTask / NSPipe -- launching and reading from a child process. Any
                app that shells out depends on this, and the ladder covers it only
                incidentally.
  t19_url.m     NSURL parsing and manipulation -- components, resolution against a
                base, percent-encoding, file URLs. Ubiquitous, and full of edge
                cases where an implementation can be subtly wrong rather than
                absent.
  t20_regex.m   NSRegularExpression -- match counting, capture groups, replacement.
                Backed by ICU, which is a large vendored dependency worth probing.
  t21_secure.m  NSSecureCoding -- archiving with requiresSecureCoding and an
                allowed-class set, plus the rejection path for a disallowed class.
                Distinct from t17, which exercises ordinary keyed archiving.
  t22_error.m   NSError / NSException -- domains, codes, userInfo round-trips,
                @throw/@catch, and the value of an exception that crosses a frame.

DETERMINISM. Ground truth is captured by running these on real macOS, so anything
varying run-to-run produces a false divergence and wastes a session. Deliberately
avoided: timestamps, pids, paths outside a fixed temp location, locale- and
ICU-version-dependent formatting, unordered enumeration, and anything touching the
network. Everything printed is a fixed string, a count, or a comparison result.

`t18_task` runs /bin/echo, which exists in the Darling runtime and on macOS, and
compares only its output and termination status.

Built for arm64 and arm64e -- a divergence found only on arm64e is worth more, since
PAC-signed binaries are the least independently verified part of the stack.

Revert with: git checkout -- scripts/10-make-corpus.sh
"""
import sys, pathlib

P = pathlib.Path("scripts/10-make-corpus.sh")

SOURCE = r'''
cat > "$SRC/t18_task.m" <<'EOF'
/* NSTask + NSPipe: launching a child and reading its output. */
#import <Foundation/Foundation.h>
#include <stdio.h>
int main(void){
    @autoreleasepool {
        NSTask *t = [[NSTask new] autorelease];
        [t setLaunchPath:@"/bin/echo"];
        [t setArguments:@[@"hello", @"task"]];
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
'''

ARM64_ANCHOR = 'compile t17_archive  "$SRC/t17_archive.m"  arm64  -framework Foundation\n'
ARM64_NEW = ARM64_ANCHOR + '''compile t18_task     "$SRC/t18_task.m"     arm64  -framework Foundation
compile t19_url      "$SRC/t19_url.m"      arm64  -framework Foundation
compile t20_regex    "$SRC/t20_regex.m"    arm64  -framework Foundation
compile t21_secure   "$SRC/t21_secure.m"   arm64  -framework Foundation
compile t22_error    "$SRC/t22_error.m"    arm64  -framework Foundation
'''

ARM64E_ANCHOR = 'compile t17_archive  "$SRC/t17_archive.m"  arm64e -framework Foundation\n'
ARM64E_NEW = ARM64E_ANCHOR + '''compile t18_task     "$SRC/t18_task.m"     arm64e -framework Foundation
compile t19_url      "$SRC/t19_url.m"      arm64e -framework Foundation
compile t20_regex    "$SRC/t20_regex.m"    arm64e -framework Foundation
compile t21_secure   "$SRC/t21_secure.m"   arm64e -framework Foundation
compile t22_error    "$SRC/t22_error.m"    arm64e -framework Foundation
'''

if not P.exists():
    print(f"FATAL: missing {P} -- run from the repo root", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "t18_task" in s:
    print("already patched")
    sys.exit(0)

anchor_src = 'EOF\n\n# --------------------------------------------------------------- compile ---'
if s.count(anchor_src) != 1:
    print(f"FATAL: source anchor found {s.count(anchor_src)}x (want 1)", file=sys.stderr)
    sys.exit(1)
s = s.replace(anchor_src,
              'EOF\n' + SOURCE + '\n# --------------------------------------------------------------- compile ---', 1)

for old, new, what in ((ARM64_ANCHOR, ARM64_NEW, "arm64"),
                       (ARM64E_ANCHOR, ARM64E_NEW, "arm64e")):
    if s.count(old) != 1:
        print(f"FATAL: {what} compile anchor found {s.count(old)}x (want 1)", file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)

P.write_text(s)
print(f"patched {P}: 5 new areas, each built for arm64 and arm64e")
