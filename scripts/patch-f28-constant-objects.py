#!/usr/bin/env python3
"""
DARLING-ARM64 FIX for FINDINGS.md F28. Idempotent. Run from ~/darling/source.

Registers the two compiler-emitted constant-object classes in the build:

  src/external/corefoundation/NSConstantArray.m   -> CoreFoundation
  src/external/foundation/src/NSConstantNumber.m  -> Foundation

The split is not a style choice. The client binary binds
_OBJC_CLASS_$_NSConstantArray from CoreFoundation and
_OBJC_CLASS_$_NSConstantIntegerNumber from Foundation, and that matches where the
superclasses live: NSArray is implemented in CoreFoundation, NSNumber in
Foundation. Defining both in CoreFoundation was tried first and the linker rejected
it outright:

    Undefined symbols for architecture arm64:
      "_OBJC_CLASS_$_NSNumber", referenced from:
          _OBJC_CLASS_$_NSConstantIntegerNumber in NSConstantObjects.m.o
      "_OBJC_METACLASS_$_NSNumber", referenced from:
          _OBJC_METACLASS_$_NSConstantIntegerNumber in NSConstantObjects.m.o

That error is also the reason no reexport reasoning is needed: each class is
defined in exactly the library the client binds it from.

Expects both .m files to already be in place (copy them in first).

Revert with:
  git checkout -- src/external/corefoundation/CMakeLists.txt \
                  src/external/foundation/CMakeLists.txt
  rm src/external/corefoundation/NSConstantArray.m \
     src/external/foundation/src/NSConstantNumber.m
"""
import sys, pathlib

EDITS = [
    ("src/external/corefoundation/CMakeLists.txt",
     "src/external/corefoundation/NSConstantArray.m",
     "\tNSConstantString.m\n",
     "\tNSConstantString.m\n\tNSConstantArray.m\n"),
    ("src/external/foundation/CMakeLists.txt",
     "src/external/foundation/src/NSConstantNumber.m",
     "\tsrc/NSNumber.m\n",
     "\tsrc/NSNumber.m\n\tsrc/NSConstantNumber.m\n"),
]

changed = 0
for cm_rel, src_rel, old, new in EDITS:
    cm, src = pathlib.Path(cm_rel), pathlib.Path(src_rel)
    if not src.exists():
        print(f"FATAL: {src} not in place -- copy it in first", file=sys.stderr)
        sys.exit(1)
    if not cm.exists():
        print(f"FATAL: missing {cm}", file=sys.stderr)
        sys.exit(1)
    s = cm.read_text()
    if src.name in s:
        print(f"  already registered: {src.name}")
        continue
    if s.count(old) != 1:
        print(f"FATAL: anchor found {s.count(old)}x (want 1) in {cm}", file=sys.stderr)
        sys.exit(1)
    cm.write_text(s.replace(old, new, 1))
    print(f"  registered {src.name} in {cm}")
    changed += 1

print(f"done ({changed} file(s) changed)")
