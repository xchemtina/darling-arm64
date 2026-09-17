# darling-arm64 — verifying the macOS translation layer on aarch64

A differential-testing harness and evidence record for **arm64 (aarch64) Darling**.

[Darling](https://github.com/darlinghq/darling) is a *translation layer, not a CPU
emulator*: the host architecture must match the binary architecture. arm64 macOS
binaries therefore need an arm64 Linux host — which is why almost no contributor can
test this surface, and why most Darling work is x86_64-only.

This repository is the other half of that problem: harnesses that run real macOS
applications under arm64 Darling, compare their behaviour against **captured native
macOS ground truth**, and keep a record honest enough that a stranger can reproduce or
falsify any number in it.

## Verified capability

| Capability | Status | Evidence |
|---|---|---|
| Stage 18 — iTerm2 Bronze (one reliable window) | **pass** | one-command bootstrap, 6m34s |
| Stage 19 — iTerm2 Silver (tabs / splits / persistence) | **pass, ~82%** | 41/50 on a faithful stage-18 copy |
| Swift core + Foundation on arm64 | **pass** | byte-identical to native ground truth (F106) |
| Swift ↔ AppKit interop | **pass with Apple's AppKit; fail with Darling's** | `SWIFT_APPKIT_ATTR_OK 1` when the shared-cache AppKit is bound, A/B/A over one flag (F107) |
| Stage 20 — CotEditor Bronze | **blocked** | neither pinned version launches on Darling's AppKit (F104); F107 names why and F110 tests the alternative |

A real macOS application runs on arm64 Darling, and Swift works. The Swift↔AppKit
descriptors live inside Apple's AppKit binary (F107); the open question is what a GUI
application does when Apple's AppKit, rather than Darling's, is bound.

## Fixes sent upstream

| PR | What | How it was proven |
|---|---|---|
| [darling-cocotron#70](https://github.com/darlinghq/darling-cocotron/pull/70) — **merged** | per-resize backing-store + shadow-surface leak | 4,768 → 419 KiB/resize (−91%), A/B/A with revert |
| [darling-cocotron#71](https://github.com/darlinghq/darling-cocotron/pull/71) | `-[X11Window setAlphaValue:]` unimplemented abstract method | restores launch on the upstream Jul 14–16 tail |
| [darlingserver#17](https://github.com/darlinghq/darlingserver/pull/17) | `thread_unblock` drops XNU's wait-timer cancel → spurious `MACH_RCV_TIMED_OUT` → libdispatch traps | core dump (`TRAP_BRKPT`, exact PC, `x0=MACH_RCV_TIMED_OUT`) + A/B/A |

## Read in this order

| File | What it gives you |
|---|---|
| **`SUMMARY.md`** | one page: verified capability, upstream PRs, what is blocking |
| **`ARCHITECTURE.md`** | how the pieces fit — VM, roots, probe engine, gates, the Darling stack |
| **`OPEN-WORK.md`** | **start here to contribute** — scoped entry points, effort, and success criteria |
| **`NEXT_STEPS.md`** | the ordered queue, with effort and rationale |
| **`DECISIONS.md`** | the load-bearing calls and why they were made |
| **`THOUGHTS.md`** | open questions and live hypotheses |
| `STATE.md` | environment, and **§Traps — traps that each cost real time** |
| `FINDINGS.md` | the authoritative record: findings F1–F110, **retractions kept in place** |
| `REPRODUCE.md` | every headline claim → the exact harness that regenerates it |

## Layout

- `tools/` — measurement harnesses, run **inside** the Linux VM alongside the Darling
  source tree. Named by the finding that produced them (`f100-*`, `f101-*`, …), so a
  number in `FINDINGS.md` leads straight to the tool that measured it.
- `scripts/` — host-side (macOS) staging: VM setup, corpus construction, native ground-truth
  capture, staged builds.
- `evidence/` — raw measurement output cited by specific findings.
- `report/` — written reports and figures.

## Method

Four rules, each learned expensively:

1. **Change one variable at a time, and always have a control.** A rate is a claim about
   an environment until a control says otherwise.
2. **No fix is a fix without A/B/A** — the effect must track the patch *and* reverse on revert.
3. **Never claim a tier works because a PR description says so.** Everything is "claimed"
   until the corpus reproduces it. Failures are reported verbatim.
4. **Match the upstream author's toolchain before modernising it.** Reproduce their
   result first, then change things deliberately.

Three claims were withdrawn by our own controls: a "psynch race" localization, a "debug
amplifies the flake to 93%" figure, and a "Swift on arm64 is zero" headline. Each
retraction stays in `FINDINGS.md` next to the evidence that falsified it.

## What is deliberately not here

- **Apple-owned assets.** The dyld shared cache, iTerm2/CotEditor bundles, the Swift
  toolchain and all corpus binaries stay on the machine that captured them. Nothing
  Apple owns is redistributed here. `scripts/10-make-corpus.sh` builds the corpus and
  captures native ground truth locally.
- **The Darling source tree.** It lives upstream at
  [darlinghq/darling](https://github.com/darlinghq/darling); these harnesses sit beside it.

## Reproducing

Requires an **aarch64 Linux VM** and an **arm64 macOS host** for ground truth. See
`REPRODUCE.md` for the full path and `STATE.md` for the environment and its traps.

```sh
scripts/00-vm-setup.sh                  # VM: deps + arm64 source tree
scripts/10-make-corpus.sh               # host: build corpus, capture native ground truth
scripts/30-build.sh all                 # VM: staged build
tools/reproduce.sh                      # VM: ladder -> Silver gates -> leak short-cycle
```

## Attribution

Darling is GPL-3.0 and its authors are credited upstream. The arm64 ladder, the staged
tiers and much of the groundwork this repository verifies are the work of the upstream
arm64 author; this repository reproduces, measures and extends that work rather than
replacing it. Attribution is preserved deliberately — forks that strip it are the reason
this record exists.

## Contributing

Start with **`OPEN-WORK.md`** for scoped entry points, then `CONTRIBUTING.md` for the
evidence standard. Short version: bring a control, bring an A/B/A, and report the failure
verbatim. Two items are marked as good first contributions and one of them needs no
special hardware.

## Licence

GPL-3.0-or-later. See `LICENSE`.
