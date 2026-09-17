#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F24. Idempotent. Run from ~/darling/source.

src/external/cocotron/AppKit/NSWindow.m
-_attachSheetContextOrderFrontAndAnimate: presents a sheet and then calls

    [self makeKeyWindow];

`self` is the PARENT window (the method is invoked as
`[window _attachSheetContextOrderFrontAndAnimate: context]` from
NSApplication -beginSheet:modalForWindow:...). So presenting a sheet makes the
*parent* key and leaves the sheet non-key.

Evidence (per-ButtonPress trace in the X11 backend):
    main  window: key=1 vis=1  -> -mouseDown: fires
    sheet/panel : key=0 vis=1  -> -mouseDown: never fires

AppKit will not route mouse input into a window that is not key, so every click on
a sheet was dropped after being correctly delivered to the window layer. On macOS,
presenting a sheet makes the sheet key.

Fix: make the sheet key, not its parent.
"""
import sys, pathlib

P = pathlib.Path("src/external/cocotron/AppKit/NSWindow.m")
OLD = """    [[sheet platformWindow] sheetOrderFrontFromFrame: sheetFrame
                                         aboveWindow: [self platformWindow]];
    [self makeKeyWindow];"""
NEW = """    [[sheet platformWindow] sheetOrderFrontFromFrame: sheetFrame
                                         aboveWindow: [self platformWindow]];
    /* DARLING-ARM64 FIX (FINDINGS.md F24): this made the PARENT key, leaving the
     * sheet non-key. AppKit does not route mouse events into a non-key window, so
     * every click on a sheet was silently dropped. macOS makes the sheet key when
     * it is presented. */
    [sheet makeKeyWindow];"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "FINDINGS.md F24" in s:
    print("already patched"); sys.exit(0)
if OLD not in s:
    print("FATAL: anchor not found", file=sys.stderr); sys.exit(1)
P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: sheet is now made key on presentation")
