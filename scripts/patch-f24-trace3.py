#!/usr/bin/env python3
"""
DARLING-ARM64 TEMPORARY DIAGNOSTIC #3 for FINDINGS.md F24. Idempotent.
Run from ~/darling/source. Requires traces #1 and #2.

Killed so far:
  * modal guard swallowing the event  -- it does not (trace #1)
  * coordinate/geometry mismatch      -- coordinates are correct (trace #2:
    modal raw=(80,60) -> transformed=(80,40) inside a 240x100 frame)

Remaining likely cause: the sheet never becomes key, so NSApplication's
-sendEvent: does not route the mouse event into its content view. This adds
isKeyWindow / isVisible to the per-ButtonPress trace.
"""
import sys, pathlib

P = pathlib.Path("src/external/cocotron/AppKit/X11.backend/X11Display.m")
FMT_OLD = 'frame=(%.1f,%.1f,%.1fx%.1f) title='
FMT_NEW = 'frame=(%.1f,%.1f,%.1fx%.1f) key=%d vis=%d title='
ARG_OLD = "(double) dbgFrame.size.width, (double) dbgFrame.size.height,\n                    delegate ?"
ARG_NEW = ("(double) dbgFrame.size.width, (double) dbgFrame.size.height,\n"
           "                    (int) [delegate isKeyWindow], (int) [delegate isVisible],\n"
           "                    delegate ?")

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "key=%d" in s:
    print("already patched"); sys.exit(0)
for needle, label in ((FMT_OLD, "format string"), (ARG_OLD, "argument list")):
    if needle not in s:
        print(f"FATAL: anchor not found ({label})", file=sys.stderr); sys.exit(1)
s = s.replace(FMT_OLD, FMT_NEW, 1).replace(ARG_OLD, ARG_NEW, 1)
P.write_text(s)
print("added isKeyWindow/isVisible to trace")
