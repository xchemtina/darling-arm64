# NEXT_STEPS — ordered queue (2026-08-15)

Ordered by *verified arm64 capability gained per hour*. Each item states what it buys,
what it costs, and how we would know it worked.

---

## 1. Pin the Swift↔AppKit blocker — the ladder's gate ⭐ highest leverage

**Status 2026-09-17: steps 1–3 done for the probe — F107.** The descriptors live in
Apple's AppKit binary; `libswiftAppKit` is an empty stub; with the cache AppKit bound the
probe passes byte-identically to native (A/B/A). The item now reads: *what does a GUI
application do on Apple's AppKit under Darling?* — `tools/f110-coteditor-apple-appkit.sh`.

**Why first:** Swift works on arm64 (F106). The *only* failure is
`AttributeScopes.AppKitAttributes.*` — the same family that blocks both pinned CotEditor
versions. That single seam gates Stage 20, which gates Stage 21 (Gold). It is bounded,
nameable work, not a port.

**Do, in order (each is cheap and informative):**
1. Confirm whether `libswiftAppKit.dylib` actually loads in the failing run, and from
   where (cache vs disk) — `dserver.log` + the probe's image list.
2. Determine whether the missing type descriptors exist in the cache's AppKit overlay
   but fail to bind because **Darling's** AppKit is selected (the leading hypothesis).
3. Flip the hybrid selection to prefer Apple's AppKit and re-run `s3_appkit_attr`. This
   may trade one failure for another — which is itself the answer.

**Success:** `s3_appkit_attr` prints `SWIFT_APPKIT_ATTR_OK 1`, or we can state precisely
why Apple's Swift AppKit bridge cannot sit on Darling's AppKit. **Effort:** 2–4 h.

---

## 2. Fix F102 (the thread-bridge broker abort) — a general crash class

**Why:** it kills *any* forking app pre-exec and also fires on SIGHUP at teardown, so it
is not a CotEditor or iTerm2 issue — it is a process-lifetime hazard on arm64. Mechanism
is confirmed (prediction verified 3/3); only the fix is outstanding.

**The fix must be two-sided** — this is the trap: blocking signals across the broker's
creation (`threads.c:263`) alone would make every Darwin thread inherit a fully-blocked
mask and go permanently signal-deaf. Capture the requesting thread's mask in
`arm64_thread_create_submit` and restore it around the inner `pthread_create`
(`threads.c:252`).

**Before building:** zero-build discriminator — re-run with
`DARLING_ARM64_THREAD_BRIDGE=0` (flip it in the probe **and all seven launchd plists
together**, or the test is contaminated). No broker ⇒ the abort must vanish.

**Success:** the `___simple_abort+0x18` ← `_sigexc_handler+0x25c` signature disappears,
no new signal-delivery failures, and it survives adversarial review. Then a fourth
upstream PR. **Effort:** 2–3 h.

---

## 3. Settle `darlingserver#17`'s real-world effect (or stop claiming it)

**Why:** the *mechanism* is proven and upstreamed; the end-to-end improvement is a
**trend, not an effect** (18%→8%, p=0.23 at n=50; p=0.096 pooled). We should either
demonstrate it or keep saying "not demonstrated".

**Do:** ~180 runs/arm on the f103 pair for 80% power at α=0.05 — but **only after items
1–2**, because if mode B is also fixed the combined effect is larger and needs fewer
runs. Fold the measurement into a single `stock` vs `all-fixes` A/B.

**Success:** a p<0.05 result either way, honestly reported. **Effort:** ~4 h unattended.

---

## 4. Close the residual failure modes on the real runtime

From the n=50 patched arm, what remains is: 2× "typed keystrokes never executed by an
already-running shell within timeout" (at tab-1 startup and post-close survivor), plus a
**silent** class — eight of the gate's late assertions are bare `[[ ]]` and print nothing
on failure. Diagnosing these needs the evidence-preservation fix (below) first.

**Effort:** 2 h. **Success:** each residual mode named, or shown to be gate-logic rather
than Darling.

---

## 5. Stop destroying our own evidence (do this alongside anything else)

**Status 2026-09-17: done — F108.** `f103-stage18-ab.sh` and `f101-realworld.sh` keep a
failing run's artifacts as `run<N>-artifacts/` plus the probe log; verified 2/2 on id26.

The gate pipes probe stdout to a `/tmp` file that is **overwritten every run**, and
drivers `rm -rf` the artifact dir **before** each run — so `iterm2-job.err` (~34 KB,
where a crash is visible) is destroyed ~4 s after every failure. Every failure so far has
needed a *re-run* to diagnose.

**Fix in our drivers, not Kevin's gate:** capture probe stdout per run; `mv` the artifact
dir aside on `rc != 0`. **Effort:** 30 min. **Pays for itself the first time.**

---

## 6. Ask Kevin the three questions only he can answer

1. **CotEditor:** his record describes reaching a live document window; we cannot
   reproduce it (no arm64 Swift AppKit path). What configuration achieved it?
2. **Version:** issue #1 pins CotEditor 4.5.5, his north-star/COMPATIBILITY pin 7.0.7.
   Empirically moot — both fail identically — but which is the intended gate?
3. **Priority:** does he want Stage 20 pursued, or iTerm2 Silver hardened to reliable
   first?

He has been silent since 2026-07-16 (no commits, no issue comments, no reply to our
issue #10), so these ride with the report rather than blocking work.

---

## Deliberately not doing

- **Building an arm64 Swift runtime.** F106 shows the Apple cache already supplies a
  working one; a port would be large, duplicative work aimed at the wrong seam.
- **Chasing the `AttributeScopes` symbols by patching Darling's AppKit blindly.** Item 1
  must say *why* they fail first — this project has spent enough on unverified fixes.
- **Any x86_64 work.** Out of mandate.
- **Editing gates/checksums to make something pass.** Ever.
