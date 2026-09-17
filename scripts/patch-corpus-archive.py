#!/usr/bin/env python3
"""
DARLING-ARM64: add a keyed-archiving corpus case. Idempotent. Run from repo root.

WHY
---
F27 is localised to `_decodeObjectBinary` (NSKeyedUnarchiver.m:436) returning a
non-object while `NSSavePanel` unarchives its NIB. Iterating on that through
`verify-text-edit` costs ~10 minutes and needs Xvfb, openbox and xdotool. This case
costs ~4 minutes and no display.

It targets what the NIB decode targets:

  * a nested graph -- NSArray -> Column -> Cell -- mirroring the failing
    NSArray -> NSTableColumn -> NSTextFieldCell chain;
  * **object identity across references**: `shared` appears in two places, which
    forces the archiver to emit a repeated UID and the unarchiver to take the
    `_refObjMap` hit at the top of `_decodeObjectBinary` (line 441). That is the
    leading hypothesis for where a raw UID reaches the caller as an object;
  * a **cycle** (column <-> cell), which is what `_tmpRefObjMap`'s
    "break infinite recursion" path exists for;
  * mixed scalars alongside the objects, since the marker dispatch handles int,
    string, bool and data on separate branches.

Whichever way it lands, the result is useful: a reproduction gives F27 a fast loop
and a regression test, and a pass narrows F27 to something specific about the AppKit
NIB rather than keyed archiving in general.

DETERMINISM: prints only counts, comparison results and decoded scalars -- no
addresses, no pointers, nothing environment-dependent. Ground truth is captured by
running this on real macOS, so anything varying between runs would produce a false
divergence.

Built for arm64 and arm64e.

Revert with: git checkout -- scripts/10-make-corpus.sh
"""
import sys, pathlib

P = pathlib.Path("scripts/10-make-corpus.sh")

SOURCE = r'''
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
'''

ARM64_ANCHOR = 'compile t16_collect  "$SRC/t16_collections.m" arm64 -framework Foundation -fobjc-arc\n'
ARM64_NEW = ARM64_ANCHOR + 'compile t17_archive  "$SRC/t17_archive.m"  arm64  -framework Foundation\n'

ARM64E_ANCHOR = 'compile t16_collect  "$SRC/t16_collections.m" arm64e -framework Foundation -fobjc-arc\n'
ARM64E_NEW = ARM64E_ANCHOR + 'compile t17_archive  "$SRC/t17_archive.m"  arm64e -framework Foundation\n'

if not P.exists():
    print(f"FATAL: missing {P} -- run from the repo root", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "t17_archive" in s:
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
print(f"patched {P}: t17_archive added for arm64 and arm64e")
