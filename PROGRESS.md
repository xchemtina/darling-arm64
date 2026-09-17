# PROGRESS

Chronological log. Newest last. Records what was tried and what actually happened,
including dead ends — the dead ends are often the most useful part.

---

## 2026-08-02 — Osxie evaluation (session 1, cut short)
Session died on a weekly rate limit mid-analysis. Established: `Osxie` is
"Darling x86_64 build - source code with submodules flattened", `fork: false`,
GPL-3.0, three author identities. No verdict reached before the cutoff.

## 2026-08-04 — Context recovery and Osxie verdict
- Recovered the lost session; confirmed the referenced "WSL2 thread" is **not on
  this machine** (exhaustive: all Claude project dirs, both accounts, Claude
  Desktop store, Codex/Grok/Hermes/Goose/Amp/Cline/Aider, 1035 ChatGPT exports,
  Spotlight). Do not repeat this search.
- **Osxie rejected** (DECISIONS D1): x86_64-only, and commits that strip upstream
  GPL-3.0 attribution while flattening submodules to hide ancestry.
- Found **PR #1753** (kkHAIKE) — a near-complete aarch64 port, unmerged, never
  independently reproduced. Adopted as Lane A.

## 2026-08-04 — Lane A on Fedora 44 (wrong platform)
- Built VM `darling-arm64`, Fedora 44 aarch64, clang 22.
- **Traps hit:** dnf5 rejects an entire transaction over one unresolvable package
  (silently installed nothing); relative submodule urls resolve against the
  branch's *tracking remote*, sending all 149 to kkHAIKE's account; nine
  submodules silently sat at the wrong commit; two sat at the right SHA with an
  **empty worktree**.
- Reached 100% with **five deviations** (4 × `-Wno-error`, 1 libffi CFI patch),
  installed successfully.
- **Container would not boot.** Diagnosed carefully: `launchd` runs as PID 1 and
  survives; a child it forks dies with `EXC_BAD_ACCESS` at address 0 (F7).
  Bisected all 20 LaunchDaemons away — still crashes, so not daemon-driven.
  Caught the ~1ms-lived child by tight-looping `/proc/<launchd>/task/*/children`.
- Also found **F8**: after a failed boot, `make install` hangs forever because
  `shutdown-user.sh` spins on `pgrep -f launchd` matching defunct mldr zombies.

## 2026-08-05 — Methodological correction, Debian 13
User critique prompted a hard look at method. **Fedora 44 was simply wrong:**

| Fedora 44 compiler | Result |
|---|---|
| clang 22.1.8 (default) | too strict for Darling's C |
| clang 18.1.8 (compat) | 94 errors inside its own libstdc++ 16 headers |

- Rebuilt on **Debian 13 / clang 19.1.7** — matching PR #1753's stated toolchain.
- Signal-to-noise transformed: a cascade of noise became **~4 genuine defects**.
- Fixed properly rather than suppressed: **F1** (`epoll_create1` undeclared),
  **F2** (`kevent_internal_s*` punned through `kevent64_s*` — corrupts the knote
  on every timer re-arm), **F9** (`strncmp` undeclared), **F10** (`select.c`
  missing `pselect.h`), **F11** (`getpgrp.c` missing `getpgid.h`), **F12**
  (ruby/fiddle selects a libffi closure API that does not exist on arm64 Apple).
- Closed the missing-declaration class exhaustively: compiled **all 285** emulation
  sources with `-fsyntax-only`; exactly one remained, now fixed.
- **Retracted an over-correction (D7):** F6 is *not* a Fedora artifact — clang 19
  rejects libffi's aarch64 CFI too. The regression is between clang 18 and 19.
- **Clean build + install succeeded** on clang 19.
- **F7 reproduced byte-for-byte** on the clean foundation — same single signal-11,
  same NSID 4, same `exception_triage_thread(1, [1, 0])`, same topology. F7 is a
  genuine defect, not an artifact. Lane A remains unable to boot.

## 2026-08-07 — Lane B discovered; everything reframed
- User revealed the WSL2 effort had reached **GUI**, and pointed at a
  `deepai-org` arm64 fork.
- Installed GitHub CLI **via flox** (user rule: flox/nix, never Homebrew — a
  `brew install` was interrupted to say so). `gh` was already present in their
  default flox env; created a **project-scoped** env instead.
- Wired **GitHub's official MCP server** (nixpkgs) at project scope, with a
  launcher that reads the token from `gh` at runtime so no credential is stored.
- User authenticated as **xchemtina**. Revealed **38 private
  `deepai-org/darling-aarch64-*` repos** — invisible unauthenticated.
- **`darling-aarch64-north-star` already runs unmodified iTerm2 3.6.11 under X11
  on ARM64**, 30-minute Bronze soak, real Settings panes, persisted state.
  Lane A parked (D8).
- Notable: they evaluated kkHAIKE's work and **did not merge PR #1753**, though
  they took several of his component PRs. They use **xnu #13, not his #14**.

## 2026-08-07 — Lane B stood up
- New VM `darling-ns`: Ubuntu 24.04.4 aarch64 (their reference host), 12 cores,
  25GB RAM, 287GB free, docker 29.1.3/aarch64.
- Cloned north-star at their documented checkpoint
  `3e41a1ca8 "Persist iTerm2 Settings across restart"`.
- **Fixed three real gaps in their own reproduction guide** (D10) — relative-url
  resolution, `sync` clobbering per-submodule config, three mirrors missing from
  the map plus case mismatches. Iterated: 12 wrong-commit → 7 → 0; 99 empty
  worktrees → 3 → 0.
- **Final: 160 submodules, 0 missing, 0 wrong-commit, 0 empty. 5.6GB.**
- Staged official **iTerm2 3.6.11**, SHA-256 verified against their pin.
- Launched `bootstrap-stable.sh` (Stage 0–17). Docker image built
  (`darling-arm64-dev:latest`, 2.34GB). Build proceeding through Foundation.
  First error seen: `libsystem_sandbox.dylib not found for architecture arm64`
  while linking `plutil`/`defaults` — build continued past it.

## 2026-08-09 — Corpus runs; F25 resolved; F24 withdrawn after a control run

**GUI verifiers: 3/7 → 5/7.** Headless guard held at 11/11 throughout.

| verifier | result |
|---|---|
| `verify-hello-window` | ✅ pass |
| `verify-controls` | ✅ pass |
| `verify-text-view` | ✅ pass |
| `verify-pty-harness` | ✅ pass |
| `verify-x11-backend` | ✅ pass (flaky — see F29) |
| `verify-text-edit` | ❌ F27, Cmd-S |
| `verify-mini-term` | ❌ new frontier, past the paste phase |

Neither newly-passing verifier is credited to a source change of ours; see the
F24 entry below for why that distinction is now taken seriously.

**Differential corpus run for the first time** (`scripts/91-corpus-runner.sh`) —
built on day one and never executed until now. **12 matched, 2 diverged, 3 skipped**
against macOS-native ground truth on identical bytes. Both **arm64e (PAC-signed)**
binaries matched exactly, as did Apple-signed `host_uname`/`host_true`/`host_false`,
pthread, dispatch, CoreFoundation and the syscall probe. The two divergences share
one cause: **F28**, Foundation is missing `NSConstantIntegerNumber`, so any binary
built against a recent SDK using `@1`-style boxed literals fails to launch. The
abort path itself then faults (SIGSEGV at `0x97`, exit 139) instead of reporting a
clean dyld error.

