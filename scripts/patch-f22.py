#!/usr/bin/env python3
"""
DARLING-ARM64 LOCAL PATCH for FINDINGS.md F22. Run from ~/darling/source. Idempotent.

src/external/dbuskit/Source/DKArgument.m:993

    IMP unboxFun = [value methodForSelector: aSelector];
    *buffer = (long long)(uintptr_t)(void*)unboxFun(value, aSelector);
                                          ^ error: too many arguments to function
                                            call, expected 0, have 2

In the modern Objective-C runtime `IMP` is `id (*)(void)` — deliberately
argument-less so that callers are forced to cast it to the real signature before
invoking. This matters far more on arm64 than on x86_64: the arm64 procedure call
standard passes variadic and non-variadic arguments differently, so calling
through an unspecified-prototype pointer is not merely sloppy, it is wrong.

dbuskit is NOT in deepai-org's configure-private-submodules.sh mirror map (same as
liblzma, F19), so a clean north-star checkout gets unpatched
darlinghq/darling-dbuskit. kkHAIKE carried a fix for this component
(darling-dbuskit#1) which deepai-org did not take.

Fix: cast to the concrete signature before calling, preserving the original
value-laundering through void*/uintptr_t.
"""
import sys, pathlib

P = pathlib.Path("src/external/dbuskit/Source/DKArgument.m")
CALL = "*buffer = (long long)(uintptr_t)(void*)unboxFun(value, aSelector);"

if not P.exists():
    print(f"FATAL: missing {P}", file=sys.stderr); sys.exit(1)
lines = P.read_text().splitlines(keepends=True)
if any("FINDINGS.md F22" in l for l in lines):
    print("already patched"); sys.exit(0)

idx = next((i for i, l in enumerate(lines) if CALL in l), None)
if idx is None:
    print("FATAL: anchor not found", file=sys.stderr); sys.exit(1)

# Preserve whatever indentation the file actually uses (it is 7 spaces here,
# which is why an indentation-sensitive anchor failed).
ind = lines[idx][: len(lines[idx]) - len(lines[idx].lstrip())]
lines[idx] = lines[idx].replace("unboxFun(value", "unboxFunTyped(value")
lines.insert(idx, (
    f"{ind}// DARLING-ARM64 LOCAL PATCH (FINDINGS.md F22): IMP is `id (*)(void)` in\n"
    f"{ind}// the modern ObjC runtime and must be cast to the real signature before\n"
    f"{ind}// being called. On arm64 this is a correctness issue, not just a warning:\n"
    f"{ind}// the AAPCS passes variadic and non-variadic arguments differently.\n"
    f"{ind}void* (*unboxFunTyped)(id, SEL) = (void* (*)(id, SEL))unboxFun;\n"
))
P.write_text("".join(lines))
print(f"patched {P}")
