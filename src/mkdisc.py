#!/usr/bin/env python3
"""mkdisc.py -- arma el Track 1 parcheado a partir de la imagen LIMPIA.

    python3 mkdisc.py "ruta/Dino Crisis (Spain) (Track 1).bin" [salida.bin]

Necesita dcmod.bin y layout.json (build.sh + gen.py). Pasos:
  1. comprueba la imagen limpia (SHA-1 del volcado de Redump);
  2. saca el ejecutable SLES_022.11 de la imagen y comprueba su SHA-256;
  3. comprime el blob (LZSS) y lo reparte en tramos del ejecutable que en el
     original son ceros, con el cargador loader3.S y su tabla de tramos en el
     primero (v6.13: tabla en vez de tres tramos fijos; se usan los tramos que
     hagan falta, de mayor a menor);
  4. escribe los enganches y apunta la entrada del ejecutable al cargador;
  5. escribe SOLO los sectores que cambian, con su subcabecera real y EDC/ECC
     recalculados. No se mueve ningun sector: el .cue y el .sbi siguen valiendo.
Si esta instalado unicorn (pip install unicorn), ademas EJECUTA el cargador y
comprueba que la RAM quede como el original + cargador + enganches + blob.
"""
import struct, subprocess, hashlib, json, sys, os, re
from lzss import compress, decompress
from edcecc import fix_sector

TRACK1_SHA1 = '29cda9847ddfb85e0b8c4f016654d171741798b7'   # Redump, disc 27940
EXE_SHA256  = 'e9fc4f360c3c178eb76f14a8d196ef6df8050c57a69fb17bd2a0657c44c090f0'
FIRST, NSEC, RAW = 164216, 309, 2352        # SLES_022.11: 309 sectores desde el 164216
BASE, GAMEENTRY = 0x80010000, 0x800121D4
LOADER = 0x800A2F90; R1END = 0x800A338C     # zona del cargador: codigo + tabla + primer tramo
FIXED = [(0x800A3804, 0x800A486C),          # la tira que el juego limpia antes del titulo
         (0x800A9C60, 0x800AA000)]          # cola del ejecutable (BSS desde 0x800A9C70)
SEGBASE = 0x80080000                        # base de las direcciones de la tabla (16 bits x 4)
MINRUN = 32                                 # corridas de ceros mas chicas no se usan
DST = 0x800D8000                            # donde se descomprime el blob
off = lambda a: 0x800 + a - BASE

def die(m): sys.exit('ERROR: ' + m)

src = sys.argv[1] if len(sys.argv) > 1 else die('falta la ruta del Track 1 limpio')
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join('build', os.path.basename(src))
img = bytearray(open(src, 'rb').read())
if hashlib.sha1(img).hexdigest() != TRACK1_SHA1:
    die('el Track 1 no es el volcado esperado (SHA-1 %s)' % TRACK1_SHA1)

sector = lambda s: img[s * RAW:(s + 1) * RAW]
exe0 = b''.join(bytes(sector(FIRST + k)[24:2072]) for k in range(NSEC))
assert hashlib.sha256(exe0).hexdigest() == EXE_SHA256, 'ejecutable inesperado'

blob = open('dcmod.bin', 'rb').read(); blob += b'\0' * (-len(blob) % 4)
L = json.load(open('layout.json'))
c = compress(blob); assert decompress(c, len(blob)) == blob

# --- tramos disponibles ------------------------------------------------------
# Cualquier corrida de ceros del ejecutable sirve: el cargador la vuelve a
# dejar en cero antes de saltar al juego. Primero la zona del cargador, despues
# los dos tramos de siempre y despues el resto, de mayor a menor.
for a, b in [(LOADER, R1END)] + FIXED:
    assert not any(exe0[off(a):off(b)]), 'el tramo %X no esta en cero' % a
