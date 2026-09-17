#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F34 (corrected diagnosis). Idempotent.
Run from ~/darling/source.

WHAT F34 ACTUALLY IS
--------------------
Not a binary-property-list parser defect. That diagnosis was wrong and is corrected
in FINDINGS.md. The parser is fine -- given a bplist that still exists, it
round-trips correctly:

    XML -> binary : bplist00, 61 bytes
    binary -> XML : correct <dict><key>Greeting</key><string>hello</string>

The real defect: `darlingPreInit` (darlingserver.cpp:237) wipes **/var/tmp** on
*every* container start, so a file written by one `darlingserver` invocation is gone
by the next one. `verify-service-tools-darling-arm64.sh` writes
`/private/var/tmp/stage10.binary.plist` in one invocation and reads it in the next,
so `plutil` receives a **missing file**, and its error message
(`plutil.m:65`) reports that as "input is not a property list" -- which is what sent
this investigation into the parser in the first place.

Proven by canary, not inferred: a file written to `$prefix/private/var/tmp` before a
single trivial `darlingserver` run is MISSING afterwards, while one written to
`$prefix/root` survives.

WHY WIPING /var/tmp IS WRONG
----------------------------
On Darwin, as on Unix generally, the two temp directories have different contracts:

  /private/tmp      (= /tmp)      volatile; cleared by periodic maintenance
  /private/var/tmp  (= /var/tmp)  **persistent**; survives reboots by design

Darling emulates macOS, so wiping /var/tmp at container start diverges from the
platform it is emulating, and silently destroys data a previous process wrote into
the same prefix. /var/run is genuinely runtime state and is still wiped.

This is upstream Darling behaviour, not arm64-specific -- but it is what fails the
arm64 headless ladder today, and deepai-org's own verifier depends on the macOS
semantics.

Revert with: cd src/external/darlingserver && git checkout -- src/darlingserver.cpp
"""
import sys, pathlib

P = pathlib.Path("src/external/darlingserver/src/darlingserver.cpp")

OLD = """	const char* dirs[] = {
		"/var/tmp",
		"/var/run"
	};
"""

NEW = """	/* DARLING-ARM64 FIX (FINDINGS.md F34): /var/tmp must NOT be wiped.
	 *
	 * On Darwin the two temp directories have different contracts:
	 *   /private/tmp     (= /tmp)     volatile, cleared by periodic maintenance
	 *   /private/var/tmp (= /var/tmp) PERSISTENT, survives reboots by design
	 *
	 * Wiping /var/tmp on every container start diverges from the platform being
	 * emulated and silently destroys data written by a previous process in the
	 * same prefix. It is what breaks verify-service-tools: that script writes
	 * /private/var/tmp/stage10.binary.plist in one darlingserver invocation and
	 * reads it in the next, so plutil received a missing file and reported it as
	 * "input is not a property list".
	 *
	 * /var/run is genuinely runtime state, so it is still wiped. */
	const char* dirs[] = {
		"/var/run"
	};
"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F34" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: dirs[] initialiser found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: /var/tmp is no longer wiped at container start")
