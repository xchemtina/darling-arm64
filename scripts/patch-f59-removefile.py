#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F59. Idempotent. Run from ~/darling/source.

DIAGNOSIS
---------
`-[NSFileManager removeItemAtPath:error:]` **cannot delete a regular file.**

    native : ... nulldev:1 nulldev_read:0~cleaned:1
    darling: ... nulldev:1 nulldev_read:0~cleaned:0

`removeItemAtPath:` (`NSFileManager.m:664`) does no work itself: it builds an
`NSFilesystemItemRemoveOperation` and starts it. That operation removes via
**`nftw(3)`** (`-main`, below), and the actual `remove()` lives *only* inside the walk
callback. Apple's own `nftw.c:113-119` refuses to walk a non-directory:

    if (rc >= 0 && nfn) {
        if (!S_ISDIR(path_stat.st_mode)) {
            errno = ENOTDIR; error = -1; goto done;   /* before any callback */
        }
    }

`nfn` is non-NULL for `nftw` (NULL only for legacy `ftw`) and the build defines
`__DARWIN_UNIX03=1`. So for a regular file the walk bails with ENOTDIR *before the
callback runs* and `remove()` is never reached. For a directory `nftw` walks happily
and deletes the regular files inside it -- which is why `t14_fileman` passes and
looks like proof that removal works. It removes a DIRECTORY; `t32` removes a FILE.

THE FIX
-------
Detect the non-directory case up front and invoke the existing callback directly,
rather than routing it through a tree walk that will refuse it. Calling the same
callback (instead of a bare `remove()`) is deliberate: it preserves the
`fileManager:shouldRemoveItemAtPath:` and `fileManager:shouldProceedAfterError:...`
delegate contracts and the existing error plumbing, so only the *reachability* of the
deletion changes, not its semantics.

`nftw.c` is NOT patched. It is Apple's Libc source and its ENOTDIR behaviour matches
real macOS; macOS Foundation simply does not use `nftw` here (it uses `removefile(3)`,
which Darling also builds -- but re-plumbing the delegate callbacks through
removefile's status callback is a much larger change than this defect warrants).

WHY lstat AND NOT stat
----------------------
Two reasons. First, correctness: a symlink must be removed as a link, not followed to
its target. Second, and worth stating: the existing `nftw` call passes only
`FTW_DEPTH` -- no `FTW_PHYS` -- so `nftw.c` selects `FTS_LOGICAL` + `FTS_COMFOLLOW`
and **directory removal currently follows symlinks and deletes their targets**. That
is recorded separately as F63 and deliberately NOT fixed here: adding `FTW_PHYS`
changes existing directory-removal behaviour and deserves its own corpus case and
control run rather than riding along with this change.

If `lstat` fails (e.g. ENOENT) we fall through to `nftw` unchanged, so the
missing-path error path keeps its current behaviour exactly.

Revert with: cd src/external/foundation && git checkout -- src/NSFilesystemItemRemoveOperation.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSFilesystemItemRemoveOperation.m")

OLD_INCLUDES = """#import <ftw.h>
#import <errno.h>"""

NEW_INCLUDES = """#import <ftw.h>
#import <sys/stat.h>   /* DARLING-ARM64 (F59): lstat/S_ISDIR */
#import <errno.h>"""

OLD_MAIN = """        ctx = self;

        int err = nftw(
            [_removePath cString],
            NSFilesystemItemRemoveOperationFunction,
            1, // ignored by the implementation, but values less than 1 and
               // more than OPEN_MAX result in EINVAL
            FTW_DEPTH
        );

        ctx = NULL;"""

NEW_MAIN = """        ctx = self;

        const char *cpath = [_removePath cString];
        int err;

        /* DARLING-ARM64 FIX (FINDINGS.md F59): removal used to go through nftw()
         * unconditionally, and nftw() REFUSES to walk a non-directory -- Apple's
         * nftw.c returns ENOTDIR before ever invoking the callback. Since the actual
         * remove() lives only inside that callback, this meant
         * -[NSFileManager removeItemAtPath:error:] could not delete a regular file
         * at all. Directories worked, which is why the defect hid: a test that
         * removes a directory passes and looks like proof that removal works.
         *
         * The callback is invoked directly rather than calling remove() here, so the
         * fileManager:shouldRemoveItemAtPath: and shouldProceedAfterError: delegate
         * contracts and the error plumbing all still apply. Only the reachability of
         * the deletion changes.
         *
         * lstat, not stat: a symlink must be removed as a link, not followed. (The
         * nftw path below still follows symlinks when deleting a tree, because it
         * lacks FTW_PHYS -- that is recorded as F63 and deliberately left alone
         * here, since changing it alters existing directory-removal behaviour.)
         *
         * If lstat fails, fall through to nftw so the missing-path error path keeps
         * its exact previous behaviour. */
        struct stat st;
        if (lstat(cpath, &st) == 0 && !S_ISDIR(st.st_mode))
        {
            struct FTW info;
            info.base = 0;
            info.level = 0;
            err = NSFilesystemItemRemoveOperationFunction(cpath, &st, FTW_F, &info);
        }
        else
        {
            err = nftw(
                cpath,
                NSFilesystemItemRemoveOperationFunction,
                1, // ignored by the implementation, but values less than 1 and
                   // more than OPEN_MAX result in EINVAL
                FTW_DEPTH
            );
        }

        ctx = NULL;"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F59" in s:
    print("already patched")
    sys.exit(0)

for old, new, what in ((OLD_INCLUDES, NEW_INCLUDES, "includes"),
                       (OLD_MAIN, NEW_MAIN, "-main nftw call")):
    if s.count(old) != 1:
        print(f"FATAL: {what} anchor found {s.count(old)}x (want 1)", file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)

P.write_text(s)
print(f"patched {P}: regular files no longer routed through nftw, which refuses them")
