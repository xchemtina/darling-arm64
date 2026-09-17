#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F63. Idempotent. Run from ~/darling/source.

DIAGNOSIS
---------
Removing a directory tree **follows symbolic links and deletes what they point at**.

`NSFilesystemItemRemoveOperation` walks the tree with:

    nftw(path, callback, 1, FTW_DEPTH);

with no `FTW_PHYS`. Darling's `nftw.c` maps that to `FTS_LOGICAL` plus
`FTS_COMFOLLOW`, i.e. *follow every symlink*. So the walk descends through a link
into whatever it points at and the callback happily `remove()`s the contents.

This is data loss outside the tree the caller named. Deleting a directory that
happens to contain a link to your home directory would empty your home directory.

MEASURED, not merely reasoned about
-----------------------------------
Recorded first as a read-only observation, then reproduced by a corpus case
(`t35_symlink`) that builds a bystander directory, puts a link to it inside the tree
being removed, and asserts the bystander survives:

    native : … removed:1 tree_gone:1 ~ victim_survived:1 outside_survived:1 …
    darling: … removed:1 tree_gone:1 ~ victim_survived:0 outside_survived:1 …

`victim_survived:0` -- Darling deleted a file it was never asked to touch.

Getting that far first required fixing **F68**: `createSymbolicLinkAtPath:` passed its
arguments to `symlink(2)` backwards, so the test's link was never created and the run
reported `victim_survived:1` for the wrong reason. Two defects stacked, with the outer
one masking the inner one as a false negative.

THE FIX
-------
Add `FTW_PHYS`, so the walk does not follow symlinks. The callback then receives the
link itself and `remove()` unlinks the link rather than its target -- which is what
macOS does.

WHY THIS IS SAFE FOR THE ORDINARY CASE
--------------------------------------
`FTW_PHYS` changes only how *links* are treated; real directories are still descended
and their contents still removed. `t14_fileman`, which removes a directory containing
regular files, must continue to pass -- it is the control for this change and is
checked after building.

Revert with: cd src/external/foundation && git checkout -- src/NSFilesystemItemRemoveOperation.m
  -- NOTE: that also reverts the F59 fix, which lives in the same file (trap 29).
     Re-apply patch-f59-removefile.py afterwards.
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSFilesystemItemRemoveOperation.m")

OLD = """            err = nftw(
                cpath,
                NSFilesystemItemRemoveOperationFunction,
                1, // ignored by the implementation, but values less than 1 and
                   // more than OPEN_MAX result in EINVAL
                FTW_DEPTH
            );"""

NEW = """            /* DARLING-ARM64 FIX (FINDINGS.md F63): FTW_PHYS added. Without it
             * nftw selects FTS_LOGICAL + FTS_COMFOLLOW and the walk FOLLOWS
             * symbolic links, so removing a directory tree deleted whatever its
             * links pointed at -- data loss outside the tree the caller named,
             * measured by t35_symlink. With FTW_PHYS the callback receives the link
             * itself and remove() unlinks the link, which is what macOS does.
             * Real directories are still descended, so ordinary recursive removal
             * (t14_fileman) is unaffected -- that case is the control. */
            err = nftw(
                cpath,
                NSFilesystemItemRemoveOperationFunction,
                1, // ignored by the implementation, but values less than 1 and
                   // more than OPEN_MAX result in EINVAL
                FTW_DEPTH | FTW_PHYS
            );"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F63" in s:
    print("already patched")
    sys.exit(0)
if "FINDINGS.md F59" not in s:
    print("FATAL: the F59 fix is missing from this file -- apply "
          "patch-f59-removefile.py first (trap 29)", file=sys.stderr)
    sys.exit(1)
if s.count(OLD) != 1:
    print(f"FATAL: anchor found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: tree removal no longer follows symlinks out of the tree")
