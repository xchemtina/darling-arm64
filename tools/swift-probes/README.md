# Swift capability probes (arm64)

Three minimal Swift programs that bisect where Swift support ends under Darling on
arm64. Build on a macOS host (they are Apple-SDK binaries and are **not committed**):

```sh
swiftc -target arm64-apple-macos12.0 -O s1_core.swift        -o s1_core.arm64
swiftc -target arm64-apple-macos12.0 -O s2_foundation.swift  -o s2_foundation.arm64
swiftc -target arm64-apple-macos12.0 -O s3_appkit_attr.swift -o s3_appkit_attr.arm64
```

Native ground truth (macOS 26, Swift 6.3.3):

| probe | native output |
|---|---|
| s1_core | `SWIFT_CORE_OK [1, 2, 3]` |
| s2_foundation | `SWIFT_FOUNDATION_OK abc true` |
| s3_appkit_attr | `SWIFT_APPKIT_ATTR_OK 1` |

Two ways to run them, and they give different answers:

- `DARLING_ARM64_INSTALL_ROOT=<root> tools/run-staged-darling-arm64.sh /swiftprobe/<name>`
  stages **no shared cache**, so every probe fails. That is F105's result, and F106 shows
  it was an artifact of the runner, not of Darling.
- Wrapped in a minimal `.app` bundle and driven through the **cache-enabled** probe
  harness (`ITERM2_PROBE_SHARED_CACHE=1`, cache mounted at `/iterm-dyld-cache`) — the
  Apple cache supplies a working arm64 Swift runtime. `tools/f107-swift-appkit-bind.sh`
  is the driver.

Result on arm64 as of F107, cache-enabled:

| probe | Darling AppKit bound (`PREFER_DISK_FRAMEWORKS=1`) | Apple AppKit bound (`=0`) |
|---|---|---|
| s1_core | `SWIFT_CORE_OK [1, 2, 3]` — byte-identical to native | — |
| s2_foundation | `SWIFT_FOUNDATION_OK abc true` — byte-identical to native | — |
| s3_appkit_attr | `Symbol not found: _$s10Foundation15AttributeScopesO6AppKitE0dE10AttributesV015ForegroundColorB0ON` | **`SWIFT_APPKIT_ATTR_OK 1`** — byte-identical to native |

The `s3` symbol is exported by **`AppKit.framework/AppKit` itself** on native macOS 26.6;
`libswiftAppKit.dylib` is a bare re-export stub of AppKit with no exports of its own. Darling
supplies its own Cocotron-derived AppKit, so the descriptor cannot exist there — which is why
the failure is `Symbol not found` rather than `Library not loaded`, and why binding the
shared-cache AppKit resolves it (F107, A/B/A over that one flag).
