#!/usr/bin/env python3
"""
Catch the short-lived container process that dies during Darling boot (FINDINGS F7).

darlingserver logs "New process created with ID <hostpid> and NSID <containerpid>"
but not the exec path, and the faulting child lives well under a second -- ps polling
at 1s intervals only ever sees it as <defunct>. This scans /proc in a tight loop and
records cmdline/exe/status for every mldr-lineage process the instant it appears.

Run it BEFORE starting `darling shell`; it exits after --seconds.
"""
import os, sys, time, argparse

ap = argparse.ArgumentParser()
ap.add_argument("--seconds", type=float, default=45.0)
ap.add_argument("--interval", type=float, default=0.002)
args = ap.parse_args()

seen = {}
deadline = time.time() + args.seconds


def read(p, default=""):
    try:
        with open(p, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except Exception:
        return default


while time.time() < deadline:
    try:
        pids = [d for d in os.listdir("/proc") if d.isdigit()]
    except Exception:
        continue
    for pid in pids:
        if pid in seen:
            continue
        comm = read(f"/proc/{pid}/comm").strip()
        cmdline = read(f"/proc/{pid}/cmdline").replace("\0", " ").strip()
        # mldr renames itself to the Mach-O it loaded, so match on either.
        blob = f"{comm} {cmdline}"
        if not any(k in blob for k in ("mldr", "launchd", "shellspawn", "iokitd",
                                       "darling")):
            continue
        try:
            exe = os.readlink(f"/proc/{pid}/exe")
        except Exception:
            exe = "?"
        ppid = ""
        for line in read(f"/proc/{pid}/status").splitlines():
            if line.startswith("PPid:"):
                ppid = line.split()[1]
                break
        seen[pid] = True
        print(f"[{time.time()%1000:8.3f}] pid={pid:<7} ppid={ppid:<7} "
              f"comm={comm:<16} exe={exe}\n"
              f"            cmdline={cmdline!r}", flush=True)
    time.sleep(args.interval)

print(f"\n--- watcher done, {len(seen)} processes captured ---", flush=True)
