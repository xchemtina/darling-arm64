# DECISIONS — the load-bearing calls, and why

Only decisions that changed what we did or what we can claim. Each records the
alternative that was rejected, because that is the part that is usually lost.

---

### D1 — Build on upstream Darling + kkHAIKE's arm64 work; reject `Osxie`
`Osxie` is x86_64-only and strips GPL-3.0 attribution from upstream. Using it would
propagate a licence defect into everything downstream. **Rejected on licence grounds
before any technical evaluation mattered.** (Standing, non-negotiable.)

### D2 — Differential testing against native ground truth, not self-consistency
Compile on macOS, capture the real output, run the identical bytes under Darling,
compare. *Alternative rejected:* "it looks right" / screenshot evidence. This is the only
reason claims like "Swift works on arm64" carry weight — `SWIFT_CORE_OK [1, 2, 3]` is
byte-identical to the Mac, not merely plausible.

### D3 — A control before crediting anything; A/B/A before calling something a fix
Effect must track the patch **and** reverse on revert. *Alternative rejected:* patch,
observe improvement, claim. This single rule has caught three overclaims (D9).

### D4 — Retractions stay in the record, next to the evidence that falsified them
`FINDINGS.md` never deletes a wrong finding. *Alternative rejected:* quietly fixing the
record. A reader must be able to audit how we were wrong, or the parts where we were
right are not checkable either.

### D5 — Reviewed roots are never modified; all measurement happens on validated copies
`install/build-arm64-stage18` is read-only in practice. A copy is only trusted once its
**control arm reproduces the recorded baseline** — the f103 pair does (12/15, then 41/50
vs the recorded 11/15). *Alternative rejected (and it bit us):* using a convenient
scratch root (`id26`) as a proxy without checking what it derived from. It was a
stage10/26.5 hybrid that fails ~100% in every condition, which produced a false
"debug amplifies the flake to 93%" claim.

### D6 — Adversarial review of any core-code patch **before** building it
Core scheduler/IPC changes get a reviewer whose job is to refute them. *Alternative
rejected:* build first, measure after. It killed a wrong psynch patch (which targeted a
race that `DSERVER_SINGLE_THREADED=ON` makes unreachable, and would have added a
reentrant-spinlock deadlock) and vetted the wait-timer fix that became PR #17.

### D7 — Core dumps, not tracing, for timing-sensitive crashes
`strace` — even filtered — slowed startup enough that the bug **disappeared** (0 crashes
in 4 runs: a false "fixed"). Cores cost nothing until death. Coupled with recovering the
*original* signal frame from the addresses `sigexc_handler` logs, this is what turned an
intermittent crash into an exact PC and return code.

### D8 — Fix mechanisms, not symptoms; upstream them on mechanism evidence
PR #17 was opened on the strength of a core-dump-proven mechanism plus an A/B/A on the
crash it removes — **not** on an end-to-end pass-rate claim, which remains unproven. The
PR body says so explicitly. *Alternative rejected:* wait for a significant end-to-end
result before contributing (slower, and the mechanism is independently correct).

### D9 — Withdraw our own claims loudly when a control disagrees
Three withdrawn this week: (a) the "psynch startup race" localization — the semaphore
signal was memberd's benign idle poll, present *more* in passing runs; (b) "debug
logging amplifies the flake to 93%" — the root fails ~100% regardless (D5); (c) "Swift
support on arm64 is zero" — an artifact of a runner that stages no shared cache. Each
correction is in `FINDINGS.md`, and (b) was also corrected **in the public PR body** so
a maintainer would not read a confounded number.

### D10 — Not shipping the F102 fix, deliberately
The mechanism is confirmed (prediction verified 3/3), but the obvious one-line fix —
blocking signals across the broker's creation — would make **every** Darwin thread
inherit a fully-blocked mask and go permanently signal-deaf: a quieter, worse bug than
the one being fixed. Recorded as a localization with the two-sided fix specified.
*Alternative rejected:* ship the one-liner and look productive.

### D11 — Stage 20 (CotEditor) over polishing Stage 19
Kevin's ladder makes Stage 20 the next rung and the gate to Gold; it is his issue #1 and
he never completed it. A second working app is the strongest generality claim available.
*Alternative rejected:* squeeze the last ~8% of flake out of an already-passing stage.
This produced F104–F106, including the discovery that Swift works.

### D12 — Test CotEditor 7.0.7 (his newer pin) over 4.5.5 (the written gate)
User's call, resolving a conflict Kevin left open. **Empirically moot** — both versions
fail at the same symbol family — and testing both is what let us say so.

### D13 — Match the project's comment density in contributions
A Darling maintainer requested changes on PR #70: *"one pet peeve I have with AI assisted
contributions is that it adds unnecessary comments in the code… a commit message is good
enough."* He was right, and our own house rule already said to match surrounding code.
Comments removed; the diff is now two lines. **Rationale belongs in the commit message,
not beside the code.** Applied to all future contributions.

### D14 — Apple-owned assets never leave the machine
dyld shared cache, iTerm2/CotEditor bundles, Swift toolchain, corpus binaries: used
locally, never committed. Bundles are additionally never patched, re-signed or rebundled
— Kevin's Definition of Done requires the *unmodified* official artifact, and a modified
one would invalidate the tier.
