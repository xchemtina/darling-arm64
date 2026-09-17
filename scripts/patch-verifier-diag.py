#!/usr/bin/env python3
"""
DARLING-ARM64 DIAGNOSTIC for the two remaining failing GUI verifiers.
Idempotent. Run from ~/darling/source.

WHY
---
`verify-mini-term` and `verify-text-edit` install **only** `trap cleanup EXIT`.
There is no ERR trap and no failure reporting whatsoever, so a failing run says
nothing at all about which command failed -- both currently fail opaquely, and the
run log is apt/EGL noise.

Stage 11 at least had an ERR trap, and even that misled us for days because it
printed `${BASH_LINENO[0]}`, which does not track `$BASH_COMMAND` (STATE.md trap 7).
So these get the corrected form from the outset: **name the command, not the line**.

WHAT IT ADDS
------------
1. Both files: a `failure()` ERR trap printing `$BASH_COMMAND`, the exit status, and
   the marker directory. `$BASH_COMMAND` is the authoritative answer to "what
   failed"; the status is the corroborating detail (124 always means a `timeout`
   expired, which localises the failure by itself).
2. `verify-text-edit` only: the application-log preservation block in `cleanup()`.
   It had one, but it was reverted along with the Cmd-B probe by
   `git checkout -- tools/verify-text-edit-darling-arm64.sh` and never restored.
   `verify-mini-term` already has it.

The marker listing is printed with a caveat in mind (STATE.md trap 8): `$prefix` is
reassigned per sub-phase in some verifiers, so treat the listing as "state of the
current prefix", never as proof that an earlier phase did not run.

Revert with: git checkout -- tools/verify-mini-term-darling-arm64.sh \
                              tools/verify-text-edit-darling-arm64.sh
"""
import sys, pathlib

TRAP_ANCHOR = "\t\ttrap cleanup EXIT\n"


def trap_block(stage: str) -> str:
    return (
        # NOTE: no apostrophes anywhere below. This whole verifier body is a
        # single-quoted `bash -lc '...'` container argument, so one apostrophe in a
        # comment terminates the string and the remainder runs on the host. That
        # has already bitten this project once.
        "\t\t# DARLING-ARM64 LOCAL DIAGNOSTIC: name the failing command.\n"
        "\t\t# In a bash ERR trap, ${BASH_LINENO[0]} does NOT track $BASH_COMMAND --\n"
        "\t\t# stage 11 blamed the wrong command for days (STATE.md trap 7). Print\n"
        "\t\t# the command itself. Status 124 always means a timeout expired.\n"
        "\t\tfailure() {\n"
        "\t\t\tlocal status=$?\n"
        f'\t\t\techo "Stage {stage} verifier failed (status $status)." >&2\n'
        '\t\t\techo "  failing command: ${BASH_COMMAND}" >&2\n'
        '\t\t\techo "  markers in the CURRENT prefix (not proof about earlier phases):" >&2\n'
        '\t\t\tls -1 "${prefix:-/nonexistent}/private/var/tmp" 2>/dev/null \\\n'
        '\t\t\t\t| sed "s/^/    /" >&2 || true\n'
        '\t\t\treturn "$status"\n'
        "\t\t}\n"
        "\t\ttrap failure ERR\n"
    )


# verify-text-edit lost its log-preservation block to a `git checkout`; restore it.
TE_CLEANUP_OLD = (
    "\t\tcleanup() {\n"
    '\t\t\t[[ -z $server_pid ]] || kill "$server_pid" 2>/dev/null || true\n'
)
TE_CLEANUP_NEW = (
    "\t\tcleanup() {\n"
    "\t\t\t# DARLING-ARM64 LOCAL DIAGNOSTIC: preserve application output.\n"
    "\t\t\t# /artifacts is bind-mounted and survives the container; /tmp is not.\n"
    "\t\t\t# Done from the EXIT trap so logs survive timeouts as well as failures.\n"
    "\t\t\tfor _f in /tmp/stage*.err /tmp/stage*.out; do\n"
    '\t\t\t\t[ -s "$_f" ] && cp "$_f" /artifacts/ 2>/dev/null || true\n'
    "\t\t\tdone\n"
    '\t\t\t[[ -z $server_pid ]] || kill "$server_pid" 2>/dev/null || true\n'
)

FILES = [
    ("tools/verify-mini-term-darling-arm64.sh", "17", None),
    ("tools/verify-text-edit-darling-arm64.sh", "15", (TE_CLEANUP_OLD, TE_CLEANUP_NEW)),
]

changed = 0
for rel, stage, extra in FILES:
    p = pathlib.Path(rel)
    if not p.exists():
        print(f"FATAL: missing {p}", file=sys.stderr)
        sys.exit(1)
    s = p.read_text()
    touched = False

    if "trap failure ERR" in s:
        print(f"  ERR trap already present: {p}")
    else:
        if s.count(TRAP_ANCHOR) != 1:
            print(f"FATAL: 'trap cleanup EXIT' found {s.count(TRAP_ANCHOR)}x "
                  f"(want 1) in {p}", file=sys.stderr)
            sys.exit(1)
        s = s.replace(TRAP_ANCHOR, TRAP_ANCHOR + trap_block(stage), 1)
        touched = True

    if extra is not None:
        old, new = extra
        if "for _f in /tmp/stage*.err" in s:
            print(f"  log preservation already present: {p}")
        elif s.count(old) != 1:
            print(f"FATAL: cleanup anchor found {s.count(old)}x (want 1) in {p}",
                  file=sys.stderr)
            sys.exit(1)
        else:
            s = s.replace(old, new, 1)
            touched = True

    if touched:
        p.write_text(s)
        print(f"  patched: {p}")
        changed += 1

print(f"done ({changed} file(s) changed)")
