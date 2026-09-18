# OPEN-WORK — what to pick up, and how you would know it worked

Entry points for contributors, ordered by **verified arm64 capability gained per hour**.
Each states what it buys, what it costs, and its success criterion. The full reasoning is
in `NEXT_STEPS.md`; the evidence standard every item is held to is in `CONTRIBUTING.md`.

**Before anything:** read `STATE.md` §Traps. Several will cost you the same hours they
already cost us.

## Can you run this work?

| You have | You can do |
|---|---|
| aarch64 Linux (a VM on Apple silicon is the normal setup) | everything below |
| arm64 macOS as well | the above, plus regenerating native ground truth |
| neither | items **5** and **6**, plus reviewing and reproducing open pull requests by reading |

x86_64 hardware cannot produce a valid result for any item here. Darling is a translation
layer, not a CPU emulator: the host architecture must match the binary architecture.

---

## 1. Get a GUI application running on Apple's AppKit ⭐ highest leverage

**Effort:** open. **Gates:** Stage 20, which gates Stage 21 (Gold).

F106 showed Swift works on arm64 and the *only* failure was the
`AttributeScopes.AppKitAttributes.*` family. F107 located it: those descriptors are exported
by **Apple's AppKit binary itself** (289 `AttributeScopes` symbols), and `libswiftAppKit`
is an empty re-export stub — so they cannot exist against Darling's Cocotron-derived AppKit.
With the shared-cache AppKit bound instead (`ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=0`) the
probe prints `SWIFT_APPKIT_ATTR_OK 1`, byte-identical to native, A/B/A over that one flag.

The open question is what a real GUI application does on Apple's AppKit, which needs
surfaces Darling does not provide. `tools/f110-coteditor-apple-appkit.sh` asked: with
Apple's AppKit the symbol resolves and CotEditor dies with a startup `SIGSEGV` inside the
shared cache (F110). Leading suspect: the duplicate classes between Apple's AppKit and
`libDarlingAppKitBootstrap`. `tools/f111-coteditor-no-bootstrap.sh` tries the shim off, but
the probe engine currently refuses that flag combination (exit 2) — making that arm runnable
without editing the upstream probe is the first concrete task; symbolicating the fault
(`atos` against the VM's cache) is the second.

**Do not** patch Darling's AppKit blindly to chase the symbols. F107 says why they are
missing; the work is deciding which AppKit a Swift application should bind, not shimming
descriptors.

---

## 2. Fix F102 — the thread-bridge broker abort

**Effort:** 2–3 h. **Buys:** a general crash class, and a fourth upstream PR.

This kills *any* forking application pre-exec and also fires on `SIGHUP` at teardown, so
it is not an iTerm2 or CotEditor issue — it is a process-lifetime hazard on arm64. The
mechanism is confirmed (prediction verified 3/3). Only the fix is outstanding, and it was
deliberately left unfixed because the obvious version is wrong.

**The trap:** blocking signals across the broker's creation (`threads.c:263`) alone would
make every Darwin thread inherit a fully-blocked mask and go permanently signal-deaf. The
fix must be two-sided — capture the requesting thread's mask in
`arm64_thread_create_submit` and restore it around the inner `pthread_create`
(`threads.c:252`).

`tools/f109-thread-bridge-discriminator.sh` is the zero-build discriminator: it flips
`DARLING_ARM64_THREAD_BRIDGE` at all eight sites (probe line 463 plus the seven generated
launchd plists) in a temporary copy of the probe and captures cores. Flip them separately
and you are measuring the mismatch, not the change.

**Success:** the `___simple_abort+0x18` ← `_sigexc_handler+0x25c` signature disappears,
no new signal-delivery failures appear, and it survives adversarial review.

---

## 3. Settle `darlingserver#17`'s real-world effect — or stop claiming it

**Effort:** ~4 h, mostly unattended. **Do only after items 1–2.**

The *mechanism* is proven and upstreamed. The end-to-end improvement is a **trend, not an
effect** (18%→8%, p=0.23 at n=50; p=0.096 pooled). We should either demonstrate it or keep
saying "not demonstrated".

Roughly 180 runs per arm on the f103 pair gives 80% power at α=0.05. Fold it into a single
`stock` vs `all-fixes` A/B with `tools/f103-stage18-ab.sh`.

**Success:** a p<0.05 result **either way**, honestly reported. A negative result is a
complete outcome here.

---

## 4. Name the residual failure modes on the real runtime

**Effort:** 2 h. **Unblocked by F108** — failing runs now keep their artifacts.

From the n=50 patched arm, what remains is two runs of "typed keystrokes never executed by
an already-running shell within timeout" (at tab-1 startup and on the post-close
survivor), plus a **silent** class: eight of the gate's late assertions are bare `[[ ]]`
and print nothing at all on failure.

**Success:** each residual mode is named, or shown to be gate logic rather than Darling.

---

## 5. Implement `-[NSButton hasDestructiveAction]` in Cocotron 🔰 good first contribution

**Effort:** 1–2 h. **Buys:** every root with a macOS ≥ 11 identity.

The first artifact ever preserved by F108 named the 100% failure of the 26.5-identity root:
`-[NSButton setHasDestructiveAction:]: unrecognized selector`, thrown from
`-[iTermWarning makeAlert]`. It is a macOS 11 API that Darling's AppKit lacks, reached
because `@available` forks on the emulated OS version (F93). A property that stores the
flag is enough; the harness is `tools/f101-realworld.sh 1` on `install-arm64-id26`, which
fails deterministically today.

**Success:** the exception is gone on id26 and the change reverses on revert.

---

## 6. Reproduce something, or falsify it 🔰 good first contribution

**Effort:** open-ended. **No patch required.**

`REPRODUCE.md` maps every headline claim to the harness that regenerates it. Pick one and
run it. Report what you got, verbatim.

A **clean, reproducible negative result is an accepted outcome** — as is overturning a
recorded finding, including one of ours. `FINDINGS.md` keeps its retractions in place;
three claims were already withdrawn by our own controls. If you can falsify a fourth, that
is real work and it is scored as such.

Use the "Challenge a finding" issue template.

---

## Deliberately not being done

Proposing these will not earn anything:

- **Building an arm64 Swift runtime.** F106 shows the Apple shared cache already supplies
  a working one. A port would be large, duplicative work aimed at the wrong seam.
- **Patching Darling's AppKit blindly** to chase `AttributeScopes` symbols. See item 1.
- **Any x86_64 work.** Out of mandate, and it cannot produce evidence here.
- **Editing gates, checksums, or thresholds to make something pass.** Ever.

## Open questions only upstream can answer

Recorded here so nobody re-derives them. The upstream arm64 author has been silent since
2026-07-16, so these ride with the report rather than blocking work:

1. **CotEditor.** The upstream record describes reaching a live document window. We cannot
   reproduce it and do not claim the record is wrong. What configuration achieved it?
2. **Version.** Issue #1 pins CotEditor 4.5.5; north-star/COMPATIBILITY pins 7.0.7.
   Empirically moot — both fail identically — but which is the intended gate?
3. **Priority.** Stage 20 pursued next, or iTerm2 Silver hardened to reliable first?