**F27 narrowed to the Save action itself.** `OBJC_PRINT_EXCEPTIONS=YES` showed
exactly two exceptions, **both caught and completed** — not an uncaught-exception
death. A Cmd-B probe was decisive:

| keystroke | windows after | screenshot |
|---|---|---|
| Cmd-B | **1** (`Untitled 1 - TextEdit`) | 13940 B, full UI |
| Cmd-S | **0** | 263 B, blank |

Key-equivalent dispatch works; the Save path terminates the process, and cleanly
enough to suggest `exit()`/`terminate:` rather than a crash.

**F25 resolved — harness bug, not a renderer defect.** With a prompt wait before
the first keystroke, line 0 reads `north-star$ echo STAGE17_COMMAND_OK` instead of
`echnorth-star$`, and the `{0,6}` selection copies `north-` instead of `echnor`.
MiniTerm's PTY reader is exonerated. The verifier still fails, but now after the
paste phase — a separate, unisolated failure.

**F24 withdrawn as a defect.** Static reading of Cocotron found the earlier fix was
inert by construction: `-makeKeyWindow` only maps and raises the platform window,
while `-becomeKeyWindow` is the sole caller of `-[NSApp _setKeyWindow:]` and hence
the only thing that can change `-isKeyWindow`. Switching to `[sheet becomeKeyWindow]`
worked — a trace confirms `sheetKey=1`, parent clicks swallowed, sheet clicks
delivered to `NorthStarModalView`.

**Then the control run overturned the whole thing.** Reverting to pristine and
running the verifier three times gave rc=0, rc=0, rc=0. The verifier passes without
the patch. The founding premise — "AppKit does not route mouse events into a
non-key window" — is false in Cocotron: `-[NSWindow sendEvent:]` dispatches
`NSLeftMouseDown` by hit-test alone, with no key-window test.

What was actually failing is **F29**: the app intermittently takes longer than 10 s
to exit after `alt+F4`, so `timeout 10s tail --pid=…` returns 124. Six passes in
eight runs today, failures spread across builds, control clean.

It was misread for days because the ERR trap printed `${BASH_LINENO[0]}`, which
does not track `$BASH_COMMAND` here — it named the modal-click assertion while the
real failure was eight lines further on. One `echo` of `$BASH_COMMAND` exposed it
on the first run afterwards. The tell had been on screen from the beginning: status
124 is `timeout`'s exit code, and the blamed line runs no `timeout`.

The `becomeKeyWindow` change is **kept but relabelled** — a semantic correction
(macOS sheets are key while presented, and the trace shows it now achieves that),
explicitly not credited with fixing any verifier.

Four traps added to `STATE.md` from this: ERR-trap line numbers, `$prefix`-relative
artifact listings, and — the expensive one — **always run the control before
crediting a patch**.

## 2026-08-09 (session 2) — F28 fixed; three new defects; a withdrawn "11/11"

**F28 fixed.** Implemented the compiler-emitted constant-object classes that recent
clang requires — `NSConstantArray` in CoreFoundation, `NSConstantIntegerNumber` in
Foundation. The split follows Apple's, and the linker enforced it: putting both in
CoreFoundation fails with `"_OBJC_CLASS_$_NSNumber", referenced from:
_OBJC_CLASS_$_NSConstantIntegerNumber`. Layouts were read out of the emitted binary
with `otool -v -s __DATA_CONST`, not guessed.

`t06_objc.arm64` went from **exit 139, "Symbol not found"** to **exit 0,
`objc:1~count:3~dict:v~class:__NSCFString`**. `count:3` is the load-bearing part —
the statically allocated array reports its elements, so both classes work rather
than merely link. Any binary built against a modern macOS SDK using `@1`-style
literals can now launch.

**F30 — `mini-term` isolated, and it is not a Darling defect.** The diagnostic went
in *before* the investigation this time, and named the failing step on the first
run. Selection `{0,6}` ✓, copy ✓, Ctrl-V paste ✓, text reaches the PTY ✓, shell
responds ✓ (`sh: north-: command not found`). What fails is a hard-coded expectation
that the first six characters of the terminal buffer are `Cannot` — a string that
appears nowhere in MiniTerm, in Darling's bash, or in the verifier outside those
assertions. Where it comes from on deepai-org's host is unresolved and recorded as
unresolved.

**Three new defects, all previously masked:**
- **F32** — no tagged-pointer strings (`__NSCFString` where macOS says
  `NSTaggedPointerString`). Cosmetic.
- **F33** — arm64e SIGSEGV inside `+[NSString stringWithFormat:]`, before any
  constant object is touched. The identical arm64 binary now runs clean, so this is
  PAC-path-specific. Register state reads as unbounded recursion; unconfirmed.
- **F34** — **Darling writes binary property lists but cannot read them.**
  XML→binary produces a valid `bplist00`; binary→XML fails with
  `plutil: input is not a property list`, from
  `NSPropertyListSerialization propertyListWithData:`. High real-world impact:
  binary is the default format for macOS preferences.

**The "11/11 headless gates" claim is withdrawn.** Three things, in order:

1. *The measurement was invalid.* The consolidation run piped the verifier into
   `tail` and read `$?` — that is `tail`'s status, always 0. It never observed the
   verifier at all.
2. *Measured properly it fails*, `RC=1`, at the service-tools rung on F34.
3. *It is not a regression.* Control with the F28 classes reverted and rebuilt:
   identical `RC=1`. Trap 9 earned its place a second time.
4. *It never passed here.* `gate-quick{,2}.log` died earlier on `libbz2` and never
   reached this rung; `gate-quick3.log` — the first run that could — failed here, as
   has every run since.

Correct statement: **11 rungs pass, the 12th fails.** Materially different from
"the suite is green", which is what "11/11" implied.

Three more traps recorded (10–12): verify that a measurement measures what you
think; `git checkout --` behaves differently across submodule boundaries and
silently discarded two earlier patches; apostrophes cannot appear anywhere inside a
single-quoted verifier body — hit for the second time, this time in my own comment.

## 2026-08-09 (session 3) — the headless ladder is green for the first time

**12/12.** `RC=0`, twelve `passed` lines, status captured directly rather than
through a pipe. This is the first time the ladder has ever passed on this machine.

**F34 fixed — and its original diagnosis withdrawn.** I had recorded it as
"Darling writes binary property lists but cannot read them". That was wrong. The
binary plist reader works: given a `bplist00` that still exists, `binary → XML`
round-trips correctly.

The real defect is one line in `darlingserver.cpp:237`:
```c
const char* dirs[] = { "/var/tmp", "/var/run" };   // wiped on EVERY container start
```
`verify-service-tools` writes `/private/var/tmp/stage10.binary.plist` in one
`darlingserver` invocation and reads it in the next; the intervening server start
deletes it. On Darwin `/private/var/tmp` is the **persistent** temp directory —
`/private/tmp` is the volatile one — so wiping it diverges from the platform Darling
emulates. Fix: stop wiping `/var/tmp`, keep wiping `/var/run`.

Proven by canary, not inferred: a file in `$prefix/private/var/tmp` is gone after
one trivial server run; one in `$prefix/root` survives.

**Controlled:**

