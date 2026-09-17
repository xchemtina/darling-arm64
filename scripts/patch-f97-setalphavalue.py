#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F97. Idempotent.
Run from ~/darling/source/src/external/cocotron.

DIAGNOSIS
---------
CoreGraphics/CGWindow.m declares -setAlphaValue: (and -setOpaque:, -setHasShadow:)
as abstract: the body is O2InvalidAbstractInvocation(). The concrete X11 backend,
AppKit/X11.backend/X11Window.m, overrides -setOpaque: and -setHasShadow: but NOT
-setAlphaValue:. Any code path that sends -setAlphaValue: to a window therefore
hits the abstract trap and the app terminates:

    *** Terminating app due to uncaught exception 'NSInvalidArgumentException',
        reason: '-setAlphaValue: only defined for abstract class.
                 Define -[X11Window setAlphaValue:] in .../CGWindow.m:86!'

Kevin's Jul 14-16 tail (merged into north-star/gap-integration) introduced such a
path, so unmodified iTerm2 dies at launch on his latest tree (FINDINGS.md F91). The
reviewed branch does not hit it, which is why it went unnoticed there.

THE FIX
-------
Implement -setAlphaValue: as a real backend method: set the EWMH
_NET_WM_WINDOW_OPACITY property on the X11 window (a CARDINAL, 0xFFFFFFFF * alpha),
exactly the mechanism a compositing WM reads for per-window opacity. Where the WM
does not composite (e.g. openbox in the probe) the property is simply ignored --
which is correct: the postcondition "the window's requested opacity is recorded on
the server" holds regardless, and the abstract trap, the actual launch blocker, is
gone. This mirrors the file's existing use of XChangeProperty/XInternAtom (line
148) and sits beside the sibling -setOpaque: override.

Revert: cd src/external/cocotron && git checkout -- AppKit/X11.backend/X11Window.m
"""
import sys, pathlib

P = pathlib.Path("AppKit/X11.backend/X11Window.m")

ANCHOR = """- (void) setOpaque: (BOOL) value {
    _isOpaque = value;
}"""

ADDITION = ANCHOR + """

/* DARLING-ARM64 FIX (FINDINGS.md F97): -setAlphaValue: is abstract in CGWindow.m
 * and was not overridden by the X11 backend, so any caller crashed the app with
 * "only defined for abstract class". Kevin's Jul 14-16 tail added such a caller,
 * killing unmodified iTerm2 at launch. Implement it against the standard EWMH
 * per-window opacity property; a non-compositing WM ignores it harmlessly, and the
 * abstract trap -- the launch blocker -- is cleared. */
- (void) setAlphaValue: (CGFloat) value {
    if (value < 0.0) value = 0.0;
    if (value > 1.0) value = 1.0;
    unsigned long opacity = (unsigned long)(value * 0xFFFFFFFFUL);
    XChangeProperty(
            _display, _window,
            XInternAtom(_display, "_NET_WM_WINDOW_OPACITY", False),
            XA_CARDINAL, 32, PropModeReplace,
            (unsigned char *) &opacity, 1);
}"""

if not P.exists():
    print(f"FATAL: missing {P} (run from the cocotron submodule root)", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F97" in s:
    print("already patched")
    sys.exit(0)
if s.count(ANCHOR) != 1:
    print(f"FATAL: anchor found {s.count(ANCHOR)}x (want 1)", file=sys.stderr)
    sys.exit(1)
if "setAlphaValue" in s:
    print("FATAL: setAlphaValue already present unexpectedly; inspect before patching", file=sys.stderr)
    sys.exit(1)

# XA_CARDINAL comes from <X11/Xatom.h>; ensure it is included.
if "Xatom.h" not in s:
    # insert after the first #import/#include block that mentions X11
    import re
    m = re.search(r'#(import|include)\s*[<"][^>"]*[Xx]11[^>"]*[>"]', s)
    if m:
        line_end = s.index("\n", m.end()) + 1
        s = s[:line_end] + "#include <X11/Xatom.h>\n" + s[line_end:]
    else:
        s = "#include <X11/Xatom.h>\n" + s
    print("added #include <X11/Xatom.h>")

s = s.replace(ANCHOR, ADDITION, 1)
P.write_text(s)
print(f"patched {P}: -[X11Window setAlphaValue:] now overrides the abstract method")
