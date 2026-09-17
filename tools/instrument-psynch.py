#!/usr/bin/env python3
# instrument-psynch.py — additive-only logging to positively confirm (or refute) the
# kw_intr stranded-grant lost-wake mechanism. NO semantic change: only dtape_log_error
# calls. Applied to kern_synch.c inside the VM. Reversible via instrument-psynch.py --revert.
import sys, re, pathlib
F = pathlib.Path("/home/crischimiadao.guest/darling/source/src/external/darlingserver/duct-tape/pthread/kern_synch.c")
MARK = "PSYNCH_INSTR"
src = F.read_text()

if "--revert" in sys.argv:
    lines = [l for l in src.splitlines(keepends=True) if MARK not in l]
    F.write_text("".join(lines))
    print(f"reverted: removed all {MARK} lines")
    sys.exit(0)

if MARK in src:
    print("already instrumented; run --revert first"); sys.exit(1)

edits = 0

# 1) MINT: after _kwq_mark_interruped_wakeup in the SEQFIT KERN_NOT_WAITING branch (~611)
anchor_mint = """				if (ret == KERN_NOT_WAITING) {
					/* interrupt post */
					_kwq_mark_interruped_wakeup(kwq, KWQ_INTR_WRITE, 1,
							nextgen, updatebits);
				}"""
add_mint = """				if (ret == KERN_NOT_WAITING) {
					/* interrupt post */
					_kwq_mark_interruped_wakeup(kwq, KWQ_INTR_WRITE, 1,
							nextgen, updatebits);
					dtape_log_error("PSYNCH_INSTR mint kwq=%p intr.seq=%u count->%u (drop signalled a not-waiting/aborted waiter)\\n", kwq, nextgen, kwq->kw_intr.count);
				}"""
if anchor_mint in src:
    src = src.replace(anchor_mint, add_mint, 1); edits += 1
else:
    print("WARN: mint anchor not found")

# 2) CLAIM GATE: instrument both the successful claim and the stranded-reject case.
anchor_gate = """	if (kwq->kw_intr.count != 0 && kwq->kw_intr.type == type &&
			(!kwq->kw_intr.seq || is_seqlower_eq(lseq, kwq->kw_intr.seq))) {
		kwq->kw_intr.count--;"""
add_gate = """	if (kwq->kw_intr.count != 0 &&
			!(kwq->kw_intr.type == type && (!kwq->kw_intr.seq || is_seqlower_eq(lseq, kwq->kw_intr.seq)))) {
		dtape_log_error("PSYNCH_INSTR claim-REJECT kwq=%p lseq=%u intr.seq=%u intr.count=%u type=%d/%d (stranded grant: contender seq too high)\\n", kwq, lseq, kwq->kw_intr.seq, kwq->kw_intr.count, type, kwq->kw_intr.type);
	}
	if (kwq->kw_intr.count != 0 && kwq->kw_intr.type == type &&
			(!kwq->kw_intr.seq || is_seqlower_eq(lseq, kwq->kw_intr.seq))) {
		dtape_log_error("PSYNCH_INSTR claim-OK kwq=%p lseq=%u intr.seq=%u\\n", kwq, lseq, kwq->kw_intr.seq);
		kwq->kw_intr.count--;"""
if anchor_gate in src:
    src = src.replace(anchor_gate, add_gate, 1); edits += 1
else:
    print("WARN: claim-gate anchor not found")

# 3) DYING HOOK: log entry + whether the kwe is still enqueued (queued vs already-signalled/stranded)
anchor_dying = """void dtape_psynch_thread_dying(thread_t thread, struct ksyn_waitq_element* kwe) {
	if (kwe->kwe_kwqqueue) {"""
add_dying = """void dtape_psynch_thread_dying(thread_t thread, struct ksyn_waitq_element* kwe) {
	dtape_log_error("PSYNCH_INSTR dying kwe=%p kwqqueue=%p (non-NULL=still-queued/aborted-before-signal; NULL=already-dequeued/grant-may-be-stranded)\\n", kwe, kwe->kwe_kwqqueue);
	if (kwe->kwe_kwqqueue) {"""
if anchor_dying in src:
    src = src.replace(anchor_dying, add_dying, 1); edits += 1
else:
    print("WARN: dying anchor not found")

F.write_text(src)
print(f"instrumented: {edits}/3 anchors patched, {src.count(MARK)} log sites")
