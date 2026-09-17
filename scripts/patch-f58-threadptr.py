#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F58. Idempotent. Run from ~/darling/source.

DIAGNOSIS
---------
`t33_thread` matches macOS exactly on **arm64** and dies with SIGSEGV on **arm64e**.
Same source, same compiler, same test -- the only variable is pointer authentication.

Localising it needed two steps, both worth recording:

  1. The case reported "no output at all", which looked like death before `main`.
     It was not: a signal death discards a block-buffered stdout (trap 23). With
     `setvbuf(stdout, NULL, _IONBF, 0)` the case turns out to complete NINE
     assertions -- including running a detached thread -- before dying.

  2. A reduced probe narrowed it further. On arm64e:

         A start / B sleep_only / C sleep_ok / D about_to_detach
         E detach_returned / [worker ran]        <-- worker body COMPLETED
         SIGSEGV

     so `sleepForTimeInterval:` works, `detachNewThreadSelector:` works, and the
     worker's own method body runs to completion. **The crash is in thread
     teardown.** The identical arm64 binary prints everything and exits 0.

THE CAUSE
---------
Two function pointers are handed to pthread through casts to an incompatible type:

    pthread_key_create(&NSThreadKey, (void (*)(void *))&NSThreadEnd);
    pthread_create(&_thread, NULL, (void *(*)(void *))&__NSThread__main__, self);

`NSThreadEnd` is declared `void(NSThread *)` and `__NSThread__main__` is declared
`void *(NSThread *)`; both are cast to their `void *` equivalents so pthread will
accept them.

Calling a function through an incompatible function-pointer type is undefined
behaviour in C, and on arm64e it is specifically the case pointer authentication is
designed to catch: a function pointer is signed with a discriminator derived from its
*type*, so a pointer signed as `void(NSThread *)` does not authenticate when pthread
calls it as `void(void *)`. It fails at exactly one moment -- when the key destructor
runs on thread exit -- which is precisely where the crash is.

That also explains why plain arm64 is unaffected: without PAC the cast is merely UB
that happens to work, because the calling convention is identical.

THE FIX
-------
Declare both functions with the signatures pthread actually calls, and move the cast
inside the function body where it is a plain, well-defined pointer conversion. No
casts of function pointers remain, so there is nothing for PAC to reject and nothing
undefined for a future compiler to exploit.

This is a correctness fix on every architecture; arm64e is just where it was visible.

Revert with: cd src/external/foundation && git checkout -- src/NSThread.m
  -- check first what else is patched there: grep -c "DARLING-ARM64 FIX" src/NSThread.m
"""
import sys, pathlib

P = pathlib.Path("src/external/foundation/src/NSThread.m")

EDITS = [
    # forward declaration
    ("static void NSThreadEnd(NSThread *thread);",
     "static void NSThreadEnd(void *thread);   /* DARLING-ARM64 (F58): pthread's type */",
     "forward declaration"),

    # key registration: drop the cast
    ("    pthread_key_create(&NSThreadKey, (void (*)(void *))&NSThreadEnd);",
     "    /* DARLING-ARM64 FIX (FINDINGS.md F58): this used to cast &NSThreadEnd from\n"
     "     * void(NSThread *) to void(void *). On arm64e a function pointer is signed\n"
     "     * with a discriminator derived from its type, so the pointer failed to\n"
     "     * authenticate when pthread called it as void(void *) -- crashing every\n"
     "     * thread at exit, which is when the key destructor runs. The function now\n"
     "     * has pthread's signature and no cast is needed. */\n"
     "    pthread_key_create(&NSThreadKey, &NSThreadEnd);",
     "pthread_key_create cast"),

    # definition of NSThreadEnd
    ("""static void NSThreadEnd(NSThread *thread)
{
    @autoreleasepool {""",
     """static void NSThreadEnd(void *threadPtr)
{
    /* DARLING-ARM64 FIX (FINDINGS.md F58): takes void * so the pointer handed to
     * pthread_key_create needs no function-pointer cast. Converting the argument
     * here is an ordinary object-pointer conversion and is always well defined. */
    NSThread *thread = (NSThread *)threadPtr;
    @autoreleasepool {""",
     "NSThreadEnd definition"),

    # definition of __NSThread__main__
    ("""static void *__NSThread__main__(NSThread *thread)
{
    @autoreleasepool {""",
     """static void *__NSThread__main__(void *threadPtr)
{
    /* DARLING-ARM64 FIX (FINDINGS.md F58): as with NSThreadEnd -- pthread's own
     * signature, so no function-pointer cast is required at the pthread_create
     * call. */
    NSThread *thread = (NSThread *)threadPtr;
    @autoreleasepool {""",
     "__NSThread__main__ definition"),

    # pthread_create: drop the cast
    ("    pthread_create(&_thread, NULL, (void *(*)(void *))&__NSThread__main__, self);",
     "    /* DARLING-ARM64 FIX (FINDINGS.md F58): cast removed, see NSThreadEnd. */\n"
     "    pthread_create(&_thread, NULL, &__NSThread__main__, self);",
     "pthread_create cast"),
]

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr)
    sys.exit(1)

s = P.read_text()
if "FINDINGS.md F58" in s:
    print("already patched")
    sys.exit(0)

for old, new, what in EDITS:
    if s.count(old) != 1:
        print(f"FATAL: {what} anchor found {s.count(old)}x (want 1)", file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)

P.write_text(s)
print(f"patched {P}: no function-pointer casts remain across the pthread boundary")
