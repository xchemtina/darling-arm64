#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F72. Idempotent. Run from ~/darling/source.

DIAGNOSIS
---------
Unmodified iTerm2 3.6.11 terminates during window creation with:

    *** Terminating app due to uncaught exception 'NSRangeException',
        reason: '-[__NSArrayM objectAtIndex:]: index 0 beyond bounds for empty array'

The first-throw stack names the site exactly (Darling frames are 0x300..., Apple's
shared-cache frames are 0x180...):

     3  AppKit    -[NSMenu itemAtIndex:] + 48                    <- Darling
     4  AppKit    -[NSPopUpButtonCell itemAtIndex:] + 56         <- Darling
     5  AppKit    -[NSPopUpButton setTitle:] + 84                <- Darling
     6  iTerm2    -[PSMOverflowPopUpButton initWithFrame:pullsDown:] + 104
     7  iTerm2    -[PSMTabBarControl setupButtons] + 244
    ...
    11  iTerm2    -[PseudoTerminal finishInitializationWithSmartLayout:...]
    19  iTerm2    -[iTermUntitledWindowStateMachine openWindowIfWanted] + 364

`NSPopUpButton.m:200`:

    - (void) setTitle: (NSString *) title {
        if ([self pullsDown]) {
            // The title gets stored in the zero index item in the menu - it made
            // sense to Apple at some point...
            [[_cell itemAtIndex: 0] setTitle: title];
            [self synchronizeTitleAndSelectedItem];
        } else {
            [super setTitle: title];
        }
    }

iTerm2 constructs `PSMOverflowPopUpButton` as a **pull-down** button and calls
`setTitle:` on it immediately, while its menu is still **empty**. `itemAtIndex:0` on
an empty menu raises `NSRangeException`, nothing catches it, and the application
terminates before its first window exists.

macOS does not throw here. Setting a title on a pull-down with no items is ordinary,
and AppKit tolerates it.

THE FIX
-------
Guard the empty case and create the item the pull-down title is supposed to live in,
which is what the surrounding comment already says the zero-index item is for. When
items exist, behaviour is unchanged.

Note the *cell* already does the equivalent thing on its non-pull-down path
(`NSPopUpButtonCell.m:440`): `itemWithTitle:` and, if absent, `addItemWithTitle:`.
This makes the button's pull-down path equally defensive rather than inventing a new
policy.

WHY NOT JUST RETURN EARLY: silently dropping the title would leave the button with no
item and no title, so the next `synchronizeTitleAndSelectedItem` would still have
nothing to show. Creating the item preserves the caller's intent, which is the whole
point of the method.

Revert with: cd src/external/cocotron && git checkout -- AppKit/NSPopUpButton.m
"""
import sys, pathlib

P = pathlib.Path("src/external/cocotron/AppKit/NSPopUpButton.m")

OLD = """- (void) setTitle: (NSString *) title {
    if ([self pullsDown]) {
        // The title gets stored in the zero index item in the menu - it made
        // sense to Apple at some point...
        [[_cell itemAtIndex: 0] setTitle: title];
        [self synchronizeTitleAndSelectedItem];
    } else {
        [super setTitle: title];
    }
}"""

NEW = """- (void) setTitle: (NSString *) title {
    if ([self pullsDown]) {
        // The title gets stored in the zero index item in the menu - it made
        // sense to Apple at some point...
        /* DARLING-ARM64 FIX (FINDINGS.md F72): this called -itemAtIndex:0
         * unguarded. A pull-down button whose menu is still empty therefore raised
         * NSRangeException, and since nothing catches it the whole application
         * terminated. Unmodified iTerm2 hits this during window creation --
         * PSMOverflowPopUpButton is built as a pull-down and its title is set
         * before any item exists -- so iTerm2 died before showing a window.
         *
         * macOS does not throw here. Creating the item the title is meant to
         * occupy preserves the caller's intent; the cell already does the
         * equivalent on its non-pull-down path (NSPopUpButtonCell.m:440), so this
         * is the existing policy applied consistently rather than a new one. */
        if ([_cell numberOfItems] == 0) {
            [_cell addItemWithTitle: (title != nil) ? title : @""];
        } else {
            [[_cell itemAtIndex: 0] setTitle: title];
        }
        [self synchronizeTitleAndSelectedItem];
    } else {
        [super setTitle: title];
    }
}"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F72" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: anchor found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: setTitle: no longer throws on an empty pull-down menu")
