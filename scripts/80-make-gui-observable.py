#!/usr/bin/env python3
"""
Block 0: make GUI verifier runs observable.

PROBLEM. The x11 verifiers run the application inside an ephemeral container and
redirect its output to /tmp/stage<N>-*.{out,err}. Only some of them ever surface
that, and only via `cat ... >&2` from an ERR trap. When a run dies on a timeout
(status 124) the ERR path is unreliable, so the entire run log can be three lines
with zero application output -- which is exactly what happened while chasing F24,
costing a whole investigation cycle.

FIX. Every verifier already bind-mounts `-v "$artifact_root:/artifacts"`, which
survives the container. Copy the app's logs there from the EXIT trap (`cleanup`),
so they persist regardless of how the run ends: success, assertion failure, or
SIGKILL from `timeout`.

Idempotent. Run from ~/darling/source.
"""
import sys, pathlib, re

TOOLS = pathlib.Path("tools")
NAMES = ["x11-backend", "hello-window", "controls", "text-view",
         "text-edit", "pty-harness", "mini-term"]

CAPTURE = (
    '\t\t\t# DARLING-ARM64 LOCAL DIAGNOSTIC: preserve application output.\n'
    '\t\t\t# /artifacts is bind-mounted and survives the container; /tmp is not.\n'
    '\t\t\t# Done from the EXIT trap so logs survive timeouts as well as failures.\n'
    '\t\t\tfor _f in /tmp/stage*.err /tmp/stage*.out; do\n'
    '\t\t\t\t[ -s "$_f" ] && cp "$_f" /artifacts/ 2>/dev/null || true\n'
    '\t\t\tdone\n'
)

changed, skipped, failed = [], [], []

for name in NAMES:
    p = TOOLS / f"verify-{name}-darling-arm64.sh"
    if not p.exists():
        failed.append((name, "missing")); continue
    s = p.read_text()
    if "preserve application output" in s:
        skipped.append(name); continue

    # Insert as the first statement of the container-side cleanup() function.
    m = re.search(r"(?m)^(\t*)cleanup\(\) \{\n", s)
    if not m:
        failed.append((name, "no cleanup() found")); continue
    insert_at = m.end()
    s = s[:insert_at] + CAPTURE + s[insert_at:]
    p.write_text(s)
    changed.append(name)

print(f"patched:  {', '.join(changed) if changed else '(none)'}")
print(f"skipped:  {', '.join(skipped) if skipped else '(none)'}")
for n, why in failed:
    print(f"FAILED:   {n} ({why})", file=sys.stderr)
sys.exit(1 if failed else 0)
