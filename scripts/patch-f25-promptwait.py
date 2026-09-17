#!/usr/bin/env python3
"""
DARLING-ARM64 TEST for FINDINGS.md F25. Idempotent. Run from ~/darling/source.

verify-mini-term-darling-arm64.sh activates the window and then immediately types
its first command, with no wait for the shell to emit its prompt:

    xdotool windowactivate --sync "$window"
    ...
    type_command "echo STAGE17_COMMAND_OK"

The terminal buffer then starts `echnorth-star$` -- the first three characters of
the typed command are echoed at column 0 before the prompt is written, so the
verifier's own (correct) `{0,6}` selection returns `echnor` instead of the expected
text and the run fails.

This waits for the prompt before the first keystroke. Corruption disappears =>
harness timing bug, report upstream. Corruption persists => genuine renderer defect
in MiniTerm's PTY reader (missing carriage-return reset on first output).
"""
import sys, pathlib

P = pathlib.Path("tools/verify-mini-term-darling-arm64.sh")
ANCHOR = '\t\ttype_command "echo STAGE17_COMMAND_OK"\n'
WAIT = (
    '\t\t# DARLING-ARM64 TEST (FINDINGS.md F25): wait for the shell prompt before\n'
    '\t\t# the first keystroke. Without this the first characters race the prompt\n'
    '\t\t# and corrupt line 0 of the terminal buffer.\n'
    '\t\tfor attempt in {1..400}; do\n'
    '\t\t\t[[ -f $prefix/private/var/tmp/mini-term-output ]] && \\\n'
    '\t\t\t\tgrep -q "north-star\\$" "$prefix/private/var/tmp/mini-term-output" && break\n'
    '\t\t\tsleep 0.05\n'
    '\t\tdone\n'
) + ANCHOR

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "FINDINGS.md F25" in s:
    print("already patched"); sys.exit(0)
if ANCHOR not in s:
    print("FATAL: anchor not found", file=sys.stderr); sys.exit(1)
P.write_text(s.replace(ANCHOR, WAIT, 1))
print(f"patched {P}: prompt wait added before first keystroke")
