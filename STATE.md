# Darling arm64 — project state

**Goal:** maximise arm64 (aarch64) macOS-translation-layer utility on this M3 Max.
**Decision taken:** build on upstream `darlinghq/darling` + kkHAIKE's arm64 work.
**Rejected:** `GatoAmarilloBicolor/Osxie` — x86_64-only, and strips GPL attribution
from upstream (see `.claude/.../memory/osxie-quality-red-flags.md`). Nothing from
Osxie is used here.

## Why this machine

Darling is a *translation layer*, not a CPU emulator — host arch must match binary
arch. An M3 Max runs **arm64 Linux at native speed** under Virtualization.framework,
and simultaneously provides the *reference implementation*: real arm64/arm64e Mach-O
binaries, Apple's dyld/libSystem, and the macOS 26 toolchain to mint test binaries.
That combination enables differential testing almost no Darling contributor can do.

## Upstream situation

- **PR #1753** (kkHAIKE, `arm64-support`): 9 commits, 168 files, +6185/−1297, plus
  ~30 companion submodule PRs. Claims working: hello world, bash, sh, perl, python,
  uname, HTTP/HTTPS, and **arm64e PAC-signed Apple CLT-26 binaries**.
  Status: `diverged, ahead 9 / behind 11`, `mergeable_state: dirty`.
- **PR #1450** (maintainer CuriousTommy, `feature/arm-support`): earlier attempt,
  stalled draft since 2024-06.
- Upstream cadence is slow (~monthly); 395 open issues. Nobody has independently
  reproduced #1753 — that is the gap we fill.

Technically credible details in #1753 (hard to fake, unlike Osxie's README):
low-VA mmap below 2^47 to dodge ObjC's 47-bit `FAST_DATA_MASK`; arm64e `signPointer`
via raw `.inst` PAC encodings; dyld chained-fixup `0x000C`; `___chkstk_darwin` export.

## Utility ladder (what "% arm64" means)

| Tier | Capability | Claimed by #1753 | Verified by us |
|---|---|---|---|
| 0 | builds on aarch64 | yes | **configure ✓ / build running** |
| 1 | mldr loads arm64 Mach-O, hello world | yes | pending |
| 2 | real Apple CLT binaries incl. arm64e PAC | yes | pending |
| 3 | shell + scripting userland | yes | pending |
| 4 | networking (HTTP/HTTPS) | yes | pending |
| 5 | ObjC runtime + Foundation | — | frontier |
| 6 | libdispatch / XPC / CF-heavy | — | frontier |
| 7 | AppKit / Cocotron GUI | — | frontier |
| 8 | real `.app` bundles | — | frontier |

Tiers 0–4 ≈ 35–40% (a working CLI userland), well past the original 10% target.

## Environment

- VM `darling-arm64`: Lima + `vz`, Fedora 44 aarch64, kernel 6.19.10, 12 cores,
  24GB RAM, 150GB disk. Native — no emulation.
- Host: M3 Max, macOS 26, Apple clang 21, SDK 26.5.

## Corpus (host-side, complete)

`corpus/bin` — 17 binaries with native ground truth in `corpus/truth/native.tsv`:

- arm64: hello, exit42, syscalls, pthread, dispatch, objc+Foundation, CoreFoundation
- **arm64e**: hello, syscalls, objc+Foundation
- Apple-signed host binaries: echo, uname, pwd, basename, true, false, wc

Gotcha recorded: copying an Apple-signed binary invalidates its signature and macOS
SIGKILLs the copy (exit 137). Ground truth is therefore taken from the **original**
paths; the copies exist only as Darling inputs (Darling doesn't check Apple's sig).

## Scripts

| Script | Where | Purpose |
|---|---|---|
| `scripts/00-vm-setup.sh` | VM | deps + clone arm64 tree |
| `scripts/10-make-corpus.sh` | host | build corpus + capture native truth |
| `scripts/20-run-corpus.sh` | VM | run corpus under Darling, score vs truth |
| `scripts/30-build.sh` | VM | staged configure → core → full build |

## Traps already hit (don't re-learn these)

1. **dnf5 rejects the entire transaction** if one package is unresolvable — one typo
   (`libXkbfile-devel` vs `libxkbfile-devel`) silently installed *nothing*.
   Always pass `--skip-unavailable`.
2. **Relative submodule URLs resolve against the current branch's tracking remote**,
   not `origin`. Checking out `kkhaike/arm64-support` with tracking made all 149
   `../darling-*.git` resolve to `github.com/kkHAIKE/*`; the ~118 repos never forked
   failed to clone. Fix: `checkout --no-track` + unset `branch.*.remote`, then
   `git submodule sync --recursive`. Clone from **darlinghq**, redirect only the 31
   kkHAIKE forks via `url.<fork>.insteadOf`.
3. Apple code-signature invalidation on copy (see Corpus above).
4. `git-lfs` is a documented Darling build dependency.
5. **A submodule can sit at the correct pinned SHA with a completely empty worktree**
   if an earlier clone was interrupted mid-checkout. `git submodule status` reports it
   as fine (no `-`, no `+`) and only CMake notices, via a confusing
   "does not contain a CMakeLists.txt file". `src/external/libcxx` and `libcxxabi` hit
   this. Detect with a worktree file-count scan, repair with
   `git -C <sub> checkout --force HEAD -- .`.
6. Nine submodules were left at the *wrong* commit by the first aborted run and were
   only caught by comparing `git ls-tree HEAD <sub>` against
   `git -C <sub> rev-parse HEAD`. **Always verify pinned-vs-actual**, since
   `insteadOf` redirection is transparent and `git config --get submodule.X.url`
   shows the canonical darlinghq URL either way — it proves nothing about routing.
7. **A bash ERR trap's `${BASH_LINENO[0]}` is not the failing command.** Stage 11's
   trap reported the modal-click assertion for days; `$BASH_COMMAND` showed the
   failing command was a `timeout 10s tail --pid=…` eight lines further on. Cost:
   most of the F24 investigation. Always print `$BASH_COMMAND` next to any line
   number. Corollary: **a status of 124 means a `timeout` expired** — if the
   reported line contains no `timeout`, the reported line is wrong. That
   inconsistency was on screen from the first failure and went unquestioned.
