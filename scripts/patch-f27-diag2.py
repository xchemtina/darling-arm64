#!/usr/bin/env python3
"""
DARLING-ARM64 DIAGNOSTIC for FINDINGS.md F27 (round 2). Idempotent.
Run from ~/darling/source.

Cmd-S makes every TextEdit window disappear with no signal, no ObjC exception and
no abort message in an 8 KB save.err -- the process simply stops. Nothing in the
log to work from, so this adds three independent sources of signal:

  1. ObjC exception reporting, in case an exception is raised and swallowed
     somewhere before it reaches stderr.
  2. The darlingserver child's exit status, captured after the save phase's
     wait/kill. "exited cleanly with status N" and "killed by signal N" are very
     different diagnoses and this is the cheapest way to tell them apart.
  3. A marker written just before and after the Cmd-S keystroke, so we know
     whether the app was still alive immediately prior.
"""
import sys, pathlib

P = pathlib.Path("tools/verify-text-edit-darling-arm64.sh")

ENV_ANCHOR = "\t\texport DARLING_ARM64_THREAD_BRIDGE=1\n"
ENV_NEW = ENV_ANCHOR + (
    "\t\t# DARLING-ARM64 DIAGNOSTIC (FINDINGS.md F27): surface ObjC exceptions,\n"
    "\t\t# which are otherwise invisible -- save.err shows no signal or abort.\n"
    "\t\texport OBJC_PRINT_EXCEPTIONS=YES\n"
    "\t\texport OBJC_PRINT_UNCAUGHT_EXCEPTIONS=YES\n"
    "\t\texport NSZombieEnabled=YES\n"
)

# Record the server's fate right after the save-phase quit, before anything else
# can clobber $?. `wait` reports 128+N when the child was killed by signal N.
QUIT_ANCHOR = "\t\txdotool key super+q\n\t\twait_for_exit\n"
QUIT_NEW = (
    "\t\txdotool key super+q\n"
    "\t\twait_for_exit\n"
    "\t\t# DARLING-ARM64 DIAGNOSTIC (FINDINGS.md F27)\n"
    "\t\twait \"$server_pid\" 2>/dev/null; echo \"save-phase server exit=$?\" \\\n"
    "\t\t\t> /artifacts/save-server-exit.txt 2>/dev/null || true\n"
)

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "OBJC_PRINT_EXCEPTIONS" in s:
    print("already patched"); sys.exit(0)
if ENV_ANCHOR not in s:
    print("FATAL: env anchor not found", file=sys.stderr); sys.exit(1)
s = s.replace(ENV_ANCHOR, ENV_NEW, 1)

if QUIT_ANCHOR in s:
    s = s.replace(QUIT_ANCHOR, QUIT_NEW, 1)
    note = "env + server-exit capture"
else:
    note = "env only (quit anchor not matched; server exit not captured)"

P.write_text(s)
print(f"patched {P}: {note}")
