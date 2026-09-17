#!/usr/bin/env python3
# core-analyze.py <core> — arm64 ELF core reader for F101.
# Prints NT_SIGINFO (signo/errno/code + union head), each NT_PRSTATUS thread
# (pid, cursig, PC, SP, LR), NT_FILE mappings, then scans the crashing thread's
# stack for values inside executable/file-backed mappings (signal-frame recovery:
# the original trap PC survives on the stack after sigexc's SIG_DFL re-raise).
import struct, sys, bisect

f = open(sys.argv[1], 'rb')
eh = f.read(64)
assert eh[:4] == b'\x7fELF' and eh[4] == 2, 'not ELF64'
e_phoff, = struct.unpack_from('<Q', eh, 0x20)
e_phentsize, = struct.unpack_from('<H', eh, 0x36)
e_phnum, = struct.unpack_from('<H', eh, 0x38)

loads = []   # (vaddr, memsz, fileoff, filesz)
notes = []
f.seek(e_phoff)
ph = f.read(e_phentsize * e_phnum)
for i in range(e_phnum):
    p_type, p_flags = struct.unpack_from('<II', ph, i*e_phentsize)
    p_offset, p_vaddr, _, p_filesz, p_memsz = struct.unpack_from('<QQQQQ', ph, i*e_phentsize+8)
    if p_type == 4: notes.append((p_offset, p_filesz))
    elif p_type == 1: loads.append((p_vaddr, p_memsz, p_offset, p_filesz, p_flags))

def read_mem(addr, size):
    for va, msz, off, fsz, fl in loads:
        if va <= addr < va + msz:
            take = min(size, va + msz - addr)
            avail = min(take, max(0, va + fsz - addr))
            f.seek(off + (addr - va))
            return f.read(avail)
    return b''

threads = []
siginfo = None
filemap = []
for off, sz in notes:
    f.seek(off); data = f.read(sz); pos = 0
    while pos + 12 <= len(data):
        nl, dl, ntype = struct.unpack_from('<III', data, pos)
        name = data[pos+12:pos+12+nl].rstrip(b'\0')
        dstart = pos + 12 + ((nl + 3) & ~3)
        desc = data[dstart:dstart+dl]
        pos = dstart + ((dl + 3) & ~3)
        if ntype == 1 and name == b'CORE' and len(desc) >= 392:      # NT_PRSTATUS
            cursig, = struct.unpack_from('<h', desc, 12)
            pid, = struct.unpack_from('<i', desc, 32)
            regs = struct.unpack_from('<34Q', desc, 112)             # x0..x30, sp, pc, pstate
            threads.append(dict(pid=pid, cursig=cursig, pc=regs[32], sp=regs[31], lr=regs[30]))
        elif ntype == 0x53494749 and name == b'CORE':                # NT_SIGINFO
            signo, errno, code = struct.unpack_from('<iii', desc, 0)
            u = struct.unpack_from('<4Q', desc, 16)
            siginfo = dict(signo=signo, errno=errno, code=code, union=[hex(x) for x in u])
        elif ntype == 0x46494c45 and name == b'CORE':                # NT_FILE
            cnt, pgsz = struct.unpack_from('<QQ', desc, 0)
            ents = [struct.unpack_from('<3Q', desc, 16 + i*24) for i in range(cnt)]
            strs = desc[16 + cnt*24:].split(b'\0')
            for (s, e, o), nm in zip(ents, strs):
                filemap.append((s, e, nm.decode(errors='replace')))

filemap.sort()
starts = [s for s, _, _ in filemap]
def resolve(addr):
    i = bisect.bisect_right(starts, addr) - 1
    if 0 <= i < len(filemap):
        s, e, nm = filemap[i]
        if s <= addr < e: return f'{nm}+0x{addr-s:x}'
    return None

print('=== NT_SIGINFO (the CORE-producing delivery) ===')
print(siginfo)
print(f'\n=== threads: {len(threads)} (first = crashing) ===')
for t in threads[:6]:
    print(f"pid={t['pid']} cursig={t['cursig']} pc=0x{t['pc']:x} ({resolve(t['pc'])}) sp=0x{t['sp']:x} lr=0x{t['lr']:x} ({resolve(t['lr'])})")

print(f'\n=== NT_FILE: {len(filemap)} mappings; the interesting ones ===')
seen = set()
for s, e, nm in filemap:
    base = nm.rsplit('/', 1)[-1]
    if base not in seen and any(k in nm for k in ('iTerm', 'dyld', 'Core', 'dispatch', 'objc', 'mldr', 'system')):
        seen.add(base); print(f'0x{s:x}-0x{e:x} {nm}')
    if len(seen) > 18: break

crash = threads[0] if threads else None
if crash:
    print(f"\n=== stack scan of crashing thread (sp=0x{crash['sp']:x}): code-range values (original frame recovery) ===")
    stack = read_mem(crash['sp'], 4096)
    hits = 0
    for i in range(0, len(stack) - 7, 8):
        v, = struct.unpack_from('<Q', stack, i)
        r = resolve(v)
        if r and hits < 40:
            print(f'  sp+0x{i:x}: 0x{v:x}  {r}')
            hits += 1
