#!/usr/bin/env python3
"""
DARLING-ARM64 DIAGNOSTIC for FINDINGS.md F27. Idempotent. Run from ~/darling/source.

TextEdit dies on Cmd-S with a SIGSEGV at a near-null address, and the frame-chain
walk added for F33 now prints a 24-frame backtrace -- but as raw runtime addresses:

    unhandled ARM64 SIGSEGV pc=0x300E68008 lr=0x300ADBCFC address=0x7
      frame 0: fp=0xFFFFF3CF0 lr=0x300AD90D8
      frame 1: fp=0xFFFFF3D50 lr=0x300ADC2CC
      ...

Symbolising those needs each image's load base, and the base is randomised per run,
so it has to come from the **same run** as the crash. `DYLD_PRINT_SEGMENTS=1` makes
dyld print `__TEXT at 0x...` per image; both then land in stage15-save.out together
and the offsets can be looked up with `nm -n` on the staged dylib (STATE.md trap 18,
which turned an F33 address into `_CFStringGetCharacters + 0x10` in ten minutes).

Scoped to the save phase only -- the launch and reopen phases are unaffected, so the
extra output does not obscure them.

Revert with: cd ~/darling/source && git checkout -- tools/verify-text-edit-darling-arm64.sh
             (note: this also drops the ERR-trap diagnostic and log preservation;
              re-apply scripts/patch-verifier-diag.py afterwards)
"""
import sys, pathlib

P = pathlib.Path("tools/verify-text-edit-darling-arm64.sh")

OLD = """		export DSERVER_INIT=/Applications/TextEdit.app/Contents/MacOS/TextEdit
		unset DARLING_EXEC_PATH DARLING_EXEC_ARG1 DARLING_EXEC_ARG2
"""

NEW = """		export DSERVER_INIT=/Applications/TextEdit.app/Contents/MacOS/TextEdit
		unset DARLING_EXEC_PATH DARLING_EXEC_ARG1 DARLING_EXEC_ARG2
		# DARLING-ARM64 DIAGNOSTIC (FINDINGS.md F27): print each image load base so
		# the SIGSEGV backtrace can be symbolised. Bases are randomised per run, so
		# they must come from the same run as the crash.
		export DYLD_PRINT_SEGMENTS=1
"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "DYLD_PRINT_SEGMENTS" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: anchor found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: save phase now prints image load bases")