| build | ladder | rungs |
|---|---|---|
| with fix | RC=0 | 12 |
| reverted (control) | RC=1 | 11 |
| restored | RC=0 | 12 |

**What caught it: a diagnostic that stayed silent.** `scripts/patch-f34-trace.py`
instruments all 113 rejection sites in `CFBinaryPList.c` through the single
`FAIL_FALSE` macro at line 728. On the failing conversion it printed *nothing* — so
the parser never rejected anything, so the data never reached it. It fired correctly
on the XML input in the same run, which is what made the silence meaningful rather
than merely inconclusive.

**Why I got it wrong the first time (F35).** `plutil.m:65` reports an unreadable
file and a malformed file with the same message. `input == nil` from a missing file
becomes "input is not a property list" — an assertion about contents that were never
examined. Two extra lines would separate them.

**Corpus: coverage 17/17, 0 skipped.** Added argv support to
`scripts/91-corpus-runner.sh` using `/exec-arguments-darling-arm64`
(`DARLING_EXEC_PATH` + `DARLING_EXEC_ARG1..8`), the same mechanism
`verify-service-tools` uses throughout; `host_wc` also gets stdin.

| | before | after |
|---|---|---|
| matched | 12 | **14** |
| diverged | 2 | 3 |
| skipped | 3 | **0** |

`host_echo` and `host_basename` match macOS byte-for-byte on first execution.
`host_wc` surfaced **F36**: Apple's `wc` links `/usr/lib/libxo.dylib`, which Darling
does not ship. Same secondary defect as F28 had — the missing-library abort path
itself faults (SIGSEGV, exit 139) instead of reporting a clean loader error. Two
independent cases now do this, so it is a property of the abort path.

GUI untouched this session, by request.

Three traps recorded (13–15): prove the input was read before debugging a parser; a
silent diagnostic can be the finding; `/private/var/tmp` did not survive a
`darlingserver` restart.

## 2026-08-09 (session 4) — loader errors are now readable

**F37 fixed.** Every loader failure in this project ended in
`unhandled ARM64 SIGSEGV` that buried the actual error. Cause:

```c
sys_abort_with_payload(...) { __simple_printf(...); sys_kill(SIGABRT); return 0; }
```

`abort_with_payload` is `noreturn` and dyld depends on it — `halt()`
(`dyld2.cpp:4545`) ends with the call and emits no epilogue, so returning fell off
the end of the function into unmapped memory. `sys_kill` cannot terminate here
because Darling catches SIGABRT via `sigexc_handler`.

Controlled:

| build | `host_wc` exit | last line |
|---|---|---|
| with fix | **134** | `Reason: image not found; code: 1` |
| reverted (control) | 139 | `unhandled ARM64 SIGSEGV …` |
| restored | **134** | `Reason: image not found; code: 1` |

Ladder re-verified **12/12 RC=0**; corpus unchanged at 14 matched / 3 diverged /
0 skipped.

**Three rebuilds before it took, and the tell was in the data the whole time.** The
fault site was byte-identical across builds — same `pc` low bits `…CF78`, same `lr`
`…DB98`, same `address=0x39`, only the ASLR base moving. `/usr/lib/dyld` links its
**own static copy** of the emulation syscalls, so rebuilding `libsystem_kernel.dylib`
and then `mldr` changed nothing; only rebuilding `src/external/dyld/dyld` did. Third
time in this project a fix landed in a binary the running code does not load —
`STATE.md` trap 16.

**F35 fixed** (`plutil`): an unreadable input now says `could not read input file`
instead of claiming the contents are malformed. Two lines, and it is the message
that sent F34 into the wrong subsystem for a session.

**F36 scoped, not fixed.** Apple's `wc` needs `/usr/lib/libxo.dylib` and `libxo`
does not exist anywhere in the Darling tree — `find` and `grep` over the whole
source return nothing. Vendoring a real BSD library is a larger job than the time
available, so it stays queued with the scope stated honestly rather than guessed at.

## 2026-08-09 (session 5) — F33 root-caused; a fix that could not be credited

**The arm64e recursion is fully understood.** A frame-chain walk added to the arm64
SIGSEGV handler (`scripts/patch-f33-backtrace.py`) turned "probably recursion" into
a printed two-frame cycle, and symbolising against CoreFoundation's load base named
both functions:

```
_CFStringGetCharacters + 0x10                  <- pc
-[__NSCFString getCharacters:range:] + 0x64    <- alternating
_CFStringGetCharacters + 0x168                 <- alternating
```

`CFStringGetCharacters` (`CFString.c:2026`) dispatches to ObjC whenever
`CF_IS_OBJC`, and `__NSCFString`'s method (`NSString.m:327`) calls straight back in.
The loop is meant to be broken by `_CFIsCFObject`. Instrumenting it showed exactly
why it is not, on arm64e only:

```
raw_isa         = 0x4c000300845838
object_getClass = 0x4c000300845838     <- PAC signature bits still present
constStrCls     = 0x  300845838        <- the real class
isCF=0
```

The object is the client binary's constant CFString; in an arm64e image its isa is
PAC-signed, Darling has no PAC hardware, and `objc-config.h:94` disables packed-isa
for Darling/arm64 so nothing masks the pointer. Every class comparison fails, CF
treats a CF object as foreign, and the bridge recurses to the stack guard page.

**And then the control refused to credit the fix.** Applying a PAC-strip to
`_CFIsCFObject` made `t06_objc.arm64e` exit 0 with correct output — but reverting it
and rebuilding gave exit 0 as well, stably across three runs. Something earlier in
the session changed the outcome; I could not attribute it. Re-instrumenting showed
`CFStringGetCharacters` is now never called at all, so the fix cannot be re-verified
either — the failing path is no longer exercised by any test.

The patch is **kept but credited with nothing**: the defect it addresses was
directly measured, and it is correct by construction for a runtime without PAC
hardware. Two traps out of this — a symptom that stops reproducing is not a fix
(17), and symbolising crash addresses is cheap and worth doing first (18).

**F38 found while symbolising: images are mapped overlapping.** `libSystem.B.dylib`
and `Foundation` both claim `0x300000000`; `libsystem_coretls` and `libsystem_malloc`
sit *inside* CoreFoundation's `__TEXT` range. Not yet investigated, and a plausible
explanation for crashes that come and go — including F33's disappearance. Next step
is `/proc/<pid>/maps` from the Linux side, to confirm it is real rather than an
artefact of how `DYLD_PRINT_SEGMENTS` reports slices.

**End state re-verified:** ladder **12/12 RC=0**, corpus **14 matched / 3 diverged /
0 skipped**, and `t06_objc.arm64e` now runs to completion — differing from macOS
only on F32's tagged-pointer class name, exactly like the arm64 build.

## 2026-08-10 — overnight: corpus tripled, arm64e ObjC runtime fixed

**Corpus: 17 cases → 39. arm64e coverage: 3 → 16. Result 30 matched / 9 diverged /
0 skipped.** Ladder held at **12/12 RC=0** throughout.

### F38 withdrawn within the hour

The overnight plan led with F38 ("images are mapped overlapping"). `/proc/<pid>/maps`
from the Linux side — the kernel's own record rather than dyld's printf — showed
**41 images, zero overlaps, a uniform 1 MB stride**. The original claim came from an
`awk` one-liner that paired `Mapping` lines with the next `__TEXT at` line and then
sorted. Refuted in 25 minutes against a 3 h budget, because it had been raised with
`/proc/maps` already named as the check to run.