8. **Marker/artifact listings captured at failure reflect whichever `$prefix` was
   current**, not the phase that failed. Stage 11 reassigns `prefix` per sub-phase,
   so its failure listing showed only the *later* randr launch's startup markers.
   The absence of `x11-backend-modal-*` looked like "never got that far" and meant
   nothing. Check which phase a listing belongs to before reading absence as
   evidence.
9. **Always run the control before crediting a patch.** `verify-x11-backend` was
   assumed broken by F24; reverting to pristine and re-running gave 3/3 passes. The
   patch was not what made it pass — the test was simply flaky (F29). One revert-
   and-rerun would have caught this at the start.
10. **Verify that a measurement measures what you think it does.** `verifier … |
    tail -25; echo "rc=$?"` reports **`tail`'s** status, which is always 0. That one
    pipe produced a reported "11/11 headless gates pass" for a suite that was
    actually exiting 1, and the claim propagated into a written report. Capture the
    status of the command you care about — `cmd > log 2>&1; rc=$?` — and never take
    a status through a pipe unless `PIPESTATUS` is read explicitly.
11. **`git checkout -- <path>` in the parent repo does not touch submodule paths**
    (`error: pathspec … did not match any file(s) known to git`), and inside a
    submodule it silently reverts *every* local change to that file — including
    unrelated patches applied earlier. Reverting `tools/verify-mini-term-*.sh` this
    way discarded both the F25 prompt-wait fix and the observability patch, which
    then had to be re-applied. Check `git status` in the submodule first, and prefer
    a targeted revert to a whole-file checkout.
12. **Apostrophes cannot appear anywhere inside a verifier body.** The whole script
    is a single-quoted `bash -lc '…'` container argument, so one apostrophe — even
    in a comment — terminates the string and the remainder runs on the host. Hit
    twice now: once in a probe, once in the word "trap's" in a comment I wrote.
13. **When a tool says the input is malformed, first prove the input was read.**
    `plutil` reports an unreadable file and a corrupt file with the same message
    ("input is not a property list"), which sent a whole session into
    `CFBinaryPList.c` when the file had simply been deleted between two
    invocations. Before debugging any parser, confirm the bytes reached it.
14. **A silent diagnostic can be the finding.** The `FAIL_FALSE` trace instrumented
    all 113 rejection sites in the binary-plist parser and printed *nothing* on the
    failing run — which proved the parser was never reached and redirected the whole
    investigation. Distinguish "the probe did not fire" from "the probe is broken"
    by confirming it fires somewhere it should; here it did, on the XML input.
15. **`/private/var/tmp` does not survive a `darlingserver` restart** (before the
    F34 fix). It is `darlingPreInit` at `darlingserver.cpp:237`. If a verifier
    writes a file in one `run_tool` and reads it in the next, that is the first
    thing to check. `/root` persists; `/var/run` is still wiped by design.
16. **When a change appears to have no effect, check you rebuilt the binary that
    actually runs.** `/usr/lib/dyld` links its own static copy of the emulation
    syscalls, so an F37 fix to `abort_with_payload.c` did nothing after rebuilding
    `libsystem_kernel.dylib`, and nothing again after rebuilding `mldr`; it only
    took effect once `src/external/dyld/dyld` was rebuilt. **The signature is a
    fault address that does not move across rebuilds** — here `pc` low bits
    `…CF78`, `lr` `…DB98` and `address=0x39` were identical every time while only
    the ASLR base changed. Third occurrence in this project; the X11 backend was an
    earlier one.
17. **A symptom that stops reproducing is not a fix.** The arm64e recursion crash
    (F33) disappeared during a session and the control showed it was not the patch
    that did it — and re-instrumenting revealed the code path was no longer being
    executed at all, so the fix could not even be re-verified. Before crediting
    anything, confirm the failing path is still *exercised*; a green result from a
    test that no longer runs the relevant code proves nothing.
18. **Symbolise crash addresses properly — it is cheap and it works.**
    `DYLD_PRINT_SEGMENTS=1` gives each image's `__TEXT` base; subtract it from the
    runtime address and look the offset up with `nm -n` on the staged dylib. That
    turned "SIGSEGV at 0x30075B7B8" into `_CFStringGetCharacters + 0x10` in about
    ten minutes, and a frame-chain walk in the signal handler turned "probably
    recursion" into a printed two-frame cycle.
