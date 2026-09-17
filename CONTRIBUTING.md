# Contributing to darling-arm64

This repository exists to increase **verified arm64 (aarch64) capability** in the
Darling translation layer. Every contribution is judged against one question:

> Does this increase verified arm64 capability, and can someone else reproduce it?

## Inbound contribution terms

Version: `2026-09-04.1`

By opening a pull request you agree that your contribution is licensed to the project
and its users under the repository's **GPL-3.0-or-later** licence (see `LICENSE`). You
retain copyright in your contribution. No copyright assignment and no separate CLA are
required. Payment, if any, does not transfer intellectual property.

Sign your commits off (`git commit -s`) if your employer requires it; a DCO sign-off is
accepted but not mandatory.

See **`OPEN-WORK.md`** for the current scoped entry points, their effort, and their
success criteria.

## What counts as an accepted outcome

Ranked by value:

1. **A tier that did not pass now passes**, reproducibly, with a control — most valuably
   Stage 20 (CotEditor Bronze), currently blocked on Swift↔AppKit interop.
2. **A defect fixed upstream** in `darlinghq/*`, with the reproduction harness added here.
3. **A finding that is falsified**, including one of ours. Retractions are first-class
   work and are kept in place in `FINDINGS.md`.
4. **A flake mechanism explained and measured** — the session-spawn flake is ~13–20% on
   the real runtime and one mechanism remains unfixed by choice (F102).
5. **A harness that makes an existing claim cheaper to reproduce.**

## What does not count

- Refactors, formatting, lint passes, dependency bumps, and comment churn.
- x86_64-only work. Darling is a translation layer, not a CPU emulator: the host
  architecture must match the binary architecture. x86_64 results say nothing here.
- A tier claimed to pass because a PR description or commit message says so.
- Any change carrying code or text from forks that strip upstream GPL-3.0 attribution.
- Numbers produced without a control, or a "fix" without an A/B/A.

## Evidence standard

A change is not accepted without evidence that someone else can regenerate.

- **Bring a control.** A rate is a claim about an environment until a control says
  otherwise. State what your control was and how many variables moved.
- **A/B/A for any fix.** The effect must track the patch *and* reverse on revert. State
  n, the measured effect, and the uncertainty. `#17` is in the record as a *trend*, not a
  proven effect (18%→8%, p=0.23 at n=50) — that is the honesty bar.
- **Report failures verbatim.** Paste the first error, not the tail; CMake and make both
  bury the root cause above hundreds of follow-on lines.
- **Name your environment.** Distro, kernel, clang version, VM type, and the Darling
  commit. Two of the first six "findings" in this project's history turned out to be
  artifacts of the environment, not defects in the code.

Add the harness that produced your evidence to `tools/`, named after the finding
(`fNNN-*`), and add the finding to `FINDINGS.md` with its citation.

## Do not redistribute Apple assets

The dyld shared cache, application bundles, the Swift toolchain and corpus binaries stay
local. Never commit them, and never add a test that requires them to be published.
`scripts/10-make-corpus.sh` builds the corpus locally.

## Agents

Any model, agent and client may contribute. Disclose the exact provider, model and
client in the pull request. Model choice and token volume never affect whether work is
accepted — only reproducible evidence does. See `AGENTS.md`.

## Review

Maintainer review happens in this repository. Automation may propose a score or a hold;
a human decides acceptance. Fixes that belong upstream should also be sent to
`darlinghq/*`, and the pull request here should link them.