### Regression cover for this week's fixes, which found two more defects

Four fixes had landed this week with no test that would catch a regression. Added
`t08_plist`, `t09_vartmp`, `t10_boxed`, `t11_bridge`, then five capability areas
nothing exercised (`t12_strings`, `t13_number`, `t14_fileman`, `t15_invoke`,
`t16_collections`), each built for arm64 **and** arm64e.

The first run paid for the whole exercise:

- **F28b** — `t10_boxed` needs `NSConstantDictionary`, which F28 had deliberately
  deferred for want of a binary to read the layout from. Now there was one.
  Implemented; `t08_plist` and `t10_boxed` ×2 went from exit 134 to exact matches.
- **F41** — `t15_invoke.arm64e` died in the ObjC runtime while the identical arm64
  binary passed.
- **F39** — `precomposedStringWithCanonicalMapping` does not recompose (NFD is
  correct, NFC is not).
- **F40** — `-[NSNumber description]` prints `ULLONG_MAX` as `-1`; CFNumber has no
  unsigned type at all, so the value is sign-extended through
  `kCFNumberSInt128Type`.

### F41: the arm64e ObjC runtime fix, and F33's missing root cause

```
[F41] FAIL inst=0x1000081f0 metacls=0x1000081c8
[F41]   [0] cls=0x1000081f0 ISA=0x510001000081c8 name=Target
```

`0x510001000081c8 & 0x0000FFFFFFFFFFFF == 0x1000081c8 == metacls`, and the high
bits varied run to run — a PAC signature, not an address. `isa_t::getClass()` in the
raw-isa path returned it unmasked, so **every class-identity comparison against a
clean pointer failed**. That kills NSInvocation, forwarding and swizzling for any
arm64e binary, and it is the same cause as F33's CF↔ObjC recursion.

Controlled: with the fix `t15_invoke.arm64e` passes and the corpus is 30/9; reverted
and rebuilt, it fails again at exit 134 and the corpus is 29/10; restored, 30/9.
This is the first fix in the project credited through a full before/after/restore
cycle on a test written specifically for it — which is exactly what trap 17 asked
for after F33 could not be credited.

**Three false starts, none of them the fix being wrong.** `objc-object.h` defines
`isa_t::getClass()` twice and Darling/arm64 compiles the *second*; and objc4 has **no
header dependency tracking at all**, so two cycles ran against a binary that never
included the change. Traps 20 and 21.

### Deliberately not attempted

- **F32 (tagged-pointer strings)** — scoped, not attempted. objc4 has the full
  machinery, but CoreFoundation has **no creation path**: `ENABLE_TAGGED_POINTER_STRINGS`
  guards code stripped from this CF vintage. Implementing it means a tagged branch in
  every CFString accessor — multi-day, on the hottest path in the system, for a
  divergence that is purely a class *name*. Accounts for 4 of the 9 remaining.
- **F36 (libxo)** — scoped honestly: exactly **7** tools on this Mac link it
  (`wc`, `df`, `w`, `uptime`, `last`, `log`, `unvis`), and libxo is absent from the
  tree, so it means vendoring a BSD library rather than wiring up something present.

## 2026-08-10 (afternoon) — F39 fixed; F27 localised after three sessions

**Ladder 12/12 RC=0. Corpus 32 matched / 7 diverged / 0 skipped. GUI 5/7.**

### F39 fixed — two normalisation methods had each other's constants

`NSString.m:1777-1816` holds four one-line methods, and two of them were swapped:
`precomposedStringWithCanonicalMapping` passed `FormKD` (compatibility
*decomposition*) where it needed `FormC`, and `decomposedStringWithCompatibilityMapping`
passed `FormC` where it needed `FormKD`. So "precompose" decomposed further, which
is precisely why NFD → NFC never round-tripped.

**The corpus only caught half of it.** `t12_strings` covered the canonical pair; the
compatibility pair was wrong in the mirror-image way and nothing tested it. Extending
the case to all four *before* fixing paid off immediately in the control:

| | with fix | reverted |
|---|---|---|
| `recomp_eq` | 1 | 0 |
| `kdecomp_len` | 8 | **7** — a compatibility *decomposition* returning composed output |
| corpus | **32 / 7** | 30 / 9 |

### F27 localised — and the previous reading was wrong

Three sessions concluded the Save action ended TextEdit "cleanly enough to suggest
`exit()`/`terminate:` rather than a crash". **It is a segfault**, and always was —
nothing was capturing it. Two earlier pieces of work made it visible: F37 (the abort
path no longer destroys its own diagnostic) and the frame-chain walk added to the
arm64 SIGSEGV handler for F33.

Symbolised against the same run's image bases:

```
_objc_msgSend + 0x8                            <- x0 = 0x22, a small integer
__decodeObjectBinary + 0x83c                   (Foundation)
-[NSKeyedUnarchiver decodeObjectForKey:]
-[NSCell initWithCoder:] -> NSActionCell -> NSTextFieldCell
-[NSTableColumn initWithCoder:]
-[NSKeyedUnarchiver _decodeArrayOfObjectsForKey:]
-[NSArray initWithCoder:]
```

Cmd-S builds `NSSavePanel`, which unarchives `NSSavePanel.nib`; while decoding the
file browser's table-column cells, `__decodeObjectBinary` returns a non-object and
the caller messages it. `address == x0`, and x0 varies between runs (`0x7`, `0x22`),
so a raw value or tag is reaching the caller where an object pointer belongs.

Ruled out: the NIB is present and staged; `CFKeyedArchiverUID` *is* implemented in
CoreFoundation; key-equivalent dispatch and uncaught exceptions were already
eliminated. Next step is narrow — instrument `__decodeObjectBinary`'s return path
and find which node type it mishandles.

Stopped at the block cap with the localisation recorded rather than pushing into a
fix, per plan.

One trap added (22): in zsh, `path` is a special array tied to `$PATH`, and using it
as an ordinary variable wipes the environment mid-script.

## 2026-08-10 (evening) — F42: `encodeConditionalObject:` was a trap

**Ladder 12/12 RC=0. Corpus 34 matched / 7 diverged / 0 skipped (41 cases). GUI 5/7.**

### The plan's first block found a different defect than it was aimed at

Block A was meant to give F27 a headless reproduction — `verify-text-edit` costs
~10 min and needs Xvfb, openbox and xdotool; a corpus case costs ~4 min and no
display. `t17_archive` archives a graph with a parent/child cycle, one object
referenced three times, and mixed scalars — the `NSArray` → `NSTableColumn` →
`NSTextFieldCell` shape.

It crashed on its first run, but in the **archiver**, not the unarchiver:

```c
static void encodeConditionalObject(NSKeyedArchiver *archiver, id object, NSString *key)
{
#warning TODO
    DEBUG_BREAK();
}
```

That is the entire function (`NSKeyedArchiver.m:314`). `NSKeyedArchiver` could not
archive **any** graph using conditional encoding — which is how every back-reference
is written: delegates, targets, an `NSCell`'s control view, an `NSTableColumn`'s
table view. It died with SIGTRAP, exit 133, and no message.

**Two things made it findable.** The reproducer being headless and cheap; and
`setvbuf(stdout, NULL, _IONBF, 0)` in a debug variant — the first attempt printed
*nothing at all* because stdout is block-buffered on a pipe and a signal death
discards the buffer. It had actually run several statements (trap 23).