19. **Parse structured diagnostic output structurally.** An `awk` one-liner that
    paired each `dyld: Mapping <path>` line with the *next* `__TEXT at` line and
    then sorted the result manufactured a defect (F38, "images are mapped
    overlapping") out of entirely correct behaviour. `/proc/<pid>/maps` showed 41
    images, zero overlaps, a uniform 1 MB stride. Pairing lines by proximity is not
    parsing.
20. **objc4 has no header dependency tracking.** There are no `.d` depfiles for
    `objc_obj`, so editing a header — `objc-object.h`, `objc-config.h`, `isa.h` —
    **never triggers a rebuild**. Two build cycles were spent on a change that was
    in the source and not in the binary. Force it:
    `find src/external/objc4 -name '*.o' -delete` before rebuilding. Sharper-edged
    cousin of trap 16.
21. **`objc-object.h` defines `isa_t::getClass()` twice** — once in the
    `SUPPORT_NONPOINTER_ISA` section (~line 234, the one with `ISA_MASK`) and once
    in the `#else` section (~line 987). Darling/arm64 sets `SUPPORT_PACKED_ISA 0`,
    so the **second** is what compiles and the first is dead code. Check which
    branch of a `#if` you are actually in before editing a header with duplicate
    definitions.
22. **In zsh, `path` is a special array tied to `$PATH`.** Assigning
    `path=usr/lib/foo.dylib` inside a loop wiped the environment and produced
    `command not found: wc` / `python3` from a script that had been working. Never
    use `path` (or `cdpath`, `fpath`, `manpath`) as an ordinary shell variable.
23. **A signal death discards a block-buffered stdout.** A corpus binary that died
    with SIGTRAP printed *nothing*, which looked like "it fails before main". It had
    in fact run several statements; stdout is block-buffered when it is a pipe, and
    the buffer went with the process. `setvbuf(stdout, NULL, _IONBF, 0)` in the
    debug variant made the checkpoints appear immediately. Before concluding a
    program produced no output, make sure output could have escaped.
24. **A reproducer written for one defect will often find another.** `t17_archive`
    was written purely to give F27 a fast headless loop; it reproduced a crash on
    its first run — in the archiver, not the unarchiver (F42). Building the cheap
    reproduction first is worth it even when it does not reproduce the thing you
    were chasing.
25. **Do not let a diagnostic's own budget hide the failure.** An F27 trace was
    bounded to 400 lines to avoid burying the crash in output; NIB decoding emits
    ~3600, so the budget ran out *before* the crash and the run looked clean. If a
    bounded trace ends without reaching the event, the bound is the first suspect.
26. **Deleting files inside a Lima VM does not return space to the host.** The disk
    image is sparse-allocated and does not shrink. Only removing a VM
    (`limactl delete`) reclaims host space; in-VM cleanup is tidiness only.
27. **The graphical verifiers install packages from the network on every run.** A
    transient DNS failure produced nine `rc=100` failures in under ten seconds each,
    which look exactly like test failures. Before reading any graphical result as a
    defect, check the run took a plausible length of time — a real run is 55--350
    seconds, an apt failure is under ten.

28. **Trap 27's own guard became wrong once F46 landed — a fast run is now a
    legitimate pass.** The `<10 s ⇒ environment failure` rule was written when the
    only way to finish quickly was for apt to fail. With the GUI dependencies baked
    into the image there is no network step, so a genuinely fast *success* now trips
    the guard: the soak logged `verify-hello-window ENV-FAIL rc=0 secs=5` — return
    code **zero**, i.e. a pass, discarded as an environment failure. The duration
    heuristic must be conditioned on `rc` (only a *non-zero* result under 10 s is
    suspect), and any graphical reliability figure computed before this correction
    **undercounts passes**. General lesson: a heuristic that encodes a workaround
    outlives the problem it was written for, and then silently corrupts the data it
    was added to protect.

29. **Reverting a file to re-apply one patch discards every OTHER patch in that
    file.** `git checkout -- src/NSXMLParser.m`, done to re-apply the F52 patch with
    a corrected import list, silently reverted the **F50** fix
    (`NSXMLParserErrorDomain`) which lived in the same file. The next build failed on
    an undeclared identifier that had been working for days, and the obvious reading
    — "my new patch is wrong" — was wrong. This is trap 11's shape at file scope
    rather than submodule scope. Before reverting a file, list what is already
    patched in it: `grep -c "DARLING-ARM64 FIX" <file>`, and re-apply every patch
    script that touches it afterwards.

30. **`$?` after a pipeline is the pipeline's LAST command — this bit us a second
    time, in the build script.** `ninja … | tail -25` followed by `rc=$?` reads
    `tail`'s status, so failed builds reported success and the script went on to
    stage, leaving the previous binary in place for the verifiers to measure. See
    FINDINGS.md F61. Two defences now in `scripts/rebuild-cf.sh`: no pipe on the
    command whose status matters, and a before/after mtime check on the staged
    binary so a no-op staging is loud instead of silent. Trap 10 said this about
    test harnesses; it applies to *every* pipeline whose status is read.

31. **Do not use the VM while a soak is measuring on it.** The graphical verifiers
    wait on bounded wall-clock loops, some as short as 1.5 s, so their pass rate is
    partly a property of machine load. A published `text-view` failure rate (2/7)
    turned out to be measuring my own concurrent greps and container builds; a
    controlled experiment on one unchanged build gave **3/3 idle pass, 0/3 loaded
    fail**. Any graphical number collected while the machine was also being worked on
    is void. See FINDINGS.md F66.

32. **Two tests calling the same selector are not necessarily testing the same code
    path.** F59's narrowing said `t14_fileman` proves `removeItemAtPath:` works, so
    the defect must be specific to the failing test's use of `NSFileHandle`. `t14`
    removes a **directory**; the failing test removes a **regular file**, and the
    implementation routes those through completely different code. The real defect —
    regular files could not be deleted at all — is far worse than what was filed.
    Before treating a passing test as proof of a capability, check it exercises the
    same path.

33. **A missing dependency in our own image reads exactly like a defect in the
    software under test.** `verify-x11-backend` failed 15/15 and was catalogued as a
    Darling defect; it was a missing CJK font, and then a missing `xrdb` hidden behind
    it. That is the second time (after F46) an image gap was recorded against Darling.
    When a graphical test fails, capture the *application's own* stdout/stderr — the
    verifiers bind-mount an artifact directory that survives the `--rm` container —
    before concluding anything.

34. **Do not take this project's own summary notes as the baseline.** `STATE.md` and
    `HANDOFF.md` said "nothing rendered" before this effort. The repository's own
    `darling-aarch64-north-star-iterm2.md` records Stages 11–19 complete three weeks
    earlier, including unmodified iTerm2 running with tabs and splits. Two reports
    shipped with a false baseline because the primary source — in the repo being
    pushed to — was never opened. See FINDINGS.md § CORRECTION 2026-08-12.

35. **Locate the artifact set a goal is defined against before judging progress
    toward it.** Every iTerm2 gate needs `install-arm64-stage18` and
    `build-arm64-stage18` plus two images this workspace never had. All work here ran
    on `install-arm64-stage10`. The iTerm2 ladder was not failed — it was never
    entered, and nobody noticed for the whole effort.

36. **Do not change a build variable you were not asked to change.** Seeding a
    Stage 18 build by copying `build-arm64-gui` and reconfiguring, I added
    `-DCMAKE_BUILD_TYPE=Release`. The original had it *empty*. Release added
    `-DNDEBUG`, which flipped `DEBUG` off while objc4's `OBJC_IS_DEBUG_BUILD` stayed
    1, and objc4's own guard fired: `error: mismatch in debug-ness macros`. Cost 25
    seconds because the guard is good — but it is the same "change one variable at a
    time" lesson this project opened with. When reusing a configured build tree,
    change only what the new target requires and nothing else.

37. **Copy the whole environment when reproducing someone else's gate.** Omitting a
    single flag (`ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1`) from a fifteen-flag probe
    configuration silently swapped Darling's AppKit for Apple's out of the shared
    cache. Apple's AppKit cannot work on Linux and died instantly, so the run measured
    nothing while looking like a clean negative result. Check *which* implementation
    loaded — frame addresses distinguish them — before trusting any outcome.

38. **`local a=$1 b="$a/x"` reads `$a` from the *outer* scope.** Bash evaluates every
    right-hand side in a single `local` declaration before any of the new locals is
    visible, so a later item referring to an earlier one silently picks up whatever
    (if anything) that name meant in the caller. Under `set -u` with no such global,
    it aborts with `unbound variable`; with a global present it quietly uses the wrong
    value, which is worse. In `prepare-macos-shared-cache.sh` the bug survived the
    `--check-only` path *only* because a global `root` happened to mask it, and
    surfaced solely because a synthetic staging test exercised the other caller. Split
    the declarations. Corollary: a helper that behaves differently depending on which
    caller invoked it is reading something it was not passed.

39.–41. recorded inline in the 2026-08-13 session notes below (subagent citations are
    leads not evidence; artifact numbers from archives not memory; `--force` destroyed
    uncommitted submodule build fixes).

42. **`pkill -f <pattern>` matches its own invoking shell** when the pattern appears
    in the command line being executed (it always does — the pkill argument is part
    of it). A cleanup step `pkill -9 -f f100-spawn-probe` SIGKILLed the very
    `bash -lc` block it was the first line of; the block died with exit 255 and none
    of the following commands ran, silently. Use a pattern that cannot match the
    caller, `pkill -f '[f]100-spawn-probe'`, or match on the process name.

43. **`$(grep -c X f || echo 0)` yields *two* lines when the count is zero** —
    `grep -c` prints `0` *and* exits 1, so the `|| echo 0` appends a second `0`. The
    variable becomes `"0\n0"`, and the next `$((sum+var))` dies with a syntax error —
    which under plain `set -u` does not stop the script, so counters silently stop
    accumulating. An entire 50-run instrumented campaign produced an empty log this
    way. Use `v=$(grep -c X f); v=${v:-0}` or `|| true` outside the substitution.

44. **A line-filter revert does not undo a structural edit.** Instrumentation that
    *rewrote* a condition into two blocks was "reverted" by deleting all lines
    containing the marker — leaving a semantically dead but real empty `if` block in
    `kern_synch.c`, invisible to the `grep -c MARKER` cleanliness check that then
    reported 0. Only `git status`/`git diff` **inside the submodule** told the truth.
    Rule: patchers must apply and revert by exact-string replacement of whole blocks,
    and cleanliness is verified by git, never by marker greps.

45. **LaTeX `geometry` with a small explicit `bottom=` silently clips page numbers**:
    the article default `\footskip` (30pt) exceeded `bottom=1.0cm` (28.4pt), placing
    the folio baseline below the physical page. The digits rendered with their bottom
    stroke cut off and `pdftotext` could not extract them at all — on paper they
    would vanish. Set `footskip=` inside the geometry options whenever `bottom=` is
    explicit, and verify with `pdftotext | grep -cE '^[0-9]+$'`.

46. **`DSERVER_LOG_LEVEL=debug` is a flake amplifier, in both directions.** Heavy
    per-event logging reorders Darling's cooperative microthread scheduling enough to
    drive the session-spawn flake from ~1–2% to 13/14 ≈ 93% (F100). As a hazard:
    debug-mode reliability numbers are *not* production numbers — never quote one as
    the other. As a technique: it turns a rare timing-sensitive bug into an on-demand
    repro, powering small-n A/B/A validation (~8 min per 14-run phase).

47. **When stripping a verifier down to a minimal probe, keep the entire launch
    environment.** The first lean spawn-probe kept only `SHARED_CACHE=1` and dropped
    the gate's other bootstrap env (`FULL_LAUNCHD`, `APPKIT_BOOTSTRAP`, `DIRECT_PTY`,
    `DISABLE_METAL`, …); iTerm2 then stalled at startup in every run — 100% false
    "fail" that mimicked the very flake under study, on both roots. Diff the gate's
    complete `env` block before trusting any stripped harness; strip *workflow*, not
    *bootstrap*.

