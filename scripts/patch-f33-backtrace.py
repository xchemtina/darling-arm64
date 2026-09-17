#!/usr/bin/env python3
"""
DARLING-ARM64 DIAGNOSTIC for FINDINGS.md F33. Idempotent. Run from ~/darling/source.

The arm64 SIGSEGV handler prints one line of registers and nothing else, so every
arm64 crash in this project has been read off `pc`, `lr` and a fault address. That
was enough to *suspect* unbounded recursion in F33 -- `lr == caller_lr`, fault
address 0xD0 below `fp`, no program output at all -- but not to establish it.

This walks the frame-pointer chain and prints it. On AArch64 the frame record is:

    [fp + 0]  caller fp
    [fp + 8]  saved lr

so the chain is trivially walkable, and a repeating `lr` is a direct read-out of
recursion rather than an inference from two registers.

SAFETY. This runs inside a signal handler, on a stack that has just faulted, so it
must not fault again. The walk is bounded to 24 frames and each step requires:
  * a non-NULL, 16-byte-aligned fp (the AArch64 AAPCS requirement);
  * a caller fp strictly greater than the current one -- the stack grows down, so
    caller frames sit at higher addresses. This also terminates on a cycle.
The existing code already dereferences `frame[1]` with no checks at all, so this
strictly reduces the risk that was already being taken.

NOTE (STATE.md trap 16): sigexc.c is compiled into libsystem_kernel.dylib *and*
statically into mldr and /usr/lib/dyld. Rebuild all of them, or the change will
appear to have no effect -- the signature being a fault address that does not move.

Revert with: cd src/external/xnu && git checkout -- \\
  darling/src/libsystem_kernel/emulation/src/linux_premigration/signal/sigexc.c
"""
import sys, pathlib

P = pathlib.Path("src/external/xnu/darling/src/libsystem_kernel/emulation/"
                 "src/linux_premigration/signal/sigexc.c")

ANCHOR = """			(void*)ctxt->uc_mcontext.gregs.regs[21],
			(void*)ctxt->uc_mcontext.gregs.regs[22]);
	}
"""

NEW = """			(void*)ctxt->uc_mcontext.gregs.regs[21],
			(void*)ctxt->uc_mcontext.gregs.regs[22]);

		/* DARLING-ARM64 DIAGNOSTIC (FINDINGS.md F33): walk the frame chain.
		 *
		 * One line of registers is not enough to tell unbounded recursion from a
		 * wild pointer, and that distinction has been guessed at more than once.
		 * On AArch64 the frame record is [fp+0]=caller fp, [fp+8]=saved lr, so a
		 * repeating lr below is recursion, read directly rather than inferred.
		 *
		 * This runs on a stack that has just faulted, so it must not fault again:
		 * bounded to 24 frames, and each step requires a non-NULL 16-byte-aligned
		 * fp (AAPCS) whose caller fp is strictly higher (the stack grows down),
		 * which also terminates on a cycle. */
		{
			uintptr_t* walk = frame;
			for (int depth = 0; depth < 24; depth++) {
				if (walk == NULL || (((uintptr_t)walk) & 0xF) != 0)
					break;
				uintptr_t next_fp = walk[0];
				uintptr_t saved_lr = walk[1];
				__simple_printf("  frame %d: fp=%p lr=%p\\n",
					depth, (void*)walk, (void*)saved_lr);
				if (next_fp <= (uintptr_t)walk)
					break;
				walk = (uintptr_t*)next_fp;
			}
		}
	}
"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "walk the frame chain" in s:
    print("already patched")
    sys.exit(0)
if s.count(ANCHOR) != 1:
    print(f"FATAL: anchor found {s.count(ANCHOR)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(ANCHOR, NEW, 1))
print(f"patched {P}: arm64 SIGSEGV now prints a frame-chain backtrace")
