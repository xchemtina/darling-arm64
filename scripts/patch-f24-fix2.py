#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F24, second attempt. Idempotent.
Run from ~/darling/source.

WHY THE FIRST FIX DID NOT WORK
------------------------------
The first attempt appended `[sheet makeKeyWindow]` to
-_attachSheetContextOrderFrontAndAnimate:. The sheet still reported key=0.
Reading Cocotron's implementation explains exactly why -- no tracing needed:

  NSWindow.m:1621  - (BOOL) isKeyWindow  { return [NSApp keyWindow] == self; }
  NSWindow.m:1848  - (void) makeKeyWindow { [[self platformWindow] makeKey]; ... }
  NSWindow.m:1876  - (void) becomeKeyWindow { [self makeKeyWindow];
                                              [NSApp _setKeyWindow: self]; ... }
  X11Window.m:559  - (void) makeKey { [self ensureMapped]; XRaiseWindow(...); }

`-[NSApp _setKeyWindow:]` is called from exactly ONE site in NSWindow.m (line
1889) and that site is inside -becomeKeyWindow. So in Cocotron the naming is
inverted relative to real AppKit: -makeKeyWindow only pokes the platform window
(map + raise), while -becomeKeyWindow is the method that performs the actual
key-window state transition. Calling -makeKeyWindow can therefore never change
what -isKeyWindow returns. The first fix raised the sheet's X window and
recalculated its key-view loop, and that was all it did.

THE FIX
-------
Call -becomeKeyWindow instead. It calls -makeKeyWindow itself (so the map+raise
still happens), then sets NSApp's key window, resigns the previous one and posts
NSWindowDidBecomeKeyNotification.

SEPARATE, RELATED DEFECT (not changed here -- one variable at a time)
--------------------------------------------------------------------
  NSWindow.m:1641  - (BOOL) canBecomeKeyWindow {
                         return (_styleMask & (NSTitledWindowMask |
                                               NSResizableWindowMask)) != 0; }
  NSPanel.h:24     NSDocModalWindowMask = 0x40
  NSWindow.m:3066  [sheet setStyleMask: NSDocModalWindowMask];   // exactly 0x40

0x40 & (0x01 | 0x08) == 0, so -canBecomeKeyWindow is NO for every sheet. The
generic activation paths that are guarded by it -- -makeKeyAndOrderFront: (2700)
and -_windowDidBecomeActive (3130) -- will therefore refuse to make a sheet key.
On macOS a document-modal sheet IS key while presented. That predicate looks
wrong, but changing it moves a second variable, so it is recorded in FINDINGS.md
and left alone until this change is measured on its own.

Revert with: git checkout -- src/external/cocotron
"""
import sys, pathlib

P = pathlib.Path("src/external/cocotron/AppKit/NSWindow.m")

OLD = """    /* DARLING-ARM64 FIX (FINDINGS.md F24): this made the PARENT key, leaving the
     * sheet non-key. AppKit does not route mouse events into a non-key window, so
     * every click on a sheet was silently dropped. macOS makes the sheet key when
     * it is presented. */
    [sheet makeKeyWindow];
"""

NEW = """    /* DARLING-ARM64 FIX (FINDINGS.md F24): -sheetOrderFrontFromFrame:aboveWindow:
     * makes the PARENT key, leaving the sheet non-key, and AppKit does not route
     * mouse events into a non-key window -- so every click on a sheet was dropped.
     * macOS makes a document-modal sheet key while it is presented.
     *
     * This must be -becomeKeyWindow, NOT -makeKeyWindow. Cocotron inverts the
     * usual AppKit naming: -makeKeyWindow (NSWindow.m:1848) only forwards to
     * -[X11Window makeKey], which is ensureMapped + XRaiseWindow, whereas
     * -becomeKeyWindow (NSWindow.m:1876) is the only caller of
     * -[NSApplication _setKeyWindow:] and hence the only thing that can change
     * what -isKeyWindow reports. -becomeKeyWindow calls -makeKeyWindow itself, so
     * the map-and-raise still happens. */
    [sheet becomeKeyWindow];
"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "[sheet becomeKeyWindow];" in s:
    print("already patched"); sys.exit(0)
if OLD not in s:
    print("FATAL: first-attempt block not found verbatim", file=sys.stderr); sys.exit(1)
P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: [sheet makeKeyWindow] -> [sheet becomeKeyWindow]")