48. **Verify what a scratch root is *derived from* before treating it as a proxy.**
    `install-arm64-id26` was used as the A/B/A root all block; only afterwards did
    `tools/f95-identity-26.sh:34,43` reveal it is a copy of **stage10** configured with
    `-DDARLING_EMULATED_OS_PRODUCT_VERSION=26.5` — a stage10/26.5 hybrid, not a stand-in
    for the reviewed stage18 runtime. It fails the full Silver gate at ~100% in every
    condition, which was misread for hours as "debug logging amplifies the flake to 93%".
    The A/B/A survived (one root, one variable) but the rate framing did not. This is
    trap 35 wearing a different hat: locate the artifact set before interpreting a number.

49. **A 100% failure rate is a claim about the environment until a control says otherwise.**
    The no-debug run came back 15/15 fail *with* the new fix, which looks exactly like
    "the fix broke it". The control (same root, same conditions, fix reverted) was also
    12/12 fail — the fix was innocent. Never publish a treatment number without the
    matching control, especially when the treatment looks bad.

50. **`__simple_abort()` cannot abort from inside `sigexc_handler`.** SIGABRT is in the
    handler's own `sa_mask` (`sigexc.c:324`), so `sys_kill` returns and control falls
    through into `brk #1`. Every such failure therefore surfaces as **TRAP_BRKPT**, never
    SIGABRT — do not read a `brk` trap as proof of a deliberate runtime `CRASH()` without
    checking whether it came from an abort that could not deliver.

