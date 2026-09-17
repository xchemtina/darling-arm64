---
name: Defect or flake
about: A reproducible failure in the runtime, a harness, or the ladder
title: ""
labels: defect
---

## What fails

## Reproduction

<!-- Exact commands. If it is intermittent, state the rate and over how many runs. -->

## Architecture and environment

- `uname -m` (Darling runtime host):
- Distro / kernel / clang:
- Darling commit:
- `git-lfs` present:

## First error

<!-- The FIRST error, not the tail. CMake and make both bury the root cause above
     hundreds of follow-on lines. -->

```
```

## Artifacts

<!-- Since F108 the real-runtime drivers keep a failing run's artifacts as
     run<N>-artifacts/. If you used an older driver, say so - they are usually gone. -->
