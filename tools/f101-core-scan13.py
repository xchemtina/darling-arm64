#!/usr/bin/env python3
# core-scan13.py <core> — scan the MAIN guest thread's (pid 13) stack for guest-code
# addresses (iTerm2 binary / dyld shared cache / frameworks / libsystem) to recover the
# original trap frame chain that survives sigexc's re-raise.
import struct, sys, bisect

f = open(sys.argv[1], 'rb')
eh = f.read(64)
e_phoff, = struct.unpack_from('<Q', eh, 0x20)
e_phentsize, = struct.unpack_from('<H', eh, 0x36)
e_phnum, = struct.unpack_from('<H', eh, 0x38)

loads, notes = [], []
f.seek(e_phoff)
ph = f.read(e_phentsize * e_phnum)
for i in range(e_phnum):
    p_type, p_flags = struct.unpack_from('<II', ph, i*e_phentsize)
    p_offset, p_vaddr, _, p_filesz, p_memsz = struct.unpack_from('<QQQQQ', ph, i*e_phentsize+8)
    if p_type == 4: notes.append((p_offset, p_filesz))
    elif p_type == 1: loads.append((p_vaddr, p_memsz, p_offset, p_filesz))

def read_mem(addr, size):
    for va, msz, off, fsz in loads:
        if va <= addr < va + msz:
            avail = min(size, max(0, va + fsz - addr))
            f.seek(off + (addr - va)); return f.read(avail)
    return b''

threads, filemap = [], []
for off, sz in notes:
    f.seek(off); data = f.read(sz); pos = 0
    while pos + 12 <= len(data):
        nl, dl, ntype = struct.unpack_from('<III', data, pos)
        name = data[pos+12:pos+12+nl].rstrip(b'\0')
        dstart = pos + 12 + ((nl + 3) & ~3)
        desc = data[dstart:dstart+dl]
        pos = dstart + ((dl + 3) & ~3)
        if ntype == 1 and name == b'CORE' and len(desc) >= 392:
            pid, = struct.unpack_from('<i', desc, 32)
            regs = struct.unpack_from('<34Q', desc, 112)
            threads.append((pid, regs[32], regs[31], regs[30]))
        elif ntype == 0x46494c45 and name == b'CORE':
            cnt, _ = struct.unpack_from('<QQ', desc, 0)
            ents = [struct.unpack_from('<3Q', desc, 16 + i*24) for i in range(cnt)]
            strs = desc[16 + cnt*24:].split(b'\0')
            for (s, e, o), nm in zip(ents, strs):
                filemap.append((s, e, nm.decode(errors='replace')))

filemap.sort()
starts = [s for s, _, _ in filemap]
def resolve(a):
    i = bisect.bisect_right(starts, a) - 1
    if 0 <= i < len(filemap):
        s, e, nm = filemap[i]
        if s <= a < e: return nm + '+0x%x' % (a - s)
    return None

pid13 = [t for t in threads if t[0] == 13]
if not pid13:
    print('no pid-13 thread'); sys.exit(1)
pid, pc, sp, lr = pid13[0]
print('main thread: pc=0x%x (%s)' % (pc, resolve(pc)))
print('             lr=0x%x (%s)' % (lr, resolve(lr)))
print('             sp=0x%x' % sp)
stack = read_mem(sp, 32768)
print('stack bytes: %d' % len(stack))
KEY = ('iTerm', 'dyld_shared_cache', 'libsystem', 'Frameworks')
hits = 0
for i in range(0, len(stack) - 7, 8):
    v, = struct.unpack_from('<Q', stack, i)
    r = resolve(v)
    if r and any(k in r for k in KEY):
        print('  sp+0x%-6x 0x%016x  %s' % (i, v, r))
        hits += 1
        if hits > 50: break
