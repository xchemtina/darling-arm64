#!/usr/bin/env python3
"""
DARLING-ARM64 LOCAL PATCHES for FINDINGS.md F1 and F2.

These are proper fixes, not -Wno-error suppressions. Run from ~/darling.
Idempotent.

F1  xnu .../linux_premigration/ext/sys/epoll.h
    Declares epoll_create / epoll_ctl / epoll_wait but NOT epoll_create1, while
    still #define-ing epoll_create1 -> __linux_epoll_create1. On aarch64 there is
    no __NR_epoll_create, so epoll_create() takes its #else branch and calls
    epoll_create1() with no declaration in scope. Dead code on x86_64, which is
    why nobody hit it. Fix: declare it.

F2  libkqueue src/linux/timer.c
    evfilt_timer_knote_enable() passed &kn->kev (struct kevent_internal_s *)
    through a const struct kevent64_s * parameter. The layouts differ --
    kevent_internal_s carries qos and ext[4] -- so the callee's writeback of
    data/flags/fflags into kn->kev read from mismatched offsets and corrupted the
    knote on every timer re-arm. Source and destination were the same object, so
    the copy was never needed; re-arm in place instead. Type-correct, no cast.
"""
import sys, pathlib

MARK = "DARLING-ARM64 LOCAL PATCH"
rc = 0


def patch(path, old, new, label):
    global rc
    p = pathlib.Path(path)
    if not p.exists():
        print(f"  {label}: FATAL missing {p}", file=sys.stderr); rc = 1; return
    s = p.read_text()
    if MARK in s:
        print(f"  {label}: already patched"); return
    if old not in s:
        print(f"  {label}: FATAL anchor not found", file=sys.stderr); rc = 1; return
    p.write_text(s.replace(old, new, 1))
    print(f"  {label}: patched {p}")


# ---------------------------------------------------------------------- F1 ---
patch(
    "src/external/xnu/darling/src/libsystem_kernel/emulation/"
    "include/linux_premigration/ext/sys/epoll.h",
    "extern int epoll_create (int __size) __THROW;",
    "extern int epoll_create (int __size) __THROW;\n"
    "\n"
    "/* DARLING-ARM64 LOCAL PATCH (FINDINGS.md F1): epoll_create1 was #define'd to\n"
    "   __linux_epoll_create1 but never declared. aarch64 has no __NR_epoll_create,\n"
    "   so epoll_create() falls through to epoll_create1() and hit an implicit\n"
    "   declaration (a hard error on clang >= 16). Dead code on x86_64. */\n"
    "extern int epoll_create1 (int __flags) __THROW;",
    "F1 epoll_create1 declaration",
)

# ---------------------------------------------------------------------- F2 ---
patch(
    "src/external/libkqueue/src/linux/timer.c",
    "int\n"
    "evfilt_timer_knote_enable(struct filter *filt, struct knote *kn)\n"
    "{\n"
    "    return evfilt_timer_knote_modify(filt, kn, &kn->kev);\n"
    "}",
    "int\n"
    "evfilt_timer_knote_enable(struct filter *filt, struct knote *kn)\n"
    "{\n"
    "    /* DARLING-ARM64 LOCAL PATCH (FINDINGS.md F2): this previously called\n"
    "       evfilt_timer_knote_modify(filt, kn, &kn->kev), passing a\n"
    "       struct kevent_internal_s * through a const struct kevent64_s *\n"
    "       parameter. The layouts differ (kevent_internal_s carries qos and\n"
    "       ext[4]), so the callee's writeback into kn->kev.data/flags/fflags\n"
    "       read from mismatched offsets and corrupted the knote on every\n"
    "       re-arm. Source and destination were the same object, so the copy was\n"
    "       never needed -- re-arm in place, type-correct and cast-free. */\n"
    "    struct itimerspec ts;\n"
    "    int tfd = kn->data.pfd;\n"
    "\n"
    "    if (!kn->kev.data)\n"
    "        kn->kev.data = 1;\n"
    "\n"
    "    convert_to_itimerspec(&ts, kn->kev.data, kn->kev.flags & EV_ONESHOT,\n"
    "                          kn->kev.fflags);\n"
    "    if (timerfd_settime(tfd, 0, &ts, NULL) < 0) {\n"
    "        dbg_printf(\"timerfd_settime(2): %s\", strerror(errno));\n"
    "        return (-1);\n"
    "    }\n"
    "\n"
    "    return (0);\n"
    "}",
    "F2 timer knote_enable type punning",
)

sys.exit(rc)
