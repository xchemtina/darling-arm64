#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F75. Idempotent. Run from ~/darling/source.

DIAGNOSIS
---------
Unmodified iTerm2 3.6.11 intermittently terminates during window setup with:

    *** Terminating app due to uncaught exception 'NSInvalidArgumentException',
        reason: '-[NSWindow disableBlur]: unrecognized selector sent to instance …'

`-[NSWindow disableBlur]` and `-[NSWindow enableBlur:]` are private AppKit SPI for
window background blur. Both selectors are present in the official iTerm2 binary
(confirmed by scanning it); Darling's AppKit declares neither, so the message is
unrecognised, the exception is uncaught, and the application dies.

It is intermittent because iTerm2 only takes this path for profiles with transparency
or blur configured, and the probe's saved preferences vary between runs.

WHY A NO-OP IS THE TRUTHFUL IMPLEMENTATION HERE, NOT A FAKE
-----------------------------------------------------------
The project's compatibility policy forbids "success-returning no-ops" that hide a
broken contract. This is not one of those, and the distinction matters:

  * Darling's X11 backend has no compositor-level background blur at all.
  * `disableBlur` asks for a postcondition -- "this window is not blurred" -- which is
    *already and permanently true*. Returning without doing anything makes the
    postcondition hold. That is a correct implementation, not a pretence.
  * `enableBlur:` cannot deliver blur. The window renders unblurred, which is a
    visible cosmetic difference and nothing more: no data is dropped, no state is
    faked, and no caller is told a value it will later rely on. iTerm2 treats blur as
    decoration and continues normally without it.

The alternative -- leaving the selector missing -- is strictly worse: it converts a
cosmetic gap into a fatal uncaught exception that prevents any window from existing.

This sits at rung 2 of the project's own stub ladder ("deterministic empty
implementation"), and is deliberately *not* claimed as blur support. It is recorded in
FINDINGS.md as an explicit unsupported-capability boundary.

Revert with: cd src/external/cocotron && git checkout -- AppKit/NSWindow.m
  -- check first what else is patched there: grep -c "DARLING-ARM64 FIX" AppKit/NSWindow.m
"""
import sys, pathlib

P = pathlib.Path("src/external/cocotron/AppKit/NSWindow.m")

ANCHOR = "@implementation NSWindow"

ADDITION = '''/* DARLING-ARM64 FIX (FINDINGS.md F75): -[NSWindow disableBlur] and
 * -[NSWindow enableBlur:] are private AppKit SPI for window background blur. The
 * official iTerm2 binary sends both. Darling declared neither, so the message was
 * unrecognised, the exception went uncaught, and the application terminated before
 * any window existed.
 *
 * Darling's X11 backend has no compositor blur. `disableBlur` therefore has a
 * postcondition that is already permanently true, and implementing it as a no-op is
 * correct rather than a pretence. `enableBlur:` cannot deliver blur; the window
 * renders unblurred, which is a cosmetic difference that drops no data and fakes no
 * state. Leaving the selectors missing is strictly worse -- it turns a cosmetic gap
 * into a fatal exception.
 *
 * This is NOT a claim of blur support. See FINDINGS.md F75. */
@interface NSWindow (DarlingARM64UnsupportedBlur)
- (void) disableBlur;
- (void) enableBlur: (CGFloat) radius;
@end

@implementation NSWindow (DarlingARM64UnsupportedBlur)

- (void) disableBlur {
    /* Nothing to disable: this backend never blurs. Postcondition holds. */
}

- (void) enableBlur: (CGFloat) radius {
    /* Unsupported by the X11 backend. The window renders unblurred. */
    (void) radius;
}

@end

'''

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F75" in s:
    print("already patched")
    sys.exit(0)
if s.count(ANCHOR) < 1:
    print(f"FATAL: anchor '{ANCHOR}' not found", file=sys.stderr)
    sys.exit(1)

s = s.replace(ANCHOR, ADDITION + ANCHOR, 1)
P.write_text(s)
print(f"patched {P}: disableBlur/enableBlur: no longer fatal (explicitly unsupported)")