51. **The diagnostic you need may be printed to a pty you are not capturing.** The
    `*** dserver_rpc_interrupt_enter failed with code -32 ***` line that names mode B's
    cause goes to **fd 1** (`simple.c:380`) — the session child's pty slave — so it
    appears in no artifact. Worse, the `kern_printf` that *would* have reached
    `dserver.log` sits at `sigexc.c:449`, **after** the abort at `:446`. Swapping those
    two lines would have turned a multi-agent investigation into a five-minute one.

52. **For a timing-sensitive crash, core dumps beat tracing.** `strace` (even filtered)
    slowed iTerm2's startup enough that the bug vanished entirely — 0 crashes in 4 runs,
    a false "fixed" signal. Core dumps cost nothing until the process dies. And Darling
    cores are richer than they look: `sigexc_handler` logs the guest addresses of its own
    `siginfo`/`ucontext`, those pages are in the dump, so the **original** signal's
    `si_code`, faulting PC and registers can be recovered even though the process died of
    a re-raised default-action signal (`tools/f101-core-origsig.py`).

53. **`git-lfs` really is a build dependency — and it was never installed in `darling-ns`.**
    Trap 4 recorded it years of sessions ago; nobody checked. The consequence was not a
    build failure but something quieter: 39 Swift SDK overlays staged as **130-byte
    pointer files** that load as nothing. That is what F71/F87's "39/209 dylibs are LFS
    pointers" hygiene line always was, and it sat unconnected to a blocked stage until
    Stage 20 hit it. Check `git lfs ls-files` in any submodule whose artifacts look
    impossibly small.

54. **"The library is missing" and "the library is the wrong architecture" are different
    findings — decode the fat header before concluding either.** Fetching the real Swift
    overlays felt like the fix; `file` then showed all 44 are **x86_64-only**. On a
    translation layer (not an emulator) that is fatal for arm64 and no amount of staging
    fixes it. One `python3` fat-header decode separated a staging bug from a capability
    boundary in seconds.

55. **A stage can be blocked far earlier than the recorded boundary says.** Kevin's
    Stage-20 notes describe blank Settings labels and an "Anura couldn't be loaded"
    alert — GUI-layer symptoms. Our attempt never reaches GUI code at all: it dies in
    dyld resolving a Swift type descriptor. When a reproduction lands *earlier* than the
    record, treat the gap as unexplained and ask, rather than assuming the record was
    optimistic or that your environment is equivalent.

56. **Nothing that is not pushed may live only in `/private/tmp`.** macOS prunes
    `/private/tmp` on its own schedule (files untouched ~3 days). On 2026-09-16 the
    session scratchpad was found empty: the staged-but-unpushed `darling-arm64` public
    repository (three commits, 275 files), its slop.cash bundle, and the slopdotcash
    clone were gone. Everything was reconstructible — canonical docs in `~/darling`,
    drivers in the VM, written files in the session transcript — but it cost a full
    rebuild, and it would have been unrecoverable for anything written only there.
    Stage anything unpushed under `~/Documents` (or push it), never under `/tmp`.

## Current status (2026-08-13, cold-host verdict) — LATEST

- **F94 complete and parked: no path reaches a cold-host build.** Eight measured
  layers: private repos → broken relative submodule URLs → unprefixed names → 35
  renamed forks (unguessable) → shallow-vs-pins → HIS default branch pins an
  unpublished dyld commit → his bootstrap single-branches submodules past their
  pins + requires undocumented authenticated `gh` → his build scripts assume
  environment prep only his (uncompletable) bootstrap provides
  (libsystem_sandbox link, 37 s). Banked numbers: reviewed-branch recursive clone
  **29m00s**; images 197 s. Working 72-rule rewrite table in
  `scripts/f91-cold-host.sh`. Upstream fixes enumerated in F94. `darling-cold` VM
  stopped, state preserved for daylight resumption if wanted.
- Everything else from the approved 8-hour plan: delivered (see previous block —
  F88–F93, leak fix ABA, note updated to 3 pages).

## Current status (2026-08-13, plan-execution morning)

- **F89: the resize leak is FIXED, full ABA.** Baseline 4,768 KiB/resize (47/47
  positive) → two one-line release hunks → **419 KiB (−91 %), shrinks now free
  memory** → revert → 4,767 KiB (pathology returns exactly). Patched gates all
  green (ladder, text-view, 3× Silver). Cocotron branch `f89-leak-fix`. Residual
  +419 KiB/resize needs a patched-build soak to characterize.
- **F93: the NSPopUpButton delta answered** — `DARLING_EMULATED_OS_PRODUCT_VERSION`
  26.5 (his) vs 12.4 (ours, verified in CMakeCache). @available forks EVERYTHING;
  our Silver runs exercised legacy paths, his Tahoe. 26.5-identity rebuild + tier
  re-run is the queued experiment; prime suspect for the quit-dialog difference.
- **F91: his Jul 14–16 tail regresses unmodified iTerm2** (setAlphaValue crash;
  silver-tabs fails fatal-diagnostic). Merge done properly (submodule-level, clean;
  branch local: `north-star/gap-integration` + cocotron/foundation
  `gap-integration`). NOT pushed (not fully green per pre-authorization).
- **F88/F90/F92 harvested**: Silver cumulative tabs 20/23, tab-close 31/36, splits
  19/21 (~87 %); flake = zero-session family (captured with artifacts); soak 12-run
  tally (clean 4 / vanish 6 / launch 1 / app-exit 1); quit dialog never *created*
  on terminal path (0/11) vs settings 2/2; leak model 8.9+8.4 KiB/kpx R²=0.94.
- **Trap 41** hit and fixed: bash/liblzma arm64 fixes were uncommitted worktree
  state, destroyed by `--force`, reconstructed and committed (`arm64-build-fixes`).
