#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F37. Idempotent. Run from ~/darling/source.

THE DEFECT
----------
`sys_abort_with_payload` prints its message, signals itself, and then **returns**:

    long sys_abort_with_payload(...)
    {
        __simple_printf("abort_with_payload: reason: %s; code: %lu\\n", ...);
        sys_kill(sys_getpid(), SIGABRT, 1);
        return 0;
    }

But `abort_with_payload` is declared `noreturn`, and dyld relies on that. `halt()`
(`dyld2.cpp:4545`) ends with the call and nothing after it, so the compiler emits no
epilogue and no return. When the syscall returns anyway, execution falls off the end
of the function into whatever bytes follow.

That is why every loader failure ends in a segfault instead of a clean error:

    abort_with_payload: reason: dyld: No shared cache present
    Library not loaded: /usr/lib/libxo.dylib
    unhandled ARM64 SIGSEGV pc=... address=0x39

Observed in two independent cases, which is what identifies it as a property of the
abort path rather than of either cause:

  F28  missing symbol  _OBJC_CLASS_$_NSConstantIntegerNumber  -> SIGSEGV address=0x97
  F36  missing library /usr/lib/libxo.dylib                   -> SIGSEGV address=0x39

Both fault addresses are small offsets from NULL, consistent with running off into
unmapped memory rather than with a wild pointer.

WHY THE SIGNAL DOES NOT STOP IT
-------------------------------
`__simple_abort()` (`simple.c:580`) issues the same `sys_kill(SIGABRT)` and follows
it with `__builtin_unreachable()`, so the same assumption is made there. Darling
installs `sigexc_handler` for the Mach exception machinery, so SIGABRT is caught
rather than fatal, and control returns to the caller.

THE FIX
-------
Guarantee the function never returns. `sys_kill` is kept first so that any Mach
exception / crash-reporting path still observes an abort; `sys_exit` then makes
termination unconditional. 128+SIGABRT (134) is the shell convention for death by
SIGABRT, so the exit status stays recognisable.

This is not arm64-specific in its cause, but it is arm64 where it was observed, and
it costs every future loader diagnosis: a truthful "Library not loaded" exit is far
easier to act on than a segfault that buries it.

Revert with: cd src/external/xnu && git checkout -- \\
  darling/src/libsystem_kernel/emulation/src/xnu_syscall/bsd/impl/misc/abort_with_payload.c
"""
import sys, pathlib

P = pathlib.Path("src/external/xnu/darling/src/libsystem_kernel/emulation/"
                 "src/xnu_syscall/bsd/impl/misc/abort_with_payload.c")

OLD = """	__simple_printf("abort_with_payload: reason: %s; code: %lu\\n", reason_string, reason_code);
	sys_kill(sys_getpid(), SIGABRT, 1);
	return 0;
}"""

NEW = """	__simple_printf("abort_with_payload: reason: %s; code: %lu\\n", reason_string, reason_code);
	sys_kill(sys_getpid(), SIGABRT, 1);

	/* DARLING-ARM64 FIX (FINDINGS.md F37): this must NOT return.
	 *
	 * abort_with_payload is declared noreturn and dyld depends on it: halt()
	 * (dyld2.cpp:4545) ends with the call and emits no epilogue, so returning
	 * falls off the end of the function into unmapped memory. Every loader
	 * failure therefore ended in "unhandled ARM64 SIGSEGV" instead of the
	 * message printed just above -- seen with both a missing symbol (F28) and a
	 * missing library (F36).
	 *
	 * The sys_kill above is kept first so any Mach-exception path still sees an
	 * abort, but SIGABRT is caught by sigexc_handler rather than being fatal, so
	 * it cannot be relied on to terminate. 128+SIGABRT is the shell convention
	 * for death by SIGABRT, which keeps the exit status recognisable. */
	sys_exit(128 + SIGABRT);
	__builtin_unreachable();
}"""

INCLUDE_OLD = "#include <darling/emulation/xnu_syscall/bsd/impl/unistd/getpid.h>\n"
INCLUDE_NEW = ("#include <darling/emulation/xnu_syscall/bsd/impl/unistd/getpid.h>\n"
               "#include <darling/emulation/xnu_syscall/bsd/impl/unistd/exit.h>\n")

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F37" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: body found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)
if s.count(INCLUDE_OLD) != 1:
    print(f"FATAL: getpid include found {s.count(INCLUDE_OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

s = s.replace(INCLUDE_OLD, INCLUDE_NEW, 1).replace(OLD, NEW, 1)
P.write_text(s)
print(f"patched {P}: abort_with_payload no longer returns to its caller")
