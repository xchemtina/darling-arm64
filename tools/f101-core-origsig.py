#!/usr/bin/env python3
# core-origsig.py <core> <siginfo_addr> <ucontext_addr>
# Extract the ORIGINAL signal's siginfo + mcontext (Linux aarch64 layouts) from the
# guest addresses that sigexc_handler logged, and resolve PC/LR via NT_FILE.
import struct, sys, bisect

f = open(sys.argv[1], 'rb')
si_addr_arg = int(sys.argv[2], 16)
uc_addr = int(sys.argv[3], 16)

eh = f.read(64)
e_phoff, = struct.unpack_from('<Q', eh, 0x20)
e_phentsize, = struct.unpack_from('<H', eh, 0x36)
e_phnum, = struct.unpack_from('<H', eh, 0x38)
loads, notes = [], []
f.seek(e_phoff); ph = f.read(e_phentsize * e_phnum)
for i in range(e_phnum):
    p_type, = struct.unpack_from('<I', ph, i*e_phentsize)
    p_offset, p_vaddr, _, p_filesz, p_memsz = struct.unpack_from('<QQQQQ', ph, i*e_phentsize+8)
    if p_type == 4: notes.append((p_offset, p_filesz))
    elif p_type == 1: loads.append((p_vaddr, p_memsz, p_offset, p_filesz))

def read_mem(addr, size):
    for va, msz, off, fsz in loads:
        if va <= addr < va + msz:
            f.seek(off + (addr - va)); return f.read(min(size, max(0, va + fsz - addr)))
    return b''

filemap = []
for off, sz in notes:
    f.seek(off); data = f.read(sz); pos = 0
    while pos + 12 <= len(data):
        nl, dl, ntype = struct.unpack_from('<III', data, pos)
        name = data[pos+12:pos+12+nl].rstrip(b'\0')
        dstart = pos + 12 + ((nl + 3) & ~3)
        desc = data[dstart:dstart+dl]
        pos = dstart + ((dl + 3) & ~3)
        if ntype == 0x46494c45 and name == b'CORE':
            cnt, _ = struct.unpack_from('<QQ', desc, 0)
            ents = [struct.unpack_from('<3Q', desc, 16 + i*24) for i in range(cnt)]
            strs = desc[16 + cnt*24:].split(b'\0')
            for (s, e, o), nm in zip(ents, strs):
                filemap.append((s, e, nm.decode(errors='replace')))
filemap.sort(); starts = [s for s, _, _ in filemap]
def resolve(a):
    i = bisect.bisect_right(starts, a) - 1
    if 0 <= i < len(filemap):
        s, e, nm = filemap[i]
        if s <= a < e: return '%s+0x%x' % (nm, a - s)
    return '?'

CODES = {0:'SI_USER', 1:'TRAP_BRKPT', 2:'TRAP_TRACE', 3:'TRAP_BRANCH', 4:'TRAP_HWBKPT', 5:'TRAP_UNK', -6:'SI_TKILL', 0x80:'SI_KERNEL'}
si = read_mem(si_addr_arg, 0x30)
signo, errno, code = struct.unpack_from('<iii', si, 0)
addr, = struct.unpack_from('<Q', si, 0x10)
print('=== ORIGINAL siginfo @0x%x ===' % si_addr_arg)
print('si_signo=%d si_errno=%d si_code=%d (%s)' % (signo, errno, code, CODES.get(code, 'other')))
print('si_addr/union = 0x%x  (%s)' % (addr, resolve(addr)))

uc = read_mem(uc_addr, 0x1D0)
fault, = struct.unpack_from('<Q', uc, 0xB0)
x = struct.unpack_from('<31Q', uc, 0xB8)
sp, pc, pstate = struct.unpack_from('<3Q', uc, 0x1A8 + 8)  # sp@0x1B0 pc@0x1B8 pstate@0x1C0
lr = x[30]
print('\n=== ORIGINAL mcontext @0x%x ===' % uc_addr)
print('fault_address = 0x%x (%s)' % (fault, resolve(fault)))
print('PC  = 0x%x  (%s)' % (pc, resolve(pc)))
print('LR  = 0x%x  (%s)' % (lr, resolve(lr)))
print('SP  = 0x%x' % sp)
for i in (0, 1, 2, 8, 16, 29):
    print('x%-2d = 0x%x  (%s)' % (i, x[i], resolve(x[i])))
# walk a few frames from the original FP (x29) chain
fp = x[29]
print('\n=== original frame-pointer chain ===')
for d in range(10):
    frame = read_mem(fp, 16)
    if len(frame) < 16: break
    nfp, ra = struct.unpack('<2Q', frame)
    print('  #%d fp=0x%x ra=0x%x (%s)' % (d, fp, ra, resolve(ra)))
    if nfp <= fp or nfp - fp > 0x100000: break
    fp = nfp
