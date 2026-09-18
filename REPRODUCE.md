# REPRODUCE — every headline claim → the exact command that regenerates it

This maps each result in the follow-up note and `FINDINGS.md` to the harness that
produces it. All harnesses live in `tools/` on branch
`north-star/arm64-verified-fixes`. They run **inside the VM**, against a staged
Stage 18 runtime, with an Apple dyld shared cache exported as
`ITERM2_SHARED_CACHE_ROOT` (see `tools/prepare-macos-shared-cache.sh`; F69/F74).

## One-shot

```sh
# from ~/darling/source, with ITERM2_SHARED_CACHE_ROOT set and a Stage 18 runtime staged:
tools/reproduce.sh            # ladder + Silver tabs + leak-ABA short cycle, pass/fail summary
```

## Claim → command

| claim (note / finding) | command | what it shows |
|---|---|---|
| Stage 18 builds + iTerm2 launches (F70/F76) | `tools/bootstrap-iterm2-stage18.sh` | one command, ~6m34s, ladder 12/12 |
| shared cache from any recent Mac (F74) | `tools/prepare-macos-shared-cache.sh --from <dir>` | stages + aliases a dyld cache |
| **Silver tier reproduces** (F80/F81/F88) | `tools/verify-iterm2-silver-{tabs,tab-close,splits}-arm64.sh` | gate exit 0; PIDs round-trip |
| Silver stability at scale (F88) | `tools/f81-silver-stability.sh` | 15× each gate, cumulative rate |
| settings-persistence (F81) | `tools/verify-iterm2-settings-persistence-arm64.sh` | mutation survives relaunch |
| **the login bug, photographed** (F79) | `tools/f79-window-screenshot.sh` | the execvp banner → live prompt |
| window-lifecycle (F77) | `tools/f77-window-lifecycle.sh` | live root-window substructure events |
| **the per-resize leak** (F84/F85) | `tools/f85-resize-leak.sh` | 3-size cycle isolating size vs direction |
| **leak fix, ABA-validated** (F89) | `tools/f92-leak-aba.sh` | baseline→patched→revert, −91% |
| the flag debt (F82) | `tools/f82-flag-matrix.sh` | 6-flag ablation, 3 load-bearing |
| quit dialog never created (F86/F88) | `tools/f86-quit-discriminator.sh` | 0 creations on the terminal path |
| Bronze soak behaviour (F83/F84) | `tools/f84-short-soaks.sh` | reliability + the mid-run vanish |
| **the 26.5/12.4 identity fork** (F93/F96) | `tools/f95-identity-26.sh` | 26.5 dies at `setHasDestructiveAction:` |
| **setAlphaValue fix restores launch** (F97) | `tools/f97-alphavalue-fix.sh` | merged tail launches again |
| the session-spawn flake, first captured (F98) | `tools/f98-session-spawn.sh` | pass/fail capture pair (framing superseded by F100) |
| **the flake: on-demand repro** (F100) | `tools/f100-gate-aba.sh <N> <label>` | rate + Wilson CI; the debug-amplifier figure this cell once cited was formally retracted (F102's correction) — see `FINDINGS.md` |
| **the three ruled-out mechanisms** (F100) | `tools/instrument-psynch.py` + `tools/f100-instr-batch.sh`; `tools/fix-resume-latch.py` + `tools/f100-gate-aba.sh`; rebuild via `tools/f100-build-id26.sh` | instrument → 0 mints; latch A/B/A 93%→93%; single-threaded config proof |
| cold-host: no path completes (F94) | `tools/f91-cold-host.sh` | the 8-layer clone/build ledger |

## Fixes on branches (pull to apply)

- **Leak** — cocotron `f89-leak-fix`; upstream `darlinghq/darling-cocotron#70`.
- **setAlphaValue** — cocotron `fix/x11-setalphavalue`; upstream `#71`.
- **NSPopUpButton / NSWindow blur** — cocotron `2fa0bef9` (F72/F75).
- **arm64 build fixes** (bash/liblzma) — `arm64-build-fixes` on each (trap 41).

## Ground rule

Every finding cites its artifacts and reproduction. `FINDINGS.md` keeps retractions
in place (with the evidence that falsified them) rather than deleting them — so the
record is auditable, not just favourable.
