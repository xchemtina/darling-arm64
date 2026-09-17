#!/usr/bin/env python3
"""
DARLING-ARM64 EXPERIMENT for FINDINGS.md F27. Idempotent. Run from ~/darling/source.

Established: TextEdit renders fully, then `super+s` makes every window vanish. With
OBJC_PRINT_EXCEPTIONS enabled only two exceptions appear and BOTH are caught and
completed ("handling ... finishing handler ... releasing completed"), so the process
is not dying on an uncaught exception -- it appears to terminate cleanly.

That points at key-equivalent dispatch: Cmd-S may be resolving to the wrong menu
action (Quit or Close) rather than Save.

This experiment substitutes a harmless key equivalent (Cmd-B / bold) for Cmd-S and
captures the window census afterwards:

  windows still present after Cmd-B  -> Cmd-S specifically is mis-dispatched, or
                                        Save itself terminates the app
  windows gone after Cmd-B too       -> ANY command-key equivalent kills the app,
                                        i.e. the fault is in key-equivalent
                                        dispatch generally, not in Save

Revert with `git checkout -- tools/verify-text-edit-darling-arm64.sh` afterwards.
"""
import sys, pathlib

P = pathlib.Path("tools/verify-text-edit-darling-arm64.sh")
ANCHOR = "\t\txdotool key super+s\n"
NEW = (
    "\t\t# DARLING-ARM64 EXPERIMENT (FINDINGS.md F27): harmless key equivalent\n"
    "\t\t# instead of Cmd-S, to separate 'Save terminates' from 'any Cmd key\n"
    "\t\t# terminates'.\n"
    "\t\txdotool key super+b\n"
    "\t\tsleep 1\n"
    "\t\timport -window root /artifacts/keytest-after-cmdb.png 2>/dev/null || true\n"
    "\t\txdotool search --onlyvisible --name . 2>/dev/null | while read -r w; do\n"
    "\t\t\tprintf \"%s\\t%s\\n\" \"$w\" \"$(xdotool getwindowname \"$w\" 2>/dev/null)\"\n"
    "\t\tdone > /artifacts/keytest-windows-after-cmdb.txt 2>/dev/null || true\n"
    + ANCHOR
)

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "keytest-after-cmdb" in s:
    print("already patched"); sys.exit(0)
if ANCHOR not in s:
    print("FATAL: anchor not found", file=sys.stderr); sys.exit(1)
P.write_text(s.replace(ANCHOR, NEW, 1))
print(f"patched {P}: Cmd-B probe inserted before Cmd-S")