taken = [(0x800A2F6C, 0x800A3390)] + FIXED      # zona del cargador entera (incluye 3 palabras que usa el juego)
extra = []
for m in re.finditer(rb'\x00{%d,}' % MINRUN, exe0[0x800:]):
    a = (BASE + m.start() + 3) & ~3; b = (BASE + m.end()) & ~3
    if b - a < MINRUN or a < SEGBASE: continue
    if any(a < te and b > ts for ts, te in taken): continue
    extra.append((a, b))
extra.sort(key=lambda r: (-(r[1] - r[0]), r[0]))

def asm(tab, tabend):
    open('loader.ld', 'w').write('SECTIONS{ . = 0x%X; .text : { *(.text) } /DISCARD/ : { *(.MIPS.abiflags) *(.reginfo) *(.pdr) *(.gnu.attributes) } }\n' % LOADER)
    D = ['-DTAB=0x%X' % tab, '-DTABEND=0x%X' % tabend, '-DSEGBASE=0x%X' % SEGBASE, '-DDST=0x%X' % DST,
         '-DDSTEND=0x%X' % (DST + len(blob)), '-DGAMEENTRY=0x%X' % GAMEENTRY]
    subprocess.check_call(['mipsel-linux-gnu-gcc', '-march=r3000', '-mabi=32', '-msoft-float', '-mno-abicalls',
                           '-fno-pic', '-c', 'loader3.S', '-o', 'loader3.o'] + D)
    subprocess.check_call(['mipsel-linux-gnu-ld', '-T', 'loader.ld', '-o', 'loader3.elf', 'loader3.o'])
    subprocess.check_call(['mipsel-linux-gnu-objcopy', '-O', 'binary', '-j', '.text', 'loader3.elf', 'loader3.bin'])
    return open('loader3.bin', 'rb').read()

codelen = len(asm(LOADER, LOADER)); assert codelen % 4 == 0
TAB = LOADER + codelen
# cuantos tramos hacen falta: la tabla ocupa lugar del primero, asi que se prueba
segs = None
for nx in range(len(extra) + 1):
    n = 1 + len(FIXED) + nx
    first = (TAB + 4 * n, R1END)
    if first[1] - first[0] < 4: continue
    cand = [first] + FIXED + extra[:nx]
    if sum(b - a for a, b in cand) >= len(c): segs = cand; break
if segs is None:
    cap = (R1END - TAB - 4 * (1 + len(FIXED) + len(extra))) + sum(b - a for a, b in FIXED + extra)
    die('no entra: comprimido %d, capacidad %d' % (len(c), cap))
TABEND = TAB + 4 * len(segs)
# el ultimo tramo se anota solo hasta donde se usa (redondeado a 4)
used = len(c) - sum(b - a for a, b in segs[:-1])
segs[-1] = (segs[-1][0], segs[-1][0] + ((used + 3) & ~3))
code = asm(TAB, TABEND); assert len(code) == codelen
table = b''.join(struct.pack('<HH', (a - SEGBASE) >> 2, (b - a) >> 2) for a, b in segs)
for a, b in segs: assert a % 4 == 0 and (b - a) % 4 == 0 and b > a and 0 <= (a - SEGBASE) >> 2 < 65536
ld = code + table

exe = bytearray(exe0)
def put(a, data, expect=None):
    o = off(a)
    if expect is None: assert not any(exe[o:o + len(data)]), 'no estaba en cero: %X' % a
    else: assert exe[o:o + len(data)] == expect, 'original distinto en %X' % a
    exe[o:o + len(data)] = data
put(LOADER, ld)
p = 0
for a, b in segs:
    put(a, c[p:p + b - a]); p += b - a
assert p >= len(c)
for a, orig, new in L['hooks']:
    put(a, struct.pack('<%dI' % len(new), *new), struct.pack('<%dI' % len(orig), *orig))
assert struct.unpack('<I', exe[0x10:0x14])[0] == GAMEENTRY
exe[0x10:0x14] = struct.pack('<I', LOADER)
stream = b''.join(bytes(exe[off(a):off(b)]) for a, b in segs)
assert decompress(stream, len(blob)) == blob