### The fix, with its limit stated

A single-pass approximation of Apple's contract: reference the object if it already
has a UID in `_objRefMap`, otherwise nil. Correct for the common shape (a child
referring back to a parent already mid-encode, since encoding is depth-first);
**wrong** if the target is encoded unconditionally only later, where Apple would
still emit a reference. Recorded rather than hidden.

Controlled: with the fix `t17_archive` passes on both arches and the corpus is 34/7;
reverted, exit 133 and 32/9. The round-trip preserves `shared_identity:1` and
`cycle:1` — exactly what conditional encoding exists for — both matching macOS.

**No relationship to F27 established.** F27 crashes *unarchiving* an AppKit NIB
produced by Apple's tools; F42 is the archiver. F27 remains open and unchanged.

### A regression that wasn't

The consolidation run showed `verify-hello-window` at rc=1 with no failed assertion.
Re-run twice on the same build: rc=0, rc=0. **Flaky, not a regression** — and since
it happened to follow a Foundation change, attributing it without re-running would
have been precisely the mistake trap 9 exists to prevent. F29's intermittency is now
known in two GUI verifiers, so a single failing GUI run is not evidence.

Two traps added (23, 24): a signal death discards block-buffered stdout; and a
reproducer written for one defect will often find another.

## 2026-08-10 (late) — F42 fixed; F27 shown to be intermittent; cache cleanup

**Ladder 12/12 RC=0. Corpus 34 matched / 7 diverged / 0 skipped. GUI 5/7.**

### F27: intermittent, and the leading hypothesis eliminated

Three consecutive runs on one build: crash, **no crash**, crash. In the middle run
the save completed, the file was written, and the verifier reached the *reopen* phase
before failing on a colour count. So the save path can work — F27 is not a missing
implementation.

Instrumented every receiver in the late half of `_decodeObjectBinary` (map-hit path,
`className`, all three class lookups, `allocWithZone:`, `initWithCoder:`,
`awakeAfterUsingCoder:`). **3582 decoded nodes, not one suspect value.** That
eliminates last session's leading hypothesis — a raw UID surfacing from `_refObjMap`.

Tested a second candidate: three `CFPropertyListRef` declarations were uninitialised
while the guard below them tests `== nil`, and two feed `CFEqual`, which messages the
pointer. It fit every symptom. Initialising them gave **rc=2, rc=2, rc=2** — not the
cause. The initialisation is kept (undefined behaviour regardless) and **credited
with nothing**.

One self-inflicted detour worth recording: the first traced run looked clean because
the trace's own 400-line budget ran out before the crash — NIB decoding emits ~3600
lines (trap 25).

### Cache cleanup

Host scratchpad 20M → 124K; report aux files removed; VM logs 27M → 940K; docker
images 5 → 2 (two stale `withbsd` tags, referenced by nothing).

**The meaningful space is not cache.** Two parked Lima VMs hold **86 GB** on the
host — `darling-deb` at 78 GB (Lane A, parked by D8) and `darling-arm64` at 7.8 GB
(Fedora, documented as "wrong platform, do not build here"). Host is at 70% (255 GB
free). Deleting them is irreversible and they are documented reference assets, so
they are flagged rather than removed.

Also worth knowing: **deleting files inside the VM does not return space to the
host** — Lima's disk image is sparse and does not shrink (trap 26).

## 2026-08-11 — five new capability areas; report rewritten for the funder

**Ladder 12/12 RC=0. Corpus 51 cases, 38 matched / 13 diverged / 0 skipped.
arm64e coverage 22 cases, 16 matching. GUI 5/7.**

### Five new corpus areas, three defects, two clean passes

Added `NSTask`/`NSPipe`, `NSURL`, `NSRegularExpression`, `NSSecureCoding` and
`NSError`/`NSException`, each for arm64 and arm64e. The pattern held — every new
area has found something on its first run:

- **F43** — `+[NSCharacterSet URLQueryAllowedCharacterSet]` is not exposed, so
  percent-encoding throws. Everything else about NSURL matches macOS exactly,
  including relative resolution and file URLs. The CF-level function
  (`_CFURLComponentsGetURLQueryAllowedCharacterSet`) exists; only the public entry
  point is missing.
- **F44** — `NSSecureCoding` archiving dies with **no output at all** (exit 133).
  Distinct from F42: ordinary keyed archiving works. Same shape as F42 was, so a
  stub is a plausible cause — stated as a hypothesis, not a finding.
- **F45** — a failed file read produces the right error with the **wrong domain**
  (not `NSCocoaErrorDomain`). Everything else in the case matches, including
  `@throw`/`@catch`/`@finally` and range-check exceptions.

**Verified working, and worth recording as such:** `NSRegularExpression` (groups,
templates, case-insensitivity, invalid-pattern errors — exercising vendored ICU
non-trivially) and `NSTask`/`NSPipe`, both exact on both arches.

### A false finding caught before it was recorded

The first NSTask case launched `/bin/echo` and failed with *"Executable path cannot
be executed"* — which read as an NSTask defect. `/bin/echo` **does not exist** in the
Darling runtime, which ships a minimal `/bin`. NSTask was correct; the test was
wrong. Rewritten against `/bin/sh -c`, it passes. Recorded in FINDINGS as a caught
false positive rather than quietly deleted.

### Reliability measured rather than asserted

Ran the capability suite and the graphical verifiers repeatedly on one unchanged
build. The ladder passes **3/3 in 11–13 seconds**. `x11-backend` came back **1/3**
this sweep, having been 3/3 in an earlier one — confirming the intermittency is real
and not tied to any change.

### Report rewritten for its actual audience

Restructured for the person funding the work rather than a mixed technical audience:
what it is in one page, what now works, how we know (and how we avoid fooling
ourselves, including the five withdrawn claims), what was fixed stated by
*consequence* first, what remains with honest costs, reliability data, explicit
decisions for them, and a limitations section. Technical detail moved to appendices.

## 2026-08-11 (extended) — six more areas, four fixes, report re-technicalised

**Ladder 12/12. Corpus 63 cases, 44 matched / 19 diverged / 0 skipped. arm64e 28
cases, 19 matching. GUI 5/7.**

### Six new capability areas, authored in parallel

KVC/KVO, NSPredicate, NSNotificationCenter, NSOperationQueue, NSXMLParser and
NSValue — six agents, one area each, then compiled natively and **checked for
determinism (two runs, identical output) before being trusted**. One needed a fix
(`NSUnknownKeyException` not declared without an explicit import).

### Four fixes

- **F43 — URL percent-encoding did not exist.** Two missing APIs, not one: the six
  `NSCharacterSet` URL character sets, then
  `-[NSString stringByAddingPercentEncodingWithAllowedCharacters:]`. The character
  strings were copied **verbatim from Apple's own source vendored in this tree**
  (`CFURLComponents_URIParser.c:22-28`), which is not compiled here — and the
  submodule's own shim header calls exactly the methods that were missing.
  `t19_url` went from an uncaught exception to an **exact match on both arches**.
- **F47 — `dictionaryWithValuesForKeys:` threw on any nil value.** Assigned nil into
  a dictionary instead of substituting `NSNull`. One line.
- **F49 — `NSOperation` had no name property.** `setName:` existed on the queue but
  not the operation.
