#!/usr/bin/env python3
"""emu.py -- control independiente del cargador: lo EJECUTA (Unicorn) sobre un
SLES_022.11 ya armado y compara la RAM al llegar al arranque del juego con
original + cargador + enganches, y el blob descomprimido con dcmod.bin.

    python3 emu.py build/SLES_022.11 "Track 1 limpio.bin"
"""
import struct, json, sys, hashlib
from unicorn import Uc, UC_ARCH_MIPS, UC_MODE_MIPS32, UC_MODE_LITTLE_ENDIAN
from unicorn.mips_const import UC_MIPS_REG_SP, UC_MIPS_REG_PC
FIRST, NSEC, RAW = 164216, 309, 2352
BASE, GAMEENTRY, DST = 0x80010000, 0x800121D4, 0xD8000
def run(exe, exe0, blob, L):
    pc0 = struct.unpack('<I', exe[0x10:0x14])[0]
    mu = Uc(UC_ARCH_MIPS, UC_MODE_MIPS32 + UC_MODE_LITTLE_ENDIAN)
    mu.mem_map(0, 0x200000); mu.mem_write(0x10000, bytes(exe[0x800:]))
    mu.mem_write(DST, b'\xAA' * len(blob)); mu.reg_write(UC_MIPS_REG_SP, 0x801FFF00)
    try: mu.emu_start(pc0, GAMEENTRY, count=20000000)
    except Exception as e: return 'excepcion: %s' % e
    if mu.reg_read(UC_MIPS_REG_PC) != GAMEENTRY: return 'no llego al arranque'
    ram = bytes(mu.mem_read(0, 0x200000))
    if ram[DST:DST + len(blob)] != blob: return 'blob distinto'
    got = bytearray(ram[0x10000:0x10000 + len(exe0) - 0x800]); want = bytearray(exe0[0x800:])
    for a, orig, new in L['hooks']:
        p = a - BASE
        if got[p:p + 4 * len(new)] != struct.pack('<%dI' % len(new), *new): return 'enganche %X mal' % a
        got[p:p + 4 * len(new)] = want[p:p + 4 * len(new)]
    d = [i for i in range(len(want)) if got[i] != want[i]]
    # lo unico que puede quedar distinto: el cargador y su tabla, dentro de su zona
    if not d: return 'no hay cargador?'
    if not (0x800A2F90 - BASE <= d[0] and d[-1] < 0x800A338C - BASE): return 'RAM distinta en %X..%X' % (BASE + d[0], BASE + d[-1])
    return 'OK (cargador y tabla en %X..%X)' % (BASE + d[0], BASE + d[-1])
if __name__ == '__main__':
    exe = bytearray(open(sys.argv[1], 'rb').read())
    img = open(sys.argv[2], 'rb')
    exe0 = b''
    for k in range(NSEC):
        img.seek((FIRST + k) * RAW + 24); exe0 += img.read(2048)
    assert hashlib.sha256(exe0).hexdigest() == 'e9fc4f360c3c178eb76f14a8d196ef6df8050c57a69fb17bd2a0657c44c090f0'
    blob = open('dcmod.bin', 'rb').read(); L = json.load(open('layout.json'))
    r = run(exe, exe0, blob, L); print('ejecutable armado:', r); assert r.startswith('OK')
    # controles negativos: la herramienta tiene que notar un byte cambiado
    import random; random.seed(1)
    diff = [i for i in range(len(exe)) if exe[i] != exe0[i] and i >= 0x800]
    bad = 0
    for t in range(12):
        e = bytearray(exe); i = random.choice(diff); e[i] ^= 0x10
        r = run(e, exe0, blob, L); bad += not r.startswith('OK')
    print('controles negativos (un byte cambiado): %d de 12 detectados' % bad)
