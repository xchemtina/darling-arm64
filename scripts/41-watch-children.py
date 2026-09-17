#!/usr/bin/env python3
"""
Identify the container process that null-derefs during Darling boot (FINDINGS F7).

Scanning all of /proc is too slow -- the child lives ~1ms. Instead: find the mldr
process running /sbin/launchd, then tight-loop on /proc/<pid>/task/*/children,
which is a single cheap read, and snapshot any new child instantly.
"""
import os, sys, time, glob

DEADLINE = time.time() + float(sys.argv[1] if len(sys.argv) > 1 else 60)


def read(p, d=""):
    try:
        with open(p, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except Exception:
        return d


def find_launchd():
    for d in glob.glob("/proc/[0-9]*"):
        cl = read(f"{d}/cmdline").replace("\0", " ").strip()
        if cl.endswith("/sbin/launchd") and "vchroot" not in cl:
            return d.split("/")[-1]
    return None


# Phase 1: wait for launchd to appear.
launchd = None
while time.time() < DEADLINE and not launchd:
    launchd = find_launchd()
if not launchd:
    print("launchd never appeared", flush=True); sys.exit(1)
print(f"launchd host pid = {launchd}", flush=True)

# Phase 2: tight-loop its children.
seen = set()
while time.time() < DEADLINE:
    kids = set()
    for t in glob.glob(f"/proc/{launchd}/task/*/children"):
        kids.update(read(t).split())
    for k in kids - seen:
        seen.add(k)
        # Read everything immediately -- this process may die in ~1ms.
        cmdline = read(f"/proc/{k}/cmdline").replace("\0", " ").strip()
        comm = read(f"/proc/{k}/comm").strip()
        try:
            exe = os.readlink(f"/proc/{k}/exe")
        except Exception:
            exe = "?"
        maps = read(f"/proc/{k}/maps")
        macho = [l.split()[-1] for l in maps.splitlines()
                 if "darling" in l and l.strip().endswith((".dylib", "dyld"))][:4]
        print(f"CHILD pid={k} comm={comm!r} exe={exe}\n"
              f"      cmdline={cmdline!r}\n"
              f"      early_maps={macho}", flush=True)
    if not os.path.exists(f"/proc/{launchd}"):
        break

print(f"--- done, {len(seen)} children seen ---", flush=True)
