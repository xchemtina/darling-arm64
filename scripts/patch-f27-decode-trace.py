#!/usr/bin/env python3
"""
DARLING-ARM64 DIAGNOSTIC for FINDINGS.md F27. Idempotent. Run from ~/darling/source.

F27: TextEdit's Cmd-S crashes with SIGSEGV in `objc_msgSend` called from
`_decodeObjectBinary + 0x83c` (NSKeyedUnarchiver.m:436), while NSSavePanel unarchives
its NIB. `x0` is a small integer -- `0x7` and `0x22` across runs -- so a raw value is
being messaged as if it were an object.

`+0x83c` is late in the function: past the marker dispatch, in the region that
resolves `$class`, allocates, and sends `initWithCoder:`. The receivers there are
`class` (from one of three lookups) and `allocated`. This prints every one of them,
so a single run identifies which is bad rather than requiring a bisect.

Probes, all gated on DARLING_ARM64_DECODE_TRACE and globally bounded -- NIB decoding
runs thousands of times and unbounded output would bury the failure:

  P1  the _refObjMap / _tmpRefObjMap hit (line ~441). The leading hypothesis is that
      a raw UID is returned here as an object, so `mapObject` is printed BEFORE
      `[mapObject retain]` touches it.
  P2  which marker branch was taken.
  P3  `className`, and the result of each of the three class lookups.
  P4  `allocated`, immediately before `initWithCoder:` is sent.

Every pointer is printed as %p and additionally flagged when it is small enough to be
a UID rather than an address (< 0x10000), because that is the signature being hunted.

Revert with: cd src/external/foundation && git checkout -- src/NSKeyedUnarchiver.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSKeyedUnarchiver.m")

HELPER = """
/* DARLING-ARM64 DIAGNOSTIC (FINDINGS.md F27) */
static int __f27_budget = 400;
#define F27_ON() (__f27_budget > 0 && getenv("DARLING_ARM64_DECODE_TRACE"))
#define F27_SUSPECT(p) (((uintptr_t)(p)) != 0 && ((uintptr_t)(p)) < 0x10000)
#define F27_LOG(fmt, ...) do { \\
    if (F27_ON()) { __f27_budget--; \\
        fprintf(stderr, "[F27] " fmt "\\n", ##__VA_ARGS__); fflush(stderr); } \\
} while (0)

"""

EDITS = [
    # P1 -- the map-hit path, printed before anything messages mapObject
    ("""        id mapObject = nil;
        if (CFDictionaryGetValueIfPresent(unarchiver->_refObjMap, (const void *)uid1, (const void **)&mapObject) ||
            CFDictionaryGetValueIfPresent(unarchiver->_tmpRefObjMap, (const void *)uid1, (const void **)&mapObject))
        {
            // break infinite recursion
            return [mapObject retain];
        }""",
     """        id mapObject = nil;
        BOOL __f27_ref = CFDictionaryGetValueIfPresent(unarchiver->_refObjMap, (const void *)uid1, (const void **)&mapObject);
        BOOL __f27_tmp = !__f27_ref && CFDictionaryGetValueIfPresent(unarchiver->_tmpRefObjMap, (const void *)uid1, (const void **)&mapObject);
        if (__f27_ref || __f27_tmp)
        {
            F27_LOG("P1 map-hit uid=%lu from=%s obj=%p suspect=%d",
                    (unsigned long)uid1, __f27_ref ? "refObjMap" : "tmpRefObjMap",
                    (void *)mapObject, (int)F27_SUSPECT(mapObject));
            // break infinite recursion
            return [mapObject retain];
        }"""),

    # P2 -- which marker branch
    ("""        else if (markerTag != kCFBinaryPlistMarkerDict)
        {""",
     """        else if (markerTag != kCFBinaryPlistMarkerDict)
        {
            F27_LOG("P2 unhandled markerTag=0x%x uid=%lu", markerTag, (unsigned long)uid1);"""),

    # P3 -- className and each class lookup
    ("""        Class class = [unarchiver classForClassName:className];
        if (class == nil)
        {
            class = [[unarchiver class] classForClassName:className];
        }
        if (class == nil)
        {
            class = NSClassFromString(className);
        }""",
     """        F27_LOG("P3a className=%p suspect=%d", (void *)className, (int)F27_SUSPECT(className));
        Class class = [unarchiver classForClassName:className];
        F27_LOG("P3b classForClassName -> %p suspect=%d", (void *)class, (int)F27_SUSPECT(class));
        if (class == nil)
        {
            class = [[unarchiver class] classForClassName:className];
            F27_LOG("P3c +classForClassName -> %p suspect=%d", (void *)class, (int)F27_SUSPECT(class));
        }
        if (class == nil)
        {
            class = NSClassFromString(className);
            F27_LOG("P3d NSClassFromString -> %p suspect=%d", (void *)class, (int)F27_SUSPECT(class));
        }"""),

    # P4 -- the allocated instance, immediately before initWithCoder:
    ("""        id allocated = [class allocWithZone:nil];""",
     """        F27_LOG("P4a about to alloc class=%p suspect=%d", (void *)class, (int)F27_SUSPECT(class));
        id allocated = [class allocWithZone:nil];
        F27_LOG("P4b allocated=%p suspect=%d", (void *)allocated, (int)F27_SUSPECT(allocated));"""),
]

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "__f27_budget" in s:
    print("already patched")
    sys.exit(0)

anchor = "static id _decodeObjectBinary(NSKeyedUnarchiver *unarchiver, NSUInteger uid1) NS_RETURNS_RETAINED\n"
if s.count(anchor) != 1:
    print(f"FATAL: function anchor found {s.count(anchor)}x (want 1)", file=sys.stderr)
    sys.exit(1)
s = s.replace(anchor, HELPER + anchor, 1)

for i, (old, new) in enumerate(EDITS, 1):
    if s.count(old) != 1:
        print(f"FATAL: probe {i} anchor found {s.count(old)}x (want 1)", file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)

P.write_text(s)
print(f"patched {P}: 4 probes inserted, env-gated and budget-bounded")
