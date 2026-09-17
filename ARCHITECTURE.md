# ARCHITECTURE — how the pieces fit together

Two systems matter here: **Darling itself** (the thing under test) and **our test
apparatus** (the thing that makes claims about it trustworthy). Confusing them has cost
us real time, so they are described separately.

---

## 1. Darling, as far as this project touches it

```
  ┌──────────────────────────────────────────────────────────────────┐
  │  macOS application (unmodified, checksum-pinned: iTerm2, CotEditor) │
  ├──────────────────────────────────────────────────────────────────┤
  │  Apple frameworks         │  Darling frameworks                   │
  │  from the dyld shared     │  from disk (Cocotron-derived)         │
  │  cache: Foundation,       │  AppKit, CoreGraphics/Onyx2D,         │
  │  CoreFoundation, Swift    │  X11 backend                          │
  │  ── "hybrid mode": which side wins is per-framework policy ──     │
  ├──────────────────────────────────────────────────────────────────┤
  │  dyld (Darling's)  ·  libSystem  ·  libdispatch  ·  libxpc        │
  ├──────────────────────────────────────────────────────────────────┤
  │  mldr — the native ELF loader that maps Mach-O and starts guests  │
  ├──────────────────────────────────────────────────────────────────┤
  │  darlingserver — userspace "kernel": Mach ports, IPC, signals,    │
  │    process/thread lifetime. Contains **duct-tape**, XNU-derived   │
  │    kernel emulation (scheduler, waitq, psynch, ipc_mqueue).       │
  ├──────────────────────────────────────────────────────────────────┤
  │  Linux (aarch64, native — no CPU emulation anywhere)              │
  └──────────────────────────────────────────────────────────────────┘
```

**Facts that shape every investigation:**

- **`DSERVER_SINGLE_THREADED=ON`** in every build root. One OS worker thread runs all
  duct-tape microthreads cooperatively (getcontext/setcontext fibers, no preemption).
  *Consequence:* whole classes of "data race" hypotheses are architecturally
  unreachable. This falsified an entire candidate fix (F100).
- **Guest processes reach darlingserver over a per-thread RPC socket.** A thread with no
  socket cannot make a call — and Darling's signal handler treats that as fatal, which is
  the whole of F102.
- **`sigexc`**: guest signals are emulated; the handler re-raises with `SIG_DFL` for
  default-action signals. *Consequence:* the process dies of a **re-raised** signal, so
  the original crash is destroyed — recovering it is a specific technique (see §3).
- **The hybrid boundary is where the ladder now sits.** Swift and Foundation come from
  the Apple cache and work; AppKit is Darling's own; `libswiftAppKit` is Apple's bridge
  *between* them and has no counterpart. That seam is Stage 20's blocker (F106).

---

## 2. Our test apparatus

### Roots (an install root + a build root are a matched pair)

| Root | Purpose | Rule |
|---|---|---|
| `install/build-arm64-stage18` | **the reviewed runtime** — every headline number | **never modified** |
| `-f103` | faithful copy of stage18; all A/B measurement | control reproduces stage18's baseline — that validation is what makes it usable |
| `-f104` | scratch for destructive experiments (Swift libs moved aside) | disposable |
| `-id26` | 26.5-identity, **stage10-derived hybrid** | **not a stand-in for stage18** — it fails the full gate ~100% in every condition (trap 48) |
| `-gap` | Kevin's merged Jul 14–16 tail + our fixes | held |

A root is only trustworthy as a proxy once its **control arm reproduces the recorded
baseline**. That is the single most expensive lesson in this file.

### The probe engine

`tools/probe-iterm2-launch-arm64.sh` is the one launcher; everything else drives it.
It builds a disposable prefix in a container, starts Xvfb + launchd + darlingserver,
mounts the app bundle read-only, optionally mounts the Apple dyld cache, runs a workflow,
then captures `windows.txt`, `screen.png`, `processes.txt`, `status.txt`, app logs and
`dserver.log`.

It is **app-parameterised** (`APP_PROBE_BUNDLE`, `APP_PROBE_BUNDLE_NAME`,
`APP_PROBE_EXECUTABLE_NAME`) — which is how CotEditor and even bare Swift binaries
(wrapped in a minimal `.app`) were tested without writing a second launcher.

Two switches carry outsized meaning:
- `ITERM2_PROBE_SHARED_CACHE=1` mounts the Apple cache. **Without it there is no Apple
  Swift/Foundation at all** — forgetting this produced a false "Swift on arm64 is zero"
  headline (F105 correction).
- `ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1` is Kevin's "hybrid mode": Apple cache
  authoritative for Foundation/Swift, Darling's AppKit/graphics selected.

### Gates vs harnesses

- **Gates** (`verify-iterm2-silver-*`) are Kevin's tier definitions — pass/fail, and we
  do not edit them to manufacture a pass.
- **Harnesses** (`f8x`–`f10x-*`) are ours, named after the finding that produced them.
  `f103-stage18-ab.sh` is the current standard: copies the reviewed pair, runs
  control/patched arms, prints rates with Wilson CIs and failure-mode composition.

---

## 3. The diagnostic pipeline (how a crash becomes a mechanism)

This sequence produced both `darlingserver#17` and F102, and is the most reusable asset
here:

1. **Amplify or reproduce** — get the failure on demand if possible.
2. **Core dumps, not tracing.** `--ulimit core=-1` + `core_pattern` into the artifact
   mount. Cores cost nothing until death; **`strace` slowed startup enough that the bug
   vanished entirely** (a false "fixed" signal).
3. **Recover the original signal frame.** `sigexc_handler` logs the guest addresses of
   its own `siginfo`/`ucontext`; those pages survive in the core, so the *original*
   `si_code`, faulting PC and registers can be read even though the process died of a
   re-raised signal. `tools/f101-core-origsig.py` does this.
4. **Symbolize** against the staged dylibs (`llvm-nm`, nearest-symbol).
5. **Adversarially review** any candidate patch to core code *before building it*.
6. **A/B/A** — effect must track the patch and reverse on revert.

Steps 2–3 are the difference between "an intermittent crash" and
"`si_code=TRAP_BRKPT`, `pc=_dispatch_mach_send_and_wait_for_reply+0x5c4`,
`x0=MACH_RCV_TIMED_OUT`".

---

## 4. Differential testing (the corpus)

Compile on macOS → capture native ground truth → run the identical bytes under Darling →
compare. 77 cases; Swift coverage added in `tools/swift-probes/` (F106), which is how
"Swift works on arm64" became a claim with byte-identical evidence rather than an
impression.

---

## 5. Where the artifacts live

| Kind | Location |
|---|---|
| Source (inside the VM) | `~/darling/source` |
| Harnesses | `source/tools/` |
| Findings, decisions, traps | repo root `.md` files |
| Run artifacts | `~/darling/f10x-*/`, `~/darling/artifacts/` |
| Apple-owned inputs (never committed) | `~/darling/downloads/{macos,iterm2,coteditor,swift}` |
| Reports to the funder | `report/` |
