#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F64. Idempotent. Run from ~/darling/source.

DIAGNOSIS
---------
`-[NSFileHandle truncateFileAtOffset:]` seeks **relative to the current position**
where macOS seeks **to the offset**:

    if (lseek(_fd, offset, SEEK_CUR) < 0)     /* should be SEEK_SET */

`ftruncate` is given the absolute offset and is correct, so the file *contents* come
out right and only the resulting file position diverges. That is why the defect
survived: it is invisible unless something reads the position afterwards.

HOW IT WAS CONFIRMED
--------------------
This one was first spotted by reading, while chasing an unrelated defect, and was
recorded as an unreproduced lead rather than fixed on inspection. Turning it into a
measurement needed a test the existing one could not provide: `t32_filehandle`
truncated through a **freshly opened** handle, and at position 0 `SEEK_CUR` and
`SEEK_SET` give the same answer, so the case was structurally blind to it.

Writing three bytes first moves the position to 3, which separates them --- from 3,
`SEEK_SET 5` lands at 5 and `SEEK_CUR 5` lands at 8:

    native : ... pre_trunc_off:3 post_trunc_off:5 ~ trunc_len:5 ...
    darling: ... pre_trunc_off:3 post_trunc_off:8 ~ trunc_len:5 ...

Exactly the predicted arithmetic, on both arches. `trunc_len:5` matches either way,
confirming that only the position is affected.

THE FIX
-------
One token: `SEEK_CUR` becomes `SEEK_SET`.

Revert with: cd src/external/foundation && git checkout -- src/NSFileHandle.m
  -- check first what else is patched there: grep -c "DARLING-ARM64 FIX" src/NSFileHandle.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSFileHandle.m")

OLD = """- (void)truncateFileAtOffset:(unsigned long long)offset
{
    FAIL_IF_CLOSED();

    if (lseek(_fd, offset, SEEK_CUR) < 0)
    {
        FAIL();
    }"""

NEW = """- (void)truncateFileAtOffset:(unsigned long long)offset
{
    FAIL_IF_CLOSED();

    /* DARLING-ARM64 FIX (FINDINGS.md F64): this was SEEK_CUR, which seeks the
     * offset RELATIVE to the current position. macOS seeks TO the offset. The
     * ftruncate below already uses the absolute offset and was always correct, so
     * the file contents matched and only the resulting file position diverged --
     * which is why nothing noticed until a corpus case was written that moves the
     * position before truncating (at position 0 the two are indistinguishable). */
    if (lseek(_fd, offset, SEEK_SET) < 0)
    {
        FAIL();
    }"""

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F64" in s:
    print("already patched")
    sys.exit(0)
if s.count(OLD) != 1:
    print(f"FATAL: anchor found {s.count(OLD)}x (want 1)", file=sys.stderr)
    sys.exit(1)

P.write_text(s.replace(OLD, NEW, 1))
print(f"patched {P}: truncateFileAtOffset: now seeks to the offset, not past it")
