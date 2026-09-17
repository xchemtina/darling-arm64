# Findings — independent reproduction of darlinghq/darling PR #1753

First independent build attempt of kkHAIKE's `arm64-support` branch on hardware and a
toolchain other than the author's. Everything here is reportable upstream and would be
useful to both kkHAIKE and the maintainer (CuriousTommy).

**Our config:** Fedora 44 aarch64, kernel 6.19.10, **clang 22.1.8**, cmake 4.3.0,
12 cores / 24GB, native (Apple M3 Max under Virtualization.framework).
**Author's config:** clang-19, distro unstated.

> ## ⚠️ METHODOLOGICAL CORRECTION — read before trusting F1–F6
>
> Choosing Fedora 44 was a **mistake**, and it contaminated everything below it.
> It was picked because upstream had recent "Fix Building For Fedora 44" commits —
> shallow reasoning, since those were *x86_64* fixes. Fedora 44 ships the newest
> clang in existence, **maximising** the distance from the author's clang-19 instead
> of minimising it. Every variable was changed at once (branch + distro + compiler +
> kernel + 5 local patches), leaving no control and no way to attribute the failure.
>
> **Partially confirmed 2026-08-05 — and then partially retracted.** Compiling
> `libffi/src/aarch64/sysv.S` with the *exact* build flags:
>
> | clang | result |
> |---|---|
> | 18.1.8 | **assembles clean** (33824-byte object, zero diagnostics) |
> | 19.1.7 (Debian, = the author's major version) | **rejects** |
> | 22.1.8 | **rejects** |
>
> The clang-18 result initially looked like proof that F6 was purely a Fedora/clang-22
> artifact. **That conclusion was wrong.** clang 19 — the author's own stated
> toolchain — rejects it too, so the regression sits between clang 18 and 19 and
> **F6 is a genuine blocker for anyone on clang ≥ 19**. The patch has been
> re-applied on the clean Debian build because it is actually required there.
>
> *Second-order lesson: over-correcting is also an error.* Having accepted a fair
> critique of the environment choice, the first confirming datapoint (clang 18) was
> accepted too readily and generalised without testing the version that actually
> mattered. One datapoint is not a trend in either direction.
>
> Open question worth asking kkHAIKE: PR #1753 states it was tested with clang-19,
> but libffi's aarch64 assembly does not build under Debian's clang 19.1.7. Different
> patch level, different component selection, or an unpublished local workaround?
>
> **Fedora 44 has no usable toolchain for this project — in either direction:**
>
> | Compiler | Result |
> |---|---|
> | clang 22.1.8 (Fedora default) | too strict for Darling's C → F1, F2, F6 |
> | clang 18.1.8 (Fedora compat pkg) | **94 errors inside `/usr/include/c++/16/bits/stl_iterator.h`** — cannot parse Fedora's libstdc++ 16 (GCC 16.1.1) |
>
> An older clang can't be paired with this distro's standard library, and the
> distro's own clang can't compile the project. The platform was simply wrong.
>
> **Corrected environment: Debian 13 (trixie) aarch64**, which ships **clang 19.0** —
> the exact version kkHAIKE built PR #1753 against — with a matching libstdc++.
> This is the control that should have existed from the start. VM `darling-deb`;
> source tree transferred rather than re-cloned. Rebuild uses **zero relaxation
> flags** with **F6 reverted**, keeping only F1 and F2 (genuine bugs, compiler-
> independent).
>
> Treat **F4 and F6 as artifacts of a bad environment choice**, not findings about
> the branch. **F1, F2, F7 and F8 remain valid** — F1 and F2 are real code defects
> and F7/F8 are runtime behaviour, though F7 must be re-confirmed on the clean
> foundation before any conclusion is drawn from it.

---

## F0 — CMake arch detection works as designed ✅

On an aarch64 host, a plain `cmake ..` correctly selects:
```
TARGET_ARM64    ON
TARGET_x86_64   OFF
TARGET_i386     OFF
```
No manual flags needed. `CMakeLists.txt:7-9` (`uname -m` → `CMAKE_SYSTEM_PROCESSOR`)
and `:142-149` (arch-conditional defaults) behave correctly. Configure completes
with no errors once the tree is intact.

---

## F1 — `epoll_create.c` fails to compile on aarch64 with clang ≥ 16 🔴

**arm64-specific. This path never compiles on x86_64.**

```
src/external/xnu/darling/src/libsystem_kernel/emulation/src/
  linux_premigration/ext/epoll_create.c:24:10: error:
  call to undeclared function '__linux_epoll_create1';
  ISO C99 and later do not support implicit function declarations
  [-Wimplicit-function-declaration]
```

Cause: the file is guarded `#if defined(__NR_epoll_create) … #else return
epoll_create1(0); #endif`. **aarch64 Linux has no `__NR_epoll_create`** (only
`epoll_create1`), so the `#else` branch is taken — and on that branch
`epoll_create1` has no declaration in scope. On x86_64 `__NR_epoll_create` exists,
the `#else` is dead code, and nobody ever noticed.

Clang ≤ 15 accepted this as a warning and it linked fine (the symbol exists with a
matching `int(int)` signature), which is why it passed for the author on clang-19 —
though clang 16 already promotes this to an error, so this may indicate the author's
build did not compile this translation unit at all.

**Proper fix:** include the header declaring `epoll_create1` on the non-`__NR_epoll_create`
path. Not a `-Wno-error` candidate for upstream.

---

## F2 — `libkqueue` type mismatch breaks the build on clang ≥ 16 🔴

```
src/external/libkqueue/src/linux/timer.c:277:48: error:
  incompatible pointer types passing 'struct kevent_internal_s *'
  to parameter of type 'const struct kevent64_s *'
  [-Wincompatible-pointer-types]
```
`evfilt_timer_knote_enable()` passes `&kn->kev` into `evfilt_timer_knote_modify()`.

**Not arm64-specific** — pre-existing sloppiness in a submodule kkHAIKE never forked
(`darling-libkqueue` is not among their 31 forks), so it is at stock darlinghq state.
Needs a real type audit, since these two structs are ABI-relevant.

---

## F3 — MIG invocation emits a malformed `#define` 🟡

```
<command line>:21:9: error: macro name must be an identifier
   21 | #define -DPRIVATE 1
```
A `-DPRIVATE` flag is being passed where MIG expects a bare macro *name*, so the
generated command line contains `#define -DPRIVATE 1`. Occurs during
`mach_host` / `mach_port` MIG generation. Build-system quoting bug; did not stop the
build, but it means those MIG steps ran degraded.

---

## F4 — Toolchain gap is the headline 🔴

The branch is developed against **clang-19**; Fedora 44 ships **clang 22.1.8**.
Clang 16 turned several long-standing warnings into hard errors, and this branch
(plus its stock submodules) has not been adapted. The author flags this in the PR body
and points at the companion LLVM-15 libc++ upgrade (#1754), but that PR addresses the
bundled libc++, **not** the C-level defects in F1/F2.

Practical consequence: **PR #1753 does not build out of the box on a current distro.**
That is a merge blocker independent of whether the arm64 runtime work is correct.

**Our workaround** (documented in `scripts/30-build.sh`, deliberately scoped):
```
-Wno-error=implicit-function-declaration
-Wno-error=incompatible-pointer-types
-Wno-error=int-conversion
-Wno-error=incompatible-function-pointer-types
```
This restores pre-clang-16 behaviour so we can reach a runnable build and measure the
runtime claims. It is a **measurement scaffold, not a fix** — F1 and F2 should be
fixed properly before anything is proposed upstream.

---

## F5 — Reproduction traps worth publishing 🟡

Anyone else trying to reproduce #1753 will hit these:

1. **Relative submodule URLs resolve against the current branch's tracking remote,
   not `origin`.** Checking out `kkhaike/arm64-support` with tracking makes all 149
   `../darling-*.git` resolve to `github.com/kkHAIKE/*`. kkHAIKE forked only 31, so
   ~118 fail with auth prompts. Clone from **darlinghq**, `checkout --no-track`, and
   redirect the 31 via `url.<fork>.insteadOf`.
2. **A submodule can sit at the correct pinned SHA with an empty worktree** if a
   clone was interrupted. `git submodule status` shows it as clean; only CMake
   notices ("does not contain a CMakeLists.txt file"). Hit `libcxx` and `libcxxabi`.
3. Verify **pinned vs actual** (`git ls-tree HEAD <sub>` vs `git -C <sub> rev-parse
   HEAD`). Nine submodules silently sat at the wrong commit after an aborted run,
   including `xnu` — i.e. we would have "built the arm64 branch" **without the arm64
   syscall fixes** and drawn false conclusions.

---

## F6 — `libffi` aarch64 assembly will not assemble for `aarch64-apple-darwin` 🔴

**The first genuinely arm64-specific runtime blocker, and the most interesting finding.**

With the F4 relaxations in place the build advances **2% → 44%**, then dies here:

```
src/external/libffi/src/aarch64/sysv.S
/tmp/sysv-*.s:43:2:  error: invalid CFI advance_loc expression
   .cfi_def_cfa x1, 40;
/tmp/sysv-*.s:204:2: error: invalid CFI advance_loc expression
   .cfi_adjust_cfa_offset (8*2 + (8 * 16 + 8 * 8) + 64)
```

Compiled as: `-target aarch64-apple-darwin20 -arch arm64` → **Mach-O**, with
`__APPLE__` defined, via clang's integrated assembler.

Two distinct parser problems:
1. `cfi_def_cfa(x1, 40);` expands with a **trailing semicolon**, which the aarch64
   Mach-O asm parser appears to fold into the CFI operand expression.
2. `.cfi_adjust_cfa_offset (…)` uses a **parenthesised arithmetic expression**, which
   the same parser rejects.

Note `sysv.S:85` already special-cases `__has_feature(ptrauth_calls) && defined(__APPLE__)`
— but we build `-arch arm64`, not `arm64e`, so `ptrauth_calls` is off and the `#else`
path (`cfi_def_cfa(x1, 40)`) is taken. Both branches use the same macro, so both are
affected.

**Why this was never hit before:** `darling-libffi` is **not** among kkHAIKE's 31
forks, so it sits at stock darlinghq state, and Darling has only ever built x86_64 —
`src/aarch64/sysv.S` has simply never been compiled by this project. (The generated
`build.make` still lists `src/x86/sysv.S` alongside it, suggesting libffi's CMake arch
selection also deserves a look.)

This is a real porting gap in the arm64 effort, independent of kkHAIKE's work, and a
concrete contribution opportunity.

### F6 resolution

`include/ffi_cfi.h` degrades every `cfi_*` macro to a no-op when
`HAVE_AS_CFI_PSEUDO_OP` is undefined — the escape hatch for exactly this case — but
`darwin/include/fficonfig_arm64.h:49` asserts it unconditionally. Undefining it
(`scripts/patch-libffi-cfi.py`) makes `src/aarch64/sysv.S` assemble and
`libffi.dylib` link.

**Tradeoff:** no DWARF unwind info through ffi trampolines. Fine for measurement;
a proper upstream fix should correct the directives (drop the trailing semicolon,
avoid parenthesised arithmetic in CFI operands) rather than disable CFI wholesale.

Also observed: libffi's CMake builds **all** arch backends together — `x86/sysv.S`,
`x86/unix64.S`, `x86/win64.S`, `arm/sysv.S` and `aarch64/sysv.S` — with no arch
selection. Harmless here but almost certainly not intended.

## Build progress summary

| Configuration | Reached | Stopped by |
|---|---|---|
| stock clang 22 | 2% | F1 (xnu epoll) + F2 (libkqueue) |
| + F4 relaxations | 44% | F6 (libffi aarch64 asm) |
| + F6 libffi patch | **100% — `make` exits 0** | — |

### ✅ PR #1753 builds to completion on Fedora 44 / aarch64 / clang 22

With **five** documented deviations: four `-Wno-error=` relaxations (F4) and one
one-line libffi patch (F6). Artifacts produced, all `ELF 64-bit LSB executable,
ARM aarch64`:

```
src/startup/darling
src/startup/mldr/mldr
src/external/darlingserver/darlingserver
239 × *.dylib
```

This is, as far as we can tell, the **first independent build of this branch**, and it
is on a newer toolchain than the author's. Tier 0 is now **verified**, not claimed.

Confirmed building along the way: `cctools-port` (incl. `aarch64-apple-darwin20-ld`
and `-ar`), `libressl` (`libcrypto.41.dylib` links), `bash`, `security_codesigning`,
and **`Foundation`** (`NSArray.m`, `NSAttributedString.m`, `NSAutoreleasePool.m`
compiling) — i.e. tier-5 material is reaching the compiler.

A `make -k` run is enumerating the remaining blocker set in one pass rather than
one-at-a-time; see `~/build-k.log` in the VM.

## F7 — container never boots: `launchd` takes SIGSEGV on aarch64 🔴🔴

**The current blocker, and the most important open question.**

`darling shell` installs and runs, creates the prefix, then fails:
```
Setting up a new Darling prefix at ~/.darling
Error connecting to shellspawn in the container
  (~/.darling/var/run/shellspawn.sock): No such file or directory
```

With `DSERVER_LOG_LEVEL=debug DSERVER_LOG_STDERR=1` the cause is explicit:
```
Replying to call #12 (dserver_callnum_sigprocess) from PID 4, TID 4
  with result code 0, new_bsd_signal_number=11
sigexc: emulating default signal effects
```
**BSD signal 11 = SIGSEGV.** The container's first process (PID 4, `launchd`)
segfaults during boot; darlingserver applies default signal effects and terminates it,
so `shellspawn` never starts and its socket never appears.

Process-level symptom: `darlingserver` alive and spinning ~47% CPU while `[mldr]`
sits `<defunct>`.

Ruled out so far:
- **Not overlayfs.** `DARLING_NOOVERLAYFS=1` produces the identical failure (worth
  testing because dmesg shows `evm: overlay not supported`).
- **Not a missing install.** `make install` completed; `/usr/local/bin/darling` is
  present and correctly setuid-root; 239 dylibs and the full framework tree installed.
- **Not darlingserver startup.** It launches correctly via the setuid path (starting
  it by hand fails with `darlingserver needs to start as root` — a red herring).

`xdg-user-dir: command not found` appears 7× during prefix setup. Cosmetic (an
`xdg-user-dirs` package we didn't install), almost certainly unrelated to the SIGSEGV,
but installing it would remove noise from future traces.

### 🔬 Refined diagnosis (this is the important part)

**`launchd` is NOT the process that crashes.** It survives as container PID 1 and stays
running. Host-side view during boot, stable across the whole attempt:
```
162445 mldr  /sbin/launchd        <- container PID 1, ALIVE
162449 mldr  [mldr] <defunct>     <- container PID 4, DEAD within <1s
```

**This is meaningful positive evidence for tier 1.** `/usr/local/libexec/darling/sbin/launchd`
is a `Mach-O 64-bit arm64 executable`, and `mldr` loads and executes it successfully.
So the arm64 loader path fundamentally *works* — dyld (also arm64 Mach-O) initialises,
launchd runs, and it issues a long, healthy stream of Mach traps to darlingserver
(`task_self_trap`, `mach_reply_port`, `mach_msg_overwrite`, …).

**What actually dies is a daemon launchd spawns (container PID 4):**
```
162449(4): calling exception_triage_thread(1, [1, 0])
162449(4): exception_triage_thread returned
Replying to call #12 (dserver_callnum_sigprocess) ... new_bsd_signal_number=11
```
Mach exception type **1 = EXC_BAD_ACCESS**, code **1 = KERN_INVALID_ADDRESS**,
subcode **0** → **null-pointer dereference at address 0x0**, translated to SIGSEGV.

### 🎯 PID 4 identified: it is a **fork of launchd itself**

Bisected by disabling daemons, then caught directly by tight-looping
`/proc/<launchd>/task/*/children` (scanning all of `/proc` is far too slow — the child
lives ~1ms; see `scripts/41-watch-children.py`):

```
launchd host pid = 164225
CHILD pid=164229 comm='mldr' exe=.../libexec/darling/mldr
      cmdline='/sbin/launchd'
      early_maps=['.../usr/lib/dyld', ...]
```

Ruled out by bisection — the SIGSEGV fires at NSID 4 in **every** case:

| Configuration | signal-11 events | peak NSID |
|---|---|---|
| all daemons enabled | 1 | 4 |
| `org.darlinghq.shellspawn.plist` removed | 1 | 4 |
| `org.darlinghq.iokitd.plist` removed | 1 | 4 |
| **all 20 LaunchDaemons removed** | **1** | **4** |

So it is **not** a plist-driven daemon. Container topology is exactly two processes:
NSID 1 = launchd (NSID 2 and 3 are its *threads*), NSID 4 = a child launchd forks
~51ms after start. The child completes a full Darwin bootstrap against darlingserver —
`checkin`, `task_self_trap`, `mach_reply_port`, `thread_self_trap`,
`set_thread_handles`, `host_self_trap`, `mach_msg_overwrite` — and only then faults.
`cmdline` still reads `/sbin/launchd` because it was captured **pre-exec**.

**Strong lead:** the fault is in a forked child, and `darlinghq/darling-xnu#14` — part
of kkHAIKE's own PR set — is described as fixing "socket EMFILE retry, connect
O_NONBLOCK temp-clear, poll/pselect timespec, `__pipe.S` x9→x19, **fork/vfork/setjmp
ABI**, mremap_encrypted stub". The arm64 fork/setjmp ABI path is exactly where this
crash lives. Either that fix is incomplete, or something adjacent to it regressed on
a newer kernel/toolchain. **Start there.**

Secondary observation: darlingserver emits hundreds of
`(dtape, Warning) -1(-1):-1(-1): Trying to lock mutex without an active thread!`
immediately before and after the child is created — duct-taped XNU code being entered
without thread context. May be ordinary noise, may be related; worth a look while in
this code.

### ✅ CONFIRMED on a clean, independent foundation (2026-08-05)

F7 was originally found on the contaminated Fedora build, so it could not be trusted.
It has now been reproduced on the clean Debian 13 / clang 19 build — **byte-for-byte
identical signature**:

| | Fedora 44 / clang 22 / 5 deviations | Debian 13 / clang 19 / minimal justified patches |
|---|---|---|
| signal-11 events | 1 | 1 |
| peak NSID | 4 | 4 |
| exception | `exception_triage_thread(1, [1, 0])` | `exception_triage_thread(1, [1, 0])` |
| topology | PID 1 launchd (thr 2,3) + forked PID 4 | identical |
| timing | ~51ms after launchd | ~46ms after launchd |

**Two distros, two compilers, two independent build configurations, same crash.**
F7 is a genuine defect in PR #1753, not an artifact of environment or of any local
patch. This is the most solid result of the whole exercise and is directly reportable
upstream.

### 🏆 F7 ROOT CAUSE FOUND AND EXPLAINED (2026-08-07)

Resolved by reading deepai-org's private forks. **Hypothesis T1 was correct.**

kkHAIKE's arm64 port creates Darwin threads through a **thread bridge** in `mldr`:
a dedicated helper thread that services thread-creation requests via a futex-driven
request queue (`arm64_thread_create_submit`, `arm64_thread_create_request`,
`arm64_futex_wait/wake` in `src/startup/mldr/elfcalls/threads.c`).

`fork()` copies only the calling thread. **The bridge's helper thread does not
survive into the child.** Its lock/sequence/request state does, now permanently
stale — so the first post-fork operation that touches the bridge dereferences it
and faults. That is exactly what we observed: the child completes a full Mach/dyld
bootstrap (`checkin`, `task_self_trap`, `mach_reply_port`, `thread_self_trap`,
`set_thread_handles`, `host_self_trap`, `mach_msg_overwrite`) and *then* dies with
`EXC_BAD_ACCESS` / `KERN_INVALID_ADDRESS` at address **0**.

**deepai-org's fix — three coordinated commits:**

| Repo | Commit | Change |
|---|---|---|
| `libsystem` | `9f94638` *Complete ARM64 child recovery after malloc unlocks* | call `__darling_arm64_thread_bridge_postfork_complete()` in `libSystem_atfork_child()` **and** `libSystem_posix_spawn_child()` |
| `libc` | `f1861f2` *Restart ARM64 thread bridge after fork handlers* | same call in `fork()`'s child path in `sys/fork.c` |
| `libc` | `d0e34ed` *Move ARM64 postfork completion into libSystem* | consolidation |

The entry point chains into mldr:
```c
void __darling_arm64_thread_bridge_postfork_complete(void) {
    sys_fork_postfork_child();
    elfcalls()->arm64_thread_bridge_postfork_complete();
}
/* mldr side */
void __mldr_arm64_thread_bridge_postfork_complete(void) {
    if (arm64_thread_bridge_enabled)
        __mldr_arm64_thread_bridge_init();   /* respawn the helper thread */
}
```

**Ordering is the crux**, and it is why the commit is titled "after malloc unlocks":
in `libSystem_atfork_child()` the call is placed *after* `_malloc_fork_child()`.
Re-initialising the bridge allocates, so it must run once the allocator is usable in
the child — but before anything else tries to create a thread.

**Verified absent from Lane A.** In the kkHAIKE tree, all three greps return nothing:
```
grep -rl "arm64_thread_bridge"        src/   ->  (empty)
grep -rn "postfork_complete|postfork" src/external/libsystem/init.c src/external/libc/sys/fork.c  ->  (empty)
grep -rn "sys_fork_postfork_child"    src/   ->  (empty)
```

So PR #1753 ships an arm64 thread bridge with **no post-fork recovery whatsoever**.
Any forked child is broken by construction — which is why `launchd` (PID 1) runs
fine but the first process it forks always dies. F7 is not a subtle bug; it is a
missing subsystem.

**This also explains a governance detail:** deepai-org merged kkHAIKE's `dyld #5`,
`libsystem #7`, `libmalloc #3`, `libplatform #4` and `libpthread #3`, but used
**xnu #13 rather than his #14** and left PR #1753 unmerged as "ARM patches
overlapping newer private ARM64 implementations". Their post-fork work supersedes it.

**To fix Lane A** (if ever wanted): port the thread bridge plus the three commits
above. Not recommended — Lane B is far ahead. Recorded because the *mechanism* is
transferable knowledge and cost real effort to establish.

### Hypothesis status

1. ~~**Our build deviations.**~~ **Largely falsified.** F1 and F2 were subsequently
   fixed *properly* (see `scripts/patch-f1-f2.py`) — not suppressed — the tree
   rebuilt clean (`make` rc=0, zero errors) and reinstalled. **The boot fails
   identically.** F6 (libffi CFI) remains a theoretical contributor but libffi is not
   plausibly on shellspawn's early-boot path.
2. **The branch genuinely doesn't boot** on kernel 6.19 / Fedora 44 / clang 22.
   Still open, and now the leading explanation. The author's claims are ~3 months old
   against clang-19 on an unstated distro.
3. **A missing companion commit.** Still open. kkHAIKE forked 31 repos; `libkqueue`
   and `libffi` are *not* among them.

### Next diagnostic steps

- **Identify PID 4 definitively.** Wrap `/usr/libexec/shellspawn` and `/usr/sbin/iokitd`
  in logging shims, or have darlingserver log the exec path on process creation
  (it currently logs only "New process created with ID … and NSID …").
- **Get the faulting PC.** darlingserver's `sigexc` path already reads the thread
  state (`Successfully read 272 byte(s) at 0x3009c4c48`) — dump the register set and
  PC at fault rather than only translating to a signal number.
- Try `clang18` (`dnf install clang18`, point `Toolchain.cmake` at it) to narrow the
  toolchain gap from 3 major versions to 1.
- Ask kkHAIKE which distro/kernel/clang they validated on. Cheapest, highest-value
  action available — and they are demonstrably responsive on the PR.

---

## F9 — `sysctl_machdep.c` uses `strncmp` without declaring it (aarch64-only) 🔴

**Found on the clean Debian 13 / clang 19 foundation, so this one is trustworthy.**

```
src/external/xnu/darling/src/libsystem_kernel/emulation/src/xnu_syscall/
  bsd/helper/misc/sysctl_machdep.c:59:7: error:
  call to undeclared function 'strncmp'; ISO C99 and later do not support
  implicit function declarations [-Wimplicit-function-declaration]
```

The code sits inside `#if defined(__aarch64__) || defined(__arm64__)` — added by
kkHAIKE in `eebaed0 "Add ARM64 (aarch64) build support for Darling on Linux"`. The
block declares `extern char *strncpy(...)` but the CPU-count helper that scans
`/proc/cpuinfo` calls **`strncmp`**, which is never declared:

```c
while (__simple_readline(fd, &rbuf, line, sizeof(line))) {
    if (strncmp(line, "processor", 9) == 0)   /* <-- undeclared */
        count++;
}
```

**aarch64-only** — on x86_64 the whole block is preprocessed away, so the defect is
invisible there. Exactly the same class as F1. Fixed by `scripts/patch-f9.py`
(declare `strncmp` alongside `strncpy`); the proper upstream fix is to include
`<string.h>` or the project's `simple.h` equivalent rather than hand-declaring
libc functions one at a time, which is what created both F1 and F9.

## F10 / F11 — same class: aarch64 `#else` branches with missing includes 🔴

Two more instances found on the clean foundation, both structurally identical to F1
and F9. The syscall emulation layer is written as:

```c
#if defined(__NR_something)
    ... use the syscall directly ...
#else
    ... fall back to a related helper ...
#endif
```

On x86_64 the `#if` arm is always taken, so **every `#else` fallback is dead code that
has never been compiled by anyone**. aarch64 lacks many of these legacy syscalls, so
those branches come alive — and they routinely reference functions whose headers the
file never includes.

| ID | File | Missing | Why aarch64-only |
|---|---|---|---|
| F1 | `ext/sys/epoll.h` + `epoll_create.c` | `epoll_create1` decl | no `__NR_epoll_create` on aarch64 |
| F9 | `misc/sysctl_machdep.c` | `strncmp` decl | inside `#if defined(__aarch64__)` block |
| F10 | `select/select.c` | `#include .../select/pselect.h` | no `__NR_select` / `__NR__newselect` |
| F11 | `unistd/getpgrp.c` | `#include .../unistd/getpgid.h` | no `__NR_getpgrp` |

F10 and F11 are fixed the **right** way — adding the missing `#include`, not
hand-declaring the symbol. F1 and F9 hand-declare only because the surrounding code
already does so; upstream should really include the proper headers in all four.

### Exhaustive sweep — this class is now closed

Rather than discovering these one slow build cycle at a time, every C source in the
emulation layer was compiled with `-fsyntax-only` using the target's real flags:

```
compiled 285 files
ALL undeclared-function errors:  1  ('sys_getpgid')
any other error kinds:           none
```

So after F1/F9/F10/F11 there are **no further missing-declaration defects anywhere in
the 285-file emulation layer**. Worth reporting upstream as a class, with the
recommendation that CI build the aarch64 target — these are invisible on x86_64 by
construction.

*(Method note: the first sweep attempt reported zero errors because shell
word-splitting mangled `-DEMULATED_VERSION="\"Darwin Kernel Version 20.6.0\""`. Zero
findings from a new harness deserves suspicion, not celebration — always verify the
harness ran.)*

### Why this matters more than the count suggests

On **clang 19 with zero relaxation flags**, the build produced **exactly one error** —
this one. Compare:

| Environment | Errors | Nature |
|---|---|---|
| Fedora 44 / clang 22 | cascade (F1, F2, F6) | mostly compiler-strictness noise |
| Fedora 44 / clang 18 | 94 | all inside libstdc++ 16 headers — unusable pairing |
| **Debian 13 / clang 19** | **1** | **a genuine arm64 code defect** |

That is the signal-to-noise difference a correct environment makes, and it is the
clearest possible vindication of the methodological correction above.

## F12 — ruby/fiddle selects an API that does not exist on arm64 Apple 🔴

**The most interesting arm64 finding after F7 — a genuine platform-semantics bug,
not a missing declaration.**

```
src/external/ruby/ruby/ext/fiddle/closure.c:264:14: error:
  call to undeclared function 'ffi_prep_closure'
```

fiddle chooses its libffi closure API with a platform heuristic:

```c
#if defined(USE_FFI_CLOSURE_ALLOC)
#elif defined(__OpenBSD__) || defined(__APPLE__) || defined(__linux__)
# define USE_FFI_CLOSURE_ALLOC 0     /* <-- taken: Darling defines __APPLE__ */
```

`USE_FFI_CLOSURE_ALLOC 0` selects the **legacy** `ffi_prep_closure()` + `mprotect()`
path. That was a safe assumption on x86 macOS. It is wrong on Apple arm64:

| SDK header | `FFI_LEGACY_CLOSURE_API` |
|---|---|
| `ffitarget_x86.h` | **1** |
| `ffitarget_arm64.h` | **0** |
| `ffitarget_armv7.h` | 0 |

With it 0, Apple's `ffi.h` guards the declaration out entirely
(`#if FFI_LEGACY_CLOSURE_API` at ffi.h:341). The legacy API writes inline
executable trampolines, which is incompatible with W^X and pointer authentication —
so Apple removed it on arm64 by design.

The modern pair (`ffi_closure_alloc` / `ffi_prep_closure_loc`) is declared
unconditionally, and **fiddle already implements that path**; it just never selects
it. `scripts/patch-f12.py` picks it explicitly on arm64 Apple before the stale
heuristic runs.

Why this class matters more than the missing-declaration class: F1/F9/F10/F11 are
"nobody compiled this branch". F12 is **"the platform's rules changed and the
heuristic wasn't updated"** — the same shape of bug likely lurks anywhere else in the
tree that treats `__APPLE__` as implying x86 semantics. Worth grepping for as a class.

## F13 — `use_ld64()` adds `-dylib_file` mappings without build dependencies 🔴

**Found in Lane B (deepai-org north-star). A nondeterministic parallel-build race.**

`bootstrap-stable.sh` failed here:
```
[5/5] Linking C executable src/external/foundation/defaults
ld: file not found: /usr/lib/system/libsystem_sandbox.dylib for architecture arm64
```

The message is misleading — nothing is missing. `cmake/use_ld64.cmake` appends
roughly 150 `-Wl,-dylib_file,<install-name>:<build-path>` mappings to every target
it is applied to, including:
```
-Wl,-dylib_file,/usr/lib/system/libsystem_sandbox.dylib:/work/build-arm64/src/sandbox/libsystem_sandbox.dylib
```
and that mapping **is** present in the generated link command. But the ninja edge is:
```
build src/external/foundation/defaults: C_EXECUTABLE_LINKER__defaults_ <obj> \
  | src/external/libsystem/libSystem.B.dylib src/external/foundation/Foundation \
  || .../arm64-apple-darwin20-ld .../libcrt1.10.6.a Foundation_arm64 libSystem.B.dylib
```
`src/sandbox/libsystem_sandbox.dylib` appears **nowhere** in the dependency list.

So the mappings create a link-time requirement with no corresponding build-order
constraint. Under `-j12`, `defaults` can be linked before `libsystem_sandbox.dylib`
has been produced, and ld64 reports the *install name* (`/usr/lib/system/...`) as
missing rather than the mapped path — which sends you hunting for a library that
was never supposed to exist on disk.

**Consequences**
- The failure is **nondeterministic** — it depends on scheduling, so it may not
  reproduce on a rebuild or on a machine with different core counts.
- An incremental re-run usually succeeds, because by then the dylib exists. That
  makes it easy to misdiagnose as transient rather than structural.
- Any of the ~150 mapped dylibs can trigger it, not just sandbox.

**Proper fix:** `use_ld64()` should add the mapped build-tree paths as target
dependencies (e.g. `add_dependencies()` for the ones built in-tree), so ninja
orders them. **Workaround used here:** re-run the build; the second pass links
against artifacts the first pass produced.

**Verification that nothing was actually missing:**
```
$ file build-arm64/src/sandbox/libsystem_sandbox.dylib
Mach-O 64-bit arm64 dynamically linked shared library, flags:<NOUNDEFS ...>   (70084 bytes)
```

*(Method note: I first concluded the mapping was absent, based on grepping
`CMakeFiles/defaults.dir/link.txt`. That file only exists for CMake's Makefile
generator — this build uses ninja, so its absence proved nothing. Check the
generator before trusting generator-specific artefacts.)*

## F14 — north-star container image is missing `libbsd-dev` (and the multiarch bridge) 🟡

**Lane B. Two stacked problems, both only visible on a clean build.**

```
FAILED: src/bsdln/CMakeFiles/bsdln.dir/ln.c.o
error: 'bsd/string.h' file not found
```

1. `darling-aarch64-getting-started/Dockerfile` **does not install `libbsd-dev`**
   at all (`dpkg -l | grep -c libbsd-dev` → 0 in their image), yet `src/bsdln`
   includes `<bsd/string.h>`.
2. Installing it is not sufficient. Ubuntu places the header at the **multiarch**
   path `/usr/include/aarch64-linux-gnu/bsd/string.h`. These translation units are
   compiled with `-nostdinc` and `-target aarch64-apple-darwin20`, so multiarch
   include directories are not searched.

Fix applied — a derived image adding the package *and* bridging the path:
```dockerfile
FROM darling-arm64-dev:latest
RUN apt-get update && apt-get install -y --no-install-recommends libbsd-dev \
 && ln -sfn /usr/include/aarch64-linux-gnu/bsd /usr/include/bsd
```

Same shape as the Debian `/usr/include/asm` bridge needed in Lane A (STATE.md).
**Distro-layout assumptions are a recurring theme:** Darling's build expects the
Fedora-style non-multiarch include layout, and every Debian-family host needs
bridging.

## F15 — `darling-coredump` (host tool) cannot find `mach/arm/boolean.h` 🟡

```
FAILED: src/hosttools/CMakeFiles/darling-coredump.dir/src/coredump/main.cpp.o
error: 'mach/arm/boolean.h' file not found
```

The header **does exist**, at
`Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/mach/arm/boolean.h`.

`darling-coredump` lives under `src/hosttools` — it is compiled as a **native Linux
host tool**, not a Darwin target, so the Darwin SDK include path is not on its
search path. On x86_64 the equivalent `mach/i386/*` path was evidently wired up;
the `mach/arm/*` case was not. An arm64-specific gap in host-tool include wiring.

Non-blocking for the runtime (it is a debugging aid), so deferred rather than
patched.

## F16 — `stage-link` sysroot is consumed by the tooling but created by nothing 🔴

**The blocker that stops a clean north-star reproduction, and the least obvious one.**

`tools/stage-darling-arm64.sh` uses it twice:
```sh
common="... -Wl,-syslibroot,/work/build-arm64/stage-link -nostdlib"   # line 52
cp -aL /work/build-arm64/stage-link/usr/lib/. /work/install/root/usr/lib/   # line 123
```
`tools/darling-arm64-smoke.sh` and JavaScriptCore's `generate-offlineasm.sh` use it
too. **Nothing creates it:**
- not a ninja target — `grep -c stage-link build.ninja` → **0**
- no cmake rule, no script, nothing in `darling-aarch64-getting-started`

`darling-aarch64-port-report.md:27` gives it away: *"a temporary **symlink-only**
link stage under `build-arm64/stage-link`"* — built by hand during development and
never automated.

**Symptom on a clean machine:** `build-headless.sh` completes **every** ninja step
("no work to do" ×4 — ash/cat/env/vim/libdispatch/notifyd, Foundation,
libsystem_info, defaults/plutil all built) and then dies at the first hand-rolled
smoke-binary link with:
```
ld: file not found: /usr/lib/system/libsystem_sandbox.dylib for architecture arm64
```
That reads as a missing library. It is actually a **missing sysroot** — those links
deliberately do *not* carry the `-dylib_file` mappings, relying on `-syslibroot`
instead. This is the same error text that appears when a `-dylib_file` mapping is
genuinely unsatisfied, which is what made it so confusing to chase.

**Fix — `scripts/71-make-stage-link.sh`.** `cmake/use_ld64.cmake` already encodes
the complete mapping as `-dylib_file <install_name>:<build_path>` — literally
"where Darwin thinks this library lives" → "where we built it". Mirroring that into
a symlink tree reconstructs the sysroot deterministically:
```
distinct mappings: 145
linked:            48
not built:         97   (GUI/optional components, expected under COMPONENTS=core)
OK /usr/lib/system/libsystem_sandbox.dylib -> .../src/sandbox/libsystem_sandbox.dylib
OK /usr/lib/libSystem.B.dylib              -> .../src/external/libsystem/libSystem.B.dylib
OK /usr/lib/system/libsystem_kernel.dylib  -> .../libsystem_kernel_firstpass.dylib
OK /usr/lib/libobjc.A.dylib                -> .../src/external/objc4/runtime/libobjc.A.dylib
```
Symlink targets keep the **container** path (`/work/build-arm64/...`) because they
are dereferenced inside docker.

**This is the highest-value thing to send deepai-org** — it is the one gap that
makes their "fresh-system reproduction guide" unable to reproduce on a fresh system,
and the fix is ~30 lines derived from data already in their build.

### Revision to F13

F13 claimed `use_ld64()`'s missing dependency edges caused the `defaults` link
failure. That is **partly wrong**. The dependency edges genuinely are absent (that
part stands, and is worth fixing), but `defaults`/`plutil` link fine once the full
graph is built — the persistent `libsystem_sandbox.dylib` failure was **F16**, the
absent sysroot, surfacing through an identical error message. Treat F13 as a latent
robustness issue, not the cause of the observed breakage.

## F17 — `build-gui.sh` cannot configure on a clean tree (`COMPONENTS=gui`) 🔴

```
CMake Error at cmake/use_ld64.cmake:184 (add_dependencies):
  The dependency target "UIFoundation" of target "AppKit" does not exist.
Call Stack: src/external/cocotron/AppKit/CMakeLists.txt:587 (reexport)
```

`build-gui.sh` configures a **fresh, separate** build tree with
`-DCOMPONENTS=gui -DCOMPONENT_gui=ON`. But AppKit (in `gui`) re-exports
`UIFoundation`, and `src/private-frameworks/CMakeLists.txt:85` gates
`add_subdirectory(UIFoundation)` behind **`COMPONENT_gui_stubs`** — a different
component. So CMake generation fails before a single object is compiled.

Fix: `COMPONENTS=gui_stubs`, which per `cmake/darling_parse_components.cmake`
depends on `gui dev_gui_stubs_common` and is therefore a superset. Configure then
succeeds (19,897 build edges).

Presumably works on their machines because the GUI tree already existed with a
wider component set from earlier work — same class as F16: the published scripts
encode what works on a machine that already has state.

## F15 (RESOLVED) — mldr's include tree has no `mach/arm/` architecture headers 🔴

Originally logged as non-blocking (it only broke the optional `darling-coredump`
host tool under `-k`). It is **fatal** for the GUI build, which has no `-k`.

Root cause is exact. `src/startup/mldr/include/mach/machine/boolean.h` dispatches
correctly:
```c
#if defined (__i386__) || defined(__x86_64__)
#include "mach/i386/boolean.h"
#elif defined (__arm__) || defined (__arm64__) || defined(__aarch64__)
#include "mach/arm/boolean.h"
#else
#error architecture not supported
#endif
```
but mldr's include tree contains **only `mach/i386/`** — the `mach/arm/` directory
was never created. The x86 side ships `boolean.h`, `vm_param.h` and `vm_types.h`,
so all three arm counterparts are needed.

Fixed by copying the canonical versions from the in-tree SDK
(`Developer/Platforms/MacOSX.platform/.../usr/include/mach/arm/`) into
`src/startup/mldr/include/mach/arm/`. These are Apple's own headers already present
in the repository — no new content, just wiring the arm64 path that x86 already had.

A clean example of the project's dominant defect class: **the arm64 branch of an
existing `#if`/`#else` was written but the files it needs were never added**, and
nobody noticed because x86_64 always takes the other branch.

## F18 — Apple's `libkern/OSByteOrder.h` doesn't recognise `__aarch64__` 🔴

**The subtlest arm64 finding so far.** Apple's header dispatches:
```c
#if (defined(__i386__) || defined(__x86_64__))
#include <libkern/i386/OSByteOrder.h>
#elif defined (__arm__) || defined(__arm64__)
#include <libkern/arm/OSByteOrder.h>
#else
#include <libkern/machine/OSByteOrder.h>
#endif
```
`__arm64__` is **Apple's** spelling. Host-side tools like `darling-coredump` are
built as native Linux binaries for `aarch64-linux-gnu`, where clang defines
**`__aarch64__`** and *not* `__arm64__` — so they match neither branch and fall
through to `libkern/machine/OSByteOrder.h`, which does not exist in mldr's include
tree.

Fixed without touching Apple's header: supply `libkern/arm/OSByteOrder.h` (symlink
to the SDK's) plus a small `libkern/machine/OSByteOrder.h` forwarder. Also wired
`include/arm` and `include/architecture/arm` to the SDK, since the chain continues
(`libkern/arm/OSByteOrder.h` → `arm/arch.h` → …).

**Effect:** GUI build progressed from edge 43 to **5791/19614**.

⚠️ **Symlinks must be RELATIVE.** The source tree is bind-mounted into the build
container at `/work/source`, so an absolute host path (`/home/<user>/darling/...`)
resolves on the host but breaks inside docker. The pre-existing i386 symlinks are
relative; match that. (Cost one wasted build cycle.)

## F19 — `liblzma` passes `-msse` on arm64; not covered by the mirror map 🔴

```
error: unsupported option '-msse' for target 'arm64-apple-darwin20'
```
`src/external/liblzma/CMakeLists.txt:10` sets `-msse -msse2 -msse3`
unconditionally. clang ≤ 11 ignored these on aarch64; clang ≥ 16 makes them a hard
error.

kkHAIKE fixed exactly this class upstream (`darling-liblzma#2`, "-msse* gated by
target arch"), but **deepai-org's `configure-private-submodules.sh` mirror map does
not include liblzma** — so on a clean north-star checkout the submodule resolves to
unpatched `darlinghq/darling-liblzma` and ~6 objects fail.

Fixed by gating the flags on `TARGET_x86_64 OR TARGET_i386`
(`scripts/patch-f19.py`). Worth reporting: either add liblzma to their mirror map,
or upstream the gate.

## F20 — `liblzma/config.h` is a checked-in x86 autoconf result 🔴

```
immintrin.h:14:2: error: "This header is only meant to be used on x86 and x64 architecture"
mmintrin.h: invalid conversion between vector type '__m64' and integer type 'int'
hresetintrin.h:42:27: invalid input constraint 'a' in asm
```
`src/external/liblzma/config.h` is an autoconf output **captured on an x86 host and
committed**, so it hardcodes `#define HAVE_IMMINTRIN_H 1`. `memcmplen.h` then does
`#ifdef HAVE_IMMINTRIN_H → #include <immintrin.h>`, dragging x86 SIMD intrinsics
into an arm64 compile.

Fixed by making the define architecture-conditional (`scripts/patch-f20.py`) rather
than deleting it, so x86 builds keep the SSE2 fast path.

**Generalisable warning:** any checked-in `config.h`/`config.status` in this tree is
an x86 artefact and is suspect for arm64. Worth auditing the other vendored
libraries for the same pattern.

## F21 — bash's `conftypes.h` has no arm64 branch 🔴

```
shell.c:1799:74: error: use of undeclared identifier 'CONF_HOSTTYPE'
  (expanded from MACHTYPE -> HOSTTYPE)
```
`src/external/bash/bash-3.2/conftypes.h` selects `HOSTTYPE` per architecture —
`__ppc__`, `__x86_64__`, `__i386__`, `__arm__` — with `#else #define HOSTTYPE
CONF_HOSTTYPE`. There is **no `__arm64__`/`__aarch64__` branch** (only 32-bit
`__arm__`), so arm64 falls to `CONF_HOSTTYPE`, which nothing defines.

Fixed by adding an arm64 branch defining `HOSTTYPE "arm64"` — matching what macOS
reports for `uname -m` on Apple Silicon, so `MACHTYPE` becomes
`arm64-apple-darwin<N>` consistently with the rest of the toolchain.

**Fifth instance of the dominant defect class.** F1, F9, F10, F11, F15, F18, F21 are
all: *an architecture dispatch exists, the arm64 arm of it was never written or
never given its files.* Invisible on x86_64 by construction. If deepai-org want one
systemic improvement, it is a CI job that compiles the aarch64 target.

## F22 — `dbuskit` calls an `IMP` without casting it 🔴

```
DKArgument.m:993:56: error: too many arguments to function call, expected 0, have 2
    *buffer = (long long)(uintptr_t)(void*)unboxFun(value, aSelector);
```
```objc
IMP unboxFun = [value methodForSelector: aSelector];
*buffer = (long long)(uintptr_t)(void*)unboxFun(value, aSelector);
```
In the modern Objective-C runtime `IMP` is `id (*)(void)` — deliberately
argument-less, so callers are forced to cast to the real signature first.

**Why this matters more on arm64 than x86_64:** the AAPCS passes variadic and
non-variadic arguments differently, so calling through an unspecified-prototype
pointer is a genuine ABI correctness problem, not merely a compiler complaint.
Fixed by casting to `void* (*)(id, SEL)` before invoking.

Like `liblzma` (F19), **`dbuskit` is absent from deepai-org's mirror map**, so a
clean checkout gets unpatched `darlinghq/darling-dbuskit`. kkHAIKE carried a fix for
this component (`darling-dbuskit#1`) that deepai-org did not take.

**Pattern worth reporting:** their `configure-private-submodules.sh` map has 32
entries, but the tree needs arm64 fixes in at least **liblzma** and **dbuskit** too.
Any component not in the map silently falls back to unpatched upstream — and the
resulting failure looks like a generic compile error, not a missing-mirror problem.

## F23 — `build-gui.sh`'s install step doesn't mount the source tree 🔴

```
CMake Error at build/src/external/cocotron/CoreGraphics/X11.backend/cmake_install.cmake:63 (file):
  file INSTALL cannot find
  "/work/source/src/external/cocotron/CoreGraphics/X11.backend/Info.plist":
  No such file or directory.
```

The file **exists**. The problem is the third docker invocation in `build-gui.sh`:
```sh
docker run --rm --platform linux/arm64 \
    -v "$build:/work/build" -v "$stage.tmp:/work/stage" \
    "$image" bash -lc 'DESTDIR=/tmp/gui-dest cmake --install /work/build --component gui ...'
```
It mounts the build tree and the staging tree but **not the source tree**, while the
generated `cmake_install.cmake` contains `install(FILES ...)` rules that reference
absolute `/work/source/...` paths — e.g.
`cocotron/CoreGraphics/CMakeLists.txt:155`,
`install(FILES ${BACKEND_INFO_PLIST} ... RENAME Info.plist)`.

Compilation therefore completes 100% and the failure only appears at install time,
which makes it look like a missing file rather than a missing mount.

Fix: add `-v "$source_root:/work/source:ro"` to that step (the first two steps
already mount it).

**Notable:** this is the fourth defect in the same script family (F16 stage-link,
F17 component set, F23 install mount). Their published scripts consistently work
on a machine that already has state, and consistently fail on a clean one — which
is precisely what `darling-aarch64-getting-started` claims to support.

## F24 — modal-dialog click events do not reach their handler 🔴 CURRENT FRONTIER

**This is the live blocker, and everything around it works.**

`verify-x11-backend-darling-arm64.sh` fails at line 318:
```sh
xdotool mousemove --window "$modal_window" 80 60 click 1
for attempt in {1..50}; do
    [[ -f $prefix/private/var/tmp/x11-backend-modal-click ]] && break
    sleep 0.05
done
test "$(cat ".../x11-backend-modal-click")" = clicked     # <-- line 318
```
The marker never appears within 2.5 s.

**Everything preceding it passes**, which makes this a narrow, well-scoped defect:

| Checked before the failure | Result |
|---|---|
| main window created, `ready` marker | ✅ |
| screen geometry `1000x680@2` (HiDPI scale factor honoured) | ✅ |
| focus, resize, cursor (`xterm`), font (`San Francisco`) | ✅ |
| keyboard events with full modifier decode (shift/control/option/command/caps/repeat/keyCode) | ✅ |
| scroll-wheel phase/momentum/precise/delta | ✅ |
| modal dialog created, `modal-ready` marker | ✅ |
| `_NET_WM_WINDOW_TYPE_DIALOG` | ✅ |
| `_NET_WM_STATE_MODAL` | ✅ |
| `WM_STATE: Normal`, `WM_PROTOCOLS: WM_DELETE_WINDOW`, `_NET_WM_ACTION_CLOSE` | ✅ |
| `WM_TRANSIENT_FOR` → main window | ✅ |
| **click on main window correctly BLOCKED while modal is up** | ✅ |
| **click on modal window reaches its handler** | ❌ |

So modal *semantics* are correct — input to the parent is properly suppressed —
but input delivery *into* the modal window does not arrive. That points at event
routing/targeting for transient windows rather than anything structural.

### Session 2 (2026-08-09) — root cause identified, fix insufficient alone

**Observability fixed first.** The previous session's "instrumentation produced no
output" was not a contradiction: the verifier never captured application stderr at
all (its whole run log was three lines, zero `objc[…]`). All six verifiers with a
`cleanup()` EXIT trap now copy `/tmp/stage*.{err,out}` into the bind-mounted
`/artifacts`, which survives both assertion failures and `timeout` SIGKILLs
(`scripts/80-make-gui-observable.py`). With that, the traces worked immediately.

**What the traces established** (per-ButtonPress, from the X11 backend):

```
xid=0x20000a title='…Smoke — UTF-8' attachedSheet=nil                    key=1 vis=1
xid=0x20000a title='…Smoke — UTF-8' attachedSheet=Darling ARM64 X11 Modal key=1 vis=1
xid=0x200018 title='Darling ARM64 X11 Modal' attachedSheet=nil            key=0 vis=1
raw=(80,60) transformed=(80.0,40.0) frame=(602.0,352.0,240.0x100.0)
```

1. **Modal blocking genuinely works** — the parent's click is swallowed only while
   `attachedSheet` is non-nil. *This reinstates the claim withdrawn last session;
   it is now directly evidenced rather than inferred from a missing marker.*
2. **The sheet's click is delivered, not swallowed** — it resolves via
   `windowForID:`, has `attachedSheet=nil`, and passes the modal guard.
3. **Coordinates are correct** — `raw=(80,60)` → `transformed=(80,40)`, comfortably
   inside a 240×100 frame (y-flip 100−60=40). The geometry-mismatch hypothesis is
   **dead**.
4. **The sheet is never key** — `key=0` while the main window is `key=1`, and
   `-mouseDown:` demonstrably works on the main window (verifier line 261 asserts
   the marker is non-empty and passes). AppKit does not route mouse input into a
   non-key window.

**Root cause located.** `AppKit/NSWindow.m:3082`,
`-_attachSheetContextOrderFrontAndAnimate:` ends with:
```objc
[[sheet platformWindow] sheetOrderFrontFromFrame: sheetFrame
                                     aboveWindow: [self platformWindow]];
[self makeKeyWindow];        // `self` is the PARENT window
```
Presenting a sheet makes the **parent** key. macOS makes the *sheet* key.

**Fix applied** (`scripts/patch-f24-fix.py`): `[sheet makeKeyWindow]`.
**Regression guard: 11/11 still passes**, so the change is safe to keep.

⚠️ **But it does not fix F24 on its own.** After the change the sheet still reports
`key=0` at click time and the verifier still fails at the same assertion. The fix is
retained because it is correct by macOS semantics and harmless, but something later
un-keys the sheet or `makeKeyWindow` does not take effect for a
`NSDocModalWindowMask` window whose platform window may not accept focus.

⚠️ **Line numbers moved.** The failure now reports "near line 324" rather than 318.
That is **not progress** — the observability patch added six lines near the top of
each verifier, shifting everything below by six. Same assertion.

**Next step:** trace `-makeKeyWindow` / `-becomeKeyWindow` on the sheet to find
whether it is never called, called and rejected, or called and then reverted —
likely in `NSWindow -makeKeyWindow` or the X11 platform window's focus handling
(`X11Window.m`, `XSetInputFocus`). Note the sheet is restyled to
`NSDocModalWindowMask` at `NSWindow.m:3066`, which may affect whether the WM will
give it focus.

### Investigation log (overnight 2026-08-08) — superseded by the above

**What was examined.** `X11Display.m:1086 postXEvent:` contains a modal guard that
*discards* the event:
```objc
NSWindow *sheet = [delegate attachedSheet];
if (sheet != nil || [delegate platformWindowIgnoreModalMessages:window]) {
    [modalWindow makeKeyAndOrderFront:delegate];
    return;                       // event dropped
}
```
and the fixture (`src/tools/x11-backend-smoke.m:216`) creates the dialog with
`[NSApp beginSheet:panel modalForWindow:mainWindow ...]`, so `mainWindow`
permanently has a non-nil `attachedSheet`. That looked decisive.

**Ruled out along the way:**
- `NSWindow.platformWindowIgnoreModalMessages:` (`NSWindow.m:3322`) is correct —
  it returns NO when `self` is the modal window.
- `CGSConnectionX11.m` has its own `XNextEvent` loop (line 351) whose
  `processXEvent:` is a **stub** (every case an empty `break;`), which looked like
  it might silently drain events. It does not: CoreGraphics and AppKit each call
  `XOpenDisplay` separately (`CGSConnectionX11.m:57`, `X11Display.m:93`), so they
  have independent event queues.
- `X11Display.processPendingEvents` (line 1517) is unfiltered — every event
  reaches `postXEvent:`.

**Unresolved contradiction.** A `fprintf` trace was added to `postXEvent:` for
`ButtonPress` only, the `X11_backend` target rebuilt, and the backend re-staged
(byte-grep confirms the trace string is present in both the object and the staged
`X11` binary). Re-running the verifier produced **zero** trace lines — yet the
scroll-phase marker was regenerated in that same run, and scroll arrives as
`ButtonPress` on Button4/5. Those two facts cannot both be true as understood.

**Most likely explanation, untested:** the running app loads its X11 backend from a
path other than the one staged into `install-arm64-stage10`. Next step is to
confirm which binary is actually mapped at runtime (e.g. log from
`+load`/constructor, or check the process's mapped images) *before* drawing any
further conclusions about event routing.

⚠️ **Correction to the claim above.** The table earlier in this entry states that
"click on parent correctly BLOCKED" demonstrates working modal semantics. That is
**not established**. The verifier asserts `test ! -e .../x11-backend-mouse` — the
*absence* of a marker — which is satisfied equally by correct modal blocking and by
the event never reaching the application at all. Given the trace result, the
vacuous explanation is now at least as likely. Do not treat modal input-blocking
as verified.

**Where to look next:** first establish which backend binary is loaded, then
re-instrument. Only after a trace actually fires does the modal-guard analysis
above become worth acting on.

**Note on the earlier "inconclusive" reading:** I previously reported this failure
as undiagnosable because the container is `--rm`. That was wrong — the verifier
bind-mounts `-v "$artifact_root:/artifacts"`, so screenshots and phase markers
**do** survive at `~/darling/artifacts/stage11-x11/`. Always check for an artifact
mount before concluding evidence was lost.

---

### F24 root cause — Cocotron inverts `makeKeyWindow` / `becomeKeyWindow`

Established by reading the implementation, not by tracing. Four lines settle it:

| site | code |
|---|---|
| `NSWindow.m:1621` | `- (BOOL) isKeyWindow { return [NSApp keyWindow] == self; }` |
| `NSWindow.m:1848` | `- (void) makeKeyWindow { [[self platformWindow] makeKey]; …key-view loop… }` |
| `NSWindow.m:1889` | `[NSApp _setKeyWindow: self];` — inside `-becomeKeyWindow` |
| `X11Window.m:559` | `- (void) makeKey { [self ensureMapped]; XRaiseWindow(…); }` |

`-[NSApplication _setKeyWindow:]` is called from **exactly one** site in
`NSWindow.m`, and that site is inside `-becomeKeyWindow`. So in Cocotron the two
selectors are the reverse of real AppKit: `-makeKeyWindow` only pokes the platform
window (map + raise), while `-becomeKeyWindow` performs the actual state
transition. **`-makeKeyWindow` can never change what `-isKeyWindow` returns.**

The first F24 fix called `[sheet makeKeyWindow]`. It raised the sheet's X window
and recalculated its key-view loop — and did nothing else. That is precisely why
the sheet still reported `key=0` afterwards. The fix was inert by construction,
not defeated by some later event reordering.

Corrected fix: `[sheet becomeKeyWindow]` (`scripts/patch-f24-fix2.py`).
`-becomeKeyWindow` calls `-makeKeyWindow` itself, so the map-and-raise is retained.

**Second, independent defect — `canBecomeKeyWindow` excludes every sheet.**

```objc
NSWindow.m:1641  - (BOOL) canBecomeKeyWindow {
                     return (_styleMask & (NSTitledWindowMask |
                                           NSResizableWindowMask)) != 0; }
NSPanel.h:24     NSDocModalWindowMask = 0x40
NSWindow.m:41-45 NSTitledWindowMask = 0x01, NSResizableWindowMask = 0x08
NSWindow.m:3066  if ([sheet styleMask] != NSDocModalWindowMask)
NSWindow.m:3067      [sheet setStyleMask: NSDocModalWindowMask];   // exactly 0x40
```

`0x40 & (0x01 | 0x08) == 0`, so `-canBecomeKeyWindow` is **NO for every sheet**.
Both generic activation paths are guarded by it — `-makeKeyAndOrderFront:`
(line 2700) and `-_windowDidBecomeActive` (line 3130) — so neither will ever make
a sheet key. On macOS a document-modal sheet *is* key while presented, so the
predicate is wrong; it should admit `NSDocModalWindowMask`.

Deliberately **not** changed in the same pass — that would move two variables at
once. It is recorded here as the next single change if `becomeKeyWindow` alone
proves insufficient or doesn't survive an activation cycle.

### ⚠️ F24 WITHDRAWN AS A DEFECT — the premise was wrong and the verifier was flaky

The corrected fix was built, staged and traced. The trace fires cleanly and proves
the key-window mechanics, but a **control run settles it the other way**.

Trace, with `[sheet becomeKeyWindow]` applied:
```
[F24/k] after becomeKeyWindow: sheet='Darling ARM64 X11 Modal' sheetKey=1
        appKey='Darling ARM64 X11 Modal' canBecomeKey=0 styleMask=0x40
[F24/x] xid=0x20000a title='…Smoke — UTF-8' sheet='…Modal' key=0 swallow=1   ← parent click blocked
[F24/x] xid=0x200018 title='…Modal' sheet='(null)' key=1     swallow=0   ← sheet click passes
[F24/a] NSLeftMouseDown window='Darling ARM64 X11 Modal' loc={80, 40}
[F24/w] window='…Modal' key=1 loc={80, 40} hit=NorthStarModalView
```
That is a complete, correct modal round-trip: parent clicks swallowed, sheet
clicks delivered to `NorthStarModalView`. It also confirms the static reading —
`canBecomeKey=0`, `styleMask=0x40`.

**But the control run passes too.** Reverting `NSWindow.m` to pristine, rebuilding
and re-running `verify-x11-backend` three times gave **rc=0, rc=0, rc=0**. With the
fix applied the same three-run sequence gave **rc=0, rc=0, rc=124**. The patch is
not what makes the verifier pass; the verifier passes without it.

**The premise was false.** F24 was built on "AppKit does not route mouse events
into a non-key window". `-[NSWindow sendEvent:]` (NSWindow.m:2463) disproves it:
```objc
case NSLeftMouseDown: {
    NSView *view = [_backgroundView hitTest: [event locationInWindow]];
    if ([view acceptsFirstResponder]) { … }
    [view mouseDown: event];        // unconditional — no key-window test
```
Cocotron delivers mouse-down by hit-test alone. Key status is irrelevant to it, so
a non-key sheet was never going to drop clicks.

**What was actually failing.** The real stage-11 failure is recorded in F29 below:
the app takes longer than 10 s to exit after `alt+F4`, and `timeout 10s tail
--pid=$server_pid` expires. It is intermittent — 6 passes in 8 runs today.

**Why it was misread for days.** The ERR trap reported only
`${BASH_LINENO[0]}`, which does **not** agree with `$BASH_COMMAND` in this script.
It said "line 318", then "line 324" after the observability patch shifted lines,
and both pointed at the modal-click assertion. Printing `$BASH_COMMAND`
(`scripts/patch-f24-diag5.py`) showed the failing command on the very first run:
```
Stage 11 verifier failed near line 330 (status 124).
  failing command: timeout 10s tail --pid="$server_pid" -f /dev/null
```
Status 124 was `timeout`'s own exit code all along — it never belonged to a line
that runs no `timeout`. That mismatch was visible in the status from the start and
was not questioned.

**Second reason it was misread.** The failure listing showed no
`x11-backend-modal-*` markers, which read as "the modal phase never got that far".
It is not evidence: `$prefix` is reassigned per sub-phase, so the listing reflects
whichever prefix was current at failure (the randr phase), not the phase that
failed. Its contents (`x11-backend-phase = pasteboards`) are startup markers from a
*later* app launch.

**Disposition of the patch.** `[sheet becomeKeyWindow]` is **kept**, relabelled from
"fix" to *semantic correction*: on macOS a document-modal sheet is key while
presented, the trace shows the change achieves exactly that, and it matters for
anything that depends on first responder or key state inside a sheet (a text field
in a sheet, for one). It is explicitly **not** credited with fixing any verifier.

`canBecomeKeyWindow` excluding `NSDocModalWindowMask` (below) is left unchanged and
still looks wrong, but with no test that distinguishes it there is nothing to
measure a change against.

**Third observation — nothing in Cocotron ever calls `XSetInputFocus`.**
`grep -rn XSetInputFocus src/external/cocotron/` returns **zero hits**. The X11
backend's `makeKey` is `ensureMapped` + `XRaiseWindow`. Keyboard input therefore
arrives only by whatever focus policy the window manager applies; AppKit never
asserts focus itself. That has not bitten the passing verifiers (typing works in
TextEdit and TextView), but it is a latent divergence from macOS worth recording,
and it is the reason a raised-but-unfocused sheet is possible at all.

## F25 (RESOLVED — harness bug) — MiniTerm: first 3 input characters echo before the prompt ✅

**Resolved 2026-08-09.** `scripts/patch-f25-promptwait.py` makes the harness wait
for the prompt string before its first keystroke, and the corruption is gone.
`last-output.txt` now begins:
```
north-star$ echo STAGE17_COMMAND_OK
STAGE17_COMMAND_OK
```
where it previously began `echnorth-star$`. The `{0,6}` selection consequently
copies `north-` instead of `echnor`, and `app-copy.txt` confirms it.

So this was **test timing, not a renderer defect** — the harness typed into the PTY
before the shell had emitted its prompt. MiniTerm's PTY reader is exonerated.

`verify-mini-term` still fails, but **further along and for an unrelated reason** —
see the frontier note at the end of this entry. Original analysis follows.

---

### Original entry — MiniTerm: first 3 input characters echo before the prompt, corrupting line 0 🔴

**`verify-mini-term` fails here, and the selection code it appears to blame is
actually correct.**

The verifier asserts the selection range is `{0, 6}` and then compares the copied
text. It got `echnor` — exactly 6 characters, so **the selection worked**. The
problem is the terminal buffer. `artifacts/stage17-mini-term/last-output.txt`
begins, byte-for-byte:

```
echnorth-star$ echo STAGE17_COMMAND_OK
```

That is `ech` + `north-star$ …`. Three characters of the typed command are echoed
at column 0 *before* the shell's prompt is emitted, so line 0 becomes
`echnorth-star$` and any selection of `{0,6}` legitimately yields `echnor`.

**Everything else in MiniTerm passes** — visible in
`artifacts/stage17-mini-term/`:

| Capability | Evidence |
|---|---|
| launch | `launch-ms.txt` = **478** ms |
| PTY + shell + command execution | `echo STAGE17_COMMAND_OK` → `STAGE17_COMMAND_OK` |
| terminal geometry | `terminal-size.txt` = **119x36**; in-app query returns `36 119` |
| Unicode, wide chars, combining marks | `✓ WIDE:中 COMB:é` line renders |
| **ANSI 16-colour, 256-colour and 24-bit truecolor** | `color-count.txt` = **520**; `C16` red, `C256` orange, `CTRUE` green in `colors.png` |
| carriage return + erase-to-EOL | `printf "ABCDE\rXY\033[K"` → `XY` |
| alternate screen buffer | `AFTER_ALT_OK` |
| text selection | range `{0, 6}` achieved |

So this is a **terminal-emulator-grade** result on ARM64, failing on a startup
ordering detail rather than anything structural.

### ✅ RESOLVED (2026-08-09) — harness timing bug, not a renderer defect

`verify-mini-term-darling-arm64.sh` does `xdotool windowactivate --sync` and then
types immediately, with **no wait for the shell prompt**:
```sh
xdotool windowactivate --sync "$window"
...
type_command "echo STAGE17_COMMAND_OK"
```
So the first keystrokes race the prompt output.

Adding a prompt wait before the first keystroke (`scripts/patch-f25-promptwait.py`)
fixes it completely:

| | line 0 of buffer | `{0,6}` selection |
|---|---|---|
| before | `echnorth-star$ echo STAGE17…` | `echnor` ❌ |
| after | `north-star$ echo STAGE17_COMMAND_OK` | `north-` ✅ |

`app-paste.txt` is also correct. **MiniTerm's terminal renderer and selection code
were never at fault** — this is purely a defect in deepai-org's verifier, and a
good one to report since the fix is three lines.

⚠️ **The verifier still exits non-zero**, but the artifacts from the 2026-08-09
consolidation run narrow *where* considerably. Everything after `colors-output` that
writes an artifact wrote one:

| artifact | value | what it clears |
|---|---|---|
| `color-count.txt` | 520 | 24-bit colour |
| `terminal-size.txt` | present | erase-to-EOL, alternate screen, resize |
| `selection.png` | 34901 B | `{0,6}` selection reached |
| `app-copy.txt` | `north-` | copy correct |
| `app-paste.txt` | `paste` | Ctrl-V delivered, paste marker written |
| `clipboard.txt` | **absent** | never reached |

So it clears the entire erase / alternate-screen / resize / selection / paste
sequence and stops between the paste marker and the clipboard read — i.e. at
`wait_for_output "^north-star\$ Cannot[[:space:]]*$"`, which expects the shell to
report that the pasted text `north-` is not a command.

**→ Now isolated. See F30.** The diagnostic was applied first this time
(`scripts/patch-verifier-diag.py`) and named the failing step on the first run,
confirming the inference above rather than resting on it.

F25 itself — the line-0 corruption and the selection mismatch it caused — is
resolved and verified.

## F26 — `UIFoundation` and `AppKit` define many of the same ObjC classes 🟡

Observed in every GUI run's `darlingserver.err`:

```
objc[1]: Class NSTextList is implemented in both
  .../UIFoundation.framework/Versions/A/UIFoundation and
  .../AppKit.framework/Versions/C/AppKit.
  One of the two will be used. Which one is undefined.
```

Duplicated so far: `NSATSTypesetter`, `NSCollectionViewLayout`,
`NSCollectionViewLayoutAttributes`, `NSCollectionViewLayoutInvalidationContext`,
`NSTextList`, `UINibEncoder`, `NSParagraphStyle`, `NSGlyphGenerator`,
`NSTextTableBlock`, `NSTextTable`, `NSFont`, `NSTextAttachment`,
`NSCollectionViewFlowLayout` — i.e. a substantial slice of the text system.

**And it is not only UIFoundation/AppKit.** `NSLayoutConstraint`, `NSLayoutAnchor`
and `NSLayoutDimension` are duplicated between **Foundation and AppKit**, which is
a second, distinct overlap and arguably more surprising — layout classes belong in
AppKit, not Foundation.

deepai-org's own `COMPATIBILITY.md` lists "duplicate cached/disk AppKit classes"
as an open issue blocking CotEditor, so this is a known problem of theirs,
independently reproduced here.

⚠️ **Not established:** whether this causes any current failure. Class duplication
with an undefined winner is *capable* of producing subtle text-layout bugs, but it
is also present in the runs that **pass** (`Controls.app`, `TextView.app`,
`PTYHarness`). Treat as suspicious, not causal, until a specific misbehaviour is
traced to it.

## F27 — TextEdit's Cmd-S: NIB decoding crashes in `objc_msgSend` 🔴

**Localised 2026-08-10.** Three sessions of assumptions replaced by a symbolised
backtrace. Not fixed, but no longer a mystery.

### The previous reading was wrong

Earlier entries concluded the Save action ended the process "cleanly enough to
suggest `exit()`/`terminate:` rather than a crash", inferred from the absence of any
signal in the captured logs. **It is a segfault**, and it always was --- there was
simply nothing capturing it. Two changes made it visible:

- **F37**, which stopped the abort path from destroying its own diagnostic; and
- the **frame-chain walk** added to the arm64 SIGSEGV handler for F33, which now
  prints a 24-frame backtrace instead of one line of registers.

### What actually happens

```
unhandled ARM64 SIGSEGV pc=0x300E68008 lr=0x300ADBCFC address=0x22 x0=0x22
```

Symbolised against the same run's image bases (`DYLD_PRINT_SEGMENTS`, then `nm -n`
on the staged dylibs --- trap 18):

| frame | symbol |
|---|---|
| pc | `_objc_msgSend + 0x8` |
| lr | `__decodeObjectBinary + 0x83c` (Foundation) |
| 0 | `__decodeObject + 0xc8` |
| 1 | `-[NSKeyedUnarchiver decodeObjectForKey:] + 0x50` |
| 2 | `-[NSCell initWithCoder:] + 0x190` (AppKit) |
| 3 | `-[NSActionCell initWithCoder:] + 0x40` |
| 4 | `-[NSTextFieldCell initWithCoder:] + 0x40` |
| 8 | `-[NSTableColumn initWithCoder:] + 0x9c` |
| 10 | `-[NSKeyedUnarchiver _decodeArrayOfObjectsForKey:] + 0x55c` |
| 11 | `-[NSArray(NSArray) initWithCoder:] + 0xc8` |

So Cmd-S constructs `NSSavePanel`, which unarchives
`AppKit.framework/Resources/en.lproj/NSSavePanel.nib` (present and correctly staged
--- checked). While decoding the file browser's `NSTableColumn` → `NSTextFieldCell`
chain, `__decodeObjectBinary` hands back something that is **not an object**, and
the caller messages it.

**`address == x0`, and x0 is a small integer** --- `0x7` in one run, `0x22` in
another. A raw value or tag is being returned where an object pointer is expected,
and `objc_msgSend` dereferences it 8 bytes in.

### Where this is not

- **Not the NIB.** `NSSavePanel.nib` exists in the staged runtime.
- **Not `CFKeyedArchiverUID`.** CoreFoundation implements it
  (`CFBinaryPList.c:103-132`), so keyed-archive object references are not simply
  unimplemented.
- **Not key-equivalent dispatch** (Cmd-B leaves the window standing) and **not an
  uncaught exception** (both exceptions are caught and completed) --- both
  established earlier and still true.

### Update 2026-08-10 (evening) — intermittent, and one candidate ruled out

**F27 is intermittent.** On one build, three consecutive runs gave: crash, **no
crash** (the save completed, the file was written, and the verifier progressed to the
reopen phase and failed there on a colour count), crash. Same binaries, same
environment.

That reframes it. The save path *can* work, so this is not "NIB decoding is
unimplemented" — it is something that goes wrong most but not all of the time.

**Candidate tested and ruled out: uninitialised reads.** Three
`CFPropertyListRef` declarations in `NSKeyedUnarchiver.m` (lines 366, 472, 519) were
uninitialised while the guard immediately below them tests `== nil` — i.e. written as
though they were NULL-initialised. Two feed `CFEqual(@"$null", string)`, which
*messages* the pointer. That fits every symptom: a small receiver, differing every
run, intermittent.

Initialising all three to NULL and re-running gave **rc=2, rc=2, rc=2** — three
crashes out of three. So it is **not the cause**, or not the whole cause.

The initialisation is **kept and credited with nothing**: reading an uninitialised
variable is undefined behaviour regardless, and the surrounding code already assumes
NULL. Ladder stayed 12/12 and the corpus 34/7 with it in.

**Instrumentation results, for whoever picks this up.** Probes on every receiver in
the late half of `_decodeObjectBinary` — the map-hit path, `className`, all three
class lookups, `allocWithZone:`, the result of `initWithCoder:` and of
`awakeAfterUsingCoder:` — reported **3582 decoded nodes and not one suspect value**
(nothing below `0x10000`). So the bad receiver is *not* any of those, which
eliminates the leading hypothesis from the last session (a raw UID surfacing from
`_refObjMap`).

Note also that the one successful run was the one with the most verbose tracing
enabled, which slows decoding considerably. Suggestive of timing sensitivity, but a
single success is far too little to claim that.

### Next step

Instrument `__decodeObjectBinary`'s return path in Foundation to print what it is
returning for the failing key, and the CF type of the decoded plist node. The
question is narrow: which node type does it mishandle such that a small integer
reaches the caller? Given the value varies between runs, an inline/immediate value
is the likeliest candidate.

### Update 2026-08-10 (overnight soak) — "intermittent" was an artifact of n=3 ⚠️

**Correcting the claim above.** The overnight soak has now run the text-edit verifier
**18 times on an unchanged build: 0 passes, 18 failures.** The "intermittent — one run
in three" characterisation rested on a **single observed pass in a sample of three**,
and it does not survive contact with a real sample size.

This matters beyond bookkeeping: "intermittent" and "deterministic under these
conditions" call for different debugging strategies, and the report was carrying the
weaker claim in three places.

**Two things the larger sample lets us say that n=3 could not:**

1. **Wall-clock slowness does not buy a pass.** The 18 failures span **58–297 s**.
   If the defect were simply "goes away when execution is slower", the 297 s run
   should have passed. It did not. Generic slowdown is therefore *not* the variable.

2. **The one success in the entire record was the run with the heaviest tracing
   enabled** — and tracing slows the *decode path specifically*, not the process
   generally. Combined with (1), the surviving hypothesis is sharper than "timing
   sensitive": if timing is involved at all, it is **fine-grained ordering within the
   decode**, not overall pace.

**Honest reading.** One pass in 19 total recorded runs is also consistent with the
single pass having been a fluke, or with tracing changing memory layout rather than
timing. The soak has made the *rate* solid; it has not identified the variable.

**What this changes.** The pass-vs-fail artifact diff that motivated the soak is not
available — there is no passing run to diff against. The soak's F27 contribution is
therefore a corrected rate plus two eliminated framings, not a root cause.


## F28 (FIXED) — Foundation was missing the compiler-emitted constant classes ✅

**Fixed 2026-08-09.** Implemented in two files, split the way Apple splits them
because that is what the client binary binds:

| class | file | bound from |
|---|---|---|
| `NSConstantArray` | `src/external/corefoundation/NSConstantArray.m` | CoreFoundation |
| `NSConstantIntegerNumber` | `src/external/foundation/src/NSConstantNumber.m` | Foundation |

Registered by `scripts/patch-f28-constant-objects.py`. The split is not a style
choice — putting both in CoreFoundation was tried first and the linker rejected it,
which is also why no reasoning about re-exports was needed:

```
Undefined symbols for architecture arm64:
  "_OBJC_CLASS_$_NSNumber", referenced from:
      _OBJC_CLASS_$_NSConstantIntegerNumber in NSConstantObjects.m.o
```

Instance layouts were **read out of the emitted binary**
(`otool -v -s __DATA_CONST __objc_intobj` / `__objc_arrayobj`), not guessed:

```c
__objc_intobj    { isa, const char *encoding, int64_t value }    // 24 B, values 1,2,3
__objc_arrayobj  { isa, NSUInteger count, const id *objects }    // 24 B, count 3
```

Those offsets hold only because `NSValue`, `NSNumber` and `NSArray` all declare
zero ivars, so `instanceSize` is 8 and the first ivar sits at offset 8 — checked in
the headers first. `SINGLETON_RR()` makes retain/release/dealloc no-ops, matching
`__NSCFConstantString`, since the instances live in read-only `__DATA_CONST`.

**Result on `t06_objc.arm64`:**

| | before | after |
|---|---|---|
| exit status | 139 | **0** |
| output | `abort_with_payload: Symbol not found: _OBJC_CLASS_$_NSConstantIntegerNumber` | `objc:1~count:3~dict:v~class:__NSCFString` |

`count:3` is the load-bearing part: the statically allocated array reports its
elements correctly, so both new classes are functioning, not merely present.

Two residual divergences remain on this binary. **Neither is this defect** — both
were masked by it, because the old failure happened before any user code ran:

- **arm64** — `class_getName([s class])` gives `__NSCFString` where macOS gives
  `NSTaggedPointerString`. Darling has no tagged-pointer strings. Recorded as F32.
- **arm64e** — SIGSEGV before the first `printf`, i.e. inside
  `+[NSString stringWithFormat:]`, well before any constant number or array is
  touched. Recorded as F33.

`NSConstantDoubleNumber`, `NSConstantFloatNumber` and `NSConstantDictionary` are
deliberately **not** implemented: no binary here references them, so their layouts
are unverified, and a wrong layout for a statically allocated object reads the wrong
memory silently instead of failing loudly — strictly worse than today's clean
"symbol not found". Add them when there is a binary to read the layout out of.

Original entry follows.

### Original entry — Foundation is missing `NSConstantIntegerNumber` 🔴

**Found by the differential corpus — the first finding from that harness, and
exactly the class deepai-org's application-level gates cannot see.**

A trivial ObjC program using boxed number literals (`@[@1, @2, @3]`), compiled on
the host Mac with Apple clang 21 / SDK 26.5, dies under Darling:

```
abort_with_payload: reason: Symbol not found: _OBJC_CLASS_$_NSConstantIntegerNumber
  Referenced from: /corpus/t06_objc.arm64 (which was built for Mac OS X 26.0)
  Expected in: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
```

Natively on macOS the same binary prints
`objc:1~count:3~dict:v~class:NSTaggedPointerString` and exits 0.

`NSConstantIntegerNumber` is the class modern Clang emits for compile-time-constant
boxed integers. **Any binary built against a recent macOS SDK that uses `@1`-style
literals will fail to launch**, which is a broad compatibility gap — and one that is
invisible to gates built from applications compiled elsewhere or older.

Both the arm64 and arm64e variants fail identically, so this is a Foundation
completeness issue, not an architecture one.

**Secondary defect in the same trace:** the missing-symbol path does not exit
cleanly. After `abort_with_payload` it produces
`unhandled ARM64 SIGSEGV pc=… lr=… address=0x97`, i.e. the abort handler itself
faults, and the process dies with 139 rather than reporting a clean dyld error.
Worth fixing independently — a truthful "symbol not found" exit is much easier to
diagnose than a segfault.

## Differential corpus — first full run (2026-08-09)

17 binaries built on the host Mac with Apple clang 21 / SDK 26.5, each one's exact
output and exit status captured by running it **natively on macOS**, then executed
under the staged north-star runtime and compared byte-for-byte.

```
  ok   host_false           exact match
  ok   host_pwd             rc 0 vs 0 (cwd differs by construction)
  ok   host_true            exact match
  ok   host_uname           exact match
  ok   t01_hello.arm64      exact match
  ok   t01_hello.arm64e     exact match      <- arm64e / PAC
  ok   t02_exit42.arm64     exact match      (exit code 42 preserved)
  ok   t03_syscalls.arm64   exact match      write/getpid/uname/mmap
  ok   t03_syscalls.arm64e  exact match      <- arm64e / PAC
  ok   t04_pthread.arm64    exact match
  ok   t05_dispatch.arm64   exact match
  ok   t07_cf.arm64         exact match
 FAIL  t06_objc.arm64       F28
 FAIL  t06_objc.arm64e      F28
 skip  host_echo / host_basename / host_wc   (runner takes no argv)

  matched 12   diverged 2   skipped 3
```

**Two results worth stating plainly:**

1. **arm64e is independently verified.** Two PAC-signed binaries produce output
   identical to real macOS, including the syscall probe
   (`w:ok~pid_positive:1~uname:1~sysname:Darwin~mmap:1~mmap_rw:1`). This was the
   least-verified part of the stack and it holds up.
2. **Apple-signed system binaries run correctly** — `host_uname`, `host_true`,
   `host_false` match native exactly.

The three skips are a harness limitation, not a failure:
`tools/run-staged-darling-arm64.sh` sets `DSERVER_INIT` and accepts no argv, so
argument-taking cases could not be driven. Adding argv support would close them.

Runner: `scripts/91-corpus-runner.sh` (standalone; mirrors their runner but mounts
the corpus and copies it into the prefix, since `DSERVER_INIT` resolves against
`/tmp/darling-prefix`, not the read-only system root).

### Update 2026-08-09 — argv support added, coverage now 17/17

The three argument-taking cases (`host_echo`, `host_basename`, `host_wc`) had been
reported as skips since the corpus was built, because the runner drives programs
through `DSERVER_INIT`, which carries no argv. The mechanism to fix that already
ships in the staged runtime and is used throughout
`verify-service-tools-darling-arm64.sh`: `/exec-arguments-darling-arm64` reads
`DARLING_EXEC_PATH` and `DARLING_EXEC_ARG1..8`. `host_wc` also needs stdin, which
`darlingserver` inherits from the calling shell.

The argument values are duplicated from `10-make-corpus.sh`'s `args_for()` /
`stdin_for()` and must stay identical — ground truth was captured on macOS with
exactly those arguments, so any drift silently compares different invocations.

| | before | after |
|---|---|---|
| matched | 12 | **14** |
| diverged | 2 | 3 |
| **skipped** | 3 | **0** |

`host_echo` and `host_basename` match macOS byte-for-byte on first execution.
`host_wc` fails on **F36** (missing `libxo.dylib`). The three divergences are now
F32 (tagged-pointer strings), F33 (arm64e `stringWithFormat:`) and F36 — all
distinct, all newly visible, none of them the corpus harness.

## F29 — `verify-x11-backend` is flaky: the app sometimes takes >10 s to exit 🟠

This is the **real** stage-11 failure, and the one F24 was mistaken for.

The smoke phase ends with:
```sh
xdotool windowactivate --sync "$window"
xdotool key alt+F4
if ! timeout 10s tail --pid="$server_pid" -f /dev/null; then
```
Intermittently the app has not exited 10 s after `alt+F4`, `timeout` returns 124,
and the whole verifier fails. Every prior "F24 failure" was this.

**Measured rate — 8 runs today, same build machine, back to back:**

| build | runs | result |
|---|---|---|
| `[sheet becomeKeyWindow]` + NSLog trace | 2 | 124, then 0 |
| `[sheet becomeKeyWindow]`, no trace | 3 | 0, 0, 124 |
| pristine (control) | 3 | 0, 0, 0 |

**6 / 8 pass.** The two failures land in different builds, and the pristine control
is clean, so nothing here attributes the flake to a source change. It is a
shutdown-latency race — 10 s is simply not always enough for this app to tear down
in this container on this host.

Two things worth doing, in this order:
1. **Measure the distribution before touching the timeout.** Log the actual
   exit latency each run rather than only pass/fail. If the tail is at 11–12 s,
   raising the bound is legitimate; if it is occasionally unbounded, the app is
   hanging on shutdown and the timeout is doing its job.
2. Only then consider raising it. Raising it first would convert a visible
   intermittent failure into an invisible slow one.

### Update 2026-08-10 — `hello-window` shows the same intermittency

A consolidation run had `verify-hello-window` at rc=1 with no failed assertion in
its output, only a `libEGL` warning. Re-run twice immediately afterwards on the same
build: **rc=0, rc=0**.

So F29 is not confined to `verify-x11-backend` — at least two GUI verifiers fail
intermittently without a real defect behind them. That matters for how GUI results
are reported: **a single failing GUI run is not evidence**, and any GUI claim should
rest on repeats.

It also nearly produced a false regression report: the failing run happened to
follow a Foundation change (F42), and attributing it without re-running would have
been exactly the mistake trap 9 exists to prevent.

**Diagnostic that found it:** `scripts/patch-f24-diag5.py`. The ERR trap printed
only `${BASH_LINENO[0]}`, which does **not** track `$BASH_COMMAND` in this script —
it reported the modal-click assertion for days. Adding one `echo` named the real
command on the first run.

→ Recorded as a trap in `STATE.md`: **never trust a bash ERR trap's line number
without printing `$BASH_COMMAND` alongside it**, and treat a status of 124 as
proof that a `timeout` failed, which localises the failure by itself.

## F30 — `verify-mini-term` expects buffer text this environment never produces 🟠

The last remaining `mini-term` failure. **Every Darling capability the failing step
exercises demonstrably works** — what fails is a hard-coded expectation about what
should be sitting at position 0 of the terminal buffer.

**Named on the first run**, because the `$BASH_COMMAND` diagnostic went in before
the investigation this time rather than after:

```
Stage 17 verifier failed (status 1).
  failing command: return 1
  markers in the CURRENT prefix (not proof about earlier phases):
    mini-term-alt-enter  mini-term-alt-exit  mini-term-copy  mini-term-input
    mini-term-output     mini-term-paste     mini-term-ready mini-term-selection
    mini-term-size
```

`return 1` is `wait_for_output` (line 112) timing out. The assertion is:

```sh
xdotool key --repeat 6 shift+Right          # select {0,6}
xdotool key ctrl+v ; xdotool key Return
test "$(cat …/mini-term-paste)" = paste
wait_for_output "^north-star\$ Cannot[[:space:]]*$"     # ← times out
grep -q "^Cannot$" /artifacts/clipboard.txt
```

So the verifier requires **the first six characters of the terminal buffer to be
`Cannot`**. Selection is a character range over the whole text-view string
(`mini-term/*.m:112-139`), so `{0,6}` is literally `[string substringWithRange:]`
from index 0.

**What actually happens here, from the captured buffer:**

```
 1  north-star$ echo STAGE17_COMMAND_OK
…
13  36 119
14  north-star$ north-
15  sh: north-: command not found
```

Position 0 is `north-`, that is what gets copied, that is what gets pasted, and the
shell answers correctly. The chain is intact end to end:

| step | evidence | verdict |
|---|---|---|
| selection `{0,6}` | `mini-term-selection` = `{0, 6}` | ✅ |
| copy to `NSPasteboard` | `app-copy.txt` = `north-` | ✅ |
| Ctrl-V paste | `app-paste.txt` = `paste` | ✅ |
| pasted text reaches the PTY | buffer line 14 shows `north-` at the prompt | ✅ |
| shell responds | line 15, `sh: north-: command not found` | ✅ |
| buffer starts with `Cannot` | it starts with `north-` | ❌ |

**Where `Cannot` could come from — unresolved, and stated as such.**
`grep -rn 'Cannot'` finds it nowhere in the MiniTerm app, in Darling's `bash`, or
anywhere in the verifier except these three assertions. MiniTerm spawns
`/bin/sh -i` with `PS1="north-star$ "` (`mini-term/*.m:283-286`), so a plausible
explanation is a shell start-up message on deepai-org's reference host — an
interactive `sh` without a controlling terminal often warns about job control —
which would occupy line 0 there and be absent here. **That is a hypothesis, not a
result.** It has not been reproduced and should not be reported as fact.

Note the expectation is also incompatible with the pre-F25 behaviour: before the
prompt-wait fix, position 0 was `echnor`. Neither `north-` nor `echnor` is
`Cannot`, so this assertion cannot have been passing in this environment at any
point.

**Recommended action:** report upstream and ask what writes `Cannot` on their host.
Do **not** patch the expectation to match our buffer — that would convert a
portability bug into a silently environment-specific test, and the underlying
question (why do our buffers differ at line 0?) may itself be a real defect.

## F31 — Foundation and CoreFoundation re-export unfiltered on arm64 🟡

Found while placing the F28 classes; consequences **not yet measured**.

Both frameworks apply a `-reexported_symbols_list` on x86_64 and neither does on
arm64:

| | x86_64 | arm64 |
|---|---|---|
| `corefoundation/CMakeLists.txt:212-219` | `reexport_x86_64.exp` + `__NSCFConstantString` alias | alias **only** |
| `foundation/CMakeLists.txt:334-340` | `reexport_x86_64.exp` | **no arm64 branch at all** |

`ls reexport_*` in either directory returns only `reexport_i386.exp` and
`reexport_x86_64.exp` — there is no `reexport_arm64.exp`. Foundation links with
`-Wl,-reexport_library,…/CoreFoundation` and `…/libobjc.A.dylib`
(`foundation/CMakeLists.txt:327`), so on arm64 it re-exports **everything** from
both, where x86_64 re-exports a curated subset.

That is an architecture-dependent difference in exported-symbol surface. It is a
plausible contributor to the F26 duplicate-class warnings, and it means a symbol
that resolves on arm64 may not resolve on x86_64 — a difference that would not show
up in any current gate.

**Explicitly not claimed:** that this causes any observed failure. Establishing that
needs a diff of the two export sets against `reexport_x86_64.exp`, which has not
been done.

## F32 — no tagged-pointer strings: `class` differs from macOS 🟡

Exposed by F28's fix — this divergence was previously masked because the binary
never launched.

```
native  : objc:1~count:3~dict:v~class:NSTaggedPointerString
darling : objc:1~count:3~dict:v~class:__NSCFString
```

`[NSString stringWithFormat:@"objc:%d", 1]` produces a 6-character string. macOS
stores short ASCII strings in the pointer itself as an `NSTaggedPointerString`;
Darling always heap-allocates, so `class_getName` reports `__NSCFString`.

Mostly cosmetic — the string's *contents* and behaviour are correct, and code that
switches on `[obj class]` identity is doing something inadvisable anyway. Recorded
because it is a real observable difference, and because a differential corpus that
compares exact output will keep flagging it. Not worth fixing before the items
above it.

## F33 — arm64e: CF↔ObjC bridging recursion, root-caused 🟠 *(no longer reproduces)*

Two results here, and they need separating carefully: **the mechanism is now known
in full detail**, and **the crash stopped reproducing for a reason I could not
attribute**.

### The crash, and the mechanism

`t06_objc.arm64e` died with SIGSEGV before printing anything. A frame-chain walk
added to the arm64 signal handler (`scripts/patch-f33-backtrace.py`) showed a
perfect two-frame cycle running into the stack guard page:

```
  frame 0: fp=0xFFF7FC020 lr=0x3007FF63C
  frame 1: fp=0xFFF7FC090 lr=0x30075B910
  frame 2: fp=0xFFF7FC1B0 lr=0x3007FF63C
  frame 3: fp=0xFFF7FC220 lr=0x30075B910      … repeating to the guard page
```

Symbolised against CoreFoundation (mapped at `0x300660000`, `nm` on the staged
dylib):

| address | symbol |
|---|---|
| `pc = 0x30075B7B8` | `_CFStringGetCharacters + 0x10` |
| `lr A = 0x3007FF63C` | `-[__NSCFString getCharacters:range:] + 0x64` |
| `lr B = 0x30075B910` | `_CFStringGetCharacters + 0x168` |

So the loop is, exactly:

```
CFStringGetCharacters              (CFString.c:2026)
  -> CF_OBJC_FUNCDISPATCHV(...)    dispatches only when CF_IS_OBJC
  -> -[__NSCFString getCharacters:range:]   (NSString.m:327)
  -> CFStringGetCharacters         … and around again
```

That loop is present unconditionally in the source. What normally breaks it is
`CF_IS_OBJC(typeID, obj)` — i.e. `!_CFIsCFObject(obj)` (`CFInternal.h:592`) —
recognising a CF object and handling it in C rather than dispatching to ObjC. CF's
own comment at `CFString.c:2034` documents the intended discipline: there is a
separate `_CFStringCheckAndGetCharacters` "for NSCFString usage; it doesn't do ObjC
dispatch", which is what `__NSCFString` ought to call.

### Why the guard failed — measured, not inferred

Instrumenting `_CFIsCFObject`'s inputs (`scripts/patch-f33-trace.py`):

```
obj=0x100004068
raw_isa         = 0x4c000300845838
object_getClass = 0x4c000300845838     <- PAC signature bits still present
constStrCls     = 0x  300845838        <- the actual class pointer
cfinfo=0x000007c8 typeID=7 tableCls=0x300846918 isCF=0
```

The object is the client binary's constant CFString. In an arm64e image the isa in
`__cfstring` is **PAC-signed**, and Darling has no PAC hardware — it emulates the
instructions by faulting and fixing up (`strip_unsupported_ptrauth_pc`,
`strip_unsupported_ptrauth_data_address` in `sigexc.c`). The signature bits survive
into `object_getClass()`, every class comparison in `_CFIsCFObject` fails, CF
concludes a CF object is a foreign ObjC object, and the bridge recurses forever.

The same trace on the **arm64** build printed nothing at all — the contrast is what
localised this to the PAC path.

**Root cause, one level down:** `objc-config.h:94` sets `SUPPORT_PACKED_ISA 0` for
`defined(DARLING) && defined(__arm64__)`, so `SUPPORT_NONPOINTER_ISA` is 0 and
objc4's isa accessors return `isa.cls` raw, with no `clsbits &= ISA_MASK` step
(`objc-object.h:250,264`). Every isa read from an arm64e image therefore carries
signature bits — this is not specific to CoreFoundation.

### ⚠️ What is fixed, what is not, and what is unexplained

**The crash no longer reproduces**, and I could not attribute that to any change I
made. Applying a PAC-strip to `_CFIsCFObject` made `t06_objc.arm64e` exit 0 with
correct output — and then **the control passed too**: reverting the fix and
rebuilding still gave exit 0, stably across three runs. Something earlier in the
session changed it. Per trap 9, that means **the fix is not credited with anything.**

Re-instrumenting afterwards showed why it cannot be re-verified either:
`CFStringGetCharacters` is **no longer called at all** by either binary, so the code
path that recursed is not exercised by any test we have.

**The `_CFIsCFObject` PAC-strip is kept** (`scripts/patch-f33-fix.py`), on the
narrow grounds that the defect it addresses was directly *measured* — `isCF=0` for a
genuine CF object, with the signature bits visible in the dump above — and the fix
is correct by construction for a runtime with no PAC hardware. It is explicitly
**not** credited with fixing the crash, and no current test exercises it.

**Still open:**
1. **Why did the crash stop?** Unattributed. Candidates not eliminated: the F37
   abort-path change, the F34 `/var/tmp` change, or a load-order effect (see below).
2. **The raw-isa problem is runtime-wide**, not CF-specific. The proper fix is in
   objc4's isa handling or in the arm64e chained-fixup path, both core changes that
   need more verification room than remained.
3. **Images are mapped overlapping.** `DYLD_PRINT_SEGMENTS` shows CoreFoundation at
   `0x300660000–0x30081FFFF` with `libsystem_coretls` (`0x3006A4000`) and
   `libsystem_malloc` (`0x3007EC000`) mapped *inside* that range, and both
   `libSystem.B.dylib` and `Foundation` claiming `0x300000000`. That is a defect on
   its own and could plausibly make crashes come and go. It also means the
   symbolisation above should be re-confirmed before anyone acts on it — though the
   symbols it produced (`_CFStringGetCharacters`, `-[__NSCFString
   getCharacters:range:]`) form a coherent, well-known bridging loop, which is
   strong independent evidence that they are right.

Recorded as **F38**.

## F38 (WITHDRAWN) — images are **not** mapped overlapping ✅

**Withdrawn 2026-08-10, one hour after being raised.** It was an artefact of my own
tooling, and the correction is worth more than the original claim.

### What the kernel actually says

A long-lived process was started under Darling and `/proc/<pid>/maps` read from the
Linux side — the kernel's own record of what is mapped, rather than dyld's account of
what it intended to map. Every file-backed image was reduced to its min/max span and
all pairs were checked programmatically:

```
file-backed images mapped: 41
NO OVERLAPS between distinct images

tightest gaps between consecutive images:
  0x100000 bytes  libSystem.B.dylib  -> libsystem_sandbox.dylib
  0x100000 bytes  libc++.1.dylib     -> libc++abi.dylib
  0x100000 bytes  libc++abi.dylib    -> libresolv.9.dylib
```

Not merely non-overlapping — a uniform 1 MB stride between consecutive images, which
is `reserveAnAddressRange` (`ImageLoaderMachO.cpp:2660`) allocating exactly as
designed. There is no defect here.

### Why I got it wrong

The original claim came from an `awk` one-liner that paired each
`dyld: Mapping <path>` line with the **next** `__TEXT at` line and then sorted the
result. `DYLD_PRINT_SEGMENTS` interleaves per-image blocks in a way that pairing
breaks, so segments were attributed to the wrong images, and sorting destroyed the
ordering that would have made it obvious. Both "`libSystem.B.dylib` and `Foundation`
share a base" and "`libsystem_coretls` sits inside CoreFoundation" were products of
that mis-pairing.

The finding was at least labelled as unconfirmed when raised, with `/proc/maps`
named as the check to run — which is why it cost an hour rather than a day.

### Two consequences worth keeping

1. **`MAP_FIXED` at `ImageLoaderMachO.cpp:2788` is still worth knowing about.** It
   silently unmaps and replaces whatever occupies the range, so if image placement
   ever *does* go wrong, the failure will be silent corruption rather than a loud
   `mmap` error. Nothing to fix today; worth remembering when something inexplicable
   happens.
2. **The F33 symbolisation is reinforced.** It depended on attributing a runtime
   address to CoreFoundation's mapped range. Addresses being cleanly partitioned
   between images is exactly what makes that attribution sound.

→ `STATE.md` trap 19: **parse structured diagnostic output structurally.** Pairing
lines by proximity and then sorting is not parsing, and it manufactured a defect out
of correct behaviour.

## F34 (FIXED) — `/var/tmp` was wiped on every container start ✅

**Fixed 2026-08-09.** One line in `darlingserver.cpp`, and it takes the headless
ladder to **12/12 — green for the first time in this project.**

### ⚠️ The first diagnosis of F34 was wrong

This entry previously said *"Darling writes binary property lists but cannot read
them"*, and identified `NSPropertyListSerialization`'s binary reader as the defect.
**That is withdrawn. The binary plist reader works correctly.**

Given a `bplist00` that still exists when `plutil` opens it, the round trip is
clean:

```
XML -> binary : bplist00, 61 bytes
binary -> XML : <dict><key>Greeting</key><string>hello</string></dict>
```

### What actually happens

`darlingPreInit` (`darlingserver.cpp:237`) wipes `/var/tmp` on **every** container
start:

```c
const char* dirs[] = { "/var/tmp", "/var/run" };
```

`verify-service-tools-darling-arm64.sh` writes
`/private/var/tmp/stage10.binary.plist` in one `darlingserver` invocation and reads
it back in the **next** one. The intervening server start deletes it, so `plutil`
opens a file that is no longer there.

Proven by canary rather than inferred — write a file to each of two directories,
run one trivial `darlingserver` invocation that touches neither:

| path | before | after one server run |
|---|---|---|
| `$prefix/private/var/tmp/canary.txt` | `canary-payload` | **MISSING** |
| `$prefix/root/canary.txt` | `canary-payload` | `canary-payload` |

### Why the misdiagnosis happened, and the diagnostic that caught it

`plutil.m:65` reports two different failures with one message:

```objc
NSData* input = [NSData dataWithContentsOfFile:… error:&error];
id plist = input ? [NSPropertyListSerialization propertyListWithData:…] : nil;
if (!plist || error)
    return fail("plutil: input is not a property list\n", 1);
```

A file that cannot be *read* produces `input == nil`, hence `plist == nil`, hence
**"input is not a property list"** — a message about parsing, for a failure that
never reached the parser. Recorded separately as **F35**.

The `FAIL_FALSE` trace (`scripts/patch-f34-trace.py`) is what settled it, and
notably **by staying silent**. It instruments all 113 rejection sites in
`CFBinaryPList.c` through the single macro at line 728. On the failing conversion it
printed nothing at all — so the parser never rejected anything, so the data never
reached it. A diagnostic that produces no output is only meaningless if it was never
going to fire; here its silence was the finding.

### The fix

`scripts/patch-f34-fix.py` — stop wiping `/var/tmp`, keep wiping `/var/run`.

On Darwin the two temp directories have different contracts, and Darling exists to
emulate Darwin:

| path | contract |
|---|---|
| `/private/tmp` (`/tmp`) | volatile; cleared by periodic maintenance |
| `/private/var/tmp` (`/var/tmp`) | **persistent**; survives reboots by design |

Wiping `/var/tmp` at container start diverges from the platform being emulated and
silently destroys data a previous process wrote into the same prefix. `/var/run` is
genuinely runtime state and is still wiped.

This is upstream Darling behaviour, not arm64-specific — but it is what failed the
arm64 ladder, and deepai-org's own verifier depends on the macOS semantics.

### Controlled result

| build | ladder | rungs passed | last line |
|---|---|---|---|
| with fix | **RC=0** | **12** | `defaults/plutil persistence smoke passed` |
| reverted (control) | RC=1 | 11 | `plutil: input is not a property list` |
| with fix, restored | RC=0 | 12 | — |

Status captured as `cmd > log 2>&1; rc=$?`, never through a pipe (trap 10).

### Correction to the ladder history, now closed

Earlier reports said **11/11**, which was wrong twice over: the measurement read
`$?` from `tail`, and the suite was in fact exiting 1. The honest reading of the
history is that the ladder had **never** passed on this machine — `gate-quick{,2}.log`
died earlier on the missing `libbz2.1.0.dylib` and never reached this rung, and
`gate-quick3.log`, the first run that could reach it, failed here.

It passes now, for the first time, at **12/12**.

## F35 (FIXED) — `plutil` reported an unreadable file as a malformed one ✅

`foundation/tools/plutil.m:65` collapses two distinct failures into one message:

```objc
NSData* input = [NSData dataWithContentsOfFile:… error:&error];
id plist = input ? [NSPropertyListSerialization propertyListWithData:…] : nil;
if (!plist || error) return fail("plutil: input is not a property list\n", 1);
```

`input == nil` (missing file, permission denied, unreadable) is reported as
"input is not a property list", which asserts something about the file's *contents*
that was never examined. This cost a full session: it sent F34 into
`CFBinaryPList.c` when the file simply was not there.

`error` is already populated by `dataWithContentsOfFile:`. Distinguishing the cases
is a couple of lines:

```objc
if (!input)
    return fail("plutil: could not read input file\n", 1);
```

Low severity, high diagnostic value — the kind of message that decides whether the
next person spends ten minutes or a day.

**Fixed 2026-08-09** (`scripts/patch-f35-plutil-msg.py`): an unreadable input now
reports `plutil: could not read input file`, and the parse failure keeps the
original message. The two cases are no longer conflated.

## F36 — Apple's `wc` needs `/usr/lib/libxo.dylib`, which Darling does not ship 🟠

Found on the first run of `host_wc`, which had been skipped since the corpus was
built and now runs (see the corpus entry below).

```
Library not loaded: /usr/lib/libxo.dylib
  Referenced from: /corpus/host_wc
  Reason: image not found; code: 1
```

`libxo` is Apple's structured-output library (`--libxo=json` and friends), linked by
a number of the BSD command-line tools in modern macOS. Darling has no
`libxo.dylib`, so those tools cannot launch at all. `host_echo` and `host_basename`,
which do not link it, both match macOS byte-for-byte.

**Same secondary defect as F28 had, so it generalises:** the missing-library abort
path does not exit cleanly. After `abort_with_payload` it produces
`unhandled ARM64 SIGSEGV … address=0x39` and dies with 139 rather than reporting a
clean loader error. Two independent missing-symbol/missing-library cases now fault
in the abort path, so this is a property of the path itself and worth fixing
independently of either cause — a truthful loader error is far easier to diagnose
than a segfault.

## F37 (FIXED) — `abort_with_payload` returned to a `noreturn` caller ✅

**Fixed 2026-08-09.** Every loader failure in this project ended in a segfault that
buried the real error. It was one missing line.

### The defect

```c
long sys_abort_with_payload(...)
{
    __simple_printf("abort_with_payload: reason: %s; code: %lu\n", ...);
    sys_kill(sys_getpid(), SIGABRT, 1);
    return 0;                       // <-- returns to a noreturn caller
}
```

`abort_with_payload` is declared `noreturn` and dyld relies on it: `halt()`
(`dyld2.cpp:4545`) ends with the call, so the compiler emits **no epilogue and no
return**. When the syscall returned anyway, execution fell off the end of the
function into unmapped memory.

`sys_kill` cannot be relied on to terminate, because Darling installs
`sigexc_handler` for the Mach exception machinery and SIGABRT is caught rather than
fatal. Note `__simple_abort()` (`simple.c:580`) makes the same assumption —
`sys_kill` then `__builtin_unreachable()` — so it is likely to have the same latent
problem.

### Why it mattered

Two independent cases, which is what identified it as a property of the abort path
rather than of either cause:

| finding | cause | before |
|---|---|---|
| F28 | missing symbol `_OBJC_CLASS_$_NSConstantIntegerNumber` | `SIGSEGV address=0x97`, exit 139 |
| F36 | missing library `/usr/lib/libxo.dylib` | `SIGSEGV address=0x39`, exit 139 |

Both fault addresses are small offsets from NULL, consistent with running into
unmapped memory rather than with a wild pointer. In both cases the *correct*
diagnosis was printed immediately before, then obliterated by the crash.

### The fix

`scripts/patch-f37-abort-noreturn.py` — keep the `sys_kill` (so any Mach-exception
path still sees an abort), then make termination unconditional:

```c
sys_exit(128 + SIGABRT);       /* 134 — the shell convention for death by SIGABRT */
__builtin_unreachable();
```

### Controlled result

| build | `host_wc` exit | last line of output |
|---|---|---|
| with fix | **134** | `Reason: image not found; code: 1` |
| reverted (control) | 139 | `unhandled ARM64 SIGSEGV pc=…CF78 lr=…DB98` |
| restored | **134** | `Reason: image not found; code: 1` |

Ladder re-verified at **12/12, RC=0** afterwards; corpus unchanged at 14/3/0.

### ⚠️ The trap that cost three rebuilds

The first two attempts **changed nothing at all**, and the tell was that the fault
site was byte-identical across builds — same `pc` low bits (`…CF78`), same `lr`
(`…DB98`), same `address=0x39` — while only the ASLR base moved.

`/usr/lib/dyld` links its **own static copy** of the emulation syscalls. Rebuilding
`libsystem_kernel.dylib` did nothing; rebuilding `mldr` did nothing; the change only
took effect once `src/external/dyld/dyld` was rebuilt and re-staged.

This is the third time in this project that a fix was applied to a binary the
running code does not load (the X11 backend was the earlier case). Recorded as
`STATE.md` trap 16: **when a change appears to have no effect, check that the binary
you rebuilt is the one being executed — an unchanged fault address across rebuilds
is the signature.**

## F41 (FIXED) — arm64e: PAC bits in isa broke every class-identity comparison ✅

**Fixed 2026-08-10.** This is the root-cause fix F33 was missing, and it took a new
corpus case to make it findable.

### The symptom

`t15_invoke.arm64e` — NSInvocation, message forwarding and method swizzling — died
with `_objc_fatal("cls is not an instance of metacls")`
(`objc-runtime-new.mm:2245`). The **identical source built for arm64 passed**.

### The evidence

Instrumenting the failing walk printed both operands:

```
[F41] FAIL inst=0x1000081f0 metacls=0x1000081c8
[F41]   [0] cls=0x1000081f0 ISA=0x510001000081c8 name=Target
[F41]   [1] cls=0x300941050 ISA=0x300941000        name=NSObject
```

`0x510001000081c8 & 0x0000FFFFFFFFFFFF == 0x1000081c8 == metacls`. The high bits
**varied run to run** (`0x56`, `0x51`, `0x3a`), which is what identifies them as a
PAC signature rather than part of an address.

`Target` is defined in the arm64e binary, so its class structures carry PAC-signed
isa pointers. `NSObject` comes from Darling's own arm64 Foundation and is clean —
which is exactly why the walk gets one level in and then fails.

### The fix

`isa_t::getClass()` in the raw-isa path now masks to 48 bits
(`scripts/patch-f41-isa-mask.py`). Darling has no PAC hardware — it emulates the
instructions by faulting and fixing up — so signature bits in an isa are never
meaningful. Darling also deliberately maps images below 2^47 (to stay clear of
ObjC's 47-bit `FAST_DATA_MASK`), and all 41 mapped images were measured in the
`0x3_0000_0000` range, so the mask cannot truncate a real class pointer. On a plain
arm64 image the high bits are already zero, making it a no-op there.

### ⚠️ Three false starts, and what each taught

This took four build cycles, and none of the failures were the fix being wrong:

1. **Patched the wrong `getClass()`.** `objc-object.h` defines `isa_t::getClass()`
   **twice** — once in the `SUPPORT_NONPOINTER_ISA` section (~line 234, with the
   `ISA_MASK` logic) and once in the `#else // not SUPPORT_NONPOINTER_ISA` section
   (~line 987). Darling/arm64 sets `SUPPORT_PACKED_ISA 0`, so the **second** one is
   what compiles; the first is dead code here.
2. **objc4 has no header dependency tracking.** There are no `.d` depfiles for
   `objc_obj` at all, so editing a header **never triggers a rebuild**. Two cycles
   were spent on a change that was in the source and not in the binary. Objects have
   to be deleted by hand:
   `find src/external/objc4 -name '*.o' -delete`. Recorded as trap 20 — it is a
   sharper-edged cousin of trap 16.
3. Dropping the `defined(DARLING) && defined(__arm64__)` guard as a test changed
   nothing, which is what proved the problem was *which function*, not *which
   branch* — a useful negative result rather than a wasted cycle.

### Controlled result

| | `t15_invoke.arm64e` | corpus |
|---|---|---|
| with fix | passes | **30 matched / 9 diverged / 0 skipped** |
| without | `cls is not an instance of metacls`, exit 134 | 29 matched / 10 diverged |

Ladder re-verified **12/12, RC=0** with the fix in place.

### Relationship to F33

Same root cause, different victim: F33 was `_CFIsCFObject` misjudging a CF object
because the same signature bits broke its class comparison. That entry's containment
fix in `_CFIsCFObject` is now **superseded** by this one, though it is left in place
— it is correct, cheap, and independent of objc4's isa representation.

## F39 (FIXED) — two normalisation methods had each other's constants ✅

Found by `t12_strings`, on both arm64 and arm64e.

```
native : … decomp_len:8 recomp_eq:1 …
darling: … decomp_len:8 recomp_eq:0 …
```

Decomposition works — `decomp_len:8` matches macOS exactly for `@"café 中文"`, so
NFD is correct. **Recomposition does not**: taking the decomposed string back
through `-precomposedStringWithCanonicalMapping` does not reproduce the original, so
NFC is either unimplemented or wrong.

Everything else in the case matches: UTF-8 length, data round-trip, case mapping,
substring search, prefix/suffix, `characterAtIndex:`, comparison. So this is
narrowly the NFC path, not Unicode handling generally.

Impact is real but bounded: any code comparing user-supplied strings that may arrive
in either normal form will mismatch. Filenames from a filesystem are the classic
case.

### Cause: the constants are swapped between two methods

`src/external/foundation/src/NSString.m:1777-1816` --- four one-line methods, two of
them holding each other's constant:

| method | should pass | actually passed |
|---|---|---|
| `decomposedStringWithCanonicalMapping` | `FormD` | `FormD` ✅ |
| `precomposedStringWithCanonicalMapping` | `FormC` | **`FormKD`** ❌ |
| `decomposedStringWithCompatibilityMapping` | `FormKD` | **`FormC`** ❌ |
| `precomposedStringWithCompatibilityMapping` | `FormKC` | `FormKC` ✅ |

So "precompose" applied *compatibility decomposition* --- it decomposed further
instead of recomposing, which is exactly why NFD → NFC did not round-trip.

**Fixed 2026-08-10** (`scripts/patch-f39-normalisation.py`). Two constants swapped
back.

### The corpus only caught half of it

`t12_strings` covered the canonical pair. The compatibility pair was wrong in the
mirror-image way --- `decomposedStringWithCompatibilityMapping` returning *composed*
output --- and nothing tested it; it was found by reading the four methods together.
The case was extended to all four before the fix landed, so both halves are pinned.

That extension immediately proved its worth in the control run:

| | with fix | reverted (control) |
|---|---|---|
| `recomp_eq` | 1 | **0** |
| `kdecomp_len` | 8 | **7** (composed length) |
| `nfd_ne_nfc` | 1 | **0** |
| corpus | **32 matched / 7 diverged** | 30 matched / 9 diverged |

`kdecomp_len:7` is the mirror-image bug caught red-handed --- a compatibility
*decomposition* returning something shorter than the composed original.

## F40 — `-[NSNumber description]` prints unsigned 64-bit values as signed 🟠

Found by `t13_number`, on both arches.

```
native : u:18446744073709551615  desc:-42 18446744073709551615 0.5
darling: u:18446744073709551615  desc:-42 -1 0.5
```

`-unsignedLongLongValue` returns the correct value, so the number is **stored**
correctly — only `-description` is wrong, printing `-1` for `ULLONG_MAX`.

Root cause is visible in `CFNumber.c:914`
(`__CFNumberCopyFormattingDescription_new`):

```c
CFSInt128Struct i;
__CFNumberGetValue(number, kCFNumberSInt128Type, &i);   // SIGNED 128
emit128(buffer, &i, false);
```

The value is converted to a **signed** 128-bit integer and sign-extended, so
`0xFFFF…FF` becomes `-1`. This is not simply a format-specifier slip:
`CFNumberType` has **no unsigned variants at all** (`kCFNumberSInt8Type` …
`kCFNumberSInt64Type`, plus floats), so CoreFoundation cannot represent the
unsignedness. On macOS, Foundation's `NSNumber` tracks it separately from CFNumber.

A fix therefore has to preserve the unsigned-ness at the NSNumber layer and format
from there, rather than delegating to CFNumber's description — more than a one-line
change, which is why it is recorded rather than attempted.

## F28b (FIXED) — `NSConstantDictionary` was also missing ✅

**Fixed 2026-08-10.** When F28 was fixed, `NSConstantDictionary` was deliberately
left out on the stated grounds that no binary referenced it and guessing a layout
for a statically allocated object fails silently rather than loudly.

A corpus case written to pin F28 (`t10_boxed.m`, containing a `@{...}` literal)
settled the question immediately:

```
$ nm -m corpus/bin/t10_boxed.arm64 | grep -i constant
  (undefined) external _OBJC_CLASS_$_NSConstantDictionary  (from CoreFoundation)
```

So a dictionary literal *does* emit a constant dictionary, and the precondition for
implementing it — having a binary to read the layout out of — was met.

Layout, read from `__objc_dictobj` and cross-checked against `__objc_arraydata`
(the keys array holds pointers into `__cfstring`, the values array pointers into
`__objc_intobj`):

```c
{ Class isa; NSUInteger <unnamed, =1>; NSUInteger count; const id *keys; const id *values; }
```

**The field at offset 8 is deliberately not interpreted.** Its position is certain;
its meaning is not, from a single sample. It is declared so later fields land
correctly and otherwise left alone.

Implemented in `src/external/corefoundation/NSConstantArray.m` beside
`NSConstantArray`, since that is where the binary binds it from. Result: `t08_plist`
and `t10_boxed` (both arches) went from **exit 134, symbol not found** to exact
matches — corpus 15 → 18 matched.

## F42 (FIXED) — `encodeConditionalObject:` was an unimplemented trap ✅

**Fixed 2026-08-10.** `NSKeyedArchiver` could not archive **any** object graph using
conditional encoding. It died with SIGTRAP and no message at all.

```c
static void encodeConditionalObject(NSKeyedArchiver *archiver, id object, NSString *key)
{
#warning TODO
    DEBUG_BREAK();
}
```

That is the whole function. `NSKeyedArchiver.m:314`.

### Impact

`encodeConditionalObject:` is not an exotic API — it is the standard way to encode a
back-reference that must not keep its target alive: delegates, targets, an
`NSCell`'s control view, an `NSTableColumn`'s table view. Any AppKit-shaped object
graph uses it, and every one of them trapped.

The failure gave nothing to work with: exit 133, no output, no message. It was
invisible until a test happened to exercise it.

### How it was found

A corpus case (`t17_archive`) written to give F27 a **headless** reproduction —
`verify-text-edit` costs ~10 minutes and needs Xvfb, openbox and xdotool; a corpus
case costs ~4 minutes and no display. The case archives a small graph with a
parent/child cycle, a shared object referenced three times, and mixed scalars,
mirroring the `NSArray` → `NSTableColumn` → `NSTextFieldCell` shape that F27 dies on.

It reproduced a crash immediately — but a **different** one, in the archiver rather
than the unarchiver. Checkpoints with unbuffered stdout localised it in one run:

```
S0 start
S1 graph built
<dies — S2 never printed>
```

**Note the buffering detail.** The first attempt printed *nothing at all*, because
stdout is block-buffered when it is a pipe and a signal death discards the buffer.
`setvbuf(stdout, NULL, _IONBF, 0)` in the debug variant is what made the checkpoints
visible. Recorded as trap 23.

### The fix, and its stated limit

Apple's contract: emit a reference if the object is encoded **unconditionally**
elsewhere in the archive, otherwise emit nil. Doing that exactly needs the whole
archive before emitting — Apple defers conditional references and resolves them at
the end.

`scripts/patch-f42-conditional-encode.py` implements a **single-pass
approximation**: if the object already has a UID in `_objRefMap`, emit that
reference; otherwise emit nil (UID 0).

- **Correct** for the common shape — a child encoding a back-reference to a parent
  that is already mid-encode. Encoding is depth-first from the root, so the parent
  is assigned its UID before its contents are written.
- **Wrong** where the target is encoded unconditionally only *later* in the archive:
  Apple emits a reference, this emits nil.

The limit is stated rather than hidden. `archiver->_conditionals` already exists and
is consulted (with an empty `// TODO`) in the unconditional path, so a proper
two-pass implementation has somewhere to start.

### Controlled result

| | `t17_archive` | corpus |
|---|---|---|
| with fix | passes, both arches | **34 matched / 7 diverged** |
| reverted | **exit 133** (SIGTRAP) | 32 matched / 9 diverged |

The round-trip preserves everything that conditional encoding exists for:
`shared_identity:1` (one object referenced three times comes back as one object) and
`cycle:1` (parent ↔ child survives), both matching macOS exactly.

### Relationship to F27

**None established.** F27 crashes *unarchiving* an AppKit NIB, which was archived by
Apple's tools, not by this code. F42 was found while building a reproducer for F27
and is a separate defect. F27 remains open and is unchanged by this fix.

## F43 — `+[NSCharacterSet URLQueryAllowedCharacterSet]` is not exposed 🟠

Found by `t19_url`, on both arm64 and arm64e.

```
+[NSCharacterSet URLQueryAllowedCharacterSet]: unrecognized selector sent to instance
```

**Everything else in NSURL works.** The case gets through scheme, host, port, path,
query, fragment and user extraction, `lastPathComponent`, `pathExtension`, relative
resolution against a base URL (`../up/x.html` → `https://example.com/up/x.html`) and
`fileURLWithPath:` — all matching macOS exactly — and only then throws.

The plumbing exists one level down:
`_CFURLComponentsGetURLQueryAllowedCharacterSet` is declared in
`corefoundation/submodules/swift-corelibs-foundation/CoreFoundation/URL.subproj/CFURLComponents.h:106`,
and `Darwin/shims/NSCharacterSetShims.h:25` wraps the host variant. What is missing
is the **public `NSCharacterSet` class method** that Cocoa code actually calls.

Impact: percent-encoding is how any code builds a URL from user input, so this is
hit by ordinary networking code rather than anything unusual. Likely small — a
category exposing the existing CF functions.

## F44 — `NSSecureCoding` archiving dies before producing any output 🔴

Found by `t21_secure`, on both arches: exit 133 (SIGTRAP) with **no output at all**,
so it dies before the first `printf` — i.e. in
`-[NSKeyedArchiver initForWritingWithMutableData:]` or `setRequiresSecureCoding:`.

Distinct from F42: ordinary keyed archiving works (`t17_archive` passes on both
arches, including shared references and a cycle). This is the secure-coding path
specifically.

Worth noting that this is the same *shape* as F42 — a SIGTRAP with no message, which
in this codebase has already once meant a `DEBUG_BREAK()` stub
(`encodeConditionalObject:`). That is a hypothesis, not a finding.

**Next step:** an unbuffered probe. A signal death discards a block-buffered stdout
(trap 23), so add `setvbuf(stdout, NULL, _IONBF, 0)` and checkpoints to see which
call it dies in; then check that call for a stub.

Impact is real: `NSSecureCoding` is mandatory for XPC and is the default for
archiving in modern macOS code.

### Diagnosis 2026-08-10 — hypothesis confirmed by reading, no probe needed ✅

The probe described above turned out to be unnecessary: the stub is visible in the
source. `NSKeyedArchiver.m:174`, in the **encode** path — which is why it fires on the
first object encoded, before any output:

```objc
Class class = [object classForKeyedArchiver];
if ([archiver requiresSecureCoding])
{
    // TODO secureCoding
    DEBUG_BREAK();
}
```

That is the entirety of secure-coding support on the writing side. The F42-shaped
hypothesis was right.

**What it should do instead.** Foundation's contract when archiving with secure
coding required is a *conformance check*: every class encoded must adopt
`NSSecureCoding` and return `YES` from `+supportsSecureCoding`, else
`NSInvalidArchiveOperationException`. There is nothing further to do on the writing
side — the security property is enforced on **decode**, by the caller naming the
classes it expects, and that path already works once the stub stops trapping.

**Also found, not fixed:** `-initRequiringSecureCoding:` (~line 555) is a stub that
ignores its argument and calls plain `-init`, so it neither sets the flag nor
configures output. No current test exercises it; recorded rather than changed blind.

Patch written, not yet applied: `scripts/patch-f44-securecoding.py`.

## F45 — a failed file read reports the wrong error domain 🟡

Found by `t22_error`. The only divergence in an otherwise exact match, on both
arches:

```
native : … read:0 gaveerr:1 cocoa:1 …
darling: … read:0 gaveerr:1 cocoa:0 …
```

`+[NSString stringWithContentsOfFile:encoding:error:]` on a missing path correctly
fails and correctly produces an `NSError` — but that error's domain is **not**
`NSCocoaErrorDomain`, where macOS puts it.

Everything else in the case matches: error domain/code/userInfo round-trips,
`localizedDescription`, `@throw`/`@catch`/`@finally`, exception name and reason, and
an out-of-range `objectAtIndex:` raising.

Small but not cosmetic: error-handling code routinely switches on domain to decide
whether a failure is recoverable, and a wrong domain silently takes the wrong branch.

### Diagnosis 2026-08-10 — located ✅

`_NSReadBytesFromFile` (`_NSFileIO.m:24`) builds its failures at **lines 33 and 44**
as:

```objc
*err = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno …];
```

and `-[NSString initWithContentsOfFile:encoding:error:]` (`NSString.m:826`) passes
that straight out to the caller.

**The tree is already inconsistent with itself:** `NSData.m:891` builds its read
failure with `NSCocoaErrorDomain`. So the two read paths disagree with each other as
well as with macOS — whichever one a caller happens to use decides which domain it
sees.

Fix is to map errno to the Cocoa file-reading code and retain the POSIX error as
`NSUnderlyingErrorKey`, which is what Foundation does, so callers wanting the errno
can still reach it and nothing is lost.

Patch written, not yet applied: `scripts/patch-f45-errordomain.py`.

## ✅ Verified working, from the same sweep

Worth recording as much as the defects, because it is what "verified" means here:

- **`NSRegularExpression`** — compilation, match counting, capture groups, template
  replacement, case-insensitive matching, and the invalid-pattern error path. Exact
  match on both arches. That exercises the vendored ICU non-trivially.
- **`NSTask` / `NSPipe`** — launching a child, reading its output to EOF, exit
  status and `isRunning`. Exact match on both arches.

**A false finding caught before it was recorded.** The first version of the NSTask
case launched `/bin/echo` and failed with *"Executable path cannot be executed"*,
which read as an `NSTask` defect. `/bin/echo` simply **does not exist** in the
Darling runtime — it ships a minimal `/bin` (bash, cat, sh, zsh, csh, tcsh, bzip2,
launchctl) — so `NSTask` was behaving correctly and the test was wrong. Rewritten to
use `/bin/sh -c`, it passes. The absence of `/bin/echo` is itself a (minor)
completeness gap, but it is not what the test was claiming.

## F46 — the graphical test harness cannot run offline 🟠

Found while measuring reliability. Nine consecutive graphical verifier runs failed in
under ten seconds each with `rc=100`:

```
W: Failed to fetch http://ports.ubuntu.com/... Could not resolve 'ports.ubuntu.com'
E: Unable to locate package xvfb
E: Unable to locate package openbox
E: Unable to locate package xdotool
```

Every graphical verifier begins with `apt-get update && apt-get install` for xvfb,
openbox, xdotool and x11-utils — **on every single invocation**. A transient DNS
failure inside the container therefore fails the run, in a way that looks like a test
failure rather than an environment failure.

Two consequences:

1. **Those nine results were discarded**, not averaged into the reliability figures.
   They measure package-mirror availability, not Darling. Reporting them as
   flakiness would have been exactly the sort of false measurement this project has
   already been caught by once.
2. **The harness is not usable as an offline regression guard**, and it is slower
   than it needs to be — the dependency install dominates a 60-second run.

Fix is straightforward and worth doing before anyone leans on these verifiers: bake
the four packages into the `darling-arm64-dev` image, or gate the install on a
`command -v xdotool` check. Either removes the network from the critical path.

DNS was verified working from both the VM and a fresh container immediately
afterwards, so the failure was transient rather than a broken configuration.

## F43 (FIXED) — URL percent-encoding was missing entirely ✅

**Fixed 2026-08-11.** Two missing APIs, not one — fixing the first revealed the
second.

1. **The six URL character sets** were absent from `NSCharacterSet`
   (`+URLQueryAllowedCharacterSet` and friends). Added in
   `corefoundation/NSCharacterSet.m`, with the character strings copied **verbatim
   from Apple's own source**, vendored in this very tree at
   `swift-corelibs-foundation/CoreFoundation/URL.subproj/CFURLComponents_URIParser.c:22-28`.
   That file is not compiled here, which is why neither the CF functions nor the ObjC
   methods existed — and `Darwin/shims/NSCharacterSetShims.h` in the same submodule
   *calls* exactly these methods, so it was written expecting them.
2. **`-[NSString stringByAddingPercentEncodingWithAllowedCharacters:]`** did not
   exist. Its counterpart `-stringByRemovingPercentEncoding` did. Implemented to
   Foundation's semantics: pass through allowed characters, UTF-8 encode everything
   else as `%XX` in **upper** case, iterating by composed character sequence so
   surrogate pairs stay intact.

Byte-exactness was the point: the corpus compares percent-encoded output against real
macOS, so a nearly-right character set fails as loudly as a missing one.

**Result:** `t19_url` went from an uncaught exception to an **exact match on both
arm64 and arm64e** — covering scheme/host/port/path/query/fragment/user extraction,
relative resolution against a base, file URLs, and both encode and decode.

## F47 (FIXED) — `dictionaryWithValuesForKeys:` threw on any nil value ✅

**Fixed 2026-08-11.** `NSKeyValueCoding.m:202` did

```objc
values[key] = [self valueForKey:key];
```

Subscript assignment rejects nil, so **any object with an unset property** threw
`Cannot set nil objects nor nil keys`. Foundation's contract is to substitute
`NSNull` — which is the entire reason `NSNull` exists in this API. One line.

Verified by `t23_kvc` getting past that point (it now fails later, on F48).

## F48 — KVC collection operators are incomplete 🟠

Found by `t23_kvc` once F47 was fixed:

```
'this class does not implement the '@distinctUnionOfObjects' operation'
```

`@count`, `@sum`, `@max`, `@min` and `@avg` all work and match macOS exactly. The
`@distinctUnionOf…` / `@unionOf…` family does not. These are used for the common
"unique values of a property across a collection" idiom.

## F49 (PARTLY FIXED) — `NSOperation` could not be named; cancellation is still ignored

**Fixed:** `-[NSBlockOperation setName:]` was an unrecognized selector —
`NSOperationQueue` had `name`/`setName:` but `NSOperation` itself did not, so no
operation could be named. Added.

**Still open (F51).** With that fixed the case runs to completion and reveals a
larger defect: **cancellation is not honoured.**

| assertion | macOS | Darling |
|---|---|---|
| cancelled operation ran | `dran:0` | **`dran:1`** |
| cancelled operation ran (second) | `sran:0` | **`sran:1`** |
| queue drained | `qcount:0` | **`qcount:1`** |
| queue empty afterwards | `empty:0` | **`empty:1`** |

An operation cancelled before it starts **executes anyway**, and the queue does not
report itself as drained. That is a functional defect, not a cosmetic one: cancelling
work is the main reason to use an operation queue.

## F50 (PARTLY FIXED) — `NSXMLParserErrorDomain`; the parser accepts malformed XML

**Fixed:** `NSXMLParserErrorDomain` was declared in the header and defined nowhere,
so any binary referencing it failed to launch with `Symbol not found`. Defined.

**Still open (F52).** With that fixed, `t27_xml` runs and shows two further defects:

| assertion | macOS | Darling |
|---|---|---|
| `parserDidStartDocument:` fired | `docstart:1` | **`docstart:0`** |
| `parserDidEndDocument:` fired | `docend:1` | **`docend:0`** |
| malformed XML rejected | `badparse:0` | **`badparse:1`** |
| error reported for malformed XML | `haserr:1` | **`haserr:0`** |
| empty document rejected | `emptyparse:0` | **`emptyparse:1`** |

Element and attribute callbacks work and match macOS. But the document-level
callbacks never fire, and — more seriously — **malformed XML parses "successfully"
with no error reported**. Code that validates input by checking whether parsing
succeeded would silently accept garbage.

## ✅ Verified working, from the same sweep

- **`NSNotificationCenter`** — named posts with `userInfo`, block and object
  observers, selective delivery, and removal. Exact on both arches.
- **`NSValue`** — boxing `NSRange`/`NSPoint`/`NSSize`/`NSRect`, arbitrary structs via
  `valueWithBytes:objCType:`, `isEqualToValue:`, `objCType` strings, and lookup in a
  collection. Exact on both arches.

## F48 (FIXED) — five KVC operator comparisons were right, six were wrong ✅

**Fixed 2026-08-11.** A copy-paste slip in `__NSKVCOperatorTypeFromKey`
(`NSKeyValueCodingInternal.m:162`). It strips the leading `@`:

```objc
NSString *operatorName = [key substringFromIndex:1];
```

then compares the first five operators against `operatorName` and **the remaining six
against `key`** — which still carries the `@`. The constants are unprefixed
(`NSKeyValueCoding.m:23-31`, e.g. `@"distinctUnionOfObjects"`), so those six could
never match and every union operator fell through to *"this class does not implement
the … operation"*.

That is exactly why `@count`, `@sum`, `@max`, `@min` and `@avg` worked while the whole
`@distinctUnionOf…` / `@unionOf…` family did not. NSArray and NSSet both already had
the dispatch cases; the failure was upstream in the name lookup.

## F51 (FIXED) — a cancelled operation ran anyway ✅

**Fixed 2026-08-11.** `-[NSOperation start]` (`NSOperation.m:262`) checked
`isExecuting` and `isReady` but **not `isCancelled`**, so an operation cancelled
before it started executed regardless. Apple's contract is that `-start` on a
cancelled operation moves it straight to finished without invoking `-main`.

The `_cancelled` flag and its KVO notifications already existed (lines 61, 179-203) —
nothing consumed them on this path. The fix also emits the `isFinished` notification,
which matters because `NSOperationQueue` observes it to drain.

| | before | after |
|---|---|---|
| cancelled operation ran | **yes** | no |

**Residual, recorded as F54:** the queue still does not clear finished and cancelled
operations from its `operations` array (`qcount`, `scount2`, `empty`, `ops` all
report 1 where macOS reports 0). Execution is now correct; the bookkeeping is not.

## F53 (FIXED) — `NSObject` had no default `-setNilValueForKey:` ✅

**Fixed 2026-08-11.** Assigning nil to a scalar property is a documented KVC path:
the framework calls `-setNilValueForKey:`, and `NSObject`'s default raises
`NSInvalidArgumentException`. Darling made the call but supplied no default, so the
program died with an unrecognized selector instead of a catchable exception.

It matters in both directions: applications override the hook to supply a default
value, and those that do not expect an exception they can catch.

Found by `t23_kvc` once F48 let the case run that far. With it, **`t23_kvc` matches
macOS exactly on both arm64 and arm64e** — KVC accessors, nested key paths,
`dictionaryWithValuesForKeys:`, all five arithmetic collection operators, the union
family, KVO observers with old/new values, nested-path KVO, observer removal, and all
three exception paths.

## F46 (FIXED) — the graphical harness no longer needs the network ✅

**Fixed 2026-08-11.** The twelve X11 packages are now baked into a
`darling-arm64-dev:guideps` image (`scripts/Dockerfile.gui-deps`), and each
verifier's `apt-get` calls are guarded on `command -v xdotool` rather than deleted —
so they still work unchanged against the plain `:latest` image.

Measured effect on `verify-controls`:

| | before | after |
|---|---|---|
| wall clock | 67–69 s | **29–35 s** |
| needs network | yes, every run | no |

This is what makes an eight-hour unattended soak worth running: roughly twice the
samples per hour, and a mirror outage can no longer silently destroy a night's data.

## F44 / F45 / F52 (ALL FIXED) — verified against the corpus 2026-08-11 ✅

Three defects diagnosed by reading and fixed in one batch. Ladder **12/12** before and
after; the corpus moved **46 matched / 17 diverged → 52 / 11** with no case regressing.

| finding | change | result |
|---|---|---|
| **F44** secure coding | `NSKeyedArchiver.m:174` `DEBUG_BREAK()` → a real `+supportsSecureCoding` conformance check raising `NSInvalidArchiveOperationException` | `t21_secure` **exact match, both arches** |
| **F45** error domain | `_NSFileIO.m` — **3** read-failure sites (one more than the two located by reading) now build `NSCocoaErrorDomain` errors, keeping the POSIX error as `NSUnderlyingErrorKey` | `t22_error` **exact match, both arches** |
| **F52** XML parser | document callbacks, a real failure mode, closing-tag matching, unclosed-element and empty-document detection, plus a missing delegate guard | `t27_xml` **exact match, both arches** |

F52 took two passes. After part 1 the case had exactly one divergence left — an empty
document still parsed as success, because the unclosed-element check keys off a
non-empty element stack and an empty document leaves the stack empty too. Part 2
(`patch-f52b-emptydoc.py`) handles zero-length input explicitly. A non-empty document
that still has no root element (whitespace, a bare comment) is **still not detected**;
that needs a new ivar and a header change, and is recorded rather than guessed at.

**Correction carried into the source.** Part 1's comment claimed its numeric error
codes were "Apple's documented values". They are libxml2's numbering and were not
verified against macOS. Nothing measured depends on them — the corpus compares the
error *domain* and whether an error exists, not the code — but the comment overstated
what had been checked and has been corrected in place.

## F66 — the graphical verifiers encode wall-clock budgets, and one "defect" was our own machine load ⚠️

**Three problems were being reported as one.** "The graphical verifiers are
intermittent" (F29) lumped together three failures with three different causes. Two
soaks and one controlled experiment separate them.

### The harness is built from fixed wall-clock budgets

`verify-text-view-darling-arm64.sh` and its siblings wait for UI state with bounded
sleep loops:

```sh
for attempt in {1..30};  do … sleep 0.05; done   #  1.5 s budget
for attempt in {1..60};  do … sleep 0.05; done   #  3 s budget
for attempt in {1..100}; do … sleep 0.05; done   #  5 s budget
for attempt in {1..300}; do … sleep 0.1;  done   # 30 s budget
```

A **1.5-second** budget for a UI to settle is not a correctness criterion; it is a
bet about machine speed. Blow the bet and the script reports a Darling defect.

### 1. `text-view` — our own contention, proven by control

The first soak measured `text-view` at **2/7**; the second, on an idle machine, at
**15/15**. Two variables had moved: the build changed *and* the machine went from
contended (I was running greps, docker builds and diagnosis on the same VM) to idle.

Controlled experiment, **one unchanged build**, alternating idle and loaded runs with
one busy loop per core (`scripts/97-contention-experiment.sh`). Alternating rather
than blocking, so drift in machine state cannot masquerade as the effect:

| round | idle | loaded |
|---|---|---|
| 1 | **passed**, 261 s | **failed**, 175 s |
| 2 | **passed**, 228 s | **failed**, 184 s |
| 3 | **passed**, 100 s | **failed**, 116 s |
| | **3/3 passed** | **0/3 passed** |

Six runs, one build, one variable, and a clean separation. Note the loaded runs
failed *faster* than two of the three idle runs passed — the opposite of what "it
just needs more time" predicts, and exactly what a wait loop hitting its ceiling and
bailing out looks like.

**So the 2/7 measured me, not Darling.** Any figure taken while the measuring machine
is also being worked on is suspect, and that includes every graphical number in the
first soak.

### 2. `hello-window` — genuinely flaky, and not load

On the **idle** machine, across 15 runs, the outcome is perfectly bimodal with zero
overlap:

```
rc=0  1 s   ×1        rc=1  11 s  ×7
rc=0  2 s   ×2        rc=1  12 s  ×2
rc=0  3 s   ×3
```

Passes finish in 1–3 s; failures cluster tightly at 11–12 s. That is not noise and it
is not contention — it is a fixed budget being exhausted on an otherwise idle
machine, so something in the startup path intermittently does not arrive. **6/15 is a
real failure rate**, unlike `text-view`'s.

### 2b. `controls` — reliable, but not invariant

15/15 in the soak, then during final verification it failed **once** and passed three
consecutive times at its usual 22--23 s. 18 of 19 overall. Recorded so that "15/15"
is not read as "never fails" — and consistent with the wall-clock fragility above
rather than with a defect in Darling.

### 2c. Back-to-back runs are less reliable than isolated ones

Two single failures during final verification, both while several verifiers ran in
sequence, neither reproducing alone: `controls` failed once then passed 3/3, and
`x11-backend` **hung to its timeout** once then passed 3/3 in 6–8 s. These tests share
an X server, a window manager and a container, so sequence leaves residual state.

Practical consequence for anyone quoting these numbers: **run graphical verifiers
individually, on an otherwise idle machine, or expect to measure the harness.**

### 3. `x11-backend` — a hard failure at the time, since fixed (F56)

0/15, always 1–3 s. Neither flaky nor load-related — and, as it turned out, not
Darling's fault either: two missing dependencies in our own container image. Now
4/4. Left in this list because it is the third distinct cause, and because
distinguishing it from the other two is the point of this finding.

### What this costs and what it is worth

It means the graphical reliability numbers in earlier reports were partly measuring
our own harness and our own working practice. It also means **Darling is better than
those numbers implied**: `controls`, `text-view` and `pty-harness` are 15/15 each on
a quiet machine, and `x11-backend` passes too once the image it needs is complete.

The general hazard, worth stating once: **a test that asserts on wall-clock time
measures the machine as much as the software**, and if the person running it is also
using that machine, it measures them too.

## F62–F65 — four defects found by reading; three since reproduced, two fixed ⚪

Recorded together because they share a provenance and a caveat: each was found by
**reading** source while chasing F59 and F60, and at the time **none had a failing
test behind it**. **F63 and F64 have since been reproduced and fixed** — see their
entries below. **F62 and F65 still have no test** and should be weighted accordingly. They are written down so they are not lost, and deliberately **not fixed** — a
defect patched on inspection alone, with nothing to credit the fix, is precisely what
trap 9 exists to prevent. Treat each as a lead with a file and a line, not as a
finding on the same footing as the measured ones above.

### F62 — out-of-bounds read in `CFAttributedString` 🟠

`CFAttributedString.c:311`, in `_CFRunArrayObjectAtIndex`:

```c
if (loc > aStr->_runArrayCount) { return NULL; }    /* should be >= */
__CFRunArrayItem *ptr = aStr->_attributes[loc];
```

`_runArrayCount` equals the string length, so valid indices are `0 … count-1`. At
`loc == count` the guard passes, and `_attributes[loc]` reads **one past the end** of
the allocation and then dereferences it. Whether any caller reaches that index is not
established — hence no fix.

### F63 (FIXED) — directory removal followed symlinks and deleted their targets ✅

`NSFilesystemItemRemoveOperation.m` called `nftw` with `FTW_DEPTH` only — **no
`FTW_PHYS`** — so `nftw.c` selected `FTS_LOGICAL` plus `FTS_COMFOLLOW` and the walk
descended *through* symbolic links, deleting what they pointed at instead of removing
the links.

**Reproduced before being fixed.** `t35_symlink` builds a bystander directory, puts a
link to it inside the tree being removed, and asserts the bystander survives:

```
native : … removed:1 tree_gone:1 ~ victim_survived:1 outside_survived:1 …
darling: … removed:1 tree_gone:1 ~ victim_survived:0 outside_survived:1 …
```

`victim_survived:0` — **Darling deleted a file it was never asked to touch.** Deleting
a directory that happened to contain a link to your home directory would have emptied
your home directory.

**Fix:** add `FTW_PHYS`. The callback then receives the link itself and `remove()`
unlinks the link, matching macOS.

**Control:** `t14_fileman` — ordinary recursive removal of a directory of regular
files — still matches exactly on both arches, so real directories are still descended.
Ladder 12/12; corpus **63 matched / 14 diverged** across 77 cases.
`scripts/patch-f63-ftw-phys.py`.

### F64 (FIXED) — `truncateFileAtOffset:` left the file position wrong ✅

`NSFileHandle.m:706` seeked with `lseek(_fd, offset, SEEK_CUR)` where macOS seeks *to*
the offset. The `ftruncate` alongside it already used the absolute offset and was
always correct, so file **contents** matched and only the resulting **position**
diverged — which is why it went unnoticed.

**Reproduced before being fixed, and that took a new test.** `t32_filehandle`
truncated through a freshly opened handle, and at position 0 `SEEK_CUR` and `SEEK_SET`
are indistinguishable — the case was structurally blind to the defect. Writing three
bytes first moves the position to 3, which separates them:

```
native : … pre_trunc_off:3 post_trunc_off:5 ~ trunc_len:5 …
darling: … pre_trunc_off:3 post_trunc_off:8 ~ trunc_len:5 …
```

Exactly the arithmetic predicted from reading (`SEEK_CUR 5` from 3 lands at 8), on
both arches, with `trunc_len` matching either way — confirming only the position was
affected.

**Fix:** one token, `SEEK_CUR` → `SEEK_SET`. `scripts/patch-f64-truncate-seek.py`.

**Control:** ladder 12/12; corpus returned to **61 matched / 14 diverged** with the
extra assertion in place, so the case now carries a regression guard it did not have
before. (It dipped to 59/16 in between — the new assertion failing on both arches is
what confirmed the defect.)

*Worth noting as method:* this is the one of the four read-only findings that was
cheap to falsify, so it was tested first. The test came before the fix, and the fix
is credited by the test rather than by the reading that suggested it.

### F65 — path-based `NSFileHandle` leaks its descriptor 🟠

`NSFileHandle.m:497-521`, `-initWithURL:flags:createMode:error:`, never sets
`NSConcreteFileHandleOwnsFileDescriptor`. `-dealloc` (`:1149`) closes only when that
flag is set, so any path-created handle released without an explicit `closeFile`
**leaks its file descriptor for the lifetime of the process**. macOS closes on dealloc
for path-created handles.

Long-running processes that open files this way would exhaust their descriptor table.
Not reproduced, so not fixed.

## F61 — `rebuild-cf.sh` reported success for failed builds, and staged stale binaries 🔴

**A defect in our own tooling, and the most dangerous thing found today**, because
every result it touched would have looked normal.

```sh
ninja CoreFoundation_arm64 Foundation_arm64 2>&1 | tail -25
rc=$?                      # <-- status of `tail`, never of ninja
[ $rc = 0 ] || { echo "BUILD FAILED"; exit $rc; }
```

This is **trap 10** — the same defect that once produced a bogus "11/11 gates pass".
`$?` after a pipeline is the last command's status, and `tail` succeeds no matter what
ninja does. So a failed build reported `rc=0`, the script proceeded to the staging
step, and printed `staged`. Nothing new was staged, so the **previous** binary stayed
in place and every subsequent verifier measured code that did not contain the change
under test (trap 16).

Observed live: `ninja: build stopped: subcommand failed.` followed immediately by
`staged`, with a CoreFoundation timestamped nine hours earlier.

The same line violated the project rule to capture the **first** error: `tail -25`
showed warnings from an unrelated translation unit while the actual
`error: use of undeclared identifier` had scrolled away. Two rebuild cycles were spent
on a log that could not contain the answer.

**Fixed** in `scripts/rebuild-cf.sh`:
- ninja's status is read directly, with no pipe;
- full output goes to a file and the **first** `error:`/`FAILED:` is printed with
  context on failure;
- the staged `Foundation` mtime is compared before and after, and a build that does
  not move it exits non-zero with an explicit "treat any result as void" warning.

The mtime guard is the important part: it makes trap 16 impossible to hit silently
rather than merely documenting it. It fired correctly on the next three builds
(`Foundation mtime 1786412531 -> 1786421159`).

**How far back does this reach?** Any earlier rebuild that failed would have been
silently skipped and its verification run against stale code. Every fix credited in
this session was re-verified after the guard was in place, so the current numbers are
sound; results from earlier sessions that were never re-run carry this risk.

## F57 — every `NSProgress` factory method returns `nil` 🔴

Found by `t34_progress`, first run, **both arches identically**. The class exists and
links (no `Symbol not found`, no crash) — and then does nothing at all:

| assertion | macOS | Darling |
|---|---|---|
| `totalUnitCount` after `progressWithTotalUnitCount:10` | 10 | **0** |
| `fractionCompleted` at 5/10 | 0.5000 | **0.0000** |
| `isFinished` at 10/10 | 1 | **0** |
| `isIndeterminate` with total −1 | 1 | **0** |
| `isCancellable` (default) | 1 | **0** |
| `isCancelled` after `-cancel` | 1 | **0** |
| `isPaused` after `-pause` | 1 | **0** |
| parent fraction with a child at 50% | 0.2500 | **0.0000** |
| `addChild:withPendingUnitCount:` | 0.5000 | **0.0000** |
| `userInfo` after `setUserInfoObject:forKey:` | `payload`, count 1 | **`(null)`, count 0** |
| `kind` after `setKind:` | set | **nil** |

Every single assertion is the zero value.

### Correction 2026-08-11 — the first diagnosis was wrong ⚠️

**This entry originally concluded "nothing is stored".** That is not what happens, and
the real cause is both simpler and more interesting. `NSProgress.m:40-47`:

```objc
+ (instancetype)progressWithTotalUnitCount: (int64_t)unitCount
{
    return nil;
}
```

All three factory methods — `+currentProgress`, `+progressWithTotalUnitCount:`,
`+discreteProgressWithTotalUnitCount:` — **`return nil`**. So the test never held an
object at all: every "zero" in the table above is Objective-C's message-to-nil
returning `0`/`NO`/`nil`. That is also why nothing crashed and no unrecognised
selector was ever raised.

**The storage underneath is genuinely implemented.** `NSProgress.m` is 200 lines and
`totalUnitCount`, `completedUnitCount`, `cancel`, `pause`, `resume`, `isCancelled`,
`isPaused`, `isCancellable`, `isPausable` and the three handler properties all have
real, `@synchronized` implementations backed by ivars declared in
`NSProgress.h:24-33`. They are simply unreachable, because nothing can hand you an
instance.

**Why fixing only the factory would make things worse.** Darling's `NSProgress.h` is
53 lines and declares 7 methods. Roughly half of what the test calls —
`fractionCompleted`, `isIndeterminate`, `isFinished`, `userInfo`,
`setUserInfoObject:forKey:`, `kind`/`setKind:`, `becomeCurrentWithPendingUnitCount:`,
`resignCurrent`, `addChild:withPendingUnitCount:` — **is not implemented at all**.
The test compiles against Apple's SDK, so those selectors exist at compile time; today
they are harmlessly swallowed by nil. Return a real object and they become
`unrecognized selector` crashes.

So the fix is not three lines. It is: the factories, `-initWithParent:userInfo:`
actually storing its arguments, the fraction/child-composition arithmetic, the
user-info dictionary, `kind`, and the thread-local current-progress mechanism, plus
new ivars in the header. That is a bounded feature implementation, not a patch —
which is why it was scoped out of this session rather than half-done.

**How the wrong diagnosis happened, since it is instructive.** "All 11 assertions
return zero" is equally consistent with "stores nothing" and with "there is no
object". I wrote down the first reading without opening the file. The distinguishing
evidence — a two-line factory — was one `sed` away.

Note the one *good* piece of news buried in the native column: macOS reports
`over_frac:2.2500` when completed exceeds total — it does **not** clamp to 1.0. Any
reimplementation must reproduce that rather than clamping.

## F58 — an arm64e-only SIGSEGV in `NSThread` 🔴

Found by `t33_thread`. **The arm64 build matches macOS exactly. The arm64e build dies
with SIGSEGV (rc=139) and no output whatsoever.**

```
t33_thread.arm64    0    main_is_main:1~multi_before:0~main_name:corpus-main~…  (exact match)
t33_thread.arm64e   139  (no output)
```

Same source, same compiler, same test — the only variable is the target architecture,
and with it pointer authentication.

**This is the most valuable kind of divergence this project can find.** arm64e/PAC is
the least independently verified part of the stack, and this is a case where the
identical program is correct on arm64 and crashes on arm64e. Everything the arm64 run
proves about the test's own validity carries over: the test is not wrong, the
environment is not wrong.

**Not yet localised.** No output was captured, but per trap 23 a signal death
discards a block-buffered stdout, so the crash may be well past `main`'s first
`printf` — the absence of output is not evidence that it died early. **Next step** is
`setvbuf(stdout, NULL, _IONBF, 0)` plus the arm64 SIGSEGV frame-chain handler that
localised F27, which will give a symbolised backtrace.

Candidate area, stated as a hypothesis only: the case exercises
`detachNewThreadSelector:toTarget:withObject:` and `+[NSThread callStackReturnAddresses]`,
and both thread entry trampolines and stack walking are places where signed pointers
are handled explicitly.

### Localised 2026-08-11 — not fixed, but no longer a mystery 🔎

Narrowed from "SIGSEGV, no output, cause unknown" to a **single statement**, by
bisection. Each step is reproducible.

**Step 1 — "no output" was false (trap 23 again).** Adding
`setvbuf(stdout, NULL, _IONBF, 0)` to the case showed it completes *nine* assertions
before dying, including running a detached thread. A block-buffered stdout had been
swallowing all of it. That change is now permanent in `t33_thread`, so any future
crash there stays diagnosable.

**Step 2 — a reduced probe.** On arm64e:

```
A start / B sleep_only / C sleep_ok / D about_to_detach
E detach_returned / [worker ran]      <-- the worker's own body COMPLETED
SIGSEGV
```

The identical arm64 binary prints everything and exits 0. So `sleepForTimeInterval:`
works, `detachNewThreadSelector:` works, the worker runs — **the crash is in thread
teardown.**

**Step 3 — bisecting the teardown.** `NSThreadEnd` is registered as the
`pthread_key_create` destructor and does three things. Gating each behind an
environment variable and rebuilding:

| skipped | result |
|---|---|
| nothing | **SIGSEGV** |
| the `NSThreadWillExitNotification` post | **SIGSEGV** — the notification is innocent |
| `[thread release]` | **clean, exit 0, full output** |

**Step 4 — inside `-[NSThread dealloc]`.** Tracing each statement: dealloc is entered,
and the crash is on the **first** one, `[_target release]`.

**Step 5 — what `_target` actually is.** Printing it just before the release:

```
self=0x10017d490  _target=0x1000080d8  _argument=0x100004048  _name=0x0
_target isa=0x1000080b0
```

`_target` is the `Class` passed to `detachNewThreadSelector:toTarget:`. It looks
entirely healthy — a plausible address, and an `isa` pointing at its metaclass **with
no PAC bits set**. It can be dereferenced without crashing.

**Step 6 — the obvious explanation, eliminated.** A standalone arm64e probe that
retains and releases a `Class`, then reads its name and `isa`, runs perfectly under
Darling. So "releasing a Class is broken on arm64e" is **not** the cause.

### Where that leaves it

The crash is `[_target release]` on a **valid** Class, executed **inside a pthread key
destructor on a dying thread**, on arm64e only. The most promising remaining
hypothesis — untested — is destructor *ordering*: key destructors run in unspecified
order, so objc's own thread-local state (autorelease pool bookkeeping) may already
have been torn down by the time this one runs, making any message send unsafe. Why
that would differ between arm64 and arm64e is exactly the question.

### A change that was made and credited with nothing

Two function pointers were being handed to pthread through casts to an incompatible
type:

```c
pthread_key_create(&NSThreadKey, (void (*)(void *))&NSThreadEnd);
pthread_create(&_thread, NULL, (void *(*)(void *))&__NSThread__main__, self);
```

Calling a function through an incompatible pointer type is undefined behaviour, and on
arm64e it is the textbook pointer-authentication failure, since a function pointer is
signed with a discriminator derived from its type. It was a good hypothesis. **It was
wrong** — declaring both functions with pthread's own signatures, so no cast remains,
did not change the crash at all.

The change is **kept and credited with nothing**, on the same basis as the
uninitialised-pointer change in F27: removing undefined behaviour is worth doing
regardless of whether it fixed the bug in front of us. Ladder 12/12 and corpus 61/14
with it in. `scripts/patch-f58-threadptr.py`.

## F59 (FIXED) — `removeItemAtPath:` could not delete a regular file ✅

Found by `t32_filehandle`. Exactly one divergence in an otherwise perfect run — every
positional-I/O assertion matches, on both arches:

```
native : …nulldev:1 nulldev_read:0~cleaned:1
darling: …nulldev:1 nulldev_read:0~cleaned:0
```

`cleaned` is `![NSFileManager fileExistsAtPath:]` after `removeItemAtPath:`. macOS
says the file is gone; Darling says it is still there.

Everything else is exact: `readDataOfLength:`, `seekToFileOffset:`, `offsetInFile`,
`readDataToEndOfFile`, `seekToEndOfFile`, append via
`fileHandleForWritingAtPath:`, `truncateFileAtOffset:`, in-place edit via
`fileHandleForUpdatingAtPath:`, both missing-path error cases, reading past EOF, and
the null device.

### Correction 2026-08-11 — the narrowing was a false lead, and the defect is far worse ⚠️

**This entry originally said:** *"This is not general file-removal breakage —
`t14_fileman` exercises `removeItemAtPath:` and passes. The distinguishing feature
here is that the path had been open through several `NSFileHandle`s."*

**Both halves of that are wrong.** `t14_fileman` removes a **directory** —
`NSString *dir = @"/private/var/tmp/corpus-t14"` in our own corpus source — while
`t32` removes a **regular file**. The distinguishing variable is
directory-vs-file. The `NSFileHandle` sequence is a **red herring** I attached to the
symptom because it was the conspicuous thing the failing test did.

**The real cause**, every link read directly in the source:

1. `-[NSFileManager removeItemAtPath:error:]` (`NSFileManager.m:664`) does no work
   itself — it builds an `NSFilesystemItemRemoveOperation`, `-start`s it, and reports
   `[op error] == nil`.
2. That operation removes via **`nftw(3)`**
   (`NSFilesystemItemRemoveOperation.m:102`), and the actual `remove()` call lives
   **only inside the walk callback** (`:75`).
3. Apple's own `nftw.c:113-119` refuses to walk a non-directory:

   ```c
   if (rc >= 0 && nfn) {
       if (!S_ISDIR(path_stat.st_mode)) {
           errno = ENOTDIR; error = -1; goto done;   /* before any callback */
       }
   }
   ```

   `nfn` is non-NULL for `nftw` (it is NULL only for legacy `ftw`), and the build
   defines `__DARWIN_UNIX03=1` (`src/external/libc/CMakeLists.txt:10`).

So for a regular file the walk bails with `ENOTDIR` **before the callback runs**, and
`remove()` is never reached. For a directory `nftw` walks happily and deletes the
regular files *inside* it via that same callback — which is exactly why `t14` passes
and looks like proof that removal works.

**`-[NSFileManager removeItemAtPath:error:]` therefore cannot delete any regular
file.** That is a core Foundation API failing on its most common input, not a corner
case involving file handles.

**Cleared while diagnosing:** `-fileExistsAtPath:` (`NSFileManager.m:187`) is a plain
`stat(2)` with no cache, so `cleaned:0` truthfully reports the filesystem; and
`-closeFile` (`NSFileHandle.m:726`) really does `close(2)` and `-dealloc` guards
against double-close. Neither is implicated.

**The lesson worth keeping:** the false narrowing came from treating "the other test
passes" as proof of a shared capability, without checking that the two tests exercise
the same thing. They did not. *Two tests calling the same selector are not
necessarily testing the same code path.*

### Fixed 2026-08-11, with control ✅

`NSFilesystemItemRemoveOperation.m` now `lstat`s the path and, when it is not a
directory, invokes the existing walk callback directly instead of routing it through
`nftw`, which refuses non-directories. Calling the same callback rather than a bare
`remove()` is deliberate: the `fileManager:shouldRemoveItemAtPath:` and
`shouldProceedAfterError:` delegate contracts and the error plumbing all still apply,
so only the *reachability* of the deletion changed.

`nftw.c` was **not** touched — it is Apple's Libc source and its ENOTDIR behaviour
matches real macOS. `lstat` rather than `stat`, so a symlink is removed as a link.

**Control:** ladder 12/12 before and after; corpus **57 → 61 matched, 18 → 14
diverged** across the batch with F60; `t32_filehandle` **exact match on both arches**.

Applied by `scripts/patch-f59-removefile.py`.

## F60 (FIXED) — attribute runs coalesced across an append ✅

Found by `t31_attrstr`. One divergence in a case that otherwise matches exactly on
both arches — including run splitting, `enumerateAttribute:`, `removeAttribute:`,
`replaceCharactersInRange:`, `insertAttributedString:`, `deleteCharactersInRange:`
and `setAttributes:`:

```
native : …appended:XYdefghij!! finallen:11~coalesced_len:9
darling: …appended:XYdefghij!! finallen:11~coalesced_len:11
```

After `setAttributes:@{@"z":@"1"}` over the whole string and then appending an
attributed string carrying **the same** attributes, the effective range at index 0 is
**9** on macOS (the two runs stay separate) and **11** on Darling (they merge).

**The test's own expectation was wrong first.** The comment in the corpus source
originally asserted that identical attributes *should* coalesce. Ground truth says
they do not, and for a translation layer ground truth wins; the comment has been
corrected rather than the expectation quietly dropped.

**Observable, if subtle.** Run boundaries are visible through `effectiveRange:` and
determine how many times `enumerateAttributesInRange:` fires, so text layout code
that walks runs sees a different structure. Lowest severity of this batch, and the
only one where Darling's behaviour is arguably the tidier of the two — it is still a
divergence.

## F55 — the corpus is self-consistent: 63 cases × 7 runs, zero flapping ✅

**The instrument has now been checked, and it holds.** Every fidelity number in this
project rests on the corpus, and until 2026-08-10 nobody had verified that it gives
the same answer twice. The overnight soak ran it seven times on an unchanged build:

```
scoreboard  7 ×  matched 46  diverged 17  skipped 0
cases whose verdict changed between runs: NONE
  -- all 63 cases gave an identical verdict across 7 runs
```

The ladder ran alongside it as a canary and passed **7/7** (12–45 s), so the
environment did not drift underneath the measurement either.

**Why this is worth a finding of its own.** It converts every "46/63 match" statement
in this project from an assumption into a measurement. A single flapping case would
have meant that any figure quoting it — and any fix credited by it — carried unstated
error bars. None does.

It also bounds what the divergences *are*: 17 cases diverge, and they diverge
**identically every time**. These are deterministic behavioural differences, not
flakiness.

## F56 (FIXED) — `verify-x11-backend` never passed: two missing image dependencies ✅

**Corrects a claim in the report.** The status table lists `x11-backend` as passing
("intermittent — see F29"). Measured over the soak plus one interactive re-run, it is
**0 passes in 8 runs**, rc=1 every time.

The reason it looked like a pass is trap 28. Five of the seven soak failures returned
in 2–8 s and were auto-labelled `ENV-FAIL (apt/network)` by the `<10 s ⇒ environment
failure` rule — a rule written when the only way to finish fast was for apt to fail.
Since F46 baked the X11 dependencies into the image **there is no network step**, so
those fast failures were real results being discarded. Recounting by return code
instead of duration turns "5 of 7 verifiers pass" into something considerably less
comfortable.

### Graphical reliability, recounted by `rc` (7 soak runs each)

| verifier | passes | duration | note |
|---|---|---|---|
| `verify-pty-harness` | **6/6** | 47–86 s | genuinely reliable |
| `verify-controls` | **6/7** | 21–29 s | reliable |
| `verify-hello-window` | **5/7** | 3–12 s | |
| `verify-text-view` | **2/7** | 76–168 s | 29% — not a pass in any useful sense |
| `verify-x11-backend` | **0/7** | 2–14 s | never passed |

### What is known about the x11-backend failure

- **It is not a launch failure.** The application starts and reaches its own runtime
  output (`_CFGetHostUUIDString`, CoreText font fallback), then the run ends without
  printing the script's success line.
- **It is not a missing window manager.** `openbox` and `wmctrl` are baked into
  `darling-arm64-dev:guideps`, so the `_NET_SUPPORTING_WM_CHECK` wait has a WM to
  find.
- **It is not the network.** No apt step remains in the image.
- The environment reports `libEGL warning: DRI3 error: Could not get DRI3 device` —
  expected for a headless `vz` VM with no GPU. Whether the smoke test genuinely
  requires accelerated rendering, or merely warns, is **not yet established**.

### FIXED 2026-08-11 — it was our image, twice over ✅

**`ARM64 X11 backend smoke passed`** — in 6–9 seconds, where before it never passed
at all.

**Corrected after more runs:** the first sample was 4/4; the honest figure is
**11 of 14**. The failures are *not* the original defect — they are an intermittent
internal timeout (status 124, ~17 s against 6–9 s for a pass), i.e. a separate and
still-open problem. Also tested and eliminated: the withdrawn F24 change was suspected
of causing it, since the F24 record showed a 124 too. Reverting F24 and rebuilding
AppKit did **not** remove the hangs (4/6 without it), so F24 is not the cause.

The verifier never had a Darling defect in it. It had **two missing image
dependencies, the second hidden behind the first**, and the failure was being
recorded against Darling.

**Blocker 1 — no fonts.** Capturing the application's own stdout (the verifier
bind-mounts `/artifacts`, which survives the `--rm` container) showed its last two
messages before it vanished were both about fonts:

```
CoreText CJK fallback font selection failed
convertFont:toHaveTrait: failed, San Francisco 2
```

The staged Darling runtime ships **no fonts of its own** — `/System/Library/Fonts` is
empty — so every font request is served by whatever fontconfig finds in the container,
which was DejaVu core plus URW base35 and *no CJK coverage at all*. Adding
`fonts-wqy-zenhei` and `fonts-liberation` (15 MB, chosen over `fonts-noto-cjk`'s
100 MB+) carried the app from dying in 1–3 s to completing the `ready`, `font`,
`focus`, `cursor`, `resize` and `phase` stages and handling `WM_DELETE_WINDOW`.

**Blocker 2 — no `xrdb`.** With fonts in place the verifier reached line 320 and died
with `xrdb: command not found` (status 127). Supplied by `x11-xserver-utils`, which
the image never installed. This one was *invisible* until the first was fixed, because
the application died long before the verifier reached that line.

Both are in `scripts/Dockerfile.gui-deps`.

**This is F46's lesson a second time:** a harness that depends on tools it does not
declare will attribute its own gaps to the software under test. Two of the five
graphical verifiers have now had a "Darling defect" turn out to be a missing package.

**And a second vindication of trap 28:** the fixed runs take **6–9 seconds**. Under
the old `<10 s ⇒ environment failure` rule, every single passing run would have been
discarded as noise.

### Knock-on: `hello-window`

Re-tested after the font fix: **5/6**, against 6/15 measured before it. That is an
improvement but **not** a claim — n=6 is too small for a rate, and the one failure
kept the same 11–12 s signature described in F66. Whether the fonts helped it needs a
proper sample.

### Corrected summary for the report

Of five graphical verifiers: **four are reliable** (`controls`, `text-view`,
`pty-harness`, `x11-backend`) and **one is flaky** (`hello-window`). The earlier
summary — "two reliable, one marginal, one rare, one never" — described an
environment, not a translation layer.

## F52 — `NSXMLParser` has no failure mode at all 🟠

*Introduced by name inside F50 but never given its own heading — the report,
`NEXT_STEPS.md` and `PROGRESS.md` all cite F52, so a reader following any of them
into this file previously found nothing. Written up here 2026-08-10.*

**Diagnosed from source, read end to end (594 lines). Patch written, not yet
applied:** `scripts/patch-f52-xmlparser.py`.

"Malformed XML parses successfully" is not one bug but six, and together they mean
the parser is *structurally incapable* of reporting failure:

| # | site | defect |
|---|---|---|
| 1 | `-parse`, line ~568 | ends in an unconditional `return YES;` — **it can never return NO, for any input** |
| 2 | `_parserError` (`NSXMLParser.h:98`) | only ever *read*, at line 575. Nothing anywhere assigns it, so `-parserError` is permanently `nil` |
| 3 | whole file | `parserDidStartDocument:` / `parserDidEndDocument:` **never appear** — the two document callbacks are simply not implemented |
| 4 | `-unexpectedIn:` | the one error path raises an `NSException` with an **empty name** (`@""`) instead of recording an error |
| 5 | `-eTag:` | carries the comment `// FIX, maybe double check name here` and does exactly that — **never checks the closing tag matches**, so `<a></b>` is accepted |
| 6 | `-abortParsing` | `NSUnimplementedMethod()` |

A seventh, found while reading: `-didEndElement` messages the delegate with **no
`respondsToSelector:` guard**, unlike every other callback in the file — a latent
crash for any delegate that does not implement it.

Points 1 and 2 are the substance. The others are why nothing ever reaches them.

**Why this ranks above a cosmetic gap.** Silently accepting malformed input is worse
than rejecting valid input. Code that validates by checking whether parsing succeeded
gets `YES` for arbitrary garbage, and nothing downstream has any signal that
something went wrong.

**Note:** this tree declares no `NSXMLParserError` enum — the header has the delegate
methods but not the codes. Code switching on parser error codes cannot compile here.
That is a small separate gap; the patch uses Apple's documented numeric values with a
comment rather than inventing an enum.

## F54 — `NSOperationQueue` does not clear finished operations 🟠

Exposed by F51. With cancellation now honoured, the remaining divergence in
`t26_operation` is bookkeeping: after operations finish or are cancelled, the queue
still reports them in `operations` and does not consider itself empty.

| assertion | macOS | Darling |
|---|---|---|
| queue count after drain | 0 | **1** |
| queue empty | 0 | **1** |
| operations array | 0 | **1** |

Execution semantics are now correct — this is the queue failing to remove completed
work from its own array.

### Diagnosis 2026-08-10 — located, but not yet explained

The removal machinery exists and has exactly one caller:

- `-[NSOperationQueue _removeFinishedOperation:]` — `NSOperation.m:1002` — guards on
  `opi->_state != NSOperationStateFinished` and returns early if the operation is not
  finished.
- Its **only** call site is `NSOperation.m:393`, inside the `isFinished` branch of
  the KVO observer, wrapped in a `dispatch_after(… 6 * NSEC_PER_MSEC …)`.

So removal is KVO-driven and deferred by 6 ms. Two candidate causes survive static
reading, and they need runtime to separate:

1. **A timing race.** The test may observe `operations` before the 6 ms
   `dispatch_after` fires. This would make the defect a test-synchronisation artifact
   rather than a queue bug — worth knowing before "fixing" anything.
2. **Asymmetric bookkeeping for never-started operations.** An operation cancelled
   before the queue starts it may never enter the queue's tracking in the way the
   removal path expects.

**Checked and cleared: my own F51 fix.** The cancellation fix returns early from
`-start`, which raised the obvious worry that it bypasses the block scheduling
removal. It does not: the fix emits `willChangeValueForKey:@"isFinished"` /
`didChangeValueForKey:` around the state change, and `-isFinished` reads
`_state == NSOperationStateFinished`, so by `didChange` the observer's
`if (![_operation isFinished]) return;` guard passes and the removal is scheduled
normally. Separately, the `qcount:1` divergence **predates** F51, so F51 did not
introduce it.

Recording this rather than patching blind: distinguishing (1) from (2) costs one
instrumented run and avoids a fix credited to the wrong cause, which has already
happened four times on this project (trap 9).

## F8 — `make install` hangs forever once the container has failed to boot 🟡

`tools/shutdown-user.sh` loops:
```sh
PID=$(pgrep -f launchd)
while [ -n "$PID" ]; do
    su --login "$RUNNING_USER" -c "darling shutdown"
    sleep 2
    PID=$(pgrep -f launchd)
done
```
After a failed boot the host retains **defunct `[mldr]` zombies whose parent is a live
`/sbin/launchd`**, so `pgrep -f launchd` keeps matching, `darling shutdown` correctly
reports "Darling container is not running", nothing is reaped, and the loop spins
forever. Observed output, repeating indefinitely:
```
Darling currently running for crischimiadao, shutting it down...
Darling container is not running
```
`make install` never returns. This is a nasty interaction: **the failure mode caused by
F7 makes reinstalling impossible**, which is exactly what you want to do while
debugging F7.

Workaround: `sudo pkill -9 -f launchd; sudo pkill -9 darlingserver` before installing.
Proper fix: bound the loop with a retry cap, and skip zombies (`ps -o stat=` starting
with `Z`) when scanning.

Related trap: `rm -rf $DPREFIX` partially fails with `Permission denied` on
`$DPREFIX/proc/*` because the prefix has live mounts. Use a fresh prefix via
`DPREFIX=~/.darling_b` when iterating, rather than fighting the mounts.

---

## Status of the runtime claims

**Tier 0 (builds on aarch64): VERIFIED** — independently, on a newer toolchain than
the author's. F1 and F2 are now fixed *properly* (`scripts/patch-f1-f2.py`), leaving
three deviations: F6's libffi patch and two `-Wno-error` flags that may no longer be
load-bearing (worth retesting without them).

**Tier 1: PARTIAL — genuine positive evidence.** `mldr` loads and executes real arm64
Mach-O binaries: `launchd` (arm64 Mach-O) boots as container PID 1, dyld initialises,
and it drives a healthy Mach trap stream against darlingserver. This is the single
most encouraging result so far and it corroborates the core of kkHAIKE's work.

**Tiers 1(complete)–4: NOT verified, blocked by F7.** A daemon launchd spawns
null-derefs, so `shellspawn` never comes up and no *user* binary has executed under
Darling here — not hello world, not bash, not arm64e. The corpus and runner are staged
(`~/corpus`, `~/20-run-corpus.sh` in the VM) and will produce a scoreboard the moment
F7 clears.

**Do not repeat the author's runtime claims as confirmed.** They remain plausible —
the code is serious and the build is sound — but unproven here.

## F60 — fix record (2026-08-11) ✅

Fixed by forcing a run boundary at the append seam, **inside the attributed-string
path only** (`CFAttributedStringReplaceAttributedString`), rather than in
`CFAttributedStringReplaceString` where the fusion happens.

That distinction is the whole design of the fix. The same
`range.location == oldLength` branch is also reached by plain
`-replaceCharactersInRange:withString:` and by `[[m mutableString] appendString:]` —
text that carries **no attributes of its own** and simply inherits the preceding
character's, for which a single extended run is the natural representation. macOS
behaviour for that case is not established by our evidence, so it was left alone.
What distinguishes the failing case is *provenance*: `appendAttributedString:` brings
its own attribute dictionary, and macOS keeps that a separate run even when the
dictionary happens to be equal.

**The risk that was checked rather than assumed.** `_CFRunArrayIsEqual` compares run
*structure*, not per-character attributes, so adding a seam could have changed which
attributed strings compare equal. `t31_attrstr` asserts `eq_same:1 eq_diff:0` and
still matches, so the equality semantics the corpus exercises are unaffected.

Also verified before writing the patch: `_CFRunArrayDestroyAttributesOfString` walks
the slot array stepping by `inp->_range.length` and destroys each unique item once, so
splitting one run into two that still tile the array leaks nothing and frees nothing
twice.

**Control:** ladder 12/12; corpus **57 → 61 matched**; `t31_attrstr` exact match on
both arches, including the three run-boundary assertions that were already passing
(`run0_len:5`, `run1_loc:5 run1_len:5`, `runs:2`) — those route through
`longestEffectiveRange`, which re-coalesces at query time, so the new storage boundary
is correctly invisible to them.

Applied by `scripts/patch-f60-appendseam.py`.

## F67 — `NSPredicate` substitution returns nothing, and a catchable exception escapes 🔴

**Found while auditing the report, not by a new test** — `t24_predicate` has diverged
since it was added, and it turns out **no finding was ever written for it**. It was
one of the corpus's divergences with nothing in this file explaining it, which also
made the report's claim that every divergence cause is characterised untrue. Recorded
now.

Both arches, identically:

```
native : …eval_true:1 eval_false:0~subst:2 names:gamma,delta~sort1:…
         …unknownkey_caught:1 name_match:1~unbound_caught:1~parse_caught:1   (exit 0)

darling: …eval_true:1 eval_false:0~subst:0 names:~sort1:…
         libc++abi: terminating with uncaught exception of type NSException
         reason: 'This class is not key value coding-compliant for the key bogusKey.'
                                                                             (exit 133)
```

Two distinct defects in one case:

### 1. `substitutionVariables` matches nothing

`subst:2 names:gamma,delta` on macOS; `subst:0 names:` under Darling. A predicate
template evaluated with substitution variables returns an empty result rather than the
two objects it should. Everything *before* it matches exactly — comparison operators,
compound `AND`/`OR`, `BEGINSWITH` with and without case sensitivity, `IN`, KVC-format
predicates, and all three sort descriptors. So predicate evaluation broadly works; it
is substitution specifically that yields nothing.

### 2. A `@catch`-able exception terminates the process

The test wraps an unknown-key access and expects to catch it — macOS reports
`unknownkey_caught:1`. Under Darling the `NSException` escapes to
`libc++abi` and kills the process with exit 133, so the last four assertions never
run.

**This is not general exception breakage.** `t22_error` exercises
`@throw`/`@catch`/`@finally`, exception name and reason, and an out-of-range
`objectAtIndex:` raising — and it matches macOS exactly. Whatever is wrong is specific
to an exception raised out of KVC/predicate evaluation, not to exceptions as such.

**Severity.** An uncatchable exception is worse than a wrong answer: the caller has
written correct defensive code and the process dies anyway. Any application that
validates user-supplied key paths this way terminates.

**Not diagnosed** — recorded with its evidence so it stops being an unexplained row in
the scoreboard. Order of attack: the escaping exception first (it truncates the test
and hides whatever the last four assertions would have said), then substitution.

## F68 (FIXED) — `createSymbolicLinkAtPath:` passed its arguments backwards ✅

Found by accident, and the accident is the interesting part.

`-[NSFileManager createSymbolicLinkAtPath:withDestinationPath:error:]`
(`NSFileManager.m:893`) called:

```objc
int err = symlink([path UTF8String], [destPath UTF8String]);
```

POSIX is `symlink(target, linkpath)` — it creates *linkpath* pointing at *target*.
Cocoa's method means "create a link **at** `path` whose contents are `destPath`". The
correct call is therefore `symlink(destPath, path)`. The arguments were reversed, so
it tried to create the link **at the destination**, pointing back at the requested
link path.

**Two failure modes, and the quiet one is worse:**

| destination | behaviour |
|---|---|
| already exists (the usual case) | `symlink` fails `EEXIST`, method returns `NO`. Visible. |
| does not exist | **succeeds**, creating a link somewhere the caller never asked for, pointing the wrong way — and no link where the caller wanted one. Silent. |

### How it was found, and the false negative it nearly caused

Nobody was looking for it. A corpus case was being written to reproduce **F63**
(directory removal following symlinks). Its first run reported:

```
setup link:0 victim:1 inner:1 ~ link_is_link:0 ~ … victim_survived:1 …
```

`victim_survived:1` is the *passing* value — it looks like F63 does not reproduce. It
was worthless: `setup link:0` says the symlink the test depends on was never created,
so the dangerous path was never exercised.

**That is trap 17 in the wild** ("confirm the failing path is still exercised"). Had
the case not asserted on its own setup, the run would have been read as evidence that
a data-loss defect does not exist. Two defects were stacked, and the outer one was
masking the inner one as a false negative.

**Fix:** swap the arguments. `scripts/patch-f68-symlink-args.py`.

**Control:** with it in, `t35_symlink` reports `setup link:1 link_is_link:1` — and
immediately exposed F63 as real (`victim_survived:0`). Both are now fixed and the case
matches macOS exactly on both arches.

**Lesson worth keeping:** *a test must assert on its own preconditions.* A test that
silently fails to set itself up reports success, and the more dangerous the defect it
was written for, the more expensive that false negative is.

**Noted, not fixed:** this method reports failures in `NSPOSIXErrorDomain`, the same
category error as F45. Out of scope here; no test covers it.

## ⚠️ CORRECTION 2026-08-12 — the graphical baseline in this record was wrong

**Claimed here and in both reports:** that nothing rendered before this effort, and
that the graphical programs which work are harnesses written for it.

**Both are false.** `darling-aarch64-north-star-iterm2.md`, in the repository this
work was pushed to, records **Stages 11–19 complete on 2026-07-11** — three weeks
before this effort began:

| stage | recorded complete |
|---|---|
| 11 | X11 backend: titled window, RGB pixel assertions, fontconfig, focus, keyboard, mouse, resize, `CLIPBOARD`/`PRIMARY`, `WM_DELETE_WINDOW` |
| 12–14 | `HelloWindow`, `Controls` (menus, buttons, real AppKit sheet), `TextView` (550,113 glyphs, undo, clipboard) |
| 15 | **`TextEdit.app`: Command-S writes exact UTF-8 bytes**, reopens from a clean prefix |
| 16–17 | PTY harness: termios, `SIGWINCH`, 1,000 shell spawn/exit cycles |
| 18–19 | **Unchanged, SHA-256-pinned official iTerm2** reaching a live shell in 9.4 s, rendering `UTF8\|é\|中\|é\|😀\|END`; tabs, splits, profiles, settings persistence, arrangement restoration |

### How the error happened

The baseline was taken from this project's own `STATE.md` and `HANDOFF.md`, which said
"nothing rendered". The primary source was never read — and it was sitting in the
repository being pushed to. This is the project's own rule inverted: *do not treat an
internal note as ground truth without checking the source it summarises.* Recorded as
**trap 34**.

### What it changes, and what it does not

**Unaffected:** every corpus result, all Foundation/CoreFoundation/objc4 findings, the
26 fixes, the self-consistency measurement. That work is independent of this error.

**Changed, and sharpened:**

- **F27 is a regression, not a gap.** Stage 15 recorded Command-S working. Our Cocotron is `f748a5da`, **61 commits ahead** of the pinned
  `c86bf11c` — verified. The pinned Darling/TextEdit revision `141eb5c` **does not
  resolve in this tree**, so comparable TextEdit sources are unconfirmed. It fails
  69/69. The right next step is **bisecting the commit range between their
  pin and here** — which was never attempted, because the defect was wrongly believed
  to be unimplemented behaviour rather than something that used to work.
- **F56 was never a Darling defect at all.** Stage 11 recorded `verify-x11-backend`
  passing. It failed 0/15 *here* because this verification's container lacked a CJK
  font and `xrdb`. The gate was fine; our environment was not.

### The honest framing

This effort added **no graphical capability**. What it added is independent
re-execution of gates someone else completed, on a different machine, in a clean
environment — and two of seven did not reproduce. That is a legitimate and useful
result, and it is a different claim from the one this record was making.

## ⚠️ CORRECTION 2026-08-12 (second) — two claims tightened

**1. The revision comparison for F27 was overstated.** The previous correction said we
are "at or after" the Stage 15 pin on both Darling and Cocotron. Only the Cocotron half
is verifiable: we are `f748a5da`, 61 commits ahead of `c86bf11c`. The pinned Darling
revision `141eb5c` **does not resolve in this tree at all** — the earlier check ran
`git log 141eb5c..HEAD` with stderr discarded, so a "not a valid object name" error was
read as "0 commits". **Trap 10 again**, in a third place: a status swallowed by
redirection. F27 is therefore "fails on a Cocotron 61 commits later, with an
unverified TextEdit revision", not a confirmed regression.

**2. Why the iTerm2 ladder was never continued — it was never entered.** Every iTerm2
gate resolves against a **Stage 18** environment: `install-arm64-stage18`,
`build-arm64-stage18`, `darling-arm64-dev:24.04`, `darling-arm64-gui-test:latest`, and
an extracted `reference/iTerm.app`. **This workspace has none of them.** All work here
ran against `install-arm64-stage10`.

The one gate that does not need Stage 18 was run today and passes:

```
tools/verify-iterm2-artifact-arm64.sh
  iTerm2-3_6_11.zip: OK
  Official unmodified iTerm2 3.6.11 artifact passed
```

So the iTerm2 line is blocked here on **absent infrastructure**, not on any defect
this effort found. The fixes made — `objc4`, `foundation`, `corefoundation`,
`darlingserver`, `xnu` — compile into every stage including 18, so they sit *under*
that ladder rather than beside it.

Recorded as **trap 35**: before judging progress against a project's goal, locate the
artifact set that goal is defined against. Twelve rungs were being climbed on Stage 10
while the target ran on Stage 18.

## F69 — the Bronze and Silver tiers cannot be independently reproduced 🔴

**Six of the seven iTerm2 gates hard-require an Apple macOS 26.5 dyld shared cache
that the project cannot redistribute.** Measured, not inferred:

| gate | needs the cache? |
|---|---|
| `verify-iterm2-artifact` | no — **passes here** |
| `verify-iterm2-bronze-soak` | **yes** |
| `verify-iterm2-silver-tabs` | **yes** |
| `verify-iterm2-silver-tab-close` | **yes** |
| `verify-iterm2-silver-splits` | **yes** |
| `verify-iterm2-settings-persistence` | **yes** |
| `probe-iterm2-launch` | **yes** |

Every one of the six sets `ITERM2_PROBE_SHARED_CACHE=1`, and the probe they all route
through fails closed:

```sh
cache_root=${ITERM2_SHARED_CACHE_ROOT:-$workspace_root/downloads/macos/26.5/dyld-stage18}
[[ -f $cache_root/dyld_shared_cache_arm64 ]] || { echo "Missing staged shared cache." >&2; exit 2; }
```

The cache came from a retained `UniversalMac_26.5_25F71_Restore.ipsw`. dyld's preflight
validates "the main file and **all 12 named subcaches**, UUIDs, mappings, protections,
slide-info ranges", and AppKit additionally needs the matching 25F71
`SystemAppearance.bundle`. `downloads/macos` does not exist in this workspace, and
there is **no extraction tooling anywhere in `tools/`**.

### Why this matters more than a missing file

The project's own README sets a contributor target of **"reaching iTerm2 in under 30
minutes"** and concedes the current path does not meet it, tracked in issue 2. This
finding names the reason precisely: *the gates that define Bronze and Silver cannot be
run by anyone who does not independently possess one specific ~15–20 GB Apple restore
image.* Not a slow on-ramp — a closed one.

**This is not a criticism of the result.** iTerm2 genuinely runs there, and the
Unmodified Binary Artifact Rule is exactly right. But "iTerm2 3.6.11 passes Bronze and
Silver" is currently a claim only its author can check, and that is worth stating
plainly to a project whose whole discipline is evidence over assertion.

### What is reproducible without it

The artifact gate, which we ran: `Official unmodified iTerm2 3.6.11 artifact passed`,
archive SHA-256 `36e78c50…7398e7` intact, and the extracted bundle's executable
matching the `42824bb0…5a83d240` the Silver gates expect. So the *inputs* verify
independently; only the *behaviour* cannot.

### Recommendation

A `SHARED_CACHE=0` variant of the launch probe would let a contributor reproduce
Darling's progress *toward* Bronze — the documented dependency sequence
(libaprutil → AVFoundation → CryptoKit → JavaScriptCore → SwiftUI) — without the
restore image. It would be a **materially weaker gate** than the one that passed
upstream and must be labelled as such, never reported as "Bronze reproduces". But it
would convert a closed door into a measurable ladder, which is what issue 2 is asking
for.

**Also confirmed unbuildable from this tree**, independent of the cache: `CryptoKit`
has no target anywhere in `src/` (the doc sources it from a private fork not present
here), and Swift's dylibs are Git-LFS pointer files. Those bound how far any
cache-free probe can get.

## F70 — Stage 18 built independently, and unmodified iTerm2 reaches CryptoKit without Apple's cache ✅

**Stage 18 now exists on a second machine.** Nothing in the tree builds one —
`bootstrap-stable.sh` ends with *"The separate Stage 18 iTerm2 asset/bootstrap path is
not automated yet"*, and both `prepare-*` scripts refuse to create the roots they
populate. `scripts/99-stage18-build.sh` closes that gap.

**It took six minutes, not the hours estimated.** The roots were seeded by *copying*
the known-good Stage 10 install and the existing GUI build directory, so ~22,000
already-built edges were reused and only the Stage 18 delta recompiled. The working
Stage 10 was never mutated.

```
05:43:40  stage18 build start (jobs=8)
05:49:59  ninja rc=0 after 6 min, 88133 log lines
          installed: cli_gui_common, core, gui, stage18, jsc
05:50:03  JavaScriptCore   45,348,976 bytes
          ScreenCaptureKit     70,356 bytes
          Metal / MetalKit / Quartz / QuickLookUI   present
          libapr / libaprutil                       present
```

**Control: the Stage 18 runtime passes the capability ladder 12/12**, so it is a sound
runtime and not a pile of objects.

Two notes for anyone repeating this:

- **`cmake --install --component stage18` has no consumer anywhere in the tree.** The
  component tag exists and nothing invokes it. Installing it is the missing link
  between a configured build root and a populated install root.
- **`libDarlingAppKitBootstrap.dylib` has an `install()` rule with no `COMPONENT`**, so
  every named-component install misses it. It lands via the default (`Unspecified`)
  component. *(Our first check for it also used the wrong filename and reported a
  false absence — the file was there all along.)*

### The cache-free probe: how far iTerm2 actually gets

`probe-iterm2-launch-arm64.sh` **defaults `ITERM2_PROBE_SHARED_CACHE=0`**, and its
cache check is conditional on that flag. Only the Bronze/Silver gates force it to 1.
So the probe runs on a machine with no Apple restore image — which is exactly the
reproducible ladder F69 asked for, and it already existed.

Result, against our independently built Stage 18:

```
exit:134
dyld: Library not loaded: /System/Library/Frameworks/CryptoKit.framework/Versions/A/CryptoKit
  Referenced from: /Applications/iTerm.app/Contents/MacOS/iTerm2
  Reason: image not found
abort_with_payload: reason: dyld: No shared cache present
```

**The official, unmodified, checksum-pinned iTerm2 3.6.11 binary loads under our own
Stage 18 and resolves its dependency chain as far as CryptoKit.** It cleared
`libaprutil` and AVFoundation — the two earlier boundaries in the project's own
documented sequence — because this Stage 18 supplies them.

**This is not Bronze and must never be reported as Bronze.** Bronze requires a
terminal window, a PTY, a shell, and twelve interactions. This is a dynamic-linker
milestone. But it is a *measured, reproducible* one obtained without the restore
image, and it locates the next real boundary precisely.

### Why CryptoKit is the boundary, and why it may be passable

`CryptoKit` has no target in this tree. The record sources it from the private
`deepai-org/darling-aarch64-swift-crypto` fork at `ded03e5`, whose BoringSSL
implementation supplies exactly the symbols iTerm2 imports (SHA-256, Curve25519/
Ed25519). **We have WRITE access to that fork.**

It needs Apple's Swift 6.2.4 runtime, and the staged Swift dylibs here are **132-byte
Git-LFS pointer files**. But `tools/prepare-swift-runtime-arm64.sh` fetches the
runtime from `download.swift.org` — a **public, SHA-256-checksummed release**
(`swift-6.2.4-RELEASE-osx.pkg`, `9c94637f…59e9`), *not* an Apple restore image.

So unlike the shared cache, this boundary is obtainable. Whether it actually clears is
recorded below.

### The CryptoKit boundary is not passable here, and the reason is a documentation gap

`deepai-org/darling-aarch64-swift-crypto` exists, we have **write** access, and the
pinned commit `ded03e55` ("Add focused Darling ARM64 CryptoKit surface") is present on
two branches. Its `DARLING_ARM64.md` says:

> "Build, ABI verification, staging, and disposable Darling runtime tests are owned by
> the private `darling-aarch64-north-star` repository."

**That tooling does not exist in that repository.** Searched our checkout and the
remote's default branch `community-integration` (`f5e5de68a`) — the only Swift-related
tools anywhere are:

```
tools/prepare-swift-runtime-arm64.sh
tools/verify-swift-cross-compile-arm64.sh
```

There is no script that builds, stages, or verifies a CryptoKit framework. So the fork
points at build tooling in a repo that does not contain it, and the CryptoKit slice
cannot be reproduced from the two repositories together.

**What clearing it would actually take:** cross-compiling Swift Crypto — a Swift
package with vendored BoringSSL — to an arm64 Mach-O framework, using the macOS Swift
6.2.4 toolchain on Linux, with an ABI surface matching what the official iTerm2 binary
imports. That is real engineering, not a missing command, and it was explicitly out of
scope for this sprint.

**Deliberately not attempted.** A hand-rolled CryptoKit that satisfies the dynamic
linker without implementing SHA-256 and Ed25519 correctly would let the probe advance
and would be worthless — the exact "success-returning no-op" the project's own
compatibility policy forbids. Better to stop at a true boundary than to pass a false
one.

### Where the cache-free ladder now stands, measured

| boundary | status here |
|---|---|
| `libaprutil` | **cleared** — Stage 18 supplies it |
| AVFoundation | **cleared** |
| **CryptoKit** | **blocked** — no target in tree, no build tooling in either repo |
| JavaScriptCore | **pre-supplied** — 45 MB framework built and staged, untested because CryptoKit blocks first |
| SwiftUI | unreachable; Swift dylibs in-tree are Git-LFS pointers |

Swift 6.2.4 was fetched and checksum-verified (`swift-6.2.4-RELEASE-osx.pkg`, OK) via
`prepare-swift-runtime-arm64.sh`, confirming that half of the CryptoKit prerequisite is
publicly obtainable. The other half — the build — is not present to run.

## F71 — 43 Swift dylibs in the staged runtime are Git-LFS pointer files 🟠

A byte-accurate scan of the staged runtime:

```
LFS pointers posing as .dylib:  43   (of 275 .dylib files total)
  130B  /usr/lib/swift/libswiftDarwin.dylib
  132B  /usr/lib/swift/libswiftCore.dylib
  130B  /usr/lib/swift/libswiftObjectiveC.dylib
  130B  /usr/lib/swift/libswiftCoreImage.dylib
  … 39 more, all under /usr/lib/swift/
```

Each is a ~130-byte text file beginning `version https://git-lfs.github.com/spec/v1`,
carrying a `.dylib` extension. **They are present in the untouched Stage 10 install
too**, so this predates this effort and applies to the runtime everything else has
shipped on.

**Why it is worse than a missing file.** A loader asked for a library that does not
exist gets a clean, diagnosable `image not found`. A loader handed a 130-byte text
file gets a malformed Mach-O, and the failure surfaces further away from its cause.
This is the same shape as F57 (`NSProgress` factories returning `nil`): a thing that
is present-but-hollow is harder to debug than a thing that is absent.

It also explains the SwiftUI boundary the project's own record describes — those
dylibs were never real in this checkout.

**A scan bug worth recording, because it nearly hid this.** The first pass used
`find -name '*.dylib' -size -1k` and reported **zero**. `-size` with a `k` suffix
rounds *up* to whole blocks, so a 132-byte file counts as one block and is excluded by
`-1k`. Byte units (`-size -600c`) found all 43. A size filter that silently rounds is
exactly the kind of instrument error this project keeps meeting — see trap 28.

**Now fixable.** `tools/prepare-swift-runtime-arm64.sh` fetches the official Swift
6.2.4 macOS toolchain from `download.swift.org` (public, SHA-256 verified) and extracts
a genuine 17 MB universal `libswiftCore.dylib` to
`downloads/swift/6.2.4/toolchain/usr/lib/swift/macosx/`. The script **downloads and
extracts but does not stage** — nothing in either repository copies those into an
install root, the same gap as the CryptoKit tooling.

## F72 (FIXED) — `-[NSPopUpButton setTitle:]` threw on an empty pull-down, killing iTerm2 ✅

**A real Darling AppKit defect, found by running unmodified iTerm2, fixed, and
controlled.** This is the first defect this effort has found *on the iTerm2 path
itself*.

```
*** Terminating app due to uncaught exception 'NSRangeException',
    reason: '-[__NSArrayM objectAtIndex:]: index 0 beyond bounds for empty array'

 3  AppKit    -[NSMenu itemAtIndex:]                      <- Darling (0x300…)
 4  AppKit    -[NSPopUpButtonCell itemAtIndex:]           <- Darling
 5  AppKit    -[NSPopUpButton setTitle:]                  <- Darling
 6  iTerm2    -[PSMOverflowPopUpButton initWithFrame:pullsDown:]
 7  iTerm2    -[PSMTabBarControl setupButtons]
11  iTerm2    -[PseudoTerminal finishInitializationWithSmartLayout:…]
19  iTerm2    -[iTermUntitledWindowStateMachine openWindowIfWanted]
```

*(Frames at `0x300…` are Darling's own AppKit; `0x180…` frames in the same stack are
Apple's CoreFoundation from the shared cache. The defect is ours, not Apple's.)*

`NSPopUpButton.m:200` called `[[_cell itemAtIndex:0] setTitle:]` with **no empty-menu
guard**. iTerm2 builds `PSMOverflowPopUpButton` as a *pull-down* and sets its title
before adding any item, so `itemAtIndex:0` raised, nothing caught it, and the
application died **before its first window existed**.

macOS does not throw here. **Fix:** create the item the pull-down title is meant to
occupy when the menu is empty — which is what the cell already does on its
non-pull-down path (`NSPopUpButtonCell.m:440`), so this applies existing policy
consistently rather than inventing one.

**Control:** capability ladder **12/12** before and after. The exception no longer
appears, and iTerm2 proceeds past window construction.
`scripts/patch-f72-popupbutton-settitle.py`.

## F73 — the next boundary: iTerm2's X11 window does not persist 🟠

> **RETRACTION (2026-08-12).** This finding was first published as *"`sys_proc_info` is
> unimplemented, so no session starts"*. **That diagnosis was wrong** and is corrected
> below. It was inferred from a correlation — 13 refused `sys_proc_info` calls next to
> a missing PID file — without checking whether the code that writes the PID file was
> ever reached. It was not. Acting on it would have sent the next session into the
> kernel shim for nothing. The original text is kept below the correction so the error
> is auditable rather than quietly deleted.

With F72 fixed, unmodified iTerm2 gets substantially further and **stays alive**:

```
ReparentNotify / MapNotify / VisibilityNotify / FocusIn     <- X11 window mapping
-[iTermSearchResultsMinimapView animator] unimplemented      (stub, non-fatal)
-[X11Display orderedWindowNumbers]() unimplemented           (stub, non-fatal)
sys_proc_info(): Unsupported callnum: 1                      x13
sys_proc_info(): Unsupported pidinfo flavor: 9
status: running                                              <- no crash
```

**What is now proven:** iTerm2 reaches `NSApplicationMain`, enters its main run loop
under Darling's X11 AppKit, constructs its terminal window and tab bar, and issues X11
window-mapping events.

**What is NOT proven, and must not be claimed:** the captured window list contains
only Openbox's own 1×1 helper windows — **no iTerm2 window appears in it**. So this is
"reached window mapping", not "displayed a usable terminal".

### The blocker — corrected

**The missing PID file is a consequence, not the fault.** The gate never types anything
until `wait_for_iterm2_window` succeeds
(`xdotool search --onlyvisible --class "^iTerm2$"`), and its *pre-typing* checkpoint
file is **absent from every run**. No shell was ever asked to write
`silver-tab1-pid.txt`, so its absence says nothing about whether a session could start.

Re-running with the gate's exact flag set and the window search widened to 45 seconds
(900 attempts) settles it: **no iTerm2 window is present in X at all**, while the
process stays alive and its own log shows `MapNotify` ×2 and `ReparentNotify` ×2 with
no exception. `ReparentNotify` means Openbox did manage a real top-level window — yet
`xwininfo -root -tree` at capture time shows only Openbox's own 1×1 helpers.

**So the boundary is that iTerm2's X11 window does not persist.** The `sys_proc_info`
refusals are noise on an unrelated polling path; implementing `proc_info` would not
move this.

**The narrow next question:** what unmaps or destroys the window between
`ReparentNotify` and capture. Sampling `xwininfo -root -tree` *during* the wait loop
rather than after it should settle that in a single run.

<details><summary>Original (wrong) diagnosis, retained for audit</summary>

> The Silver gate needs a live shell to run
> `printf %s $$ > /artifacts/silver-tab1-pid.txt`. No session is established, and
> `sys_proc_info` is called 13 times and refused every time. iTerm2 uses `proc_info`
> to track its session child processes, so a terminal session plausibly cannot come up
> without it. **Unproven causally** — the correlation is strong and the next step is
> to implement enough of `proc_info` to answer it.

</details>

Two non-fatal stubs also surfaced on this path and are worth noting for whoever
continues: `-[X11Display orderedWindowNumbers]` (`X11Display.m:1081`) and
`-[NSView animator]` (`NSView.m:3009`).

## F74 — a macOS **26.6** shared cache works, where the ladder assumed 26.5 ✅

The single most reusable result of this sprint, and the one this machine was uniquely
able to produce.

Every Bronze/Silver gate resolves `ITERM2_SHARED_CACHE_ROOT` to
`downloads/macos/26.5/dyld-stage18`, sourced from a retained
`UniversalMac_26.5_25F71_Restore.ipsw` (F69). **That is not the only cache that
works.** This host runs macOS **26.6 (25G72)**, whose cache is present as ordinary
files at:

```
/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/
  dyld_shared_cache_arm64e            + 11 subcaches + .atlas + .map   (1.9 GB on disk)
```

Staged into the workspace and pointed at with `ITERM2_SHARED_CACHE_ROOT`, dyld loads
it and iTerm2 links through it — **CryptoKit stops being a blocker entirely**, because
the cache supplies it. That removes the boundary F70 recorded, without the private
Swift-Crypto fork and without building anything.

### One non-obvious step, worth writing down

The naming matters. dyld derives subcache paths by appending suffixes to **the main
cache path it was handed**, so pointing it at `dyld_shared_cache_arm64` while the
subcaches are named `…arm64e.01` fails with:

```
dyld: dyld cache load error: shared cache file open() failed
```

Symlinking the *whole set* (`dyld_shared_cache_arm64*` → `…arm64e*`, including
`.02.dylddata`, `.03.dyldreadonly`, `.04.dyldlinkedit`, `.atlas`, `.map`) fixes it, and
dyld then reports `Using shared cache for …`. Aliasing only the main file is not
enough — that intermediate failure is easy to misread as "the cache is incompatible".

### Why this matters

- **The 26.5 pin is a convention, not a requirement.** A contributor with any
  reasonably current Apple Silicon Mac can supply a cache from their own running OS.
  Combined with F69, that meaningfully reopens a door which looked closed: the blocker
  was never "you need *this* IPSW", it was "you need *a* cache, and nothing says so".
- **The port tolerates a macOS it has never been tested against.** Apple's
  CoreFoundation, Foundation and libobjc from 26.6 load alongside Darling's own AppKit,
  and the hybrid reaches an application run loop.

### Honest limits

Not a Bronze or Silver pass — the gates still fail (F73). Not proof that 26.6 is
equivalent to 26.5; only that it gets this far. And the cache is Apple's property:
used locally on the machine whose OS it came from, **never committed** — the same rule
applied to `corpus/bin`.

## F75 (FIXED) — `-[NSWindow disableBlur]` unrecognised, killing iTerm2 intermittently ✅

The second defect found on the iTerm2 path, and the one that made the first look
unstable.

After F72, a reproducibility check gave **run 1 clean, run 2 crashed** — which briefly
looked like F72 being incomplete. It was not. Run 2's exception was a different one:

```
*** Terminating app due to uncaught exception 'NSInvalidArgumentException',
    reason: '-[NSWindow disableBlur]: unrecognized selector sent to instance 0x70170bc00'
```

`-[NSWindow disableBlur]` and `-[NSWindow enableBlur:]` are private AppKit SPI for
window background blur. Both selectors are present in the official iTerm2 binary
(confirmed by scanning it). Darling declared neither, so the message was unrecognised,
the exception uncaught, and the application terminated.

**Intermittent because it is profile-dependent**: iTerm2 only takes this path when the
active profile has transparency or blur configured, and the probe's saved preferences
vary between runs. That is worth noting on its own — *a crash that depends on saved
application state will look like flakiness*, and this project has already been misled
by apparent flakiness twice (F29, F66).

### Why a no-op is truthful here rather than a fake

The project's policy forbids success-returning no-ops that hide a broken contract.
This is not one, and the distinction is worth being precise about:

- Darling's X11 backend has **no compositor blur at all**.
- `disableBlur` asks for the postcondition *"this window is not blurred"* — already and
  permanently true. Returning without acting makes it hold. That is a correct
  implementation.
- `enableBlur:` cannot deliver blur. The window renders unblurred: a cosmetic
  difference that drops no data, fakes no state, and returns no value a caller will
  later rely on.
- Leaving the selectors missing is **strictly worse** — it converts a cosmetic gap into
  a fatal exception that prevents any window from existing.

Rung 2 of the project's own stub ladder. **Explicitly not a claim of blur support.**

### Control, and the combined result

Ladder **12/12** before and after. With F72 and F75 together, across **three
consecutive runs**:

```
  run 1: exception=NONE  MapNotify=2  status=running
  run 2: exception=NONE  MapNotify=2  status=running
  run 3: exception=NONE  MapNotify=2  status=running
```

**Unmodified iTerm2 3.6.11 now reliably launches on an independently built Stage 18
with a macOS 26.6 shared cache, reaches its run loop, constructs its terminal window
and tab bar, maps an X11 window, and stays alive with no uncaught exception.**

Still not Bronze, and still no rendered terminal — the captured window list holds only
the window manager's own 1×1 helpers, and the Silver gate still fails on the missing
shell-session evidence described in F73. But the crash-free path to window mapping is
now reproducible rather than a single lucky run.

## ⚠️ F73 CORRECTED — the blocker is the window, not `sys_proc_info`

F73 named `sys_proc_info` as the likely reason no shell session starts. **That was
wrong**, and the correction matters because it would have sent the next session into
the kernel shim for nothing.

### How the gate actually decides

`verify-iterm2-silver-tabs` never types anything until it finds a window:

```sh
window=$(wait_for_iterm2_window) || exit 1        # xdotool search --onlyvisible --class "^iTerm2$"
xdotool windowactivate --sync "$window"
xdotool type --delay 20 -- "$ITERM2_PROBE_TYPE_TEXT"   # printf %s $$ > …/silver-tab1-pid.txt
```

The checkpoint file `iterm2-before-input-status.txt`, written immediately *before*
typing, is **absent from every run**. So the gate never found a window, never typed,
and the missing PID file is a *consequence*, not the fault. No shell was ever asked to
run anything.

### The measurement

Probe re-run with the Silver gate's **exact** flag set and `WAIT_SECONDS=45` (a
300→900 attempt window search):

```
probe rc=0  secs=56  status=running
  window found?      NO
  typed landed?      NO
  iTerm window in X?  0
  windows >1x1:      (none)
```

Meanwhile iTerm2's own log for that run shows **`MapNotify` ×2 and `ReparentNotify`
×2**, no exception, and it continues loading NIBs (`NSTextField initWithCoder`) to the
end. `ReparentNotify` is emitted when a window manager reparents a **real, mapped,
top-level window** into its frame — so Openbox did manage a window.

**Yet `xwininfo -root -tree` at capture shows only Openbox's own 1×1 helpers and
nothing with `iTerm` in its name or class.** A window is created, mapped and
reparented, and is gone by the time anything looks for it.

So the corrected boundary is: **iTerm2's X11 window does not persist**, and
`sys_proc_info` is noise on an unrelated polling path.

### A methodological error worth recording (trap 37)

The first long-wait run appeared to confirm "no window ever" — but it had loaded
**Apple's** AppKit from the shared cache (frames at `0x1849…`) instead of Darling's
(`0x300e…`), because I omitted `ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1`, which the gate
sets. Apple's AppKit cannot work on Linux and died at once, so that run measured
nothing.

**Dropping one flag from a fifteen-flag configuration silently changed which AppKit
was under test.** When reproducing someone's gate, copy their whole environment, not
the parts that look relevant — and check *which* implementation actually loaded before
trusting the result.

### Next step for whoever continues

Instrument `X11Window` destruction/unmapping rather than the kernel. The question is
narrow: what unmaps or destroys the window between `ReparentNotify` and the harness's
first look? Capturing `xwininfo` *during* the wait loop rather than after it would
settle it in one run.

## F76 — the Stage 18 on-ramp did not exist; it does now, and it takes ~7 minutes ✅

**Filed against `deepai-org/darling-aarch64-north-star` issue 2** ("Provide a
reproducible one-command ARM64 developer bootstrap"), which is open and targets
*"a new contributor can reach the terminal in under 30 minutes"*.

### The gap, stated precisely

There was no path from a Stage 0–17 runtime to a launchable Stage 18. Three separate
facts combine into a dead end:

- `bootstrap-stable.sh` stops at Stage 0–17 and says so: *"The separate Stage 18
  iTerm2 asset/bootstrap path is not automated yet."*
- `cmake --install --component stage18` **has no caller anywhere in either
  repository.** The component tag exists; nothing invokes it.
- Both `prepare-*` scripts refuse to create the roots they populate.

So every iTerm2 gate resolved against `install-arm64-stage18`, and nothing in the tree
could produce one. That is what trap 35 recorded the hard way.

### What now exists

`tools/bootstrap-iterm2-stage18.sh` — prerequisites → shared cache → seeded roots →
configure/build/stage → capability ladder → artifact gate → launch probe, timed per
phase. It is resumable, does a bounded disk check, installs no host packages, and
works against a **disposable prefix** (`DARLING_STAGE18_ROOT`).

`tools/prepare-macos-shared-cache.sh` — stages a cache from any recent Apple Silicon
Mac (F74) and creates the whole-set arm64 aliases dyld derives (F69), which is the
step that otherwise produces a misleading `shared cache file open() failed`.

### Measured, on a disposable prefix seeded from Stage 10 + the GUI build tree

| phase | time |
|---|---|
| prerequisites | 1 s |
| shared-cache validation | <1 s |
| seed install root + build tree | 3 s |
| **configure + ninja (cold, from the seeded tree)** | **5 m 31 s** |
| stage components + runtime check | 13 s |
| iTerm2 artifact gate + extraction | 1 s |
| launch probe (45 s wait) | 47 s |
| **total, first run from a seeded Stage 0–17 runtime** | **6 m 34 s, measured as one uninterrupted run** |
| total, resumed run (build tree reused) | 75 s |

> **Correction (same day).** An earlier version of this table showed "≈7m40s" —
> a number **stitched together** from the first run's build phase (6m18s, after
> which its staging step failed on the `/etc` symlink defect below) and the later
> phases of the re-runs that followed the fix. A stitched sum is not a measurement.
> The 6m34s above is a single uninterrupted run on a freshly deleted prefix with
> the fixed script (`bootstrap-run5.log`), and it also validates the per-entry
> staging merge on a genuinely clean prefix, which the 41 s re-run could not.
> Incidental result: deleting a used prefix needs sudo — the docker phases write
> root-owned files through the bind mount, and a half-deleted prefix looks
> reusable to the resume check while being corrupt. The script header now warns.

The prefix it produced is a faithful reproduction of the hand-built Stage 18:
capability ladder 12/12, `JavaScriptCore` **45,348,976 bytes** — byte-identical in size
to F70's.

**What this does NOT establish.** The 7m40s starts from an existing Stage 0–17 runtime,
the two container images, and the iTerm2 archive. **A genuinely clean host is not
measured and is not claimed** — and that is the number issue 2 asks for. The script
prints this caveat itself, and refuses to quote its own total against the 30-minute
target when it detects it merely resumed.

**The acceptance criterion it fails.** Issue 2 asks the bootstrap to *"run a short
iTerm2 terminal check"*. It cannot: iTerm2 launches, passes the ladder, reaches its run
loop and emits `MapNotify` ×2 with no uncaught exception, but no terminal is reachable
because the window does not persist (F73). The script says so in its own output and
tells the reader not to read a successful run as Bronze.

### Two defects found in the writing of it, both self-inflicted and both instructive

1. **The staging step aborted on `cp: cannot overwrite directory '/etc' with
   non-directory`.** The install tree ships Darwin-style `etc -> private/etc` and
   `var -> private/var`; a seeded root already has a real `etc` directory, so a plain
   `cp -a src/. dst/` refuses and abandons the entire copy. The merge is now per-entry
   and skips symlinks that would replace a real directory. More importantly the step
   now **verifies the payload landed** rather than trusting `cp`'s exit status, because
   a partial copy can still return 0.

2. **The first version reported `MapNotify events=0` when `iterm2-job.err` was empty.**
   The probe's default wait is 10 s — too short for iTerm2 to write anything — so the
   run published *absence of evidence* in the shape of a measurement. Fixed twice over:
   the wait now defaults to the 45 s the F73 run used, and an empty log is reported as
   "NO APPLICATION LOG CAPTURED", never as a zero. With that corrected the probe shows
   `MapNotify` ×2, reproducing F73 through the bootstrap.

   This is the same failure mode as trap 10 and trap 37: a missing input rendered as a
   clean negative result. It is worth noting it recurred *while writing a script whose
   whole purpose was reproducibility*.

## F77 — the window doesn't "fail to persist"; iTerm2 withdraws and destroys it itself, 1.4 s after mapping, with no session ever spawned ✅

**Method.** F73 ended with: *"capturing `xwininfo` during the wait loop rather than
after it would settle it in one run."* This run does that, without touching the probe:
two observers were attached to the probe's own container via `docker exec` — a live
`xev -root -event substructure` stream (every create/map/unmap/destroy/reparent on the
root window, timestamped per line) and a 2 Hz `xwininfo -root -tree` poller. Flags,
install root and images identical to the F73 runs; the observers are the only new
variable. Harness: `scripts/f77-window-lifecycle.sh`; artifacts:
`artifacts/f77-window-lifecycle/`.

### The complete lifecycle, from the event stream

```
t+2.452  0x80000f created (400x422)                first candidate window, never mapped
t+2.657  0x80002d created (503x136)                alert-shaped, never mapped
t+2.660  0x800031 created (400x422)                THE terminal window
t+2.969  0x200064 created (1x1) = openbox frame; ReparentNotify 0x800031 -> frame
t+2.977  MapNotify                                 visible, 985x377, class ("iTerm2" "iTerm2")
t+4.397  UnmapNotify                               1.42 s later: client withdrawal
t+4.400  ReparentNotify 0x800031 -> root           openbox releases it (XWithdrawWindow sequence)
t+4.402  DestroyNotify frame
t+4.411  0x800055 created (400x422)   -+           two fresh windows created and
t+4.431  0x800059 created (503x136)    | 35 ms     destroyed in one burst --
t+4.433  DestroyNotify 0x800055        |           the alert that never lived
t+4.446  DestroyNotify 0x800059       -+
t+4.448  DestroyNotify 0x800031                    terminal window gone
         ... no further events for the remaining ~70 s; process stays alive
```

The app's own log at the same instant: the window is *fully built* (tab bar, toolbelt,
`PTYTextView`, session fonts) — then `UnmapNotify`, **`NSTextField initWithCoder` ×2**
(a dialog being constructed from a nib), one vibrancy stub, and silence.

**So "the window does not persist" was the wrong frame.** Nothing external unmaps it.
**iTerm2 withdraws and destroys its own window** — the unmap→reparent-to-root→destroy
sequence is the client-side withdrawal protocol — and the alert it builds immediately
afterwards dies within 20 ms, consistent with a sheet whose parent window is already
gone. A refinement to F73's capture note: unmapped iTerm2-class windows *do* persist
in the final tree (`0x80000f`, `0x80002d`); what the gate can never find is a
*visible* one.

### Why it closes: no session ever existed

The probe's end-of-run process table (`processes.txt`) shows the full Darwin tree:

```
 46  darlingserver          122  securityd        131  shellspawn
108  /sbin/launchd          124  iTerm2           133  launchservicesd
120  opendirectoryd         127  cfprefsd         135  iokitd    152  notifyd
```

**iTerm2 has zero children. No shell process ever appears.** A terminal window whose
session never attaches is a zero-session window, and iTerm2 closes those — the 1.4 s
of visible life is iTerm2's own session-startup window, not an X11 defect.

### The prime suspect, stated as a suspect

`iterm2-job.err` contains, interleaved with session setup:

```
libxpc: bootstrap pipe lookup com.apple.system.opendirectoryd.libinfo: 1102   (x8)
```

while **opendirectoryd itself is running** (pid 120, same launchd namespace). The
libinfo pipe is how `getpwuid()` resolves the user record — including `pw_shell`, the
login shell iTerm2 launches. A daemon that is alive but whose lookup port is not
reachable from the app is a bootstrap-namespace wiring question, not a missing
service.

**Not yet proven:** that the libinfo failure is what aborts session launch. The causal
chain has evidence at every link except that one (window closes ← zero sessions ← no
shell child ← *?* ← libinfo lookup fails). Two cheap discriminators, in order:

1. **Check the author's own run logs for the same line.** If their working runs also
   show `libinfo: 1102`, sessions can start despite it and the suspect is innocent.
2. Run a minimal Darwin binary under the same full-launchd environment calling
   `getpwuid(getuid())` and print `pw_shell` — direct test of the resolution path.

### Consequences

- The F73 next-step ("instrument X11Window destruction") is **done and answered** —
  and the answer moves the investigation out of the X11 backend entirely, into
  session launch (fork/exec, PTY, user resolution) under full launchd.
- `-[X11Display orderedWindowNumbers]` / `-[NSView animator]` stubs and
  `sys_proc_info` remain bystanders: present in the log, unchanged by the window's
  fate, exactly as F73's retraction said.

## F78 — the debug-log lever does not fire; the preference propagates, the log never appears 🟠

iTerm2's entire session-failure path logs via `DLog`, a no-op unless debug logging is
on (source: `DebugLogging.h`), which is why stderr says nothing when the window
closes. The advanced setting `startDebugLoggingAutomatically` was seeded as a plain
user preference into the prefix template
(`<install root>/root/private/var/root/Library/Preferences/com.googlecode.iterm2.plist`
— the same directory LaunchServices already populates, and it demonstrably propagates
into the ephemeral per-run prefix). Result: **plist present inside the running prefix,
`debuglog.txt` absent everywhere in the container** (whole-filesystem sweep). Either
the setting needs iTerm2's own start-logging path to flush, or the log lives only in
memory until logging is stopped. Not pursued further because F79 answered the
underlying question without it. Harness: `scripts/f78-session-launch-debug.sh`.

## F79 — photographed: the session dies because `/usr/bin/login` does not exist; with it staged, a live shell prompt persists ✅

**Method.** iTerm2 v3.6.11 source shows the forked child, on exec failure, writes a
plain-text banner INTO THE PTY and then `sleep(1); _exit(1)`
(`iTermPosixTTYReplacements.c`) — which is why F77's window lived 1.42 s. So the
window itself displays the diagnosis. A 4 fps `import` screenshot burst inside the
probe's container photographed it. Harness: `scripts/f79-window-screenshot.sh`.

**Run 1 (control — environment identical to F77 plus the inert F78 plist).** The
window renders correctly — menu bar, tab bar, terminal text — and displays:

```
The program could not be run (execvp failed)
The failing command was:
login -fp root
The reason for the failure was: No such file or directory (errno 2)
```

**Root cause of F73/F77, on screen in iTerm2's own words:** the default profile's
"Login Shell" command is `login -fp root`, and the staged runtime has no
`/usr/bin/login`. The binary IS built (`system_cmds/login.tproj`, PAM-linked, and a
second one in `shell_cmds`) and installs under **component `cli`** — which the Stage
18 staging set (`cli_gui_common core gui stage18 jsc Unspecified`) never includes.
The runtime already ships `libpam.2` and `libbsm.0`, so the binary was the only
missing piece. Kevin's runs presumably never hit this because his root includes the
cli component; "direct PTY mode" only swizzles `runJobsInServers` to NO
(`appkit_bootstrap.m:1047`) and does not touch the command.

**Run 2 (one variable changed: `login` staged into the runtime).** The terminal
window appears and **persists to the end of capture (30+ s, steady), showing a live
shell prompt:**

```
Darling [~] #  █
```

`login -fp root` executed, bash started, prompt painted, session alive,
`status=running`. The F77 "prime suspect" (`opendirectoryd.libinfo` lookup failures)
is **cleared** — those 1102 refusals appear in the working run too; they were noise,
exactly the trap F73's retraction warned about, avoided this time only because the
suspicion was stated as a suspicion and tested before being acted on.

**Chain of evidence, each link one run apart:** F77 (no login): window dies at
1.42 s → F79r1 (F78 plist added, still no login): identical death, banner
photographed → F79r2 (login added): live persistent shell. Screenshots:
`artifacts/f79-run1-no-login/frames/1786546727.40.png` (banner),
`f79-window-screenshot/frames/1786547016.51.png` (prompt).

**Fix required in the tree:** the Stage 18 staging must include `login` (done ad hoc
here by copying from a `--component cli` install; the durable fix is adding the
binary — or the `cli` component — to the bootstrap's staging step).

## F80 — the Silver tabs gate passes: first reproduction of the Silver tier outside its author's machine ✅

With `/usr/bin/login` staged (F79), `verify-iterm2-silver-tabs-arm64.sh` was run
unmodified against the hand-built Stage 18 and the macOS 26.6 cache:

```
iTerm2 Silver tabs passed: independent shells 76 and 82        exit code 0
```

Evidence chain, re-verified by hand rather than trusted from the exit code:
tab 1 shell PID 76 with a typed `printf %s $$` round-trip returning 76; tab 2 opened
via the gate's tab workflow, PID 82, round-trip matching; `shells=2`;
`status=running`; exactly one iTerm2 process in the final process table; **zero**
occurrences of `uncaught exception|segmentation fault|trace/bpt trap` in
`iterm2-job.err` and `darlingserver.err`.

Two environment gaps of ours (F56's class — the image, not Darling, not the gate)
surfaced and were fixed en route:

1. **`scrot` was missing from our GUI test image.** The probe's Silver evidence step
   is `scrot /artifacts/silver-tabs.png || true` — the `|| true` swallows the
   failure, so the first gate run did every behavioural step (both tabs, both
   round-trips) and then failed only on the absent screenshot. Installed into the
   image (previous tag kept as `darling-arm64-gui-test:pre-scrot`).
2. **`rg` was missing from the VM**, and the gate's fatal-diagnostic check is an
   `if rg …; then fail` — with rg absent the condition is simply false, and the
   check **silently skips**. The passing run was therefore validated by running that
   grep manually (clean) before the pass was believed, and ripgrep is now installed
   so the check runs live. Worth an upstream note: a missing tool in an `if <tool>`
   guard converts a verification into a no-op without any error output.

**The other two Silver gates, run immediately after (with rg present, so every
check including the fatal-diagnostic grep ran live):**

```
iTerm2 Silver tab close passed: shell 76 closed; shell 81 survived    exit 0
iTerm2 Silver splits passed:    pane 77 closed;  pane 82 survived     exit 0
```

**The complete Silver tier — tabs, tab-close, splits — reproduces on this machine.**

**Scope of the claim:** one passing run of each gate, on this machine, with a 26.6
cache. The Bronze soak (30-minute recurring workload) has not been run. Nothing here
is a multi-run stability statement.

## F72 addendum — Apple's actual behaviour, measured natively

The F72 fix note asserted "macOS does not throw here" without a recorded test. Now
measured, on this host (macOS 26, Apple AppKit, native arm64):

```objc
NSPopUpButton *b = [[NSPopUpButton alloc] initWithFrame:… pullsDown:YES];
[b setTitle:@"overflow"];   // menu empty — iTerm2's exact call order
// → NO exception; numberOfItems stays 0; title reads back empty
```

So Apple **tolerates and ignores** the call: no throw, no item created, title
dropped. Our fix creates the zero-index item and keeps the title — more generous
than Apple's observed semantics. For iTerm2 the difference is invisible (it never
reads the title back before adding items), but strict fidelity would no-op instead;
flagged to the upstream author as their call.

## F83 — the Bronze soak fails at iteration 20 of ~97: the terminal window vanishes mid-session 🟠

First run of `verify-iterm2-bronze-soak-arm64.sh` on this machine (the strictest
gate: 30 minutes of typed round-trips every ~10 s, alternating window resizes each
iteration, RSS and CPU ceilings, and a clean full shutdown at the end).

**Result: 19 clean iterations, then failure at iteration 20 — 242 s in.**

```
requested_seconds=1800   elapsed_seconds=242   iterations=20
completed=0   failure=foreground-status   session_exited=0
```

Evidence from the artifacts (run 1; several files were later overwritten by run 2 —
see the caveat below — but all of the following was read before that):

- **Cadence:** iterations ran steadily ~11–12 s apart (status files 0001–0019, each
  containing exactly `37` from the typed `/bin/sh -c "exit 37"` round-trip).
- **Memory is not the cause:** RSS grew 4,531,612 → 4,601,000 kB over 19 iterations
  (~70 MB; the gate's ceiling is +512 MB growth, and extrapolation to 97 iterations
  stays under it).
- **The app never crashed:** final state `S (sleeping)`, no fatal diagnostics.
- **Iteration 20 produced no app-side log activity at all.** Iterations 1–19 each
  leave repaint noise in `iterm2-job.err`; the log's last write coincides with
  iteration 19's status file, and nothing follows. The typed keystrokes of iteration
  20 never reached the application.
- **The terminal window is gone at teardown.** The final window list shows only the
  unmapped 503×136 alert-candidate and 12×12 helpers — no terminal window. So
  between iteration 19 and 20, the terminal window disappeared; `xdotool
  getactivewindow` then addressed something else, and the typed command went
  nowhere. `foreground-status` is the harness noticing that, 30 s later.

**What is NOT yet known:** whether the session's shell died with the window (an
F79-class session death mid-soak — but note `login` was present and 19 round-trips
succeeded) or the window closed while the shell lived; and whether iteration ~20 is
deterministic. Run 1's process table was lost to the artifact overwrite before it
was read. A second run is answering the reproducibility question; its result is
recorded below.

### Run 2: the workload passes; the failures move to the edges

The second run (reproducibility check) ran the **full 1800 s: 148 iterations, all
clean** — `completed=1, failure=none, session_exited=1`, 148/148 status files each
exactly `37`, 12/12 clipboard pastes, 148 smaps + 148 stat captures, zero fatal
diagnostics. **Run 1's iteration-20 window-vanish is therefore flaky, not
deterministic** (1 occurrence in 2 runs; the 30-minute workload itself is sound).

The gate still exits 1, on three post-soak checks:

1. **`quit confirmation window not found`** — after the soak, the gate sends the
   quit keystroke and waits for iTerm2's confirm-quit dialog, which never appears.
   Everything downstream cascades from that: `status.txt` stays `running` instead of
   `exit:0`, the prefix shutdown never runs, 20 process dumps remain.
   **Hypothesis (not proven): iTerm2's modal dialog windows never get mapped under
   Darling's X11 AppKit.** Three independent observations now fit it: the F77 alert
   burst (dialog windows created and destroyed in 35 ms), run 1's teardown tree
   (an unmapped 503×136 iTerm2 window), and this missing quit dialog. This is the
   sharpest next frontier this soak exposes.
2. **RSS growth 536,864 KiB vs the 524,288 KiB ceiling — 2.4 % over.** This machine
   ran 148 iterations where the reference machine ran 97 (faster per-iteration
   turnaround); growth is ~3.6 MB *per iteration*, so a fixed ceiling implicitly
   assumes the reference iteration count. Two true statements: the ceiling does not
   scale with iteration count (gate calibration), and **~3.6 MB leaks per soak
   iteration** (a real leak worth hunting; at the author's 97 iterations it stays
   comfortably under the ceiling, which is presumably why it survived upstream).
3. The leftover-mldr check — same cascade as (1).

**Operational caveat (cost a forensic artifact):** the bronze gate does not honour
`ITERM2_PROBE_ARTIFACTS` the way the launch probe does — run 2, launched with an
override pointing elsewhere, wrote into the default directory anyway and clobbered
run 1's remaining artifacts. Read everything you need from a failed soak before
starting the next one.

## F81 — stability: 16/16 gate runs pass, including the never-run seventh gate ✅

Five consecutive runs of each Silver gate plus the first-ever run of the
settings-persistence gate, sequentially on an idle machine
(`scripts/f81-silver-stability.sh`; full per-run logs in `~/darling/f81-stability/`):

```
silver-tabs        5/5   (20-23 s per run)
silver-tab-close   5/5   (31-33 s per run)
silver-splits      5/5   (21 s per run)
settings-persistence 1/1 (84 s) — "passed across processes 238 and 248"
```

Zero flakes in 15 Silver runs. The settings-persistence pass is substantial in its
own right: it opens the real Settings window, mutates a checkbox, **quits iTerm2
through its confirmation dialog**, relaunches a *second* iTerm2 process through the
launchd relaunch job, reopens Settings, and requires the mutated state to be
pixel-identical across processes. Preferences persistence through cfprefsd,
quit/relaunch, and dialog interaction all work — early in a session.

**Which constrains F83's hypothesis and partially retracts it:** modal dialogs do
map and respond — the settings gate's quit-confirm dialog appeared within a minute
of launch and was clicked successfully, five minutes after the soak's quit dialog
failed to appear at the 30-minute mark. So "modal dialogs never map" is wrong as
stated; the honest revision is **"the quit-confirmation dialog fails to appear after
a long session (observed once, after 148 iterations and ~537 MB of RSS growth),
while the identical dialog works in a fresh session."** Late-session degradation —
plausibly connected to the per-iteration leak — not a general modal failure.

## F82 — the profile-dependency matrix: 3 of 6 iTerm2-specific bootstrap behaviours are load-bearing for Silver ✅

The upstream record states the iTerm2-specific bootstrap behaviours "must become
general AppKit/X11 behavior or be removed before the Definition of Done" — a debt
declared but never measured. With Silver passing (F80/F81), the ablation is
meaningful. Method: replicate the silver-tabs gate's exact probe environment, invoke
the probe directly (gates unmodified), flip one flag per run
(`scripts/f82-flag-matrix.sh`; artifacts `~/darling/f82-matrix/`). The control run
reproduced the gate's pass through the harness before any cell was trusted.

| flag ablated | result | failure shape |
|---|---|---|
| — (control) | **PASS** (tab1=76, tab2=81) | — |
| `DISABLE_LOCALE_DISCOVERY` | **FAIL** | window alive (11 iTerm2-class X entries), but no typed round-trip ever lands |
| `DIRECT_PTY` | **FAIL** | no iTerm2 window at capture — the F77 zero-session closure shape; the `runJobsInServers` multiserver path still fails even with `login` present |
| `STABLE_KEYBOARD_SOURCE` | **FAIL** | no iTerm2 window at capture; run also ~2.5× slower (47 s) |
| `OPAQUE_TEXT` | PASS (77/82) | — |
| `DISABLE_METAL` | PASS (76/81) | — |
| `APPKIT_REOPEN` | PASS (76/81) | — |

No uncaught exceptions in any cell — every failure is silent, which matches the
F79/F83 pattern of sessions dying without stderr evidence.

**Scope:** one run per cell. A FAIL names a dependency; a PASS means one run
survived without the flag, nothing stronger. `APPKIT_BOOTSTRAP=0` is deliberately
not a cell (it disables the insertion library and all sub-flags at once);
`PREFER_DISK_FRAMEWORKS=0` is not a cell (trap 37 already established it loads
Apple's AppKit from the cache and dies instantly); `BASIC_KEY_INPUT` is not set by
any Silver gate.

**What this buys upstream:** the generalisation debt now has a priority order.
`OPAQUE_TEXT`, `DISABLE_METAL` and `APPKIT_REOPEN` look removable or
default-able (single-run evidence); `DIRECT_PTY`, `STABLE_KEYBOARD_SOURCE` and
`DISABLE_LOCALE_DISCOVERY` are the three that must become general behaviour — and
each now has a named failure shape to chase.

## F84 — the soak leak is a per-resize leak, proportional to window size; and the quit-chain failure bracketed by short soaks ✅

### Part 1 — the leak's shape, from the full 148-iteration RSS curve

F83 reported ~3.6 MB/iteration from endpoint arithmetic and flagged that a curve
could show steps rather than a slope. The full curve (`soak-smaps-0001..0148`,
extracted to `f84-rss-curve.txt`) settles the shape:

- **147 of 147 deltas are positive. Zero negative, zero flat.** Memory never
  shrinks and never holds — every single iteration leaks.
- **The rate is constant**: 3,771 / 3,650 / 3,570 / 3,616 KiB/iter across the four
  quarters. No acceleration, no saturation.
- **The variance is bimodal and tracks the alternating resize** (even iterations →
  760×500, odd → 900×600):

  | resize step | n | mean leak | median |
  |---|---|---|---|
  | 760×500 | 74 | 2,274 KiB | 2,224 KiB |
  | 900×600 | 73 | 5,049 KiB | 5,032 KiB |

- **A second, smaller leak rides on the every-6th-iteration scroll:** +330 KiB
  against non-scroll iterations *of the same window size* (t≈4.0), once the
  every-12th clipboard-paste iterations are excluded. Small next to the resize
  (~15 % of the smaller step) but real.

**Corrections to my first pass at this data, both found by adversarial review:**

1. **It is NOT proportional to window area, and I should not have said it was.**
   1.42× the area buys 2.22× the leak (implied bytes/pixel: 6.13 at 760×500 vs 9.58
   at 900×600). A pure pixel-area law is ruled out by the two points themselves.
2. **Target size is perfectly confounded with resize direction.** The soak strictly
   alternates, so *every* 900×600 step is a grow and *every* 760×500 step is a
   shrink. **"Growing leaks 5,049 KiB, shrinking leaks 2,274 KiB" fits this data
   exactly as well** — and is arguably the more physical reading. A third,
   non-alternating size would separate them; this run cannot.
3. My first reading called the scroll effect "~130 KiB, noise". That comparison was
   contaminated: every scroll iteration is even, so I compared a subset against a
   group containing it. Properly controlled it is +330 KiB and ~4σ.

**Where to hunt (inference, not measurement):** a per-resize allocation that is
never released — the X11 backing-store / image-buffer path in Darling's AppKit X11
backend is the obvious suspect. The numbers above are the aim, not the proof.

**Consequence for the gate, independent of mechanism:** the soak runs a fixed
1800 s wall-clock loop with a ~10 s inter-iteration sleep, so iteration count scales
with machine speed while the growth ceiling is a fixed 524,288 KiB. This machine did
148 iterations and overflowed by 2.4 %. A faster machine overflows regardless of
Darling's health. The ceiling should scale with iteration count, or the workload
should pin iterations rather than wall-clock.

### Part 2 — the quit-confirmation dialog: two retractions, and what the artifacts actually support

This finding has now been wrong twice, in opposite directions. Both versions are
recorded because the error pattern matters more than either claim.

**Retraction 1 (of F83).** F83 called the missing post-soak quit dialog
"late-session degradation", on the grounds that "the identical dialog works in a
fresh session (settings gate)". That contrast was invalid: I had not checked that
the two gates exercise the same path.

**Retraction 2 (of my correction to F83).** I then asserted the opposite — that the
settings gate "sets `ITERM2_PROBE_QUIT_CONFIRM=0` and never shows a confirmation
dialog at all", and generalised to *modal alerts never stay mapped*. **That is also
wrong, and the artifacts falsify it:**

```
artifacts/stage22-iterm2-settings-persistence/settings-persistence-first-quit.txt
    pid=238   dialog=0x6000df   exited=1
artifacts/stage22-iterm2-settings-persistence/settings-persistence-relaunch-quit.txt
    pid=248   dialog=0x6000b0   exited=1
```

The settings gate **found a 510×126 window twice, clicked it, and the app exited.**
Mechanically: `ITERM2_PROBE_QUIT_CONFIRM` is read at exactly one line of the probe
(`:2043`) and only decides whether the *bronze* path polls for the dialog — it is a
harness switch, not an iTerm2 preference, and setting it to 0 does not suppress any
dialog. The settings gate's own quit path polls for the same `/510x126/` geometry
independently (`:1519`). So the settings gate was never silent on this question; it
was evidence pointing the other way, and I had asserted its meaning without reading
its artifacts.

**What the artifacts actually support, and nothing more:**

| quit path | polls for | result |
|---|---|---|
| bronze soak (`:2047`), `super+q` to the terminal window after the workload | 510×126 | **not found, 5/5 runs**, 89 s to 30 min |
| settings gate (`:1519`), `super+q` to the Settings window | 510×126 | **found, 2/2 quits** (`0x6000df`, `0x6000b0`), clicked, app exited |

The dialog therefore *can* appear under Darling's X11 AppKit. The discriminator is
something about the two paths — which window is activated before `super+q`, and/or
what preceded it — and **is not established**. One of the five bronze failures has a
plain explanation already: run 3 had lost its terminal window at iteration 6, so
`super+q` had no target. The other four do not.

Caveat on the positive evidence: `xwininfo -root -tree` enumerates unmapped windows
too, so the settings artifacts prove the 510×126 window *existed in the tree*, not
that it was painted. That is still fatal to "never stay mapped".

**The trap, stated for the next session:** twice now I have asserted a contrast
between two runs without first verifying they exercise the same code path — and both
times the artifacts needed to check were already on disk. Read the two paths before
claiming a difference between them means anything.

### Part 3 — soak reliability across five runs: three distinct outcomes

Full tally of every Bronze soak run on this machine (two in F83, three here):

| run | duration | outcome |
|---|---|---|
| F83 r1 | 1800 s | **mid-run vanish** at iteration 20 (`foreground-status`) |
| F83 r2 | 1800 s | workload clean, 148 iterations |
| F84 r1 | 300 s | workload clean, 28 iterations |
| F84 r2 | 300 s | **soak never started** — 0 iterations, no summary |
| F84 r3 | 300 s | **mid-run vanish** at iteration 6 (`foreground-status`) |

So the workload completes cleanly in **2 of 5 runs**; a mid-run window vanish occurs
in **2 of 5**, at iterations 20 and 6 — a real intermittent with no fixed trigger
iteration, and not a ceiling on session length (148 iterations succeeded once).

**Run 2 is a third, distinct failure mode**, initially and wrongly written up here as
a harness slip. The gate reported `Missing soak summary`; the archive shows **zero
`soak-status-*` files and an empty RSS curve**, so the soak loop was never entered —
the failure is upstream of the workload, in the pre-soak window/shell setup (the
F77/F79 family). Which specific step failed cannot now be established: run 3
overwrote the shared artifact directory before those files were read. That is F83's
overwrite caveat biting a second time, and the lesson is stronger than first stated —
**archive a failed soak's artifacts before the next run starts, not after.**
`f84-short-soaks.sh` archives four files per run and should archive the whole
directory.

## F85 — resize direction resolved: growing leaks 1.67× more than shrinking *at the same target size* ✅

F84 could not attribute the leak: the Bronze soak alternates exactly two window sizes,
so target size and resize direction are perfectly confounded. F85 breaks the confound
by driving a **three-size cycle** so the same target is reached from both directions,
in one process, under one set of conditions:

```
700x450  ->  900x600  ->  1100x750  ->  900x600  ->  (x12 rounds, 48 resizes)
             ^grown into              ^shrunk into
```

Kevin's gates and probe are unmodified; xdotool is driven from inside the probe's own
container, as the F77 observers were. Harness: `scripts/f85-resize-leak.sh`; samples:
`f85-samples.txt`.

### The decisive comparison

| arrival at **900×600** | n | mean leak | median |
|---|---|---|---|
| by **growing** (from 700×450) | 12 | **5,685 KiB** | 5,570 |
| by **shrinking** (from 1100×750) | 12 | **3,403 KiB** | 3,348 |

**Same target size, same process, 1.67× difference. Direction is a real factor** —
which the soak data could not have shown at any sample size.

### But size matters too, so neither explanation alone was right

| step | n | mean leak | target area |
|---|---|---|---|
| 700×450, shrunk into | 11 | 1,555 KiB | 315 kpx |
| 900×600, shrunk into | 12 | 3,403 KiB | 540 kpx |
| 900×600, grown into | 12 | 5,685 KiB | 540 kpx |
| 1100×750, grown into | 12 | 8,194 KiB | 825 kpx |

Both directions scale with target area, and the marginal cost per pixel is
similar in each (~8.8 KiB per 1000 px growing, ~8.2 shrinking); growing carries an
additional roughly-2 MB penalty on top. **Stated as a model this is unvalidated** —
two points per direction fit a two-parameter line exactly — so the defensible claims
are the ordering and the 1.67× ratio, not the coefficients.

### Every resize leaks; none is free

**47 of 47 deltas positive. Zero negative, zero zero.** Even shrinking to the
smallest size in the cycle leaks 1,555 KiB. Total drift 217,528 KiB across 47
resizes. Consistent with F84's soak numbers (760×500 shrink 2,274; 900×600 grow
5,049) measured through an entirely different driver.

**Reading for whoever fixes it:** each resize allocates a target-area-sized buffer
and never releases the old one; the grow path costs about twice the shrink path per
pixel, suggesting an extra allocation (or a copy) that only the grow path performs.
That is an inference from allocation *behaviour*, not from reading the code.

**Two harness defects on the way here, both mine, both already-known traps:**
run 1 produced 48 perfect resizes and 48 *empty* RSS samples (over-escaped `$pid`
inside an already-single-quoted block); the fix then introduced an apostrophe — in a
*comment* — into that same block, which is STATE.md trap 12 for the fourth time and
truncated the script. Worse, `bash -n script && echo OK` and the copy-to-VM were on
separate lines, so a failed syntax check did not stop the push. The check must gate
the push.

## F86 — the quit dialog is path-dependent, not duration-dependent: settled ✅

F84 left the bronze-vs-settings quit difference explicitly unexplained and named the
one variable that separates the two families of explanation: **duration**. The
shortest bronze soak run with a live window had been 300 s / 28 iterations. F86 runs
the unmodified gate at its documented `ITERM2_SOAK_SECONDS=30` knob, three times
(`scripts/f86-quit-discriminator.sh`):

```
run 1: 3 iterations, failure=none            -> quit confirmation window not found
run 2: 0 iterations, failure=application-exited (discarded: no window at quit)
run 3: 3 iterations, failure=none            -> quit confirmation window not found
```

**Usable runs 2/3; dialog found in 0/2.** At 30 seconds and 3 iterations, with a
live window and a clean workload, the dialog is still absent.

**Conclusion: duration and iteration count are not the variable.** The failure
tracks the *path* — `super+q` sent to the terminal window (bronze, 0 finds across
every run at every duration) versus to the Settings window (settings gate, 2/2
finds). This closes out F83's original "late-session degradation" idea for good,
independently of the reasoning error that first retracted it.

**Still not established:** *why* the two paths differ. Candidates not yet tested —
which window holds focus when `super+q` is delivered; whether iTerm2 suppresses the
confirmation when its only session is the soak shell; whether the dialog is posted
but as a sheet attached to a window the poller does not enumerate. Naming candidates
is not evidence for any of them.

### Bronze soak reliability, all eight runs to date

| outcome | n |
|---|---|
| workload completed clean | 4 (148, 28, 3, 3 iterations) |
| mid-run window vanish (`foreground-status`) | 2 (iterations 20 and 6) |
| launch-stage failure (soak never entered) | 1 |
| `application-exited` during soak | 1 |
| **quit dialog found** | **0 of 7 runs that reached the quit stage** |

The `application-exited` mode is new here and is a fifth distinct outcome; with one
occurrence it is recorded, not characterised.

## F87 — 20 broken symlinks and a corrected LFS-pointer count in the staged runtime 🟠

Both were reported to the funder before being recorded here; recording them now with
their reproduction commands, and correcting one of the numbers.

**20 dangling symlinks** in the Stage 18 runtime — verified:

```sh
find "$DARLING_ARM64_INSTALL_ROOT/root" -xtype l | wc -l     # -> 20
```

They are `libkrb5.dylib`, `libcom_err.dylib`, `libdes425.dylib`, `libkrb5support.dylib`,
`libkrb4.dylib`, `libk5crypto.dylib` and several `sasl2` modules
(`libgssapiv2.2.so`, `libcrammd5.2.so`, …). Each points at nothing, so a loader
resolving one gets ENOENT at the end of a symlink chain rather than a clean absence.

**Correction to F71's "43 of 275".** That figure mixed a Stage 10 numerator with a
denominator that counted symlinks as well as files. Counted consistently — regular
files only, content checked for the `version https://git-lfs` header rather than
inferred from size:

| runtime | dylib **files** | Git-LFS pointer files |
|---|---|---|
| Stage 10 | 204 | **43** |
| Stage 18 | 209 | **39** |

So F71's 43 was right for Stage 10 and its 275 was the wrong denominator. The
Stage 18 runtime — the one the iTerm2 gates actually use — is **39 of 209**.

```sh
while IFS= read -r f; do
  head -c 40 "$f" | grep -q "^version https://git-lfs" && echo "$f"
done < <(find "$ROOT" -name '*.dylib' -type f) | wc -l
```

The size heuristic that produced the original figure (`-size -600c`) is not reliable
here: it matches 105 files in Stage 18, most of which are small real libraries.

## F88 — overnight driver: stability at n=15, four more soak vanishes, the quit dialog is never created, and a two-factor leak model ✅

One driver (`scripts/f88-overnight.sh`), six phases, serial, whole-dir archiving;
artifacts `~/darling/f88-overnight/`. Baseline control green before anything ran.

**B — Silver stability at n=15 each:** tabs **13/15**, tab-close **11/15**, splits
**13/15**, settings-persistence 1/1. The n=5 "zero flakes" statement (F81) does not
survive a larger sample; the gates are ~82 % reliable here per run.

**C — four more 30-minute soaks: all four died of the mid-run window vanish**
(`foreground-status` at iterations 68, 10, 145, 22). Cumulative soak record, twelve
runs: workload clean 4 (148, 28, 3, 3 iterations), mid-run vanish 6 (@20 @6 @68 @10
@145 @22), launch-stage failure 1, application-exited 1. The vanish is the dominant
long-run failure mode; iteration numbers show no fixed trigger.

**D — quit-dialog mechanism, settled at the creation level.** With a live window and
a clean 3-iteration workload (summary: `completed=1 failure=none` — the observation
is valid), `xev -root -event substructure` recorded **zero 510×126 window creations**
on the bronze quit path. Combined with the settings path creating it 2/2: **iTerm2
never posts the confirmation dialog when `super+q` is delivered to the terminal
window in this configuration.** Not timing, not mapping. Why it declines to post it
remains open.

**E — leak model validated on independent data.** 16 mixed-magnitude resizes over 5
sizes (non-alternating), fit host-side:

```
leak ≈ 8.94 KiB/kpx (target area) + 8.40 KiB/kpx (grow magnitude) − 1.39 MB    R²=0.943
```

Single-factor models reach only R²≈0.90 each; both factors carry near-equal weight.
Supersedes F85's "ordering and ratio only" caveat with a validated two-factor form —
consistent with roughly one stranded buffer of the target size per resize plus one
proportional to the grown region.

## F90 — the Silver flake, captured with artifacts: it is the zero-session family 🟠

Failure-driven capture (`scripts/f90-flake-capture.sh`): tab-close ×15 with per-run
whole-dir archiving; **14/15 passed, 1 failure captured** ("Missing Silver tab-close
evidence: silver-tab1-pid.txt"). The archive classifies it: **zero iTerm2-class
windows in the tree at capture, zero children, no exception, `status=running`,
app log ending at `MapNotify/FocusIn` + one libinfo line** — the F77/F79 signature
exactly. So even with `login` staged, a session intermittently never spawns
(~7–27 % of runs across tonight's samples) and the zero-session window closes.
Whether this shares a root with the mid-soak vanish (which strikes after many
*successful* round-trips) is not established. Combined Silver tally to date:
tabs 20/22, tab-close 17/21 (incl. this capture run 14/15), splits 19/21.

## F91 — the 110-commit gap, merged and measured: HIS TAIL REGRESSES UNMODIFIED iTERM2 🟠

The proper merge (submodule-level first) was clean everywhere the driver's naive
attempt conflicted: cocotron `2fa0bef93 + 2cb336aec → 2a1751dce` (clean), foundation
`→ 966ed8840` (clean), superproject `→ 4c3e8f83a` on local branch
`north-star/gap-integration`, with our idempotent-apt hunk re-applied to
`verify-text-view` after taking theirs.

Built via the bootstrap into **separate roots** (`build-arm64-gap`,
`install-arm64-gap`) — the reviewed runtime untouched. Ladder on the merged tree:
**12/12**. Then the launch probe:

```
*** Terminating app due to uncaught exception 'NSInvalidArgumentException',
reason: '-setAlphaValue: only defined for abstract class.
         Define -[X11Window setAlphaValue:] in .../CoreGraphics/CGWindow.m:86!'
```

`verify-iterm2-silver-tabs` on the merged tree: **rc=1, "Fatal application
diagnostic found in probe output"** (the gate's rg check working as designed).

Attribution so far: cocotron is unchanged between the two pointers for
`setAlphaValue` (no implementation either side; same caller files; zero
alpha-related line changes in NSWindow.m/NSView.m), and the four leak-path files are
untouched — so the trigger sits in his superproject-side changes (110 commits,
Jul 14–16; his libappkit_bootstrap diff moves NSImageSymbolConfiguration out, probe
gained ~10 commits) and is **not yet located**. His record shows no iTerm2 gate runs
after Jul 14 — the regression is consistent with his final two CotEditor-focused
days never re-running the iTerm2 tier. **Per the fully-green rule the gap branch is
NOT pushed.**

## F92 — (experiment ID) the leak-fix A/B/A validation — written up under F89 ✅

Tombstone so the numbering is self-explaining: F92 was the A/B/A run itself
(baseline 4,768 → patched 419 → revert 4,767 KiB/resize). Its write-up lives in
F89; harness `tools/f92-leak-aba.sh`, artifacts `f92-{A,B,Aprime}.txt`.

## F93 — the NSPopUpButton delta, answered: it was the emulated OS version, and it is a corpus-wide hidden variable ✅

Our one ask to Kevin is withdrawn — we answered it from his own record
(`kevin-record/NSPOPUPBUTTON-MEMO.md`, full citations).

**Mechanism.** His cocotron never guarded `-[NSPopUpButton setTitle:]`: the file is
byte-identical between his Jul 13 pin, our fork-base pin, and his head. The crash
line simply never ran for him. iTerm2 3.6.11's `-[PSMTabBarControl setupButtons]`
forks on `@available(macOS 26, *)`: the Tahoe branch builds a plain `NSButton`
overflow control and returns *before* the `PSMOverflowPopUpButton` line whose
unconditional `setTitle:` detonates the cocotron defect. His Stage 18 is configured
with **`-DDARLING_EMULATED_OS_PRODUCT_VERSION=26.5`** (his record, Jul 12, alongside
his `_availability_version_check` fix); ours carries the default — verified directly:
`build-arm64-stage18/CMakeCache.txt` reads
`DARLING_EMULATED_OS_PRODUCT_VERSION:STRING=12.4` — so our iTerm2 took the legacy
branch.

**Consequences, stated plainly:**
1. F72's guard remains a real fix — any Darling reporting a pre-26 version hits it.
2. **Every `@available` in every app is a hidden fork between his environment and
   ours.** Our Silver passes exercised iTerm2's *legacy* tab path; his exercised
   Tahoe. Same gates, same binary, partially different app code paths.
3. The bronze quit-dialog difference and the intermittent session-spawn flake are
   now *candidates* for version-gated behaviour — hypothesis only, one experiment
   away (rebuild with 26.5 identity, re-run the tier).
4. Eliminated by evidence: a cocotron guard on his side; bootstrap interception;
   preference routing.

## F89 — the resize leak: two-line fix, validated by full ABA ✅

The localization (`kevin-record/LEAK-LOCALIZATION.md`) named two sites: the
`O2Surface` retained by `-[O2BitmapContext initWithSurface:flipped:]` but never
released by its caller `-[X11Window createCGContextIfNeeded]` (stranded on every
resize, because `-[O2Context resizeWithNewSize:]` unconditionally returns NO and the
context is rebuilt per ConfigureNotify), and the shadow surface in
`-[O2Context_builtin endTransparencyLayer]` never freed. Two one-line `release`
hunks. Full ABA on the reviewed tree (`scripts/f92-leak-aba.sh`, cocotron branch
`f89-leak-fix`; per-arm samples archived):

| arm | mean Δ/resize | positive | 900×600 grown-into | 900×600 shrunk-into |
|---|---|---|---|---|
| A — baseline | 4,768 KiB | 47/47 | 5,679 | +3,403 |
| **B — patched** | **419 KiB** | 24/47 | 3,208 | **−3,060** |
| A′ — reverted | 4,767 KiB | 47/47 | 5,675 | +3,398 |

- Baseline reproduces F85's original numbers to within 6 KiB (5,685/3,403 then;
  5,679/3,403 now) — the instrument is stable.
- **The patch removes 91 % of mean per-resize growth**, and shrink-arrivals now
  *release* memory — the remaining pattern is alloc-on-grow / free-on-shrink,
  i.e. a backing store correctly tracking window size rather than a monotonic leak.
- **Revert restores the pathology exactly** — the full ABA closes; per trap 9 this
  earns "candidate fix", not merely "localized".
- No regression: patched ladder 12/12, text-view pass, Silver tabs/tab-close/splits
  all pass. (Post-revert control: ladder pass; one silver-tabs flake at the known
  ~18 % rate, consistent with F88/F90.)
- Residual: mean +419 KiB per resize under the mixed cycle — direction-balanced but
  not zero; a long soak on the patched build is the follow-up that would
  characterize it (and would likely put Kevin's own +44,020 KiB / 12-interaction
  Bronze numbers, and his 512 MB ceiling, comfortably in the green).
- Branch `f89-leak-fix`; **upstream PR darlinghq/darling-cocotron#70** (open).

## F94 — a cold host cannot clone the repository at all: every submodule URL is broken as shipped 🟠

Measured on a genuinely fresh VM (`darling-cold`, Ubuntu 24.04 + docker + git,
nothing else): `git clone --recurse-submodules` of
`deepai-org/darling-aarch64-north-star` fails for **100 % of submodules**.

Mechanism, verified URL by URL: `.gitmodules` uses relative URLs
(`../darling-cocotron.git`, `../darling-AvailabilityVersions.git`, …) which resolve
against the superproject's org — `deepai-org/darling-X`. But the org's six actual
forks are named `darling-aarch64-X` (verified: `deepai-org/darling-cocotron` → 404,
`deepai-org/darling-aarch64-cocotron` = our push target), and the other ~143
submodules exist only under `darlinghq`. **No vanilla contributor can pass step
zero — including the author, who has evidently never cold-cloned his own repo.**
This is the sharpest possible evidence for his issue 2 ("reproducible one-command
ARM64 developer bootstrap"): the failure is at `git clone`, minutes before any
tooling this project has built or measured.

The full depth, learned across three failed clone attempts: the org actually holds
**35 renamed forks** (not six), with names case-folded and underscore-normalized in
ways `.gitmodules` cannot predict (`IOKitUser` → `darling-aarch64-iokituser`,
`bootstrap_cmds` → `darling-aarch64-bootstrap-cmds`), several pinned to commits
that exist nowhere else (IOKitUser `4157959` is one of his own Stage 10 pins); the
remaining ~114 submodules resolve only at `darlinghq`, including names with no
`darling-` prefix at all (`cctools-port`). The working rewrite table — two identity
pins, 35 exact fork mappings generated mechanically from a working tree's remotes,
and two broad fallbacks — is scripted in `scripts/f91-cold-host.sh` phase 0a. **A
new contributor could not construct this table without an already-working checkout
to copy it from.** The durable upstream fix is absolute URLs in `.gitmodules`.

A seventh and final defect, found once every URL was fixed: **his default branch
(`community-integration`) pins a dyld commit (`6e6c5084…`) that exists on no public
ref of the dyld fork** — the author's own current tree is un-fetchable by anyone,
himself included from a fresh machine. (Our reviewed branch's pins are all
live-reachable — verified with fresh fetches — so the cold run clones it directly.)

The cold-host timing (F91's purpose) therefore measures "cold host + documented
workarounds + the reviewed branch", and will say so wherever it is quoted. Also
noted: the repositories are private, so a contributor needs credentials before step
zero even begins. Six failed attempts, each one layer deeper — auth, relative URLs,
unprefixed names, renamed forks, shallow-vs-pins, an unpublished pin — are
themselves the measured answer to issue 2's question.

**And the author's own one-command path (`bootstrap-stable.sh`) cannot complete on
a cold host either**, at three independent layers, measured: (1) it clones
`community-integration --single-branch`, whose dyld pin is unpublished; (2) its
submodule configuration single-branches submodules, missing pins that are reachable
only from other branches (configd `4d1bafa6` — present on the fork, absent from the
fetched branch — killed it at 1,194 s twice); (3) it hard-requires an authenticated
GitHub CLI, undocumented. An eighth layer ended the exercise: run directly, his `build-headless.sh` fails in
37 s linking against `/usr/lib/system/libsystem_sandbox.dylib` — his build scripts
assume environment preparation that only his (uncompletable) bootstrap performs,
and that preparation is nowhere documented. **The cold-host exercise is parked
here, its verdict complete without a grand total: no path — his or ours — reaches
a build on a cold host today.** The two hard numbers it banked: reviewed-branch
recursive clone **29m00s** (issue 2's entire 30-minute budget consumed before the
first compile), and container images 197 s. The gap between "works in the author's
workspace" and "works from nothing" is the finding; closing it is upstream work
(absolute submodule URLs, published pins, documented prerequisites, environment
prep in the build scripts themselves), not measurement work.

## F95 — (experiment ID) the 26.5-identity run — written up under F96 ✅

Tombstone: F95 was the experiment that rebuilt with Kevin's `26.5` identity;
its result (the fork base dies at `setHasDestructiveAction:`) is the substance
of F96. Harness `tools/f95-identity-26.sh`, roots `*-id26`.

## F96 — the 26.5 identity does not "match his world": our fork base cannot run iTerm2's Tahoe path ✅

F93 predicted that `DARLING_EMULATED_OS_PRODUCT_VERSION` forks every `@available`.
F95 tests it directly: the reviewed tree + f89 leak fix, rebuilt with
`-DDARLING_EMULATED_OS_PRODUCT_VERSION=26.5` (matching Kevin), isolated roots,
`install-arm64-id26`.

Result: **ladder 12/12, but every iTerm2 gate fails — Silver 0/3 tabs, 0/3
tab-close, 0/3 splits, leak cycle 0 samples, soak never establishes a window.**
Mechanism, from the gate's own log:

```
*** Terminating app due to uncaught exception 'NSInvalidArgumentException',
    reason: '-[NSButton setHasDestructiveAction:]: unrecognized selector ...'
```

On 26.5, iTerm2's `-[PSMTabBarControl setupButtons]` takes the Tahoe branch (F93)
and builds `PSMTahoeOverflowButton`, which sends `setHasDestructiveAction:` — a
macOS-26-era `NSButton` method **our cocotron fork base does not implement**. That
support is exactly the Tahoe/AppKit work Kevin did *after* our 2026-07-14 fork base.

**What this settles, and it is significant rather than a downgrade:**
- Our Silver reproduction is valid, but specifically on iTerm2's **12.4 legacy
  path**. It was never on the Tahoe path Kevin's environment uses.
- Flipping identity to 26.5 is **not** a free "match his world" switch, and must
  NOT be a bootstrap default — it makes our tree fail iTerm2 outright. (A2 dropped.)
- The two trees are complementary: **ours** runs the legacy path but lacks Tahoe
  AppKit (`setHasDestructiveAction:`); **his tail** has Tahoe AppKit but regresses
  the `setAlphaValue` path (F91). Reaching the Tahoe path with a working iTerm2
  needs *his* post-fork AppKit — which is what the gap integration (F97) tests.
- The ~87% Silver flake and the soak vanishes (F88/F90) are therefore properties of
  the 12.4 legacy path; whether Kevin's 26.5 Tahoe path is more or less reliable is
  a question only answerable on a tree that has both his AppKit support and a fixed
  `setAlphaValue` — i.e. after F97.

## F97 — a ~15-line backend override restores unmodified iTerm2 LAUNCH on Kevin's own Jul 14–16 tail ✅

F91 found that the merged tail dies at launch: `-[X11Window setAlphaValue:] only
defined for abstract class`. Root cause (F97): `CGWindow.m` declares
`setAlphaValue:`/`setOpaque:`/`setHasShadow:` abstract; the X11 backend overrides
`setOpaque:` and `setHasShadow:` but **never overrode `setAlphaValue:`** — a latent
gap that any caller trips. The callers (`NSView.m`, `NSWindow.m`) are byte-identical
across the gap, so his tail did not add one; its bootstrap/foundation changes make
iTerm2's launch reach an existing caller that the reviewed tree's launch does not.

**The fix** (`scripts/patch-f97-setalphavalue.py`): implement `setAlphaValue:` as a
real backend method setting the EWMH `_NET_WM_WINDOW_OPACITY` CARDINAL — the standard
per-window opacity property, ignored harmlessly by a non-compositing WM. ~15 lines,
beside the sibling `setOpaque:` (X11Window.m:512).

**Result, on the merged tree in isolated `-gap` roots:**

| | before fix (F91) | after fix (F97) |
|---|---|---|
| launch probe | dies at `setAlphaValue`, no window | **no exception; iTerm2 runs, 11 windows in the tree, MapNotify events** |
| silver-tabs | rc=1 (fatal diagnostic = the crash) | rc=1, but now at the *session-spawn* boundary (`silver-tab1-pid.txt` missing) |

**So the launch-blocking crash is definitively removed** — his newest tree runs
unmodified iTerm2 again. It does not yet pass Silver: it stops at the same
zero-session boundary seen intermittently on the reviewed tree (F90), plus a
non-fatal `X_ConfigureWindow`/BadValue on the Tahoe construction path. The remaining
gap is session-spawn, shared with our tree — not a new wall.

**The fix is a correct standalone abstract-method override, valuable regardless of
Kevin's tree.** Pushed to his cocotron fork as `fix/x11-setalphavalue` (`14b76d42`);
upstream **PR darlinghq/darling-cocotron#71** (open). The superproject
`gap-integration` branch stays held (not fully green — session-spawn open).

## F98 — the Silver flake is not one bug: two distinct modes, both in darlingserver's early thread/semaphore init 🟠

The intermittent Silver flake (F90) and the merged tree's Silver block (F97) share
one gate symptom — `silver-tab1-pid.txt` missing, "session never spawns." F98
captured a pass and a fail with darlingserver debug logging
(`ITERM2_PROBE_LIFECYCLE_DEBUG=1`, `scripts/f98-session-spawn.sh`) and diffed them.
It is not a single failure:

**Mode A — early hang, no window (this capture, FAIL run 5).** iTerm2 *execs*
successfully (`execve … iTerm2 … ret 0`) but then produces **zero log output**, maps
**no window**, `status=running` — it is hung before the AppKit bootstrap prints its
first line. darlingserver's tail shows it stalled at
`dserver_callnum_semaphore_timedwait` (×18) right after a
`proc_get_effective_thread_policy: unimplemented` stub. Thread/microthread activity
collapses versus a passing run (88,826 → 4,691 thread ops; 1,612 → 29 microthreads):
the process does almost nothing because it is blocked in early init.

**Mode B — window built, session never spawns (F90 run 4).** 147 lines of app log,
window and `PTYTextView` constructed, then no shell — the *late* boundary. A
different failure with the same gate result.

**Controlled away (trap 9):** the `pthread_canceled → EINVAL(-22)` spam that looked
suspicious is a **red herring** — the passing run has *far more* of it (76,482 calls,
38,241 EINVAL) than the failing run (3,512 / 1,756). It is normal traffic; the lower
count in a fail just reflects the process doing less before it stalls.

**Mode A is a livelock, not a clean hang.** The failing run's darlingserver log
spans the full 34-second window (10,316 lines) in a repetitive
`semaphore_timedwait` ↔ `mach_msg_overwrite` loop: a thread waits on a semaphore
that never signals, times out, does a mach message, and waits again — no forward
progress for the whole window, so the app's init thread never proceeds and never
logs.

**Two red herrings controlled away (trap 9).** Both `pthread_canceled → EINVAL`
(FAIL 3,512 / PASS 76,482) and the `proc_get_effective_thread_policy: unimplemented`
stub (FAIL 10 / PASS 813) appear *far more* in passing runs — neither is the
discriminator; they are normal traffic that a fail simply does less of before it
livelocks.

**Localization for upstream:** the flake is a **darlingserver-level concurrency race
in the semaphore / mach-message emulation**, not iTerm2 or AppKit logic — which is
why every app-side hypothesis failed. The signature is a thread livelocked in
`semaphore_timedwait`/`mach_msg_overwrite` during early startup (Mode A) or an
analogous stall at session-launch (Mode B). Not fixed here — a subtle IPC race is
not a two-hour fix — but now pointed at the right subsystem, with a captured
pass/fail pair and two eliminated suspects to start from.

## F99 — the flake sharpened (two modes), and the merged tail passes Silver tabs ✅🟠

Higher-resolution capture (`scripts/f99-race-capture.sh`, darlingserver debug on)
plus a merged-tree retest (`d1-run*`) refine F98 in two ways.

### The flake is heterogeneous — and Mode B is dominant
Of 3 fails captured this round, **all 3 were Mode B** (F98's Mode A, the early
livelock, is the rarer one):

- **Mode A (rare):** iTerm2 execs, then livelocks before any output — no window, no
  shell, empty app log; darlingserver spins `semaphore_timedwait ↔ mach_msg_overwrite`.
- **Mode B (dominant):** iTerm2 builds the window and reaches text layout (250+ app-log
  lines); a shell **does** exec (6 shell/login `execve` in the fail, same as a pass);
  tab 1's PID is even written — then **the window vanishes mid-gate** (0 iTerm2 windows
  in the tree at capture, while a shell lingers). This is the same client
  self-withdrawal as the soak mid-run vanish (F77/F83), *not* a failed session spawn.

So "session never spawns" (F79/F90 framing) was imprecise: the session usually *does*
spawn; the window withdraws under it. Both modes are darlingserver/X11 timing races,
not iTerm2 logic — confirming why every app-side hypothesis failed.

### The merged tail (his Jul 14–16 + our setAlphaValue fix) passes Silver tabs
Retesting the F97 merged tree (isolated `-gap` roots; cocotron `13816c5f5`) through
`verify-iterm2-silver-tabs`: **1 of 4 passed** — *"iTerm2 Silver tabs passed:
independent shells 77 and 82."* The 3 fails were the same two flake modes (1 B, 2 A).

**So the F97 result upgrades:** his newest tree doesn't merely launch with our fix —
**it passes Silver tabs**, gated only by the same darlingserver flake that caps our
reviewed tree, not by anything in his code. His tail + our two fixes = a working
Silver-passing iTerm2 (on the 12.4 legacy path, flake-limited).

### F99 (cont.) — source localization: it is a psynch startup race, NOT the semaphore loop (a red herring caught by adversarial review)

A 4-agent deep-read of darlingserver's kernel-emulation (`localize-darlingserver-race`
workflow) plus a discriminator run localized the flake — and the adversarial synthesis
**overturned its own readers**, which is the load-bearing part.

**The `semaphore_timedwait ↔ mach_msg_overwrite` loop is a red herring.** Three readers
independently concluded it was a lost-wakeup livelock in the duct-tape semaphore path.
The discriminator refutes that: the loop appears **more** in a *passing* run (1,658
`semaphore_timedwait`) than in the fails (~1,050–1,076) — it is **memberd's benign 5 s
idle poll**, present whether or not the gate passes. The readers anchored on the
last-logging daemon and mis-attributed causality — precisely the "credit a signal
without controlling it" trap (trap 9). Writing that up as the root cause, which we were
one step from doing, would have been a false finding.

**The real cause: an intermittent iTerm2 pthread/psynch (libdispatch mutex) startup
race.** In the captured fails, `psynch` traffic is heavy (200–356 calls;
100 `psynch_mutexwait` / 100 `psynch_mutexdrop` in FAIL1), and **2 of 3 fails show
"process dying"** in `dserver.log` — a crash component, not a pure hang. Fix locus,
per the synthesis: `duct-tape/pthread/kern_synch.c` (psynch ownership/wake atomicity,
~lines 1949–1991). A **real secondary hazard** the readers did find and is worth
hardening regardless: the `Thread::resume()` / `_suspended` TOCTOU
(`src/thread.cpp:655–666`) — a wake dropped when it lands before the waiter parks —
sitting under the author's own comment *"maybe we should throw an error here?"*
(`thread.cpp:660`).

**Not fixed here, deliberately.** This is a core pthread-emulation concurrency bug;
a correct fix needs the psynch ownership/wake path made atomic and an A/B/A over
≥200 spawns to prove the ~15% rate drops to ~0 (one variable, revert to confirm). That
is careful upstream work, not a one-night patch on the layer every Darling process
depends on. What this engagement delivers is the **precise localization with a
validation plan and a controlled-out red herring** — a filable bug report, which is
the honest and more useful hand-off. Discriminator commands are in the synthesis;
captures at `~/darling/f99-race-capture/`.

## F100 — the session-spawn flake re-diagnosed: a reliable repro + three falsified mechanisms (corrects F99); root cause still open 🟠

This stretch built a **reliable repro** for the ~13% Silver session-spawn flake
(F90/F98/F99) and used it as a powered A/B/A to test the leading hypotheses. Three were
**falsified by controlled experiment.** The earlier F99 framing — "an intermittent
darlingserver race with a 2/3 crash (process-dying) component, localized to a psynch
startup race in `kern_synch.c`" — does not survive; the correction is the finding.

**The reliable repro (the key new asset).** The flake is **timing/scheduling-sensitive**.
On the reviewed-class runtime it fails ~1–2% of spawns normally, but with
`DSERVER_LOG_LEVEL=debug` (heavy per-event logging that reorders cooperative microthread
scheduling) it fails **13/14 ≈ 93%** (95% Wilson CI [69%, 99%], `f100-gate-aba.sh` on
`install-arm64-id26`). That turns a rare flake into an on-demand one — the handle any
future fix needs. It also directly evidences the bug class: a lost wake whose occurrence
depends on event ordering.

**Falsified with controls:**
1. **Cross-thread psynch data race — UNREACHABLE.** `DSERVER_SINGLE_THREADED:BOOL=ON` in
   every build root (verified): one OS worker runs all duct-tape microthreads
   cooperatively, no preemption. An 8-agent adversarial workflow's own first candidate (a
   `kw_lock` wrap of `dtape_psynch_thread_dying`) was refuted by its adversarial phase
   before any build — it targets a race that cannot occur in the shipped build and would
   have added a reentrant-spinlock deadlock (`_psynch_mutexwait:782` holds `kw_lock` across
   `thread_deallocate_safe`).
2. **"Crash / process-dying" (F99) — CAUSALITY-INVERTED.** Zero duct-tape panics / zero
   `removing item from empty/wrong queue` / zero prepost-guard trips in any captured fail
   (STEP-0 grep, f99 FAIL1/2/3). A real double-remove would `panic()` = `printf();abort()`
   and kill the **whole** darlingserver (iTerm2 included) — impossible for an intermittent
   single-session failure where iTerm2 survives ~85% and retries. The "process-dying" is
   the fork-failure teardown that *calls* `dtape_psynch_thread_dying` (the trigger), not a
   crash it causes.
3. **psynch `kw_intr` stranded-grant lost-wake — NOT FIRING.** Additive instrumentation
   (`dtape_log_error` at the `KERN_NOT_WAITING` mint :609-612, the `is_seqlower_eq` claim
   gate :512, and the dying hook): across 60+ passing runs **and** the debug-induced fails,
   the mint fired **0 times**; the dying hook fired ~26×/run but always benignly
   (`kwe_kwqqueue == NULL` = normal completion). The stranded-grant mechanism the source
   analysis proposed does not occur on the failures.
4. **Host-side `resume()`/`_suspended` check-then-act lost-wake — NO EFFECT.** A standard
   pending-wake latch (host-side only: `thread.hpp` + `Thread::resume()`/`suspend()`,
   `_resumePending`) built cleanly and ran the A/B/A: **baseline 13/14 (93%) → patched
   13/14 (93%)**, identical, no new failure modes. The latch changed nothing; reverted.

**Established:** the failure is a session-spawn mutex/wait that never completes (the login
`-sh` fork for tab1 or tab2 never appears — `silver-tab{1,2}-pid.txt` missing), balanced
psynch traffic (34/34), no crash, no panic. It is a **timing-sensitive lost wake** whose
specific locus is **not** any of the three mechanisms above.

**Open (honest):** the true cause remains unidentified after three controlled
falsifications. It is now reproducible on demand (debug-amplified ~93%), so the next
attempt starts from a powered repro and a narrowed field — the fork/`posix_spawn` →
session-startup wait path, not the psynch mint or the resume latch.

**Method note:** the adversarial workflow (`wf_225d4999-fb3`) corrected its own synthesized
patch; every hypothesis was killed by a control or an A/B/A, never by assertion — the same
discipline that caught the memberd red herring. No fix is claimed because none validated.

Harnesses (all on the branch): `f100-spawn-probe.sh`, `f100-instr-batch.sh`,
`f100-gate-aba.sh`, `instrument-psynch.py`, `fix-resume-latch.py`; captures under
`~/darling/f100-runs/`, `~/darling/f100-instr/`, `~/darling/f100-gate-aba/`,
`~/darling/f100-gate-id26/`.

## F101 — the flake's first mechanism FOUND and FIXED: dtape `thread_unblock` drops XNU's wait-timer cancel (mode A closed; a second bug, mode B, unmasked) ✅🟠

**The mechanism, core-dump grade.** With core dumps enabled in the probe container
(`--ulimit core=-1` + `core_pattern` into the artifact mount — zero runtime
perturbation, unlike strace which suppressed the crash entirely), the crashing
iTerm2's own core yielded the original signal frame that sigexc's re-raise normally
destroys (the handler's logged pointers `sigexc_handler(5, siginfo, ucontext)` still
point at live stack memory in the core):

- original **si_code = TRAP_BRKPT** (a self-executed arm64 `brk`; external-kill
  hypothesis dead), **PC = `_dispatch_mach_send_and_wait_for_reply+0x5c4`** in
  Darling's libdispatch, **x0 = 0x10004003 = MACH_RCV_TIMED_OUT**, caller frames
  libxpc → CF (a synchronous XPC round-trip to cfprefsd).
- libdispatch's reply-port receive is **untimed** (`mach.c:812`,
  `MACH_MSG_TIMEOUT_NONE`); `MACH_RCV_TIMED_OUT` is impossible-by-contract and hits
  `DISPATCH_INTERNAL_CRASH(kr, "Unexpected error from mach_msg_receive")`
  (`mach.c:866`). libdispatch is behaving correctly; the kernel emulation lied.

**The defect (one omission).** dtape reimplements `thread_unblock`
(`duct-tape/src/thread.c:608`) as 5 lines — and omits the wait-timer cancel block
that XNU's `thread_unblock` performs (`osfmk/kern/sched_prim.c:631-635`). Any *timed*
wait that completes normally therefore leaves `thread->wait_timer` armed with
`wait_timer_is_set = TRUE`; the stale timer later fires while the thread sits in an
unrelated **untimed** wait; `thread_timer_expire`'s handshake passes and delivers a
spurious `THREAD_TIMED_OUT` → `MACH_RCV_TIMED_OUT` → the brk above. This also
explains the debug-logging amplification (slower runs ⇒ far higher chance the thread
is parked in the reply receive when a stale short timer lands) — and it is a
whole-runtime defect: every Darling process is exposed to spurious timeouts.

**The fix.** Restore XNU's exact cancel block inside dtape's `thread_unblock`
(host-side Darling glue; `timer_call_cancel` is already used under the same locking
in this very file's destroy path, `thread.c:141-144`). Applied via
`tools/fix-stale-wait-timer.py` (exact-string apply/byte-perfect revert).

**Adversarial review (pre-build): SAFE-TO-TEST.** Five attack lines all held with
file:line evidence — lock order acyclic (the *arm* path exercises the identical lock
set), arm/cancel accounting balanced in both race orders, no load-bearing staleness
(`mutex_pause`'s self-timer unaffected), single-threaded-safe (expirations are
kernel microthreads on the same cooperative pool). Honest caveat kept: removing
stale kicks could unmask latent hangs in long soaks.

**The A/B/A — validated by failure composition** (debug-amplified gate, n=14/arm,
identical clean builds):

| arm | pass | tab-1 fails (mode A) | tab-2 fails (mode B) |
|---|---|---|---|
| baseline  | 1 | **12** | 1 |
| patched   | 3 | **1**  | 10 |
| restore   | 0 | **9**  | 5 |

Mode A collapses under the patch and **returns on revert** — the effect tracks the
fix. The overall gate stays red under the amplifier because **a second, previously
masked bug now gates**: mode B — the tab-2 session child is created and dies ~100 ms
later **without ever exec'ing login** (fingerprint verified in the patched fails:
no tab-2 exec; iTerm2 then takes **SIGABRT**, not mode A's SIGTRAP). Baseline runs
rarely reached it because mode A killed them at tab-1 first. Mode B is a distinct
open bug (F102), being captured with the same core pipeline.

Fix branch: darlingserver `fix/thread-unblock-stale-wait-timer` (submodule origin
`deepai-org/darling-aarch64-darlingserver`); **upstream PR `darlinghq/darlingserver#17`** (opened against
upstream `main`, where the identical unfixed `thread_unblock` is present — this is an
upstream defect affecting every Darling user, not an arm64-fork artifact). Harnesses: `f101-trace-diff.sh`, `f101-core-capture.sh`,
`fix-stale-wait-timer.py`; artifacts under `~/darling/f101-*`, cores in
`f101-core/analysis/`; A/B/A logs `f100-gate-aba/{baseline-clean,patched-staletimer,restore-staletimer}`.

**Two method notes worth keeping.**
- **strace suppressed the bug entirely** (0 crashes in 4 runs; iTerm2 never even reached
  tab spawn) — syscall tracing slows startup so much the race window closes. Core dumps
  are the right instrument for a timing-sensitive crash: zero cost until death, and they
  preserve the original signal frame that sigexc's SIG_DFL re-raise otherwise destroys.
- **The recovery trick:** Darling's `sigexc_handler` *logs the guest addresses of its own
  `siginfo` and `ucontext` arguments* (`sigexc_handler(5, 0x302750DA0, 0x302750E20)`).
  Those addresses are still mapped in the core, so the ORIGINAL signal's `si_code`,
  faulting PC and register set can be read straight out of the dump even though the
  process ultimately died of a re-raised default-action signal. This is a reusable
  technique for any Darling crash.

## F102 — the second, previously-masked bug: the forked session child aborts inside Darling's own signal handler 🟠

With F101's fix in place, the dominant failure becomes mode B, and the same core-dump
pipeline localized it in one pass. Two independent captures of the tab-2 child give a
byte-identical crash: **si_code = TRAP_BRKPT, PC = LR = `___simple_abort+0x18`, with
`_sigexc_handler+0x25c` as the return address on its stack.** The child crashed *inside
Darling's signal handler*.

The only `__simple_abort()` in `sigexc_handler` is `sigexc.c:446`:
```c
int status = dserver_rpc_interrupt_enter();
if (status != 0) { __simple_printf("*** dserver_rpc_interrupt_enter failed ... ***"); __simple_abort(); }
```
It sits **before** the handler's `kern_printf("sigexc_handler(...)")` at `:449` — which is
exactly why the server log shows no `sigexc_handler` line for the child while showing one
for iTerm2. So: **a signal was delivered to the post-fork, pre-exec child, and the child's
RPC to darlingserver failed, so the handler aborted the process.**

Relevant structure (unverified as cause; the mechanism hunt is F102's open half): the
dserver RPC socket is **per-thread** (`mach_driver_get_fd()` → `__dserver_per_thread_socket()`,
`lkm.c:125`), `mach_driver_init()` is documented as running "after forking" (`lkm.c:61-64`),
and the fd guards carry `guard_flag_close_on_fork` with the comment *"Fork children install
their guards in sys_fork"* (`lkm.c:100-107`). The child also freezes ~52% of the way through
a ~1020-call post-fork cancellation sweep before dying.

**Not claimed:** why the RPC fails. Recorded as a precise, reproducible localization —
crash site, failing call, and the exact line — not a diagnosis.

## CORRECTION (2026-08-15) — the "debug amplifier" claim in F100/F101 was confounded by root choice ⚠️

F100 and F101 state that `DSERVER_LOG_LEVEL=debug` "amplifies the flake from ~1–2% to
~93%". **That is not supported.** The 93% was measured on `install-arm64-id26`, and a
control run afterwards shows id26 fails the full Silver tab-close gate at ~100%
*regardless of logging or patch state*:

| id26, full gate | debug | fix #1 | fail rate |
|---|---|---|---|
| baseline | on | no | 11/12 |
| patched | on | yes | 11/14 |
| revert | on | no | 14/14 |
| real-world | **off** | yes | **15/15** |
| **control** | **off** | **no** | **15/15** |

The last row is the one that matters: **without the fix and without debug, id26 still
fails 15/15 = 100%** (95% CI [80%, 100%]). So debug logging was never shown to be the amplifier — id26 is simply a
bad root for this gate. `tools/f95-identity-26.sh:34,43` shows why: id26 is a copy of
**`install-arm64-stage10`** (not stage18) configured with
`-DDARLING_EMULATED_OS_PRODUCT_VERSION=26.5`. It is a stage10-derived, 26.5-identity
hybrid — not a stand-in for the reviewed `install-arm64-stage18` runtime, whose measured
full-gate rate is tab-close 11/15 pass.

**What survives this correction, and why:**
- **F101's mechanism** — proven at code level by the core dump (`TRAP_BRKPT`,
  `_dispatch_mach_send_and_wait_for_reply+0x5c4`, `x0 = MACH_RCV_TIMED_OUT`) plus the
  omission being present verbatim in upstream `main`. Root-independent.
- **F101's A/B/A** — internally valid: one root, one variable, and the *mode-A crash
  composition* moved 12 → 1 → 9 with revert-restore. It measures the crash, not the
  suite.
- **Fix #1 caused no regression** — the no-debug rate is identical (15/15 with the fix,
  15/15 without it) — a perfectly symmetric control.

**What is withdrawn:** the amplifier claim, and any implied real-world improvement.
**Unmeasured:** fix #1's effect on the reviewed stage18 runtime. That is the first job
of the next block. The public PR body (`darlinghq/darlingserver#17`) has been edited to
state this scope honestly rather than leave the confounded claim standing.

## F102 — mode B fully explained: mldr's arm64 thread-bridge broker cannot do RPC, and Darling's signal handler makes that fatal ✅🟠

**Mechanism (confirmed by evidence, with a prediction verified 3/3).**
With `DARLING_ARM64_THREAD_BRIDGE=1` (set by the probe, gated at `mldr.c:134-136`), the
fork child runs `__mldr_arm64_thread_bridge_init()` → a raw `pthread_create`
(`threads.c:263`) creating a **broker** thread. The broker never registers a bridge
entry (`arm64_thread_bridge_register` has exactly one call site, `threads.c:490`, in
`darling_thread_entry`), so for it `__darling_thread_rpc_socket()` returns **-1**
(`threads.c:725`: `return bridge ? bridge->rpc_fd : -1;`). The broker also inherits an
**open signal mask**, while the child's main thread has signals blocked for most of its
~1020-call pre-exec sweep (`dserver_rpc_hooks_atomic_begin`, mask `0x7fffffff`). So a
process-directed signal (SIGWINCH from iTerm2's pty resize) is delivered **to the
broker**; `sigexc_handler` runs there; `dserver_rpc_interrupt_enter()` sees a negative
socket and returns `-LINUX_EPIPE` (**-32**) *without making any syscall*
(generated `rpc.c:1802-1809`); `sigexc.c:446` aborts — killing the child before it ever
execs `/usr/bin/login`. iTerm2 then takes SIGCHLD and aborts itself.

**The prediction that confirms it:** this mechanism requires the crashing thread to be a
*non-main* thread (a fork child's main thread always has `tid == pid` and resolves to
`__dserver_main_thread_socket_fd`). Checked against three cores captured *before* the
hypothesis existed: process 81 → crashing tid 82; process 83 → tid 84; process 77 → tid
81. **3/3.** Each child core has exactly two threads (main + broker), as required.

**Why the aarch64 port is the regression:** the non-aarch64 path `abort()`s on this exact
"thread has no per-thread socket" condition (`threads.c:734`); every aarch64 path returns
before reaching it, and `t_server_socket = new_rpc_fd` (`threads.c:512`) is a dead store
on aarch64. The port silently converted *impossible-state → abort* into
*impossible-state → -1 → EPIPE → abort inside a signal handler*.

**Fix: NOT applied — deliberately.** The obvious one-line change (block signals across
the broker's creation, `threads.c:263`) **is a regression on its own**: `darling_thread_entry`
never sets a mask, so every Darwin thread created through the bridge would inherit the
fully-blocked mask and go permanently signal-deaf. A correct fix is two-sided (capture
the requesting thread's mask in `arm64_thread_create_submit` and restore it around
`threads.c:252`). Recorded rather than rushed.

**Zero-build discriminator for the next block:** re-run with
`DARLING_ARM64_THREAD_BRIDGE=0` (flip it in `probe-iterm2-launch-arm64.sh:463` *and* the
seven launchd plists together, or the test is contaminated) — no broker is created, and
mode B must disappear entirely.

**Bonus:** the same defect fires with SIGHUP on already-exec'd shells at teardown
(`run1/core.mldr.76`, `run3/core.mldr.77`), so this is a general process-lifetime hazard
on arm64, not a tab-2-only one.

## F103 — the honest real-world A/B for the F101 fix, on a faithful copy of the reviewed runtime (n=15: no significant difference) 🟠

F101's A/B/A was run on `install-arm64-id26`, which the correction above showed is a
stage10/26.5 hybrid that fails the full gate ~100% of the time. This is the same
experiment done properly: **a byte-faithful copy of the reviewed `install-arm64-stage18`
pair** (`install-arm64-f103` + `build-arm64-f103`; the reviewed roots are never
modified), **no debug amplifier**, one variable — only `darlingserver` is rebuilt
between arms.

**The copy is validated as faithful.** The unpatched control passes **12/15**, against
the historically recorded stage18 tab-close rate of **11/15**. A scratch root that
reproduces the reviewed baseline is the precondition for any claim here — and unlike
id26, this one does.

| arm (n=15, no amplifier) | pass | fail-rate | 95% CI | mode-A (tab1) fails | mode-B (tab2) fails |
|---|---|---|---|---|---|
| control (unpatched) | 12/15 | 20% | [7%, 45%] | **2** | 0 |
| patched (F101) | 13/15 | 13% | [4%, 38%] | **0** | 2 |

**Result: no statistically significant difference at n=15.** The confidence intervals
overlap heavily; 20% → 13% is entirely consistent with noise. The mode-A signature
disappearing (2 → 0) is *consistent* with F101's mechanism but is two events, and two
events prove nothing.

**What this does establish:**
- The fix causes **no regression** on the reviewed-equivalent runtime (13/15 ≥ 12/15).
- The real-world flake on stage18 is **~13–20%**, not the ~93% figure the withdrawn
  amplifier claim implied — that number belonged to a broken root.
- Mode B (F102) is present on the healthy runtime too (2 tab-2 failures in the patched
  arm), so it is not an id26 artifact.

**What it does not establish:** that F101 measurably improves the real-world pass rate.
That claim requires more runs, which is why an n=50 arm-pair is running. Until it
lands, the honest position for any report is: *mechanism proven and upstreamed;
real-world effect not yet demonstrated at this sample size.*

Harness `tools/f103-stage18-ab.sh` (copies, both arms, Wilson CIs, failure-mode
composition); artifacts `~/darling/f103-stage18-ab-n15/`.

### F103 (cont.) — the powered arms: a consistent favourable trend that does NOT reach significance

Repeated at **n=50 per arm** on the same faithful stage18 copy, same single variable:

| arm (n=50, no amplifier) | pass | fail-rate | 95% CI | mode-A (tab1) | mode-B (tab2) | close |
|---|---|---|---|---|---|---|
| control (unpatched) | 41/50 | 18% | [10%, 31%] | **6** | 0 | 2 |
| patched (F101) | 46/50 | **8%** | [3%, 19%] | **2** | 0 | 2 |

**Significance (Fisher exact, two-tailed):**
- overall fail rate 9/50 vs 4/50 — **p = 0.23**
- mode-A failures 6/50 vs 2/50 — **p = 0.27**
- pooled with the n=15 arms, mode-A 8/65 vs 2/65 — **p = 0.096**
- pooled overall 12/65 vs 6/65 — **p = 0.20**

**Verdict: not demonstrated.** Every arm and every metric points the same way (the fix
never looks worse, and the mode-A signature it targets is always the one that shrinks),
and that consistency is worth something — but no comparison clears p<0.05, so the
honest statement is a *trend*, not an effect. Reporting 18%→8% as "the fix more than
halves the flake rate" would be exactly the overclaim the correction above already had
to retract once.

**What it would take:** for a true 18%→8% difference, ~180 runs per arm are needed for
80% power at α=0.05 (≈2 h per arm on this machine). That run is the way to settle it;
it has not been done.

**Standing position for any report:** F101's *mechanism* is proven at core-dump level
and is upstreamed (`darlinghq/darlingserver#17`) on that basis — the crash it removes is
real, and the receive it fixes is untimed by contract. Its *effect on the end-to-end
gate* is an unconfirmed favourable trend. Those are two different claims and only the
first is established.

Artifacts `~/darling/f103-stage18-ab-n50/`; the n=15 arms in `-n15/`.

## F104 — Stage 20 (CotEditor Bronze) is blocked on arm64 before any GUI code runs: Darling has no arm64 Swift SDK overlays 🔴

First attempt at Kevin's **Stage 20**, the next rung after the Stage 19 Silver we
reproduced and the stated gate for Stage 21 (iTerm2 Gold). Both officially pinned
CotEditor builds were acquired **unmodified** via his own
`tools/prepare-coteditor-artifact-arm64.sh` (7.0.7, DMG `353997fd…` + executable
`02955bf9…` both verified) and, for the written gate's version, 4.5.5 (DMG
`9ba6ffec…` verified). Both carry a real **arm64 slice** (4.0 MB / 53.5 MB), so this is
not an architecture-availability problem in the app.

**Result: neither version launches. Both die at dynamic-link time, before a single
window is mapped** (the X11 tree contains only Openbox windows in every attempt):

```
4.5.5:  dyld: Symbol not found: _$s10Foundation15AttributeScopesO6AppKitE0dE10AttributesV014ParagraphStyleB0OMn
7.0.7:  dyld: Symbol not found: _$s10Foundation15AttributeScopesO6AppKitE0dE10AttributesV015BackgroundColorB0OMn
        Referenced from: /Applications/CotEditor.app/Contents/MacOS/CotEditor
        Expected in: flat namespace
```

Demangled, both are nominal type descriptors (`…Mn`) in
`Foundation.AttributeScopes.AppKitAttributes` — the Swift attributed-string scope types
that live in the **Swift SDK overlays** (`libswiftFoundation.dylib`,
`libswiftAppKit.dylib`).

**Root cause chain, each step verified:**
1. Darling ships **44 Swift SDK overlays** in `src/external/swift`. A fat-header decode
   of every one shows **all 44 are x86_64-only — zero contain an arm64 slice.**
   arm64 Darling therefore has *no* Swift SDK overlays of its own.
2. In this VM they were additionally **130-byte Git-LFS pointer files**, because
   **`git-lfs` was never installed here** — despite `STATE.md` trap 4 recording it as a
   documented Darling build dependency. Installing `git-lfs` and running `git lfs pull`
   against the public `darlinghq/darling-swift` fetched the real objects (e.g.
   `libswiftFoundation.dylib` 3,258,048 bytes, matching its pointer's recorded size).
   **They are still x86_64-only.** This also identifies what F71/F87's "39/209 dylibs are
   LFS pointers" hygiene note actually was: exactly these 39 Swift overlays — a note
   nobody had connected to a blocked stage.
3. The Apple **arm64e shared cache does contain the symbol family**
   (`AttributeScopesO6AppKit` present in the `.01` subcache), so the runtime exists on
   the machine; the app simply cannot reach it.
4. **Controlled test of the shadowing hypothesis:** on a dedicated copy
   (`install-arm64-f104`, leaving the validated f103 root untouched) all 39 stub
   overlays were moved aside — one variable — and the failure was **byte-identical**.
   So the disk stubs were not shadowing the cache; Darling's hybrid dyld mode
   (`ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1`, which Kevin's record describes as "Apple
   cache authoritative for Foundation/Swift") **does not route Swift overlay symbols
   from the cache for this app.**

**What this means for the ladder.** Stage 20 is not blocked by storyboards, bindings,
CoreText or X11 — the things Kevin's boundary notes describe. It is blocked *earlier*,
at Swift runtime availability: **an arm64 Darling cannot currently launch a Swift AppKit
application at all.** Closing it requires either building arm64 Swift SDK overlays or
making cache resolution work for them. That is the true gate to Stage 20, and therefore
to Gold.

**Kevin's version conflict, resolved empirically:** issue #1 pins 4.5.5, his
north-star/COMPATIBILITY pin 7.0.7. The question is **moot for Stage 20** — both fail
identically at the same symbol family, so the choice does not affect the outcome.

**Open discrepancy, stated rather than explained away:** his record describes reaching a
CotEditor *live document window* and an *"Anura couldn't be loaded"* alert — i.e. much
further than this. Either his environment supplied Swift overlays ours does not, or that
work ran under a different configuration. We have not reproduced his position and do not
claim his record is wrong; the difference is unexplained and is the first thing to ask
him.

**Not claimed:** any Stage-20 tier. This is a measured launch boundary, not a gate
result.

Harness `tools/f104-coteditor-launch-arm64.sh` (drives the existing probe engine via its
`APP_PROBE_*` parameters; `TYPE_TEXT` empty so the generic capture path runs; cores
enabled; artifacts preserved per attempt). Artifacts `~/darling/f104-coteditor/{first-light,v455,v455-nostubs}/`.
Bundles are unmodified, read-only, and **not committed** (upstream-licensed third-party
software).

## F105 — the general finding behind F104: Darling's Swift runtime is x86_64-only, so **no Swift program runs on arm64** 🔴

F104 established that CotEditor cannot launch. This generalises it from one app to the
platform, by differential test rather than inference.

**Three minimal Swift probes** were built with the host toolchain (Swift 6.3.3,
`-target arm64-apple-macos12.0`), each with native ground truth captured on macOS first —
the project's standard differential method. The corpus had **zero** Swift coverage before
this; the sources are now in `tests/swift-probes/`.

| probe | what it needs | native (macOS) | under Darling arm64 |
|---|---|---|---|
| `s1_core` — pure Swift, no imports | `libswiftCore` only | `SWIFT_CORE_OK [1, 2, 3]` | **no output, silent failure** |
| `s2_foundation` — `import Foundation` | + `libswiftFoundation` overlay | `SWIFT_FOUNDATION_OK abc true` | **`dyld: Library not loaded: /usr/lib/swift/libswiftFoundation.dylib`** |
| `s3_appkit_attr` — the exact CotEditor symbol family | + `libswiftAppKit` overlay | `SWIFT_APPKIT_ATTR_OK 1` | **`dyld: Library not loaded: /usr/lib/swift/libswiftAppKit.dylib`** |

**Control:** the same runner, same root, same invocation with a non-Swift binary
(`/hello-libsystem-arm64-0`) prints `hello from native Darling arm64`. So stdout capture
works and `s1_core`'s silence is a real failure, not a harness artifact.

**Why:** a fat-header decode of every Swift library in the staged root shows
**`libswiftCore.dylib` is x86_64-only**, as are `libswiftRemoteMirror`,
`libswiftSwiftOnoneSupport`, `libswift_Differentiation`, and all 44 SDK overlays.
**Not one Swift library in Darling has an arm64 slice** — core or overlay. Darling is a
translation layer, not a CPU emulator, so an x86_64 Swift runtime is unusable by an
arm64 process no matter how it is staged.

**The consequence, stated plainly:** *Swift support on arm64 Darling is currently zero.*
Not "degraded", not "missing an overlay" — a pure `print()` Swift program does not run.
Everything downstream follows: CotEditor (Swift/AppKit) cannot launch, so **Stage 20 is
unreachable**, and since Kevin's ladder makes Stage 20 the gate for Stage 21, **iTerm2
Gold is gated behind an arm64 Swift runtime that does not exist yet.**

**What this reframes.** The Stage-20 boundary is not a GUI/storyboard problem to be
chipped at — it is a missing runtime. Closing it means building the Swift core + SDK
overlays for arm64 (or routing the Apple cache's arm64e Swift images, which do contain
the symbols — see F104 §3). That is a substantial, well-defined piece of upstream work,
and it is now the single highest-leverage item on the arm64 ladder.

**Corrects by extension:** F104 attributed the block to "no arm64 Swift *SDK overlays*".
That was too narrow — the core runtime is missing too.

**Unexplained, and worth asking Kevin directly:** his record describes reaching a
CotEditor live document window. With no arm64 Swift runtime present in this tree, we
cannot reproduce that, and we do not claim his record is wrong — the gap is unexplained
and is the first question for him.

Probes + method: `tests/swift-probes/` (sources and README; the SDK-built binaries are
local-use only and not committed, per the corpus policy).

### CORRECTION to F105 (same session) — "Swift support on arm64 is zero" is too strong; it is established only *without* the Apple shared cache ⚠️

F105 concluded *"Swift support on arm64 Darling is currently zero."* Checking my own
harness afterwards shows that claim outruns the evidence, in one specific way.

**The gap:** the three Swift probes were run through
`tools/run-staged-darling-arm64.sh`, which **does not stage or mount the Apple dyld
shared cache** (verified: no `SHARED_CACHE`/`dyld_shared_cache` handling in the runner,
and neither `install-arm64-f103` nor `-f104` has anything under
`root/System/Library/dyld/`). The probe harness mounts it separately at run time
(`probe-iterm2-launch-arm64.sh:442`, `-v "$cache_root:/iterm-dyld-cache:ro"`). So the
probes measured Darling's **own disk Swift libraries only**.

**Why that matters — the two configurations fail differently:**

| configuration | failure |
|---|---|
| **no Apple cache** (Swift probes) | `dyld: Library not loaded: /usr/lib/swift/libswiftCore.dylib` — nothing loads |
| **with Apple cache** (both CotEditor runs) | `dyld: Symbol not found: …AttributeScopes…`, *"Expected in: flat namespace"* |

A `Symbol not found` (rather than `Library not loaded`) indicates the Swift libraries the
app depends on **did resolve** — CotEditor bundles no Swift itself (only
`Sparkle.framework`), so those can only have come from the cache. The cache-backed path
therefore gets *further* than "zero".

**What remains established (unchanged):**
- Darling's bundled Swift runtime is **x86_64-only** — `libswiftCore.dylib` and all 44
  SDK overlays, by fat-header decode. Unusable by an arm64 process, full stop.
- **Without** the Apple cache, no Swift binary runs on arm64: all three probes fail to
  load `libswiftCore`, against a passing non-Swift control through the same runner.
- Both CotEditor versions fail at the same `AttributeScopes.AppKitAttributes` symbol
  family, so Stage 20 is blocked and the 4.5.5/7.0.7 conflict is moot.

**What is withdrawn:** the blanket "Swift on arm64 is zero", and with it the implication
that Stage 20 needs a full arm64 Swift runtime *built* before anything can move. The
cache may already supply most of it; the failure may be a narrow symbol-resolution
defect rather than a missing runtime.

**The experiment that settles it** (first job next session, ~30 min): run the same three
probes **with the cache mounted and staged** — either by teaching
`run-staged-darling-arm64.sh` the probe's `-v "$cache_root:/iterm-dyld-cache:ro"` plus
its in-container staging, or by driving the probes through the probe harness. If
`s1_core` then prints `SWIFT_CORE_OK`, Swift substantially works on arm64 via the cache
and Stage 20's blocker is a specific missing symbol — a very different, much smaller
problem than "no Swift runtime".

Recorded because the distinction changes what the next block should attempt, and because
a too-strong claim in the record is worse than none.

## F106 — Swift **works** on arm64 Darling (core + Foundation, byte-identical to native); Stage 20 is blocked by a narrow Swift↔AppKit overlay gap ✅🟠

The experiment the F105 correction called for, run to completion. The three Swift probes
were wrapped in minimal `.app` bundles and driven through the **cache-enabled** probe
harness (`ITERM2_PROBE_SHARED_CACHE=1`, cache mounted at `/iterm-dyld-cache`) instead of
the CLI runner that stages no cache.

| probe | native macOS 26 (ground truth) | arm64 Darling + Apple cache |
|---|---|---|
| `s1_core` — pure Swift | `SWIFT_CORE_OK [1, 2, 3]` | **`SWIFT_CORE_OK [1, 2, 3]`** ✅ |
| `s2_foundation` — `import Foundation` | `SWIFT_FOUNDATION_OK abc true` | **`SWIFT_FOUNDATION_OK abc true`** ✅ |
| `s3_appkit_attr` — `AttributeScopes.AppKitAttributes` | `SWIFT_APPKIT_ATTR_OK 1` | `Symbol not found: _$s10Foundation15AttributeScopesO6AppKitE0dE10AttributesV015ForegroundColorB0ON` |

**Two of three match native output byte-for-byte.** This is the first verified evidence
in this engagement that **Swift runs on arm64 Darling at all** — sorting, generics,
`NSString` bridging, `UUID`, the Foundation overlay — all correct.

**This settles F105's correction, and overturns its headline.** "Swift support on arm64
is zero" was an artifact of testing through a runner that stages no shared cache. With
the cache present, Swift core and Foundation work. Darling's *bundled* Swift libraries
remain x86_64-only and unusable (F104/F105, unchanged) — but they are not the path that
matters: the Apple cache supplies a working arm64 Swift runtime.

**The real Stage-20 blocker, now precisely bounded.** The only failure is the
`AttributeScopes.AppKitAttributes.*` family — the Swift↔AppKit bridging types
(`ForegroundColor` in our probe; `BackgroundColor` in CotEditor 7.0.7; `ParagraphStyle`
in 4.5.5 — same family every time). Note the failure is **`Symbol not found`**, not
`Library not loaded`: the Swift AppKit overlay resolves, but these specific type
descriptors do not.

**Leading explanation (hypothesis, not yet proven):** `libswiftAppKit` is Apple's
Swift↔AppKit bridge and pairs with *Apple's* AppKit. Darling deliberately supplies its
**own** AppKit (Cocotron-derived) — Kevin's hybrid mode is documented as "Apple cache
authoritative for Foundation/Swift, **Darling AppKit** selected". So the Swift AppKit
overlay's attribute-scope metadata has no Apple AppKit behind it. If that is right, the
gap is not "Swift is missing" but "Swift's AppKit bridge has no counterpart in Darling's
AppKit" — a bounded, nameable piece of work rather than a missing runtime.

**What this means for the ladder.** Stage 20 (CotEditor Bronze) — and Stage 21 (Gold)
behind it — is gated on Swift AppKit interop, not on a Swift port. That is a far smaller
and better-defined problem than F105 implied, and it is the highest-leverage item on the
arm64 ladder.

**Next experiments (cheap, ordered):** (1) confirm whether `libswiftAppKit.dylib` is
actually loaded from the cache in the failing run, and from where; (2) determine whether
the missing descriptors exist in the cache's AppKit overlay but fail to bind because
Darling's AppKit is selected; (3) test the hybrid selection with Apple's AppKit
preferred, to see whether the symbol resolves (this may trade one failure for another,
which is itself informative).

Method note: the corpus now has Swift coverage (`tools/swift-probes/`), and this result
came from differential testing against captured native ground truth — the same method
that produced every reliable finding in this record.

## F107 — the Swift↔AppKit descriptors live inside Apple's AppKit binary; `libswiftAppKit` is an empty re-export stub — so they cannot exist against Darling's AppKit ✅

F106's leading hypothesis, tested where it is cheapest and most authoritative: against the
reference implementation on the arm64 macOS host (macOS 26.6, `dyld_info`), not inside the
VM. This is differential testing against ground truth, the same method as every reliable
finding here — only this time the ground truth answers the question outright.

**The exact symbol F106 reported missing is exported by AppKit itself:**

```
$ dyld_info -exports /System/Library/Frameworks/AppKit.framework/AppKit | grep ForegroundColorB0ON$
        0x69FDE450  _$s10Foundation15AttributeScopesO6AppKitE0dE10AttributesV015ForegroundColorB0ON
```

All eight descriptors of `ForegroundColorAttribute` (`…B0OMn`, `…B0OMa`, `…B0ON`, the
`AttributedStringKey` / `Decodable…` / `Encodable…` conformances, `name`) are in
`AppKit.framework/AppKit`. So are the families CotEditor trips on — `BackgroundColor`
(7.0.7) and `ParagraphStyle` (4.5.5), eight descriptors each. AppKit exports **289**
`AttributeScopes` symbols in total.

**`libswiftAppKit.dylib` exports nothing.** It is a pure re-export stub:

```
$ dyld_info -exports    /usr/lib/swift/libswiftAppKit.dylib     → (no exports)
$ dyld_info -dependents /usr/lib/swift/libswiftAppKit.dylib
        re-export      /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit
                       /usr/lib/libSystem.B.dylib
```

| binary (native macOS 26.6 arm64) | `AttributeScopes` exports | `ForegroundColor` descriptors |
|---|---|---|
| `AppKit.framework/AppKit` | **289** | **8** |
| `libswiftAppKit.dylib` | 0 (re-exports AppKit) | 0 |
| `Foundation.framework/Foundation` | 668 | 0 (`AppKit` extension, not Foundation's) |
| `libswiftFoundation.dylib` | 0 | 0 |

**What this settles.** Apple compiled the Swift AppKit overlay *into the AppKit binary*;
`libswiftAppKit` exists only so old link lines still resolve. Darling deliberately supplies
its own Cocotron-derived AppKit (Kevin's hybrid mode: Apple cache authoritative for
Foundation/Swift, **Darling AppKit** selected). Darling's AppKit is a different binary and
contains no Swift metadata, so `AttributeScopes.AppKitAttributes.*` has nowhere to come
from. This is exactly why F106 saw `Symbol not found` rather than `Library not loaded`:
the stub resolves (it re-exports whatever AppKit is bound), and the descriptor is absent
from the AppKit that got bound.

**What this means for the ladder.** Stage 20 is not blocked by a missing Swift runtime
(F106) and not by a missing overlay dylib (this finding). It is blocked by **which AppKit
is bound**. There are exactly two ways forward, and neither is "patch the symbols in":

1. **Bind Apple's AppKit from the cache** for Swift-AppKit applications — the hybrid
   selection flipped (`ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=0` under
   `DARLING_DYLD_SHARED_CACHE_AUTHORITATIVE=1`). Kevin chose Darling's AppKit for a reason;
   Apple's AppKit will demand WindowServer/SkyLight/CoreGraphics surfaces Darling does not
   provide. This trades one failure for another — and *which* failure is the next finding.
2. **Give Darling's AppKit Swift metadata for these scopes** — i.e. implement the
   `AppKitAttributes` scope against Cocotron's `NSColor`/`NSParagraphStyle`. Bounded, but
   it is real Swift-on-Cocotron work, not a shim.

**Closes NEXT_STEPS item 1, steps 1–2** ("state precisely why Apple's Swift AppKit bridge
cannot sit on Darling's AppKit"). Step 3 (the flip) is the next experiment and is a single
documented flag — one variable.

**Cost:** four `dyld_info` invocations on the host. No build, no VM. The record's most
expensive question so far was answered by asking the reference implementation directly.

**In-VM confirmation and the flip (2026-09-07, `tools/f107-swift-appkit-bind.sh aba`).**
The F106 `s3_appkit_attr.app` bundle, driven through the cache-enabled probe engine on the
`install-arm64-f103` root with the F104 known-good environment, A/B/A over **one** flag,
`ITERM2_PROBE_PREFER_DISK_FRAMEWORKS` (1 = Kevin's hybrid, Darling's AppKit from disk;
0 = Apple's AppKit from the shared cache). ~22 s per arm.

| arm | flag | `iterm2-job.out` | `iterm2-job.err` | AppKit mapped from |
|---|---|---|---|---|
| A1 | 1 | *(none)* | `dyld: Symbol not found: _$s10Foundation15AttributeScopesO6AppKitE0dE10AttributesV015ForegroundColorB0ON` | disk (`libswiftAppKit` from cache, AppKit not) |
| **B** | **0** | **`SWIFT_APPKIT_ATTR_OK 1`** | no dyld error; objc duplicate-class warnings (`NSTouch`, `NSSearchToolbarItem`, …) between Apple's AppKit and `libDarlingAppKitBootstrap` | `dyld: Using shared cached for …/AppKit.framework/Versions/C/AppKit` |
| A2 | 1 | *(none)* | same `Symbol not found` as A1 | as A1 |

**B is byte-identical to native ground truth** (`SWIFT_APPKIT_ATTR_OK 1`). The effect
tracks the flag and reverses on restore. So the Stage-20 symbol failure is a *framework
selection* outcome, not a missing runtime and not a missing overlay — exactly what the
host-side export tables predicted.

**What B does not show.** `s3_appkit_attr` never creates a window or enters
`NSApplicationMain`. The duplicate-class warnings are the first visible cost of binding
Apple's AppKit on Darling: Darling's `libDarlingAppKitBootstrap.dylib` and Apple's AppKit
both implement `NSImageSymbolConfiguration`, `NSSearchToolbarItem`, `NSFilePromiseReceiver`,
`NSTouch`. Whether a real GUI application survives Apple's AppKit — and what it needs first
— is F110's question (`tools/f110-coteditor-apple-appkit.sh`, the F104 CotEditor driver with
this one flag flipped).

## F108 — our drivers no longer destroy the evidence of a failing run (NEXT_STEPS item 5, verified 2/2) ✅

**The defect.** The Silver gate (`verify-iterm2-silver-tab-close-arm64.sh:40`) pipes the
probe's stdout to a fixed path, `/tmp/iterm2-silver-tab-close.log`, overwritten every run;
and our A/B drivers (`f103-stage18-ab.sh:45`, `f101-realworld.sh:16`) `sudo rm -rf` the
gate's artifact directory *before* each iteration. Net effect: `iterm2-job.err` — ~20–35 KB,
the one file in which a crash is actually visible — was destroyed a few seconds after every
failure, and every failure so far needed a re-run to diagnose. (The F104 driver already
preserved per attempt; the two real-runtime A/B drivers were the holdouts.)

**The fix, in our drivers only — Kevin's gate and probe are untouched.** After each
iteration with `rc != 0`: copy the gate's `/tmp` probe log to `run$i-probe.log`, and
`sudo mv` the artifact directory to `run$i-artifacts` (then `chown` it back to the user, per
the F97 root-owned-artifacts trap). Passing runs still discard their artifacts, so disk
stays bounded (f90's rule: passing artifacts add nothing). Eight lines per driver.

**Verification — one variable, on a root that fails deterministically.** `install-arm64-id26`
fails the full gate ~100% (F102 correction: 15/15 with and without the fix), which makes it
the cheapest possible test bed for "does a failing run keep its artifacts" — the driver is
under test here, not Darling.

```
tools/f101-realworld.sh 2 f108-check        # 23:18:50 → 23:20:33, ~50 s per gate run
REALWORLD [f108-check] n=2 pass=0 fail=2 fail-rate=100% 95% CI [34%, 100%]
f101-realworld/f108-check/
  run1.log  run1-probe.log (491 B)  run1-artifacts/  iterm2-job.err 29,558 B  + 27 files
  run2.log  run2-probe.log (491 B)  run2-artifacts/  iterm2-job.err 19,717 B  + 27 files
```

Both failing runs left `iterm2-job.err`, `iterm2-job.out`, `darlingserver.err`,
`com.googlecode.iterm2.plist`, the `mldr-<pid>*` snapshots and the probe log behind, owned by
the user. Control: the gate's verdict and rate are unchanged (2/2 fail on id26, exactly the
recorded ~100%); the driver's added lines run only after the gate has returned.

**Cost:** 30 minutes and two gate runs. **Pays for itself the first time** — NEXT_STEPS
item 4 (the residual failure modes on the real runtime) was blocked on exactly this.
