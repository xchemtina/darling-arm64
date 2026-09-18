#!/usr/bin/env python3
# fix-stale-wait-timer.py — F101 fix: restore XNU's wait-timer cancel in dtape's
# thread_unblock. dtape's rewrite omitted the cancel block from
# xnu/osfmk/kern/sched_prim.c thread_unblock(); a timed wait completing normally
# therefore leaves its wait_timer armed, and the stale timer later fires into an
# unrelated untimed wait (spurious THREAD_TIMED_OUT -> MACH_RCV_TIMED_OUT ->
# libdispatch's untimed reply receive -> DISPATCH_INTERNAL_CRASH brk -> iTerm2 dies:
# the session-spawn flake). Exact-string apply/revert.
import sys, pathlib
F = pathlib.Path.home() / "darling/source/src/external/darlingserver/duct-tape/src/thread.c"
TAG = "F101 stale wait timer"

anchor = """// thread locked
boolean_t thread_unblock(thread_t xthread, wait_result_t wresult) {
	dtape_thread_t* thread = dtape_thread_for_xnu_thread(xthread);
	thread->xnu_thread.wait_result = wresult;
	dtape_hooks->thread_resume(thread->context);
	return TRUE;
};"""

patched = """// thread locked
boolean_t thread_unblock(thread_t xthread, wait_result_t wresult) {
	dtape_thread_t* thread = dtape_thread_for_xnu_thread(xthread);
	thread->xnu_thread.wait_result = wresult;
	// F101 stale wait timer: cancel any pending wait timer, exactly as XNU's
	// thread_unblock does (osfmk/kern/sched_prim.c). Without this, a timed wait
	// that completes normally leaves wait_timer armed; the stale timer later
	// fires during an unrelated *untimed* wait and delivers a spurious
	// THREAD_TIMED_OUT, which surfaces as MACH_RCV_TIMED_OUT on libdispatch's
	// untimed reply-port receive -- a contract violation libdispatch treats as
	// fatal (brk in _dispatch_mach_send_and_wait_for_reply).
	if (thread->xnu_thread.wait_timer_is_set) {
		if (timer_call_cancel(&thread->xnu_thread.wait_timer)) {
			thread->xnu_thread.wait_timer_active--;
		}
		thread->xnu_thread.wait_timer_is_set = FALSE;
	}
	dtape_hooks->thread_resume(thread->context);
	return TRUE;
};"""

s = F.read_text()
if "--revert" in sys.argv:
    if patched in s:
        F.write_text(s.replace(patched, anchor, 1)); print("reverted cleanly")
    else:
        print("patched form not found; nothing reverted" if TAG not in s else "WARN: tag present but block mismatch")
    sys.exit(0)

if TAG in s:
    print("already applied"); sys.exit(1)
assert anchor in s, "anchor not found"
F.write_text(s.replace(anchor, patched, 1))
print("applied: F101 stale-wait-timer fix in thread_unblock")
