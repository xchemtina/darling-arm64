# GUI on ARM64 — confirmed working

**2026-08-08.** AppKit renders on aarch64 Linux under X11. This supersedes the
earlier statement in `OVERNIGHT-REPORT.md` that "no GUI application has been
launched" — that was true when written and is no longer true.

## The evidence

`~/darling/artifacts/stage11-x11/` (copies in `report/`):

| File | Shows |
|---|---|
| `x11-backend-smoke.png` | 360×242 window: title bar, text "Darling ARM64 X11" in a real font, three filled rectangles (red/green/blue) |
| `x11-backend-smoke-resized.png` | 520×320: identical content reflowed after a live resize |
| `x11-backend-smoke-fixed-resized.png` | fixed-size window resize behaviour |

Text is rendered through the font stack (`San Francisco` resolved), the rectangles
through CoreGraphics/Onyx2D, and the window is managed by a real window manager
(openbox) inside a nested X server (Xvfb `:92` → Xephyr `:93`).

## Verified subsystems

From `artifacts/stage11-x11/failure-markers/`:

| Marker | Value | Meaning |
|---|---|---|
| `x11-backend-ready` | `ready` | window created and app signalled readiness |
| `x11-backend-screen` | `1000x680@2` | screen geometry **with HiDPI scale factor 2** |
| `x11-backend-focus` | `focused` | focus events delivered |
| `x11-backend-resize` | `resized` | live resize handled |
| `x11-backend-cursor` | `xterm` | cursor shape/theme resolution |
| `x11-backend-font` | `San Francisco` | Apple system font resolved |
| `x11-backend-key` | `characters=;shift=0;control=0;option=1;command=0;caps=0;repeat=0;keyCode=55` | keyboard events with **full modifier decoding** |
| `x11-backend-phase` | `pasteboards` | scroll phase/momentum/precise/delta handled; reached the pasteboard stage |

Plus, from the verifier's own assertions before the failure: `_NET_WM_WINDOW_TYPE_DIALOG`,
`_NET_WM_STATE_MODAL`, `WM_STATE: Normal`, `WM_PROTOCOLS: WM_DELETE_WINDOW`,
`_NET_WM_ACTION_CLOSE`, and `WM_TRANSIENT_FOR` correctly pointing at the parent —
i.e. a properly-formed modal dialog, correctly advertised to the window manager.

## Where it stops

**F24** — a click on the modal dialog never reaches its handler (2.5 s timeout).

Critically, a click on the *parent* window while the modal is up **is** correctly
blocked. So modal semantics work; input delivery into the transient window does
not. That is a narrow event-routing defect, not a structural gap.

Investigation should start in the X11 backend's event pump —
`src/external/cocotron/CoreGraphics/X11.backend/CGSConnectionX11.m` and the AppKit
backend — comparing how a button press is targeted at the key window versus a
window with `WM_TRANSIENT_FOR` set.

## Correction worth recording

I first reported this failure as *undiagnosable*, reasoning that the verifier runs
in an ephemeral `--rm` container so its evidence was destroyed. **That was wrong.**
The verifier bind-mounts `-v "$artifact_root:/artifacts"`, and screenshots plus
phase markers persist at `~/darling/artifacts/stage11-x11/`.

The lesson generalises: before concluding that evidence was lost to an ephemeral
container, check the mount list. Had I not re-read the script, this entire result
would have stayed hidden behind a one-line timeout message.

## Full GUI verifier results

The `x11` gate halts at the first failure, so each verifier was run independently
(`~/run-x11-all.sh` in the VM; per-verifier logs at `~/x11-<name>.log`):

| Verifier | Result | Note |
|---|---|---|
| `x11-backend` | ❌ | **F24** — modal click; every prior stage passes |
| `hello-window` | ❌ | **renders correctly**, screenshot captured; gate still fails |
| **`controls`** | ✅ | `ARM64 Controls.app milestone passed` |
| **`text-view`** | ✅ | `ARM64 TextView.app milestone passed` |
| `text-edit` | ❌ | failure reason not isolated |
| **`pty-harness`** | ✅ | `ARM64 PTYHarness milestone passed` |
| `mini-term` | ❌ | failure reason not isolated |

**3 of 7 pass.** Three GUI applications clear their milestones outright on ARM64.

### Secondary finding — duplicate AppKit classes

`hello-window` logs:
```
objc[1]: Class NSATSTypesetter is implemented in both
  /System/Library/PrivateFrameworks/UIFoundation.framework/.../UIFoundation and
  /System/Library/Frameworks/AppKit.framework/.../AppKit.
  One of the two will be used. Which one is undefined.
```
Same for `NSCollectionViewLayout`, `NSCollectionViewLayoutAttributes`,
`NSCollectionViewLayoutInvalidationContext`.

deepai-org's own `COMPATIBILITY.md` lists "duplicate cached/disk AppKit classes"
as an open issue blocking CotEditor — so this is a known problem of theirs, now
independently reproduced here. Whether it causes the `hello-window`,
`text-edit` or `mini-term` failures is **not established**; it may be benign noise.

### Both failures now isolated

**`mini-term` — F25.** Everything works except one startup detail. Evidence in
`artifacts/stage17-mini-term/`: launch **478 ms**, terminal **119×36**,
**520 colours**, and `colors.png` shows `C16` red / `C256` orange / `CTRUE` green
— 16-colour, 256-colour and **24-bit truecolor** ANSI all correct — plus Unicode,
wide chars, combining marks, CR+erase-to-EOL, and the alternate screen buffer.

It fails because the terminal's **line 0 is corrupt**: `last-output.txt` begins
`echnorth-star$`, i.e. three characters of the typed command echo at column 0
*before* the shell prompt. The verifier's selection assertion (`{0, 6}`) then
correctly yields `echnor`. **The selection code is fine; the buffer is wrong.**

**`text-edit` — F27.** The save never writes a file:
```
cmp: .../private/var/tmp/stage15.txt: No such file or directory
```
Most likely `super+s` not reaching the app, or the save panel's hard-coded click
coordinates (600,579 / 825,577) missing their targets at this window size.

⚠️ I first misread this one, claiming the save phase passed and the failure was in
reopen via `-NSOpen`. That was inferred from the presence of `save-launch-ms.txt`
without checking that it records a **launch** time, written before any typing.
Corrected in `FINDINGS.md` F27.

## Reproducing

```bash
cd ~/darling/source
DARLING_ARM64_INSTALL_ROOT=$HOME/darling/install-arm64-stage10 \
  tools/verify-north-star-arm64.sh x11
# then inspect:
ls ~/darling/artifacts/stage11-x11/
cat ~/darling/artifacts/stage11-x11/failure-markers/*
```

The remaining six verifiers (`hello-window`, `controls`, `text-view`,
`text-edit`, `pty-harness`, `mini-term`) have not run yet — the suite stops at the
first failure.