- Note updated to 3 pages (both formats, clean, still stamped `c14f4854`):
  results/flake honesty, F89 fix, F93 answer replacing the ask, F91 regression,
  quit-dialog creation-level result. Cold-host VM provisioning; number follows
  separately.
- **Decision queue for the user:** send the note; push FINDINGS/harnesses (restamps
  head); push gap branch? (held — not green); offer f89-leak-fix upstream to Kevin.

## Current status (2026-08-12 night, Kevin-corpus interiorized)

- **KEVIN-RECORD.md now exists (project root, 248 KB, itemized, cited)** — digests
  of everything he wrote: the 5,932-line north-star doc, 8 aux docs (4 never read
  before: roadmap, port-report, rejected-PR audit, COMPATIBILITY), all issues, and
  his 311 July commits. Raw sources in `kevin-record/raw/`. **Standing rule (user,
  emphatic): consult it before ANY claim about his repo** — memory
  `kevin-record-canon` enforces this across sessions.
- **`report/KEVIN-TIMELINE.pdf`** — one-page visual of his eight-day arc (Jul 9
  start → Jul 10 ladder day → Jul 11 apps+cache route → Jul 12 plumbing → Jul 13
  first window→Bronze → Jul 14 Silver day (our fork base ~11:28 mid-day!) → Jul 15
  CotEditor → Jul 16 last push).