- **F50 — `NSXMLParserErrorDomain` was declared and never defined**, so any binary
  referencing it failed to launch.

### Three new defects behind those fixes

Fixing the crashes let the tests run far enough to expose real behaviour:

- **F51 — cancellation is ignored.** An operation cancelled before it starts
  **executes anyway** (`dran:1` vs `0`), and the queue never reports itself drained.
  Functional, not cosmetic.
- **F52 — malformed XML parses "successfully".** No error reported, and the
  document-start/end callbacks never fire. Element and attribute callbacks are
  correct. Code validating input by checking parse success silently accepts garbage.
- **F48 — `@distinctUnionOfObjects` unimplemented.** The other KVC collection
  operators all match macOS.

**Verified working:** NSNotificationCenter and NSValue, exact on both arches.

### Report rewritten again — the funder is a developer

The previous rewrite pitched it at a non-specialist and pushed the technical
substance into appendices. Corrected: added a *Three defects in detail* section
carrying the actual register dumps, the symbolised backtrace, the `DEBUG_BREAK()`
stub, the control tables, and the four-build-cycle story behind the arm64e fix.
The plain-language framing stays as the spine; the evidence is back in the body.
Now 20 pages.

## 2026-08-11 (evening) — four fixes, GUI harness freed from the network, soak built

**Ladder 12/12. Corpus 63 cases, 46 matched / 17 diverged / 0 skipped.
arm64e 28 cases, 20 matching. GUI 5/7.**

### F46 — the graphical harness no longer needs the network

Twelve X11 packages baked into `darling-arm64-dev:guideps`
(`scripts/Dockerfile.gui-deps`), and each verifier's `apt-get` calls guarded on
`command -v xdotool` rather than deleted — so they still work unchanged against the
plain `:latest` image. `verify-controls`: **67–69 s → 29–35 s**, network out of the
critical path. Done first precisely because it is what makes an unattended night
worth running: roughly twice the samples per hour, and a mirror outage can no longer
destroy the data silently.

### Three fixes, all found by the corpus

- **F48 — five KVC operator comparisons were right and six were wrong.**
  `__NSKVCOperatorTypeFromKey` strips the `@` into `operatorName`, then compares the
  first five against it and the remaining six against the still-prefixed `key`. The
  constants are unprefixed, so the whole `@distinctUnionOf…`/`@unionOf…` family could
  never match. Exactly why the arithmetic operators worked and the union family did
  not.
- **F51 — a cancelled operation ran anyway.** `-start` checked `isExecuting` and
  `isReady` but not `isCancelled`. Also emits the `isFinished` notification, which is
  what lets the queue drain.
- **F53 — `NSObject` had no default `-setNilValueForKey:`**, so a documented,
  catchable exception arrived as an unrecognized selector.

Together these took **`t23_kvc` to an exact match on both arches** — accessors,
nested key paths, all five arithmetic operators, the union family, KVO with old/new
values, nested-path KVO, observer removal and all three exception paths.

**New residual: F54** — with cancellation honoured, the queue still does not clear
finished operations from its `operations` array. Execution is correct; bookkeeping is
not.

### Overnight soak built and dry-run

`scripts/95-overnight-soak.sh` plus `96-soak-summarise.sh`, installed at
`~/soak/`. **Principle: measurement only** — no source edits, no rebuilds, no
re-staging, so a night that goes wrong costs only time. Four measurements
interleaved: corpus self-consistency (never checked before), F27 failure rate *with
artifacts kept from both outcomes so a pass can be diffed against a fail*, graphical
reliability, and the ladder as a canary.

Two things the dry run caught before the real run: bash cannot do float arithmetic,
so an hours argument silently produced an empty budget and the loop never ran (now
integer minutes); and a run under ten seconds is counted as an environment failure,
not a test result — conflating those is how nine earlier measurements became
meaningless.

Early signal from the dry run: **the corpus gave identical verdicts for all 63 cases
across runs.** Two runs is weak, but the mechanism works and the night will make it
strong.

## 2026-08-11 — Overnight soak, three fixes, six new corpus areas, and a bad build script

**Result: ladder 12/12; corpus 75 cases, 57 matched / 18 diverged / 0 skipped
(arm64 26/34, arm64e 25/34, Apple-signed 6/7).**

### The soak, and what it was actually worth

Ran eight hours unattended under one rule — *measurement only, no source edits, no
rebuilds, no re-staging* — so that nothing it saw could be an artifact of the machine
changing underneath it. It answered two of its three questions and killed the third.

- **Corpus self-consistency (F55): answered, and clean.** 63 cases × 7 runs, every
  case identical every time, ladder 7/7 as an environment canary. This is the first
  time the instrument every fidelity claim depends on has been checked. The 18
  divergences are stable behaviour, not flakiness.
- **F27 pass/fail diff: unobtainable.** The whole design assumed a pass would turn up
  to diff against a failure. **0 passes in 21 runs.** What it did deliver is better
  than nothing: the "intermittent — one run in three" claim, which came from a single
  success in a sample of *three*, is withdrawn; and because the 21 failures span
  58–297 s, generic slowness is eliminated as the variable.
- **Graphical reliability: worse than reported, and the reporting was the problem.**
  See below.

### The heuristic that was corrupting its own data (trap 28)

The soak labelled any run under ten seconds an environment failure — a rule written
when the only way to finish fast was for `apt` to fail. Once F46 baked the
dependencies into the image there was no network step, so the rule started discarding
*real results*: five genuine `verify-x11-backend` failures, and one genuine **pass**
(`rc=0` in 5 s) logged as a network problem.

Recounting by exit code instead of duration turned "5 of 7 verifiers pass" into
`pty-harness` 6/6, `controls` 6/7, `hello-window` 5/7, `text-view` **2/7**,
`x11-backend` **0/7**. The report had listed `x11-backend` as passing (**F56**).

### Three fixes, diagnosed by reading while the soak owned the machine

Read-only work is the right thing to do while a measurement run is in progress, and
diagnosis has been the expensive half of every fix here anyway.

- **F44** — secure-coding archiving. The predicted `DEBUG_BREAK()` stub was right
  there in the encode path (`NSKeyedArchiver.m:174`); no probe needed. Replaced with
  the `+supportsSecureCoding` conformance check Foundation actually specifies.
- **F45** — wrong error domain on a failed read. `_NSFileIO.m` reported
  `NSPOSIXErrorDomain`; **three** sites (one more than reading had found), now
  `NSCocoaErrorDomain` with the POSIX error kept as `NSUnderlyingErrorKey`. The tree
  was already inconsistent with itself — `NSData.m:891` used the Cocoa domain.
- **F52** — `NSXMLParser`. Not one bug but six: `-parse` ended in an unconditional
  `return YES`, `_parserError` was never assigned, both document callbacks were
  absent, the sole error path raised an unnamed exception, `-eTag:` never checked the
  closing tag, `-abortParsing` was unimplemented. Took two passes — after part 1 an
  *empty* document still parsed as success, because the unclosed-element check keys
  off a non-empty element stack.

Corpus went **46/63 → 52/63** on these three, with no case regressing.

### Two mistakes of mine, both instructive

- **Reverting `NSXMLParser.m` to re-apply the F52 patch silently deleted the F50
  fix**, which lived in the same file. The build then failed on an identifier that
  had worked for days, and the obvious reading of that failure was the wrong one
  (trap 29).