# control opcional: ejecutar el cargador (Unicorn)
try:
    from unicorn import Uc, UC_ARCH_MIPS, UC_MODE_MIPS32, UC_MODE_LITTLE_ENDIAN
    from unicorn.mips_const import UC_MIPS_REG_SP, UC_MIPS_REG_PC, UC_MIPS_REG_A0, UC_MIPS_REG_A1
    mu = Uc(UC_ARCH_MIPS, UC_MODE_MIPS32 + UC_MODE_LITTLE_ENDIAN)
    mu.mem_map(0, 0x200000); mu.mem_write(0x10000, bytes(exe[0x800:]))
    mu.mem_write(DST & 0x1FFFFF, b'\xAA' * len(blob)); mu.reg_write(UC_MIPS_REG_SP, 0x801FFF00)
    mu.reg_write(UC_MIPS_REG_A0, 0x12345678); mu.reg_write(UC_MIPS_REG_A1, 0x9ABCDEF0)
    mu.emu_start(LOADER, GAMEENTRY, count=20000000)
    assert mu.reg_read(UC_MIPS_REG_PC) == GAMEENTRY, 'el cargador no llego al arranque del juego'
    assert mu.reg_read(UC_MIPS_REG_SP) == 0x801FFF00 and mu.reg_read(UC_MIPS_REG_A0) == 0x12345678 \
        and mu.reg_read(UC_MIPS_REG_A1) == 0x9ABCDEF0, 'el cargador toco sp/a0/a1'
    ram = bytes(mu.mem_read(0, 0x200000))
    want = bytearray(exe0[0x800:])
    want[LOADER - BASE:LOADER - BASE + len(ld)] = ld
    for a, orig, new in L['hooks']:
        want[a - BASE:a - BASE + 4 * len(new)] = struct.pack('<%dI' % len(new), *new)
    assert ram[DST & 0x1FFFFF:(DST & 0x1FFFFF) + len(blob)] == blob, 'el cargador no dejo el blob'
    assert ram[0x10000:0x10000 + len(want)] == bytes(want), 'el cargador dejo la RAM distinta'
    assert not any(ram[:0x10000]) and not any(ram[0x10000 + len(want):DST & 0x1FFFFF]) \
        and not any(ram[(DST & 0x1FFFFF) + len(blob):0x1FF000]), 'el cargador escribio fuera de lugar'
    print('cargador ejecutado (unicorn): RAM correcta')
except ImportError:
    print('(unicorn no instalado: se salta la ejecucion del cargador)')

# sectores: misma cabecera y subcabecera, datos nuevos, EDC/ECC recalculados
changed = []
for k in range(NSEC):
    s = FIRST + k
    orig = sector(s)
    t = bytearray(orig); fix_sector(t)
    assert bytes(t) == bytes(orig), 'EDC/ECC no reproduce el sector %d' % s
    new = exe[k * 2048:(k + 1) * 2048]
    if new != exe0[k * 2048:(k + 1) * 2048]:
        r = bytearray(orig); r[24:2072] = new; fix_sector(r)
        img[s * RAW:(s + 1) * RAW] = r; changed.append(s)

os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
open(out, 'wb').write(img)
open(os.path.join(os.path.dirname(out) or '.', 'SLES_022.11'), 'wb').write(exe)
free = (R1END - TAB - 4 * (1 + len(FIXED) + len(extra))) + sum(b - a for a, b in FIXED + extra) - len(c)
print('cargador %d B + tabla %d B (%d tramos)' % (len(code), len(table), len(segs)))
for a, b in segs: print('   tramo %08X..%08X  %4d B' % (a, b, b - a))
print('blob %d -> comprimido %d; libres con todos los tramos de >= %d bytes: %d B' % (len(blob), len(c), MINRUN, free))
print('%d sectores: %s' % (len(changed), changed))
print('escrito %s\n  SHA-1 %s' % (out, hashlib.sha1(img).hexdigest()))
