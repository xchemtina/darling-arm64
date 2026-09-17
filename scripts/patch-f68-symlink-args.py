#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F68. Idempotent. Run from ~/darling/source.

DIAGNOSIS
---------
`-[NSFileManager createSymbolicLinkAtPath:withDestinationPath:error:]` passes its two
arguments to `symlink(2)` **the wrong way round**:

    int err = symlink([path UTF8String], [destPath UTF8String]);

POSIX is `symlink(const char *target, const char *linkpath)` -- it creates
*linkpath*, pointing at *target*. Cocoa's method means "create a link **at** `path`
whose contents are `destPath`". So the correct call is `symlink(destPath, path)`:
destination first, link location second. The code has them reversed, so it tries to
create the link at the destination, pointing back at the requested link path.

TWO FAILURE MODES, and the quieter one is worse:

  * If the destination already exists -- the common case, since you usually link to
    something real -- `symlink` fails with EEXIST and the method returns NO. Noisy,
    but at least visible.
  * If the destination does **not** exist, the call SUCCEEDS and creates a symbolic
    link in a place the caller never asked for, pointing the wrong way, while no link
    appears where the caller wanted one. Silent, and wrong in two directions at once.

HOW IT WAS FOUND
----------------
Not by looking for it. A corpus case was being written to reproduce F63 (directory
removal following symlinks and deleting their targets). The case reported
`setup link:0 link_is_link:0` -- the symlink it needed had never been created -- and
so its headline assertion, `victim_survived:1`, was **meaningless**: the dangerous
path was never exercised.

That is trap 17 exactly ("confirm the failing path is still exercised"). Had the
setup line not been asserted on, the run would have been read as evidence that F63
does not reproduce, which would have been a false negative on a data-loss defect.

Revert with: cd src/external/foundation && git checkout -- src/NSFileManager.m
  -- check first what else is patched there: grep -c "DARLING-ARM64 FIX" src/NSFileManager.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSFileManager.m")

OLD = "    int err = symlink([path UTF8String], [destPath UTF8String]);"

NEW = """    /* DARLING-ARM64 FIX (FINDINGS.md F68): the arguments were reversed.
     * symlink(2) is symlink(target, linkpath) -- it creates linkpath pointing at
     * target -- while this method means "create a link AT path whose contents are
     * destPath". Passing (path, destPath) therefore tried to create the link at the
     * destination, pointing backwards.
     *
     * When the destination already existed this failed with EEXIST and returned NO.
     * When it did not, it silently SUCCEEDED and created a link in the wrong place,
     * pointing the wrong way, with no link where the caller asked for one. */
    int err = symlink([destPath UTF8String], [path UTF8String]);"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F68" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: anchor found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: symlink() arguments now in POSIX order (target, linkpath)")