- **`rebuild-cf.sh` had been reporting success for failed builds** (**F61**).
  `ninja … | tail -25` followed by `rc=$?` reads *`tail`'s* status. Failed builds
  reported `rc=0`, the script staged nothing, printed `staged`, and left the previous
  binary for the verifiers to measure. This is trap 10 — the same defect that once
  produced a bogus "11/11 gates pass" — recurring in the build path (trap 30). The
  `tail` also violated the capture-the-first-error rule and cost two rebuild cycles
  on a log that could not contain the answer.

  Fixed with a check that cannot be forgotten rather than with vigilance: the staged
  binary's mtime is compared before and after, and a build that does not move it
  exits non-zero.

### Six new corpus areas — four defects and two clean passes

Authored host-side while the soak ran, then gated: each case compiled for both
arches and **run three times natively requiring byte-identical output** before being
trusted. All 12 binaries passed that gate.

- **Clean:** `NSCache` (`t29`), `NSScanner` (`t30`) — exact match, both arches.
- **F57** — every `NSProgress` **factory method returns `nil`**, so the test never
  held an object and all 11 "zero" readings were messages to nil. The storage
  underneath is genuinely implemented; it is simply unreachable. *(First recorded as
  "stores nothing" — corrected 2026-08-11 after reading the file, which took one
  `sed`.)*
- **F58** — **arm64e-only SIGSEGV in `NSThread`.** The identical arm64 binary matches
  macOS exactly. Across 34 paired cases this is the *only* arch-specific divergence,
  which makes it both a strong endorsement of the PAC work and the single most
  interesting defect open.
- **F59** — **`removeItemAtPath:` cannot delete a regular file at all.** It removes
  via `nftw(3)`, whose `__DARWIN_UNIX03` path returns `ENOTDIR` on any non-directory
  *before* invoking the callback that does the actual `remove()`. *(First narrowed to
  "specific to the close-then-remove sequence, since `t14_fileman` passes" —
  corrected: `t14` removes a **directory**, `t32` a **regular file**. The
  `NSFileHandle` lead was a red herring.)*
- **F60** — attribute runs coalesce across an append where macOS keeps them separate.
  My test comment had asserted the opposite; ground truth won and the comment was
  corrected rather than the expectation quietly dropped.

Deliberate non-assertions in the new cases: `NSCache` eviction (documented as
unspecified), thread IDs and priorities, and locale-formatted `NSProgress`
descriptions. Asserting any of them would manufacture divergences that say nothing.

### Report

Regenerated, 22 pages. Corrects two claims it previously made — `x11-backend` passing
and F27 being intermittent — folds in the measured reliability table, and adds the
new findings. A short 90-minute soak was relaunched on the final build so the next
session starts from measured ground rather than an assumption.

## 2026-08-11 (second block) — three fixes, and two "Darling defects" that were ours

**Result: ladder 12/12; corpus 75 cases, 61 matched / 14 diverged / 0 skipped
(arm64 28/34, arm64e 27/34, host binaries 6/7). Graphical: four verifiers reliable,
one flaky.**

The block was ordered accuracy-first, because the report was about to be sent and
**three of its claims were wrong** — all three mine.

### The three corrections

1. **`text-view` was published as 2/7. It is 15/15.** Between the two soaks that
   produced those numbers, *two* variables had moved: the build changed and the
   machine went from contended (I was running searches, container builds and
   diagnosis on the same VM) to idle.

   Reading the harness supplied a mechanism — the graphical verifiers wait on bounded
   wall-clock loops, some as short as **1.5 seconds**. So we tested it properly: one
   unchanged build, six runs, alternating idle and loaded.

   | round | idle | loaded |
   |---|---|---|
   | 1 | passed, 261 s | failed, 175 s |
   | 2 | passed, 228 s | failed, 184 s |
   | 3 | passed, 100 s | failed, 116 s |

   **3/3 against 0/3.** The published failure rate was measuring *me*. Recorded as
   **F66**. Note the loaded runs failed *faster* than two of the idle runs passed —
   the opposite of "it needed more time", and exactly what a wait loop hitting its
   ceiling looks like.

2. **F57 was diagnosed wrong.** I had written "`NSProgress` stores nothing". In fact
   `NSProgress.m:40-47` — all three factory methods `return nil`, so the test never
   held an object and every "zero" was a message to nil. The accessors underneath are
   genuinely implemented, just unreachable. The distinguishing evidence was one `sed`
   away and I wrote the conclusion without opening the file.

3. **F59's narrowing was a false lead.** I had written that `t14_fileman` proves
   general removal works, so the defect must be specific to the close-then-remove
   sequence. `t14` removes a **directory**; `t32` removes a **regular file**.

### F59 — much worse than filed, and now fixed

`-[NSFileManager removeItemAtPath:error:]` removes via `nftw(3)`, and the actual
`remove()` lives only inside the walk callback. Apple's `nftw.c` refuses to walk a
non-directory — `ENOTDIR`, returned *before the callback runs*. So
**`removeItemAtPath:` could not delete a regular file at all**. Directories worked,
which is exactly why the defect hid behind a passing test.

Fixed by `lstat`-ing the path and invoking the existing callback directly for
non-directories — preserving the delegate contracts rather than calling bare
`remove()`. `nftw.c` was left alone: it is Apple's Libc source and its behaviour
matches real macOS.

### F56 — never passed, and never Darling's fault

`verify-x11-backend` had failed 15/15. Capturing the application's own output showed
its last messages were about **fonts**, and the staged runtime ships none of its own.
Adding a 15 MB CJK font took it from dying in 1–3 s to completing six test stages —
which exposed a *second* missing dependency the first had hidden: `xrdb`.

With both: **`ARM64 X11 backend smoke passed`, 4/4, 6–9 s.** Two of five graphical
verifiers have now had a "Darling defect" turn out to be a missing package in our own
image. The passing runs take 6–9 s, so under the old `<10 s ⇒ environment failure`
rule every one of them would have been discarded.

### F60 — fixed narrowly, on purpose

Attribute runs were coalescing across an append. Cause: the append seam is fused in
place before the appended text's own attributes are consulted. Fixed **only in the
attributed-string path**, because plain string appends carry no attributes of their
own and a single extended run is right for them — and macOS behaviour there is not
established by our evidence. Checked rather than assumed: `_CFRunArrayIsEqual`
compares run *structure*, so the fix could have changed equality semantics; the
corpus's `eq_same`/`eq_diff` assertions still hold.

### Four defects recorded but deliberately not fixed

**F62–F65**, all found by reading source while diagnosing the above: an
out-of-bounds read in `CFAttributedString`; directory removal that **follows symlinks
and deletes their targets**; `truncateFileAtOffset:` using `SEEK_CUR` for `SEEK_SET`;
and path-based `NSFileHandle` leaking its descriptor. None has a failing test, so
none was patched — a fix with nothing to credit it is what trap 9 exists to prevent.
They are labelled as unreproduced in the report.

## 2026-08-11 (third block) — F58 bisected to one statement

**State unchanged and verified: ladder 12/12; corpus 75 cases, 61 matched / 14
diverged.**

Spent the block on **F58**, the arm64e-only `NSThread` SIGSEGV — the most on-mission
defect open, since arm64e is the least independently verified part of the stack and
the identical arm64 binary passes, giving a perfect built-in control.