- **Date corrections from his history:** his first iTerm2 window was **Jul 13
  09:24** (not Jul 11 as we'd been saying); Silver gates passed early Jul 14
  (pre-fork-base), Silver *completion* + soak→workload replacement post-fork-base.
  Note fixed in both formats.
- Note also now: acknowledges his Jul 14 workload redesign (our ceiling advice was
  already implemented by him), cites his own 44,020 KiB/12-interaction leak log
  (~3.7 MB/iter — corroborates our ~3.6), scopes Silver claim to his runner's three
  gates, discloses fork gap.

## Current status (2026-08-12 night, F88 overnight run)

- **Overnight driver running** (`scripts/f88-overnight.sh`, launched 22:33, ~6h,
  report lands at `~/darling/f88-overnight/OVERNIGHT-REPORT.md` on the VM):
  A baseline control → B Silver ×15 each + settings-persistence → C bronze soak ×4
  (whole-dir archived) → D quit-dialog observers on both paths (was a 510×126 window
  ever *created* on the bronze path?) → E leak model validation (16-step mixed
  non-alternating resize sequence) → F **110-commit gap integration on LOCAL branch
  `north-star/gap-integration`** (merge origin default, rebuild, ladder, gates incl.
  first-ever `silver-workload` run). **Nothing pushed overnight** — morning review
  decides.
- **Fork-gap discovered tonight** (via terminology check!): our branch forks at
  `3e41a1ca` (Jul 14, 11:28 UTC); Kevin pushed 110 commits Jul 14–16 incl. a 4th
  Silver gate (`silver-workload`) and Cocotron view-scaling work. His last activity:
  Jul 16. Note updated with scoping; his Jul 11 iTerm2 run predates the fork.
- **Note to Kevin rewritten compact** (user: too wordy): 2 pages, TikZ timeline
  carries the mistake story, 4 tables, screenshot pair as the causal diagram. Both
  `.md`/`.tex` in sync, head `c14f4854` stamped. Timeline claims now dated (11 Aug,
  "opening days" — never "weeks"; user corrected an overstatement).
- Morning ritual: read `OVERNIGHT-REPORT.md`, decide on pushing the scratch branch,
  update the note's stats if B-phase upgrades 5/5 → 15/15+ before the user sends.

## Current status (2026-08-12, F85/F86 block)

- **F85 — resize direction resolved.** A three-size cycle (700×450 → 900×600 →
  1100×750 → 900×600) reaches the *same* target from both directions in one process:
  **grown into = 5,685 KiB, shrunk into = 3,403 KiB, n=12 each, 1.67×.** Direction is
  real — and size matters too (1,555 / 3,403 / 5,685 / 8,194 KiB at 315k / 540k /
  540k / 825k px), so neither factor alone was right. **47/47 resizes leaked; none
  free.** Marginal cost/pixel similar both ways (~8.8 vs ~8.2 KiB per 1000 px) with
  ~2 MB extra on grow — model unvalidated (2 points/direction), so only the ordering
  and ratio are claimed.
- **F86 — the quit dialog is path-dependent, settled.** At `ITERM2_SOAK_SECONDS=30`
  (3 iterations, live window, clean workload) the dialog is still absent, **0/2
  usable runs**. Duration and iteration count are NOT the variable; `super+q` to the
  terminal window never produces a dialog at any duration, to the Settings window
  always does. Why remains unestablished — candidates named, none claimed.
- **Bronze soak, 8 runs:** clean 4, mid-run vanish 2, launch-stage 1,
  `application-exited` 1 (new, fifth mode, one occurrence). Quit dialog found in
  **0 of 7** runs reaching the quit stage.
- Pushed `7cd4664a`. Note + PDF regenerated (4 pages, F1–F86).
- **Next, in value order:** why the two quit paths differ (focus? sheet vs window?
  session count?); the mid-run vanish; generalising F82's three load-bearing flags;
  clean-host bootstrap timing (issue 2's actual number).

## Current status (2026-08-12, F84 block)

- **The soak leak is localised** (F84): per-resize and proportional to window area.
  All 147 RSS deltas positive, rate constant, and the split is exact — 760×500
  iterations leak 2,274 KiB, 900×600 leak 5,049 KiB. Suspect: the X11
  backing-store / image-buffer path (a 900×600 RGBA buffer is ~2.1 MB). Curve saved
  at `f84-rss-curve.txt`.
- **The quit-dialog finding has been wrong TWICE and is now stated as measurement
  only.** F83 said "late-session degradation" (invalid contrast). I then said the
  settings gate "never shows a confirmation dialog" and generalised to *modal alerts
  never map* — **also wrong**: `settings-persistence-{first,relaunch}-quit.txt` show
  a 510×126 dialog **found and clicked twice** (`0x6000df`, `0x6000b0`).
  `QUIT_CONFIRM` is read at probe `:2043` only and gates whether the *bronze* path
  polls; it suppresses nothing. Supported facts only: bronze quit path never finds
  the dialog (5/5, 89 s–30 min); settings quit path finds it (2/2). Discriminator
  **unestablished**.
- **The leak is NOT proportional to window area** (1.42× area → 2.22× leak), and
  target size is **perfectly confounded with grow-vs-shrink** (strict alternation).
  Scroll effect is +330 KiB at ~4σ, not the "~130 KiB, noise" first written.
  Measurement stands; mechanism claims withdrawn.
- **"The author's 97 iterations" was never traceable** — it came from a subagent
  citation I did not verify, and is removed everywhere.
- **Soak reliability, 5 runs:** workload clean 2/5 (148 and 28 iterations), mid-run
  window vanish 2/5 (iterations 20 and 6), launch-stage failure 1/5 (soak never
  entered — artifacts lost to the shared-directory overwrite; `f84-short-soaks.sh`
  now archives the whole directory per run).
- Pushed `76a79b12`. Note + PDF regenerated with all of the above.
- **Trap 39:** asserting a contrast between two runs without verifying they
  exercise the same code path. Three wrong diagnoses now (F73 `sys_proc_info`,
  F83 late-session, F84 modal-mapping) — and every time, the deciding artifacts
  were already on disk, unread.
- **Trap 12 recurrence (fourth time):** an apostrophe inside a single-quoted
  `bash -c '...'` container argument. Hit again on 2026-08-12 *in a comment* I wrote
  while fixing a different bug in the same block ("container's shell"). Knowing the
  trap is not enough — grep the block for `'` before shipping it. Compounding error:
  I ran `bash -n script && echo OK` and the copy-to-VM on a *separate* line, so a
  failed syntax check did not stop the push. Gate the push on the check.
- **Trap 41:** the perpetually-dirty submodules (`bash`, `liblzma`) were carrying
  **uncommitted arm64 build fixes** in their worktrees — and `git submodule update
  --force` destroyed them, breaking the next build with x86 `-msse` flags on arm64.
  "Dirty but ignorable" state that every session tiptoes around is a landmine, not
  furniture: commit such fixes to a named branch immediately (now done for liblzma
  as `arm64-build-fixes`; bash pending its next failure to reveal what its fix was).
- **Trap 40:** a subagent's citation is a lead, not evidence. The "97 iterations"
  figure was quoted with a file and line range that does not contain it, and reached
  a document bound for the funder. Verify any number a subagent attributes to a
  source before repeating it.

## Current status (2026-08-12, hardening block)

- **Stability measured: 16/16.** Silver tabs 5/5, tab-close 5/5, splits 5/5 (zero
  flakes, 20–33 s/run), settings-persistence **passed its first-ever run** (F81).
- **Bronze soak run twice** (F83): the 30-min workload completed clean once (148/148
  round-trips, 12/12 pastes) and failed flakily once at iteration 20 (window
  vanished, 1-in-2, unexplained). Gate edges fail genuinely: post-soak quit dialog
  never appears after a long session (works in a fresh one — NOT a general modal
  failure), and a real ~3.6 MB/iteration RSS leak overflows the fixed ceiling at
  this machine's 148-iteration pace (author's 97 stays under).
- **Generalisation debt measured** (F82): of the six iTerm2-specific bootstrap
  behaviours, **load-bearing = DIRECT_PTY, STABLE_KEYBOARD_SOURCE,
  DISABLE_LOCALE_DISCOVERY** (named failure shapes, all silent); OPAQUE_TEXT,
  DISABLE_METAL, APPKIT_REOPEN survived single-run ablation.
- **Note to Kevin is a 3-page PDF**: `report/NOTE-TO-KEVIN.pdf` (three screenshots:
  execvp banner, live prompt, two-tab gate evidence). Head stamped `e79277f2`.
- Pushed `e79277f2`: FINDINGS.md F1–F83, f81/f82 harnesses, scrot →
  Dockerfile.gui-deps (was only a hand-committed local image layer).
- Next frontiers, in value order: the late-session quit-dialog failure + RSS leak
  (F83), the 1-in-2 soak window-vanish, generalising the three load-bearing flags,
  multiserver-without-DIRECT_PTY, clean-host bootstrap timing (issue 2's number).

## Current status (2026-08-12, Silver block)

- **THE COMPLETE SILVER TIER PASSES** (F80): tabs (shells 76/82, typed round-trips),
  tab-close (76 closed, 81 survived), splits (pane 77 closed, 82 survived) — all
  exit 0, one run each, on the hand-built Stage 18 with the macOS 26.6 cache. First
  reproduction of the Silver tier outside its author's machine. Bronze soak NOT run.
- **Root cause of the dying window was one missing binary** (F79): the default
  profile runs `login -fp root` and `/usr/bin/login` (component `cli`) was never in
  our staged runtime. Photographed: iTerm2's own execvp banner on screen, then with
  login staged, a live `Darling [~] #` prompt. The libinfo-1102 suspect is cleared —
  those lines appear in passing runs too.
- **Two of our environment gaps fixed** (F56's class): GUI image lacked `scrot`
  (evidence step swallowed by `|| true`), VM lacked `rg` (gate's fatal-diagnostic
  `if rg` check silently skipped — re-ran it by hand before believing the pass).
  Image tag `darling-arm64-gui-test:pre-scrot` preserves the before state.
- **F72 addendum**: Apple's real behaviour measured natively — no throw, no item
  created, title dropped. Our fix keeps the title (more generous); flagged to Kevin.
- Bootstrap now stages `login` and verifies it landed; measured single uninterrupted
  run 6m34s (bootstrap-run5.log). Note to Kevin fully rewritten after a 6-agent
  adversarial fact-check (5 must-fixes found and applied, incl. "six of seven gates"
  → five, stitched 7m40s → measured 6m34s).

## Current status (2026-08-12, F77 block)

- **F77: the window question is answered, and the answer relocates the frontier.**
  Live substructure-event capture (observers `docker exec`ed into the probe's own
  container; probe unmodified) shows iTerm2's terminal window mapped and visible for
  **1.42 s**, then **withdrawn and destroyed by the client itself** — followed by an
  alert-shaped window that lives 20 ms. End-of-run process table: **iTerm2 has zero
  children; no shell ever spawned.** The window closing is iTerm2's own zero-session
  policy, not an X11 defect. Frontier moves from the X11 backend to **session launch
  under full launchd**.
- Prime suspect (suspect, not conclusion): `com.apple.system.opendirectoryd.libinfo`
  bootstrap pipe lookup fails ×8 **while opendirectoryd is running** — the
  `getpwuid()`/`pw_shell` resolution path. Cheapest discriminator: grep Kevin's
  working-run logs for the same `1102` line; if present there too, the suspect is
  innocent.
- Note to Kevin rewritten as one coherent document (`report/NOTE-TO-KEVIN.md`):
  answers "why couldn't you continue from my iTerm2" directly, contains the F77
  result and two questions only he can answer cheaply. Adversarial fact-check
  workflow run against it before sending.
- Harness: `scripts/f77-window-lifecycle.sh`; artifacts
  `~/darling/artifacts/f77-window-lifecycle/` on the VM.

## Current status (2026-08-12, bootstrap block)

- **The Stage 18 on-ramp now exists** (F76): `tools/bootstrap-iterm2-stage18.sh` plus
  `tools/prepare-macos-shared-cache.sh`. From a seeded Stage 0–17 runtime to a launched
  unmodified iTerm2 in **≈7 m 40 s** (resume: 75 s), on a disposable prefix, with the
  capability ladder passing 12/12 and `JavaScriptCore` at 45,348,976 bytes — the same
  size as the hand-built Stage 18 of F70.
- **Filed against issue 2, and it does not close it.** A clean-host timing is not
  measured, and the "short iTerm2 terminal check" cannot run because the window does
  not persist. The script prints both gaps itself.
- **F73's published diagnosis was wrong and has been retracted in place.** The boundary
  is that iTerm2's X11 window does not persist; `sys_proc_info` is noise on an
  unrelated polling path. The original text is retained under a `<details>` block so
  the error stays auditable. The note to Kevin already carried the correction — the
  findings file did not, and that contradiction is now closed.
- Reproduced through the bootstrap: `MapNotify` ×2, no uncaught exception,
  `status=running`.

## Current status (2026-08-11, second block)

- **Ladder 12/12.** Corpus **77 cases: 63 matched / 14 diverged / 0 skipped**
  (arm64 29/35, arm64e 28/35, Apple-signed host binaries 6/7).
- **Graphical: four verifiers reliable, one flaky.** `controls` 15/15,
  `text-view` 15/15, `pty-harness` 15/15, `x11-backend` **4/4 after F56 was fixed**
  (0/15 before), `hello-window` 5/6 (was 6/15). `mini-term` is F30, a test defect.
- **Corpus validated against itself across two builds** (F55): 63 cases × 7 runs, then
  75 × 16. Zero flapping in 23 runs.
- F27: **0 passes in 69 runs across two builds.** Not intermittent.
- Fixed this block: **F56** (image had no CJK font, then no `xrdb` — both ours, not
  Darling's), **F59** (`removeItemAtPath:` could not delete a regular file at all),
  **F60** (attribute runs coalesced across an append).
- **F58 localised** (not fixed): bisected to `[_target release]` in
  `-[NSThread dealloc]`, inside a pthread key destructor on a dying thread, arm64e
  only. Skipping that one release makes it vanish. The function-pointer-cast
  hypothesis was implemented and **disproved**; the change is kept for removing UB
  and credited with nothing.
- **F63 fixed** — directory removal followed symlinks and **deleted files outside the
  tree** (real data loss, reproduced by `t35_symlink` before being touched). Control:
  `t14_fileman` still exact, so ordinary recursive removal is unaffected.
- **F68 fixed** (new) — `createSymbolicLinkAtPath:` passed `symlink(2)` its arguments
  backwards. Found only because a test asserted on its own setup: without that, a
  data-loss defect would have been filed as "does not reproduce" (trap 17).
- **F64 fixed** (`truncateFileAtOffset:` seeked with `SEEK_CUR` where macOS uses
  `SEEK_SET`). Notable for method: the existing test was *structurally blind* to it —
  at position 0 the two behaviours are identical — so a new assertion was written and
  shown to fail **before** anything was changed.
- Still read-only, unreproduced: **F62**, **F65**.
- New:
  **F66** (the graphical verifiers assert on wall-clock deadlines, so their pass rate
  partly measures machine load; one published failure rate was measuring our own
  concurrent work, proven by a controlled idle-vs-loaded experiment).
- Corrected three claims that were wrong in the shipped report: `text-view` 2/7,
  F57's diagnosis, and F59's narrowing. All three are in the report's
  "conclusions withdrawn" table rather than quietly swapped.
- Build loop `~/rebuild-cf.sh` verifies the staged binary's mtime moved (F61).
- Read `NEXT_STEPS.md` for the ordered queue. Report:
  `report/darling-arm64-status.pdf` (25 pages).

## Historical status (2026-08-05)

- Tree: 149/149 submodules, 0 mismatched, 0 empty, HEAD `b91f0948`. Verified arm64
  content present in `xnu` (`12132d9`) and `dyld` (`cce174b`).
- CMake configures cleanly: `TARGET_ARM64=ON`, `TARGET_x86_64=OFF`, Release.
- Full build running in VM: `nohup make -j12 > ~/build.log`.
  Check: `limactl shell darling-arm64 -- tail -40 ~/build.log`.
- Corpus complete on host; not yet run under Darling (needs the build to finish).
