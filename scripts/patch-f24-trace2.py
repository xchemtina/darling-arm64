#!/usr/bin/env python3
"""
DARLING-ARM64 TEMPORARY DIAGNOSTIC #2 for FINDINGS.md F24. Idempotent.
Run from ~/darling/source. Requires patch-f24-trace.py to have been applied first.

Established so far by trace #1:
  * the modal (an NSPanel shown via -beginSheet:modalForWindow:) IS resolved by
    -windowForID: and its ButtonPress is NOT swallowed by the modal guard;
  * modal blocking of the PARENT works correctly (parent click is swallowed);
  * -mouseDown: works on the main window's view (verifier line 261 asserts the
    marker is non-empty and that assertion passes).

So the event reaches the panel's NSWindow but never reaches its content view.
Leading hypothesis: the sheet's AppKit frame disagrees with the geometry the X
server/WM actually gave the transient window, so the converted point misses the
content view during hit-testing.

This prints the raw X coordinates, the transformed AppKit point, and the window's
frame, for every ButtonPress -- enough to confirm or kill that hypothesis.
"""
import sys, pathlib

P = pathlib.Path("src/external/cocotron/AppKit/X11.backend/X11Display.m")
ANCHOR = """        pos = [window
                transformPoint: NSMakePoint(ev->xbutton.x, ev->xbutton.y)];
"""
TRACE = ANCHOR + """        /* DARLING-ARM64 TEMPORARY DIAGNOSTIC (FINDINGS.md F24 trace #2) */
        {
            NSRect dbgFrame = [delegate frame];
            fprintf(stderr,
                    "[F24b] raw=(%d,%d) transformed=(%.1f,%.1f) "
                    "frame=(%.1f,%.1f,%.1fx%.1f) title='%s'\\n",
                    ev->xbutton.x, ev->xbutton.y, (double) pos.x, (double) pos.y,
                    (double) dbgFrame.origin.x, (double) dbgFrame.origin.y,
                    (double) dbgFrame.size.width, (double) dbgFrame.size.height,
                    delegate ? [[delegate title] UTF8String] ?: "(nil)" : "(nil delegate)");
            fflush(stderr);
        }
"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "[F24b]" in s:
    print("already patched"); sys.exit(0)
if ANCHOR not in s:
    print("FATAL: anchor not found", file=sys.stderr); sys.exit(1)
P.write_text(s.replace(ANCHOR, TRACE, 1))
print(f"patched {P} with trace #2")
