#!/usr/bin/env python3
"""
DARLING-ARM64 LOCAL DIAGNOSTIC for FINDINGS.md F27. Idempotent.
Run from ~/darling/source.

verify-text-edit-darling-arm64.sh drives TextEdit's save flow entirely through
synthetic input with hard-coded panel coordinates, and takes NO screenshot during
the save phase (only in the reopen phase, which is never reached). When the save
silently produces no file there is therefore nothing to look at.

This inserts three captures:
  save-1-typed.png   after the text is typed, before Cmd-S
  save-2-panel.png   after Cmd-S      -> did the save panel actually open?
  save-3-after.png   after the Save click -> did the panel accept/close?

It also records the full-screen state, since the panel may be a separate
top-level window that "-window $main" would miss entirely.
"""
import sys, pathlib

P = pathlib.Path("tools/verify-text-edit-darling-arm64.sh")

STEPS = [
    ('\t\txdotool key super+s\n',
     '\t\timport -window "$main" /artifacts/save-1-typed.png 2>/dev/null || true\n'
     '\t\timport -window root /artifacts/save-1-typed-root.png 2>/dev/null || true\n'
     '\t\txdotool key super+s\n'
     '\t\tsleep 1\n'
     '\t\timport -window root /artifacts/save-2-panel.png 2>/dev/null || true\n'
     '\t\txdotool search --onlyvisible --name . 2>/dev/null | while read -r w; do\n'
     '\t\t\tprintf "%s\\t%s\\n" "$w" "$(xdotool getwindowname "$w" 2>/dev/null)"\n'
     '\t\tdone > /artifacts/save-2-windows.txt 2>/dev/null || true\n'),
    ('\t\txdotool mousemove 825 577 click 1\n',
     '\t\txdotool mousemove 825 577 click 1\n'
     '\t\tsleep 1\n'
     '\t\timport -window root /artifacts/save-3-after.png 2>/dev/null || true\n'),
]

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
s = P.read_text()
if "save-2-panel.png" in s:
    print("already patched"); sys.exit(0)

for anchor, replacement in STEPS:
    if anchor not in s:
        print(f"FATAL: anchor not found: {anchor.strip()!r}", file=sys.stderr)
        sys.exit(1)
    s = s.replace(anchor, replacement, 1)

P.write_text(s)
print(f"patched {P} with save-phase captures")
