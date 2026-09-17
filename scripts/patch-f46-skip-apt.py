#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F46. Idempotent. Run from ~/darling/source.

Every graphical verifier runs `apt-get update && apt-get install` for its X11
dependencies on EVERY invocation. Measured consequences:

  * ~50 s of a ~165 s run is dependency installation;
  * a transient DNS failure fails the run in under ten seconds, looking exactly like
    a test failure -- nine runs of a reliability sweep were invalidated that way.

With the dependencies baked into the image (scripts/Dockerfile.gui-deps, tagged
darling-arm64-dev:guideps) the installs become redundant. This guards them on a
presence check rather than deleting them, so the verifiers still work unchanged
against the plain `:latest` image -- the change is a speed-up, not a new hard
dependency.

`xdotool` is the sentinel: it is installed by every graphical verifier and is not
present in the base image.

Revert with: git checkout -- tools/
"""
import sys, pathlib, re

GUARD = "command -v xdotool >/dev/null 2>&1 || "
VERIFIERS = [
    "verify-x11-backend", "verify-hello-window", "verify-controls",
    "verify-text-view", "verify-text-edit", "verify-pty-harness",
    "verify-mini-term",
]

total = 0
for name in VERIFIERS:
    p = pathlib.Path(f"tools/{name}-darling-arm64.sh")
    if not p.exists():
        print(f"  skipped (absent): {name}")
        continue
    s = p.read_text()
    if GUARD in s:
        print(f"  already patched: {name}")
        continue

    lines = s.split("\n")
    out, n = [], 0
    for line in lines:
        stripped = line.lstrip()
        indent = line[:len(line) - len(stripped)]
        # Guard the statement that STARTS an apt-get update / install. Continuation
        # lines (trailing backslash) belong to the same command and must be left be.
        if re.match(r"apt-get (update|install)\b", stripped):
            out.append(indent + GUARD + stripped)
            n += 1
        else:
            out.append(line)
    if n:
        p.write_text("\n".join(out))
        print(f"  patched: {name} ({n} apt call{'s' if n != 1 else ''} guarded)")
        total += n
    else:
        print(f"  no apt calls found: {name}")

print(f"done ({total} guarded)")
