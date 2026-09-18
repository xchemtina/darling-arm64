#!/usr/bin/env python3
# fix-resume-latch.py — pending-wake latch for the session-spawn lost wake (F100).
# resume() arriving before suspend() sets _suspended must not be dropped: latch it and
# have suspend() reschedule itself. Host-side only (thread.hpp + thread.cpp), does NOT
# touch shared Apple kern_synch.c. Reversible with --revert.
import sys, pathlib
BASE = pathlib.Path.home() / "darling/source/src/external/darlingserver"
HPP = BASE / "internal-include/darlingserver/thread.hpp"
CPP = BASE / "src/thread.cpp"
TAG = "F100 latch"

hpp = HPP.read_text(); cpp = CPP.read_text()

hpp_anchor = "\t\tbool _suspended = false;\n"
hpp_add = "\t\tbool _suspended = false;\n\t\tbool _resumePending = false; // F100 latch: a resume that raced ahead of suspend()\n"

resume_anchor = """void DarlingServer::Thread::resume() {
	{
		std::shared_lock lock(_rwlock);
		if (!_suspended) {
			// maybe we should throw an error here?
			return;
		}
	}

	Server::sharedInstance().scheduleThread(shared_from_this());
};"""
resume_new = """void DarlingServer::Thread::resume() {
	{
		std::unique_lock lock(_rwlock); // F100 latch: need write access to _resumePending
		if (!_suspended) {
			// A resume that arrives before suspend() has set _suspended would be dropped
			// here, parking the microthread forever (the session-spawn lost wake, F100).
			// Latch it so the imminent suspend() reschedules instead of parking.
			_resumePending = true;
			return;
		}
	}

	Server::sharedInstance().scheduleThread(shared_from_this());
};"""

suspend_anchor = """	_rwlock.lock();
	_suspended = true;
	_rwlock.unlock();

	unlockMeWhenSuspending = unlockMe;"""
suspend_new = """	_rwlock.lock();
	_suspended = true;
	bool hadPendingResume = _resumePending; // F100 latch
	_resumePending = false;
	_rwlock.unlock();

	if (hadPendingResume) {
		// A resume arrived before we suspended (F100 session-spawn lost wake): don't park
		// forever -- schedule ourselves so doWork() resumes us through the normal path.
		Server::sharedInstance().scheduleThread(shared_from_this());
	}

	unlockMeWhenSuspending = unlockMe;"""

if "--revert" in sys.argv:
    hpp = hpp.replace(hpp_add, hpp_anchor)
    cpp = cpp.replace(resume_new, resume_anchor).replace(suspend_new, suspend_anchor)
    HPP.write_text(hpp); CPP.write_text(cpp)
    print("reverted latch:", TAG not in (hpp+cpp))
    sys.exit(0)

if TAG in (hpp + cpp):
    print("already applied"); sys.exit(1)

n = 0
if hpp_anchor in hpp: hpp = hpp.replace(hpp_anchor, hpp_add, 1); n += 1
else: print("WARN hpp anchor miss")
if resume_anchor in cpp: cpp = cpp.replace(resume_anchor, resume_new, 1); n += 1
else: print("WARN resume anchor miss")
if suspend_anchor in cpp: cpp = cpp.replace(suspend_anchor, suspend_new, 1); n += 1
else: print("WARN suspend anchor miss")

HPP.write_text(hpp); CPP.write_text(cpp)
print(f"applied latch: {n}/3 anchors, tag present={TAG in (hpp+cpp)}")
