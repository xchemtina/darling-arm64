# SUMMARY — where arm64 Darling stands (2026-09-17)

One page. Everything here traces to `FINDINGS.md` (F1–F108) on
`deepai-org/darling-aarch64-north-star` → `north-star/arm64-verified-fixes` @ `aae7ac5e9`.

## The headline

**A real macOS app runs on arm64 Darling, and Swift works.** iTerm2 passes Kevin's
Stage 19 (Silver) tier — tabs, tab-close, splits, settings-persistence — reproduced
independently for the first time outside his machine. Separately, Swift core and
Foundation now produce **byte-identical output to native macOS** on arm64.

## Verified capability

| Capability | Status | Evidence |
|---|---|---|
| Stage 18 — iTerm2 Bronze (one reliable window) | **pass** | one-command bootstrap, 6m34s |
| Stage 19 — iTerm2 Silver (tabs/splits/persistence) | **pass, ~82%** | 41/50 on a faithful stage18 copy; 12/15, 13/15, 11/15 per gate at n=15 |
| Swift core + Foundation on arm64 | **pass** | byte-identical to native ground truth (F106) |
| Swift + AppKit interop | **pass with Apple's AppKit, fail with Darling's** | `SWIFT_APPKIT_ATTR_OK 1` when the shared-cache AppKit is bound; A/B/A over one flag (F107) |
| Stage 20 — CotEditor Bronze | **blocked** | neither pinned version launches on Darling's AppKit (F104); F107 names why, F110 tests Apple's AppKit |
| Stage 21 — iTerm2 Gold | not started | gated behind Stage 20 |

## Fixes contributed upstream (3 PRs, all open)

| PR | What | How it was proven |
|---|---|---|
| `darling-cocotron#70` | per-resize backing-store + shadow-surface leak | 4,768 → 419 KiB/resize (−91%), A/B/A with revert |
| `darling-cocotron#71` | `-[X11Window setAlphaValue:]` unimplemented abstract method | restores launch on Kevin's own Jul 14–16 tail |
| `darlingserver#17` | `thread_unblock` drops XNU's wait-timer cancel → spurious `MACH_RCV_TIMED_OUT` → libdispatch traps | core dump (`TRAP_BRKPT`, exact PC, `x0=MACH_RCV_TIMED_OUT`) + A/B/A |

`#70` had a maintainer review (comments were unnecessary); addressed — the diff is now
two lines, no comments.

## The one thing blocking the ladder

**Which AppKit a Swift application binds.** Swift itself works (F106). F107 located the
only failing symbol family, `AttributeScopes.AppKitAttributes.*`, in the reference
implementation: those descriptors are exported by **Apple's AppKit binary itself** (289
`AttributeScopes` symbols), and `libswiftAppKit.dylib` is a bare re-export stub of AppKit
with no exports of its own. Darling deliberately binds its own Cocotron-derived AppKit, so
the descriptors cannot exist — `Symbol not found`, not `Library not loaded`. With the
shared-cache AppKit bound instead (`ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=0`) the probe prints
`SWIFT_APPKIT_ATTR_OK 1`, byte-identical to native, A/B/A over that one flag.

What is not yet known is what a *GUI* application does on Apple's AppKit under Darling —
it needs surfaces Darling does not provide, and the first visible cost is already there
(duplicate `NSTouch`/`NSSearchToolbarItem`/… classes between Apple's AppKit and
`libDarlingAppKitBootstrap`). That is F110, the F104 CotEditor driver with the one flag
flipped. It gates Stage 20, which gates Gold.

## What is honestly still open

- **F110** — CotEditor on Apple's AppKit: result pending at the time of writing.
- **The 26.5-identity root's 100% failure is now named** — the first artifact F108 ever
  preserved shows `-[NSButton setHasDestructiveAction:]: unrecognized selector` from
  `-[iTermWarning makeAlert]`, a macOS 11 API Darling's AppKit lacks, reached because
  `@available` forks on the emulated OS version (F93). Bounded Cocotron work; not yet done.

- **The session-spawn flake** (~13–20% on the real runtime). One mechanism found and
  fixed (`#17`); a second (F102, mldr's thread-bridge broker) fully explained but
  deliberately **not** fixed — the one-line version would make every Darwin thread
  signal-deaf.
- **`#17`'s real-world effect is a trend, not a proven effect** (18%→8%, p=0.23 at
  n=50). The *mechanism* is proven; the end-to-end improvement is not.
- **Kevin's CotEditor "live document window"** — he recorded reaching it; we cannot
  reproduce it and do not claim his record is wrong. Unexplained; first question for him.

## Method (why the numbers can be trusted)

Differential testing against captured native macOS ground truth; a control before
crediting anything; A/B/A with revert-restore before calling something a fix; retractions
kept in place with the evidence that falsified them. **Three claims were withdrawn by our
own controls** this week — a "psynch race" localization, a "debug amplifies the flake to
93%" figure, and a "Swift on arm64 is zero" headline. Each was caught before or shortly
after it shipped, and each correction is in the record.

See `README.md` (orientation), `ARCHITECTURE.md` (how it fits together),
`NEXT_STEPS.md` (ordered queue), `DECISIONS.md` (why), `THOUGHTS.md` (open questions),
`STATE.md` §Traps (55 traps that cost real time).
