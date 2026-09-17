# THOUGHTS — open questions, live hypotheses, and what this week taught

Speculative by design. Nothing here is a claim; claims live in `FINDINGS.md`.

---

## The live hypothesis (the one that matters)

**Swift↔AppKit is the seam, and it may be structural rather than a bug.**

`libswiftAppKit` is Apple's Swift↔AppKit bridge. It expects *Apple's* AppKit behind it.
Darling deliberately supplies its **own** AppKit (Cocotron-derived) — Kevin's hybrid mode
is literally documented as "Apple cache authoritative for Foundation/Swift, **Darling
AppKit** selected". So the bridge's `AttributeScopes.AppKitAttributes` type descriptors
have nothing to bind to.

If that is right, three futures follow, and they are very different in cost:

1. **Routing fix.** The cache's AppKit overlay is present but not selected/bound. Someone
   flips policy and Swift AppKit apps start working. *Cheap — hours.*
2. **Bridge shim.** Darling's AppKit must export the metadata the Swift overlay expects.
   *Moderate — a real but bounded piece of work.*
3. **Genuine incompatibility.** Apple's Swift AppKit overlay cannot sit on a
   reimplemented AppKit at all, and Swift GUI apps need Darling's own Swift AppKit
   overlay. *Expensive, and worth knowing early.*

Item 1 of `NEXT_STEPS.md` exists to distinguish these. **We should not start writing code
until we know which world we are in** — that is exactly the mistake that produced three
wrong flake fixes.

## Questions I cannot answer from here

- **How did Kevin reach a CotEditor live document window?** His record says he did; we
  cannot, and we have no arm64 Swift AppKit path. Either his configuration differed in a
  way the record does not capture, or that work ran somewhere we have not reproduced. I
  have deliberately not resolved this by assuming he was wrong — the record has been
  right and we have been wrong more often than the reverse.
- **Is the residual "typed keystrokes never execute" mode one bug or two?** It appears at
  tab-1 startup and at post-close survivor. Duration arithmetic suggests a shared
  input/PTY-delivery latency cause, but the artifacts that would confirm it are deleted
  four seconds after every failure.
- **Does `darlingserver#17` actually help end users?** The mechanism is real and the
  crash it removes is real. Whether it moves the end-to-end rate is still p=0.23. I would
  rather leave that "not demonstrated" than round it up.

## What this week actually taught

**The controls earned their keep three times.** Each of the withdrawn claims — the psynch
localization, the 93% amplifier, the zero-Swift headline — *felt* solid when written. Two
were caught by a control run afterwards; one by re-reading my own harness. The pattern is
consistent: **the error was never in the measurement, it was in the environment the
measurement ran in.** A number is a statement about a configuration, and the configuration
is the thing that must be verified first.

**Instrumentation can destroy the phenomenon.** `strace` made the bug vanish. That is not
a curiosity — it means the whole class of "add logging and re-run" debugging was
unavailable, and the only viable instrument was one with zero cost until failure. Worth
remembering the next time something is "too flaky to debug": maybe the debugger is the
flake.

**The best result of the week came from distrusting a result of the week.** "Swift on
arm64 is zero" was a strong, clean, wrong finding. Checking the harness that produced it
turned it into "Swift works, and the blocker is one symbol family" — which is both truer
and far better news. The instinct to re-examine a *finished* finding is worth more than
speed.

**A maintainer told us something useful about how we work.** The PR #70 review — "one pet
peeve I have with AI assisted contributions is that it adds unnecessary comments" — is a
fair and specific critique. The commit message is the place for rationale; the diff should
be the change. That generalises well beyond that PR.

## Uncomfortable observations worth keeping

- **We have been measuring on a broken root for part of this work.** `id26` fails ~100%
  in every condition, and it took a control to notice. Everything measured there is
  suspect unless it was an internal A/B on that same root.
- **The gates destroy their own failure evidence.** Every diagnosis so far needed a
  re-run. That is a tax on every future investigation and it is 30 minutes to fix.
- **Nine of Kevin's ten issues have zero comments and he has been silent a month.** We
  are advancing his ladder without feedback. The reports exist partly to force that
  conversation — the three questions in `NEXT_STEPS.md` §6 are the ones that would most
  change what we do next.

## A note on what "progress" means here

It is tempting to measure this work in fixes shipped. The more honest measure is
**how much of the map is now trustworthy**: which tiers reproduce, on which roots, with
which controls, and which claims we have had to withdraw. By that measure the week was
good — three upstream PRs, Swift verified working on arm64, the Stage-20 blocker bounded
to one symbol family, and three false claims removed before they could mislead anyone.
