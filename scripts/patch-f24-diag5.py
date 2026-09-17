#!/usr/bin/env python3
"""
DARLING-ARM64 DIAGNOSTIC for FINDINGS.md F24. Idempotent. Run from ~/darling/source.

The stage-11 ERR trap reports only `${BASH_LINENO[0]}` and a status. That has now
twice led to a wrong reading of where the run stopped, because:

  * the reported status was 124 (timeout's exit code) at a line that runs no
    `timeout`, so the status does not belong to the line; and
  * the trace proves the modal click was delivered and `wmctrl -ic` appears to
    have run afterwards, which contradicts "failed at line 324".

So print the failing command itself (`$BASH_COMMAND`) and list the marker
directory at failure time. Both are one line each and remove the guesswork.

Revert with: git checkout -- tools/verify-x11-backend-darling-arm64.sh
"""
import sys, pathlib

P = pathlib.Path("tools/verify-x11-backend-darling-arm64.sh")

OLD = '''			echo "Stage 11 verifier failed near line ${BASH_LINENO[0]} (status $status)." >&2
'''
NEW = '''			echo "Stage 11 verifier failed near line ${BASH_LINENO[0]} (status $status)." >&2
			# DARLING-ARM64 DIAG (FINDINGS.md F24): the line number alone has
			# twice been misread. Name the command and show the markers.
			echo "  failing command: ${BASH_COMMAND}" >&2
			echo "  markers present at failure:" >&2
			ls -1 "${prefix:-/nonexistent}/private/var/tmp" 2>/dev/null \\
				| sed "s/^/    /" >&2 || echo "    (none)" >&2
'''

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "failing command:" in s:
    print("already patched"); sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: anchor found {s.count(OLD)}x (want 1)", file=sys.stderr); sys.exit(1)
P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: failure() now reports BASH_COMMAND and the marker listing")
