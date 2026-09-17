#!/usr/bin/env python3
"""
DARLING-ARM64 TRACE for FINDINGS.md F24, fourth attempt. Idempotent.
Run from ~/darling/source.

WHY THIS ONE SHOULD WORK WHEN THE EARLIER ONES DIDN'T
-----------------------------------------------------
Attempts 1-3 used fprintf(stderr, ...) and were read through a verifier that
discarded application output entirely -- the whole run log was three lines. That
is fixed (scripts/80-make-gui-observable.py): stage11-smoke.out and .err are now
copied to /artifacts by the cleanup EXIT trap, and stage11-smoke.out is confirmed
to contain the backend's own NSLog stream (MappingNotify, EnterNotify, FocusIn,
...). So this trace uses NSLog and lands in a file we can actually read.

WHAT IT ANSWERS
---------------
A ButtonPress on the sheet has to survive three hops. Each hop gets one line:

  [F24/x]  X11Display -postXEvent:      did the X event arrive, did windowForID:
                                        resolve it, whose window is it, is that
                                        window key, and did the attachedSheet
                                        guard swallow it?
  [F24/a]  NSApplication -sendEvent:    did the queued NSEvent come back out of
                                        the run loop, and with which window?
  [F24/w]  NSWindow -sendEvent:         did it reach the target window, and what
                                        did -hitTest: find at that point?

Whichever [F24/...] line is missing names the hop that drops the click. If all
three appear and hitTest returns NorthStarModalView, then the click is delivered
and the defect is in the marker write instead.

Revert with: git checkout -- src/external/cocotron
"""
import sys, pathlib

EDITS = []

# ---- hop 1: X11Display -postXEvent: -------------------------------------------
EDITS.append((
    "src/external/cocotron/AppKit/X11.backend/X11Display.m",
    """    if (ev->type == KeyPress || ev->type == KeyRelease ||
        ev->type == ButtonPress || ev->type == ButtonRelease ||
        ev->type == MotionNotify) {
        NSWindow *sheet = [delegate attachedSheet];
        if (sheet != nil || [delegate platformWindowIgnoreModalMessages:window]) {
            NSWindow *modalWindow = sheet != nil ? sheet : [NSApp modalWindow];
            [modalWindow makeKeyAndOrderFront:delegate];
            return;
        }
    }
""",
    """    if (ev->type == KeyPress || ev->type == KeyRelease ||
        ev->type == ButtonPress || ev->type == ButtonRelease ||
        ev->type == MotionNotify) {
        NSWindow *sheet = [delegate attachedSheet];
        /* DARLING-ARM64 TRACE (FINDINGS.md F24) */
        if (ev->type == ButtonPress) {
            NSLog(@"[F24/x] xid=0x%lx resolved=%d title='%@' sheet='%@' "
                  @"key=%d modal='%@' appKey='%@' swallow=%d",
                  (unsigned long) ev->xany.window, window != nil,
                  [delegate title], [sheet title],
                  (int) [delegate isKeyWindow], [[NSApp modalWindow] title],
                  [[NSApp keyWindow] title],
                  (int) (sheet != nil ||
                         [delegate platformWindowIgnoreModalMessages:window]));
        }
        if (sheet != nil || [delegate platformWindowIgnoreModalMessages:window]) {
            NSWindow *modalWindow = sheet != nil ? sheet : [NSApp modalWindow];
            [modalWindow makeKeyAndOrderFront:delegate];
            return;
        }
    }
""",
))

# ---- hop 2: NSApplication -sendEvent: -----------------------------------------
EDITS.append((
    "src/external/cocotron/AppKit/NSApplication.m",
    """- (void) sendEvent: (NSEvent *) event {
    if ([event type] == NSKeyDown) {
""",
    """- (void) sendEvent: (NSEvent *) event {
    /* DARLING-ARM64 TRACE (FINDINGS.md F24) */
    if ([event type] == NSLeftMouseDown) {
        NSLog(@"[F24/a] NSLeftMouseDown window='%@' loc=%@",
              [[event window] title],
              NSStringFromPoint([event locationInWindow]));
    }
    if ([event type] == NSKeyDown) {
""",
))

# ---- hop 3: NSWindow -sendEvent: ----------------------------------------------
EDITS.append((
    "src/external/cocotron/AppKit/NSWindow.m",
    """    case NSLeftMouseDown: {
        NSView *view = [_backgroundView hitTest: [event locationInWindow]];

        if ([view acceptsFirstResponder]) {
""",
    """    case NSLeftMouseDown: {
        NSView *view = [_backgroundView hitTest: [event locationInWindow]];

        /* DARLING-ARM64 TRACE (FINDINGS.md F24) */
        NSLog(@"[F24/w] window='%@' key=%d loc=%@ hit=%@", [self title],
              (int) [self isKeyWindow],
              NSStringFromPoint([event locationInWindow]),
              NSStringFromClass([view class]));

        if ([view acceptsFirstResponder]) {
""",
))

# ---- also: did -becomeKeyWindow actually take? ---------------------------------
EDITS.append((
    "src/external/cocotron/AppKit/NSWindow.m",
    """    [sheet becomeKeyWindow];
""",
    """    [sheet becomeKeyWindow];
    /* DARLING-ARM64 TRACE (FINDINGS.md F24) */
    NSLog(@"[F24/k] after becomeKeyWindow: sheet='%@' sheetKey=%d appKey='%@' "
          @"canBecomeKey=%d styleMask=0x%lx",
          [sheet title], (int) [sheet isKeyWindow], [[NSApp keyWindow] title],
          (int) [sheet canBecomeKeyWindow], (unsigned long) [sheet styleMask]);
""",
))

changed = 0
for rel, old, new in EDITS:
    p = pathlib.Path(rel)
    if not p.exists():
        print(f"FATAL: missing {p}", file=sys.stderr); sys.exit(1)
    s = p.read_text()
    if new in s:
        print(f"  already patched: {p}")
        continue
    if s.count(old) != 1:
        print(f"FATAL: anchor found {s.count(old)}x (want 1) in {p}",
              file=sys.stderr)
        sys.exit(1)
    p.write_text(s.replace(old, new, 1))
    print(f"  traced: {p}")
    changed += 1

print(f"done ({changed} file(s) changed)")
