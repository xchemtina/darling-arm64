#!/usr/bin/env python3
"""
DARLING-ARM64 TEMPORARY DIAGNOSTIC for FINDINGS.md F24. Idempotent.
Run from ~/darling/source.

Hypothesis: clicks aimed at the sheet land on an X window that is NOT registered
in X11Display's _windowsByID, so `windowForID:` returns nil, `delegate` is nil, and
`case ButtonPress:` posts an NSEvent with `window: nil` -- which goes nowhere.

Why that is plausible:
  * X11SubWindow.m creates a real X child window (XCreateSimpleWindow) but never
    calls -setWindow:forID:, whereas X11Window.m registers itself at line 257.
  * NSView.m:1276 and :1961 create sub-windows for layer-backed views
    ([_layerContext setSubwindow: [_window _createSubWindowWithFrame: ...]]).

This logs one line per ButtonPress with everything needed to confirm or refute:
the XID, whether it resolved, the delegate's title, its attachedSheet, and
[NSApp modalWindow]. Remove once F24 is understood.
"""
import sys, pathlib

P = pathlib.Path("src/external/cocotron/AppKit/X11.backend/X11Display.m")
ANCHOR = """    if (ev->type == KeyPress || ev->type == KeyRelease ||
        ev->type == ButtonPress || ev->type == ButtonRelease ||
        ev->type == MotionNotify) {"""

TRACE = """    /* DARLING-ARM64 TEMPORARY DIAGNOSTIC (FINDINGS.md F24) */
    if (ev->type == ButtonPress) {
        NSWindow *dbgSheet = [delegate attachedSheet];
        fprintf(stderr,
                "[F24] ButtonPress xid=0x%lx resolved=%s title='%s' "
                "attachedSheet=%s modalWindow=%s\\n",
                (unsigned long) ev->xany.window,
                window ? "YES" : "NO(unregistered)",
                delegate ? [[delegate title] UTF8String] ?: "(nil title)" : "(nil delegate)",
                dbgSheet ? [[dbgSheet title] UTF8String] ?: "(untitled)" : "nil",
                [NSApp modalWindow] ? [[[NSApp modalWindow] title] UTF8String] ?: "(untitled)" : "nil");
        fflush(stderr);
    }

""" + ANCHOR

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "[F24] ButtonPress" in s:
    print("already patched"); sys.exit(0)
if ANCHOR not in s:
    print("FATAL: anchor not found", file=sys.stderr); sys.exit(1)
P.write_text(s.replace(ANCHOR, TRACE, 1))
print(f"patched {P}")
