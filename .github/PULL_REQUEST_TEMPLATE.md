<!-- A number without a control is a claim about an environment, not a result. -->

## What this changes

<!-- One paragraph. What is now true that was not true before? -->

## Architecture

<!-- REQUIRED. x86_64 results are not accepted: Darling is a translation layer, not a
     CPU emulator, so the host architecture must match the binary architecture. -->

- `uname -m` on the Darling runtime host:
- `uname -m` on the ground-truth host (if a baseline was regenerated):

## Environment

- Distro / kernel:
- clang version:
- VM type:
- Darling commit:
- `git-lfs` present: <!-- without it, Swift libraries stage as 130-byte pointer files -->

## Control

<!-- REQUIRED for any measured claim. -->

- What was the control?
- How many variables moved relative to it?

## A/B/A

<!-- REQUIRED for anything called a fix. Without A' it is a coincidence. -->

| Arm | n | Result |
|---|---|---|
| A (baseline) | | |
| B (patched) | | |
| A′ (reverted) | | |

Effect size and uncertainty:

<!-- Label a trend as a trend. The standard in this record: darlingserver#17's mechanism
     is proven, but its end-to-end effect is reported as a trend, not an effect
     (18% -> 8%, p=0.23 at n=50). An honest trend is accepted; an overstated claim is not. -->

## Evidence

- Harness added to `tools/` as `fNNN-*`:
- Finding added to `FINDINGS.md`:
- `REPRODUCE.md` updated (if this establishes a headline claim):

<!-- Paste the FIRST error, not the tail, for anything that failed. -->

## Record

- [ ] This does not overturn an existing finding
- [ ] This overturns finding # ______ , and the retraction is left in place next to the evidence that falsified it

## Checklist

- [ ] No Apple-owned assets committed (shared cache, app bundles, Swift toolchain, corpus binaries)
- [ ] No gate, checksum, or threshold edited to make something pass
- [ ] No code or text vendored from a fork that strips upstream GPL-3.0 attribution
- [ ] If this fixes a Darling defect, the upstream `darlinghq/*` pull request is linked below
- [ ] Agent contributions declare the exact provider, model, and client

Upstream PR (if any):
