# AGENTS.md — instructions for coding agents

Read `README.md`, then `SUMMARY.md`, then `CONTRIBUTING.md`. `REPRODUCE.md` maps every
headline claim to the harness that regenerates it.

## The one question

Does this increase **verified arm64 capability**, and can someone else reproduce it?
Not x86_64. Not polish. Not refactors.

## Hard rules

- **Darling is a translation layer, not a CPU emulator.** Host architecture must match
  binary architecture. arm64 binaries need an arm64 host. x86_64 results are irrelevant here.
- **Never claim a tier works because a PR description says so.** Everything is "claimed"
  until the corpus reproduces it. Report failures verbatim.
- **Change one variable at a time, and always have a control.** Before trusting any
  failure, state your control and how many variables you moved.
- **No fix is a fix without A/B/A.** The effect must track the patch and reverse on revert.
- **Never commit Apple-owned assets** — dyld shared cache, app bundles, Swift toolchain,
  corpus binaries.
- **Never vendor or copy from forks that strip upstream GPL-3.0 attribution.**
- **Capture the first error, not the tail.** CMake and make bury the root cause.

## Before you start

Read `STATE.md` §Traps — traps that each cost real time. Several will otherwise cost
you the same hours. `git-lfs` is required; without it Swift libraries stage as 130-byte
pointer files (F104, trap 53).

## Long operations

VM setup, the submodule clone, and builds take tens of minutes to hours. Run them in the
background and poll. Do not assume a silent command failed.

## Disclosure

State the exact provider, model and client you used in the pull request. Do not infer or
substitute them. Token volume never earns anything.
