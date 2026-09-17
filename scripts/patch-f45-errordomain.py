#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F45. Idempotent. Run from ~/darling/source.

DIAGNOSIS
---------
A failed file read produces the right error with the wrong domain:

    native : … read:0 gaveerr:1 cocoa:1 …
    darling: … read:0 gaveerr:1 cocoa:0 …

`_NSReadBytesFromFile` (`_NSFileIO.m:24`) reports failures as

    [NSError errorWithDomain:NSPOSIXErrorDomain code:errno …]

at lines 33 and 44, and `-[NSString initWithContentsOfFile:encoding:error:]`
(`NSString.m:826`) passes that straight out. macOS reports `NSCocoaErrorDomain` with
a file-reading code.

The codebase is already inconsistent about this: `NSData.m:891` builds its read
failure with `NSCocoaErrorDomain`, so the two paths disagree with each other as well
as with macOS.

It is not cosmetic. Error-handling code routinely switches on domain to decide
whether a failure is recoverable, and a wrong domain silently takes the wrong branch
— the caller never sees an error it recognises.

THE FIX
-------
Map errno to the corresponding Cocoa file-reading code, and keep the POSIX error as
`NSUnderlyingErrorKey`, which is what Foundation does — no information is lost, and
callers that do want the errno can still reach it.

Codes are Apple's documented values (`NSFileReadNoSuchFileError` 260,
`NSFileReadNoPermissionError` 257, `NSFileReadUnknownError` 256); this tree does not
declare the enum, so they appear numerically with a comment.

Revert with: cd src/external/foundation && git checkout -- src/_NSFileIO.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/_NSFileIO.m")

HELPER = '''
/* DARLING-ARM64 FIX (FINDINGS.md F45): read failures were reported in
 * NSPOSIXErrorDomain; macOS reports NSCocoaErrorDomain with a file-reading code.
 * Callers switch on domain to decide whether a failure is recoverable, so the wrong
 * domain silently sends them down the wrong branch. The POSIX error is preserved as
 * NSUnderlyingErrorKey, as Foundation does, so nothing is lost.
 *
 * Codes are Apple's documented values; this tree declares no enum for them.
 * (NSData.m:891 already used NSCocoaErrorDomain, so these two paths disagreed with
 * each other as well as with macOS.) */
static NSError *_DarlingCocoaReadError(int posixCode, NSString *path)
{
    NSInteger cocoaCode;
    switch (posixCode) {
        case ENOENT: case ENOTDIR: cocoaCode = 260; break;  /* NoSuchFile     */
        case EACCES: case EPERM:   cocoaCode = 257; break;  /* NoPermission   */
        default:                   cocoaCode = 256; break;  /* UnknownError   */
    }

    NSError *underlying = [NSError errorWithDomain: NSPOSIXErrorDomain
                                              code: posixCode
                                          userInfo: nil];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] =
        [NSString stringWithUTF8String: strerror(posixCode)];
    info[NSUnderlyingErrorKey] = underlying;
    if (path != nil) {
        info[NSFilePathErrorKey] = path;
    }

    return [NSError errorWithDomain: NSCocoaErrorDomain
                               code: cocoaCode
                           userInfo: info];
}

'''

OLD = "*err = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:strerror(errno)]}];"
NEW = "*err = _DarlingCocoaReadError(errno, path);"

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F45" in s:
    print("already patched")
    sys.exit(0)

n = s.count(OLD)
if n == 0:
    print("FATAL: no NSPOSIXErrorDomain read-error sites found", file=sys.stderr)
    sys.exit(1)
s = s.replace(OLD, NEW)

anchor = "void *_NSReadBytesFromFile("
if s.count(anchor) != 1:
    print(f"FATAL: function anchor found {s.count(anchor)}x (want 1)", file=sys.stderr)
    sys.exit(1)
s = s.replace(anchor, HELPER + anchor, 1)

P.write_text(s)
print(f"patched {P}: {n} read-error site(s) now report NSCocoaErrorDomain "
      f"with the POSIX error preserved as NSUnderlyingErrorKey")