**Took it from "SIGSEGV, no output, cause unknown" to a single statement**, by
bisection rather than guesswork:

1. **"No output" was false** — trap 23 again. `setvbuf(stdout, NULL, _IONBF, 0)`
   revealed nine completed assertions, including a detached thread running. That
   change is now permanent in `t33_thread`.
2. A reduced probe showed `sleepForTimeInterval:`, `detachNewThreadSelector:` and the
   worker's own body all complete. **The crash is in thread teardown.**
3. Gating `NSThreadEnd`'s three statements behind an env var: skipping the
   notification still crashes; **skipping `[thread release]` makes it vanish**.
4. Tracing `-[NSThread dealloc]`: the crash is on its **first** statement,
   `[_target release]`.
5. Printing the ivars: `_target` is a **valid Class** with an `isa` pointing at its
   metaclass and **no PAC bits**.
6. A standalone arm64e probe that retains, releases and inspects a `Class` works
   perfectly — so "releasing a Class is broken on arm64e" is eliminated.

**A hypothesis I implemented and disproved.** Two function pointers were handed to
pthread through casts to an incompatible type — undefined behaviour, and on arm64e the
textbook pointer-authentication failure, since function pointers are signed with a
type-derived discriminator. It fit the symptom exactly, including *why* only arm64e
would care. Declaring both functions with pthread's own signatures so no cast remains
**changed nothing**. Kept anyway for removing UB, and **credited with nothing** —
the same treatment the uninitialised pointers got in F27.

Best remaining hypothesis, untested: pthread key destructors run in unspecified order,
so objc's thread-local state may already be torn down when this one runs.

**Cost/benefit, honestly:** the block bought a localisation and an eliminated
hypothesis, not a fix. That is a fair outcome for a defect with this shape, and the
eliminations are written down so the next attempt starts where this one stopped
rather than repeating it.

### Also this block — F64 reproduced, then fixed

`truncateFileAtOffset:` seeked with `SEEK_CUR` where macOS uses `SEEK_SET`. It had
been sitting in the read-only group (F62–F65) with no test behind it.

**The existing test could not have caught it.** `t32_filehandle` truncated through a
freshly opened handle, and at position 0 `SEEK_CUR` and `SEEK_SET` are
indistinguishable — the case was structurally blind. Writing three bytes first moves
the position to 3 and separates them, and the run produced exactly the predicted
arithmetic:

```
native : … pre_trunc_off:3 post_trunc_off:5 …
darling: … pre_trunc_off:3 post_trunc_off:8 …
```

Corpus dipped to 59/16 while the new assertion was failing, then returned to **61/14**
with the one-token fix in. The case now carries a regression guard it never had.

That ordering — reproduce, *then* fix — is the template for the three read-only
findings that remain, and F63 (directory removal following symlinks and deleting their
targets) is the one worth doing first, because it is potential data loss.

## 2026-08-11 (fourth block) — a data-loss bug, and the false negative that nearly hid it

**Ladder 12/12; corpus 77 cases, 63 matched / 14 diverged.**

Took the recommendation from the previous block and went after **F63** — directory
removal following symlinks — using the reproduce-then-fix template. It produced two
fixes and the best methodological illustration this project has yet had.

### The false negative

`t35_symlink` builds a bystander directory, puts a link to it inside the tree being
removed, and asserts the bystander survives. First run under Darling:

```
setup link:0 victim:1 inner:1 ~ link_is_link:0 ~ … victim_survived:1 …
```

`victim_survived:1` is the **passing** value. Read casually: F63 does not reproduce.

It was worthless — `setup link:0` says the symlink was never created, so the dangerous
path was never exercised. **Trap 17 in the wild.** Had the case asserted only on its
conclusion and not on its own setup, a data-loss defect would have been filed as
non-existent.

### F68 — the reason the setup failed

`createSymbolicLinkAtPath:withDestinationPath:` called
`symlink([path …], [destPath …])`. POSIX is `symlink(target, linkpath)`, so the
arguments were reversed: it tried to create the link **at the destination**, pointing
backwards. When the destination existed it failed with `EEXIST`; when it did not, it
**silently succeeded in the wrong place**. One-line fix.

### F63 — real, and now fixed

With F68 fixed the test ran properly and the defect appeared at once:

```
native : … victim_survived:1 outside_survived:1 …
darling: … victim_survived:0 outside_survived:1 …
```

Darling deleted a file it was never asked to touch. `nftw` was called without
`FTW_PHYS`, so the walk descended *through* symbolic links. Deleting a folder
containing a link to your home directory would have emptied your home directory.

Fixed by adding `FTW_PHYS`. **Control:** `t14_fileman` — ordinary recursive removal —
still exact on both arches, confirming real directories are still descended.

### Report

Rewritten after a critical read. Three changes: the F68 false-negative story moved
from an appendix row into the method section, because it is the concrete proof of a
discipline the report had only been asserting; the data-loss fix given prominence in
the opening rather than one table row; and the soak's "75 cases" annotated, since the
corpus is 77 today and the two figures looked like a contradiction.

## 2026-08-12 — onto the iTerm2 ladder: Stage 18, a 26.6 cache, and two AppKit fixes

**Stage 10 ladder 12/12, corpus 63/77. Stage 18 built, ladder 12/12.**

The approved plan could not reach its goal, and that was established before spending
the night on it: six of seven iTerm2 gates hard-require a macOS 26.5 dyld shared cache
from a retained restore image we do not have (**F69**). The fallbacks in the plan were
worth the time.

**Stage 18 built independently, in six minutes** (**F70**). Nothing in either repo
builds one. Seeding from copies of the known-good Stage 10 install and the existing
GUI build tree meant only the delta recompiled. JavaScriptCore (45 MB) and
ScreenCaptureKit staged.

**A macOS 26.6 cache works where the ladder pins 26.5** (**F74**) — the single most
reusable result. This host's own cache loads and CryptoKit stops being a blocker
entirely. One trap: dyld derives subcache paths from the main path handed to it, so
the whole set must be aliased.

**Two real Darling AppKit defects, found by running unmodified iTerm2, both fixed:**

- **F72** — `-[NSPopUpButton setTitle:]` called `itemAtIndex:0` with no empty-menu
  guard; iTerm2 sets a pull-down's title before adding items, so it raised and killed
  the app before its first window.
- **F75** — `-[NSWindow disableBlur]` did not exist. *Intermittent*, because iTerm2
  only takes that path for profiles with transparency configured — which briefly made
  F72 look incomplete. A crash gated on saved application state looks exactly like
  flakiness, and this project has now been fooled by that three times.

Combined: three consecutive runs, no exception, window mapping reached, process alive.

**F73 corrected.** I first named `sys_proc_info` as the session blocker. Wrong. The
gate types nothing until it finds a window, and its pre-typing checkpoint is absent
from every run. The real boundary is that **iTerm2's X11 window does not persist**.

**Two of my own errors, both instructive:**

- Reconfiguring a copied build tree with `CMAKE_BUILD_TYPE=Release` when the original
  was empty tripped objc4's debug-ness guard in 25 seconds (**trap 36**).
- Omitting one flag from a fifteen-flag probe configuration silently loaded *Apple's*
  AppKit from the cache instead of Darling's; it died instantly and looked like a
  clean negative result (**trap 37**).

Both are the same lesson the project opened with: change one variable at a time, and
check which implementation actually loaded before trusting an outcome.
