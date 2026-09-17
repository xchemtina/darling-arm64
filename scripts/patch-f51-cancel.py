#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F51. Idempotent. Run from ~/darling/source.

THE DEFECT
----------
An NSOperation cancelled before it starts **executes anyway**, and the queue never
reports itself drained. Measured by t26_operation against real macOS:

    assertion                        macOS   Darling
    cancelled operation ran            0        1
    cancelled operation ran (2nd)      0        1
    queue drained                      0        1
    queue empty afterwards             0        1

Cancelling work is the main reason to use an operation queue, so this is functional
rather than cosmetic.

CAUSE
-----
`-start` (NSOperation.m:262) checks `isExecuting` and `isReady` before invoking
`main`, but never checks `isCancelled`. Apple's contract is explicit: starting a
cancelled operation must move it directly to finished **without running main**. The
`_cancelled` flag and its KVO notifications already exist (lines 61, 179-203) --
nothing consumed them on this path.

THE FIX
-------
Check `isCancelled` after the readiness checks and before the executing transition,
and take the operation straight to finished with the same KVO notifications the
normal completion path emits. Emitting them matters: `NSOperationQueue` observes
`isFinished` to drain, which is why the queue also stayed non-empty.

Revert with: cd src/external/foundation && git checkout -- src/NSOperation.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSOperation.m")

OLD = """        if (![_operation isReady])
        {
            [NSException raise:NSInvalidArgumentException format:@"Operation is not ready"];
            [_operation release];
            return;
        }

        if (_state != NSOperationStateExecuting)
"""

NEW = """        if (![_operation isReady])
        {
            [NSException raise:NSInvalidArgumentException format:@"Operation is not ready"];
            [_operation release];
            return;
        }

        /* DARLING-ARM64 FIX (FINDINGS.md F51): a cancelled operation must NOT run.
         *
         * This check was absent, so an operation cancelled before it started
         * executed anyway -- and because the finish notification never fired, the
         * queue never drained either (NSOperationQueue observes isFinished).
         * Apple's contract: -start on a cancelled operation moves it straight to
         * finished without invoking -main. The KVO notifications below mirror the
         * normal completion path exactly, which is what lets the queue notice. */
        if ([_operation isCancelled])
        {
            [_operation willChangeValueForKey:@"isFinished"];
            _state = NSOperationStateFinished;
            [_operation didChangeValueForKey:@"isFinished"];
            [_operation release];
            return;
        }

        if (_state != NSOperationStateExecuting)
"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F51" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: anchor found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: -start now honours isCancelled")
