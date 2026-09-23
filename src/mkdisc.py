#!/usr/bin/env python3
"""mkdisc.py -- arma el Track 1 parcheado a partir de la imagen LIMPIA.

    python3 mkdisc.py "ruta/Dino Crisis (Spain) (Track 1).bin" [salida.bin]

Necesita dcmod.bin y layout.json (build.sh + gen.py). Pasos:
  1. comprueba la imagen limpia (SHA-1 del volcado de Redump);
  2. saca el ejecutable SLES_022.11 de la imagen y comprueba su SHA-256;
  3. comprime el blob (LZSS) y lo reparte en los tres tramos de ceros del
     ejecutable, con el cargador loader2.S en el primero;
  4. escribe los enganches y apunta la entrada del ejecutable al cargador;
  5. escribe SOLO los sectores que cambian, con su subcabecera real y EDC/ECC
     recalculados. No se mueve ningun sector: el .cue y el .sbi siguen valiendo.
Si esta instalado unicorn (pip install unicorn), ademas EJECUTA el cargador y
comprueba que la RAM quede como el original + cargador + enganches + blob.
"""
import struct, subprocess, hashlib, json, sys, os
from lzss import compress, decompress
from edcecc import fix_sector

TRACK1_SHA1 = '29cda9847ddfb85e0b8c4f016654d171741798b7'   # Redump, disc 27940
EXE_SHA256  = 'e9fc4f360c3c178eb76f14a8d196ef6df8050c57a69fb17bd2a0657c44c090f0'
FIRST, NSEC, RAW = 164216, 309, 2352        # SLES_022.11: 309 sectores desde el 164216
BASE, GAMEENTRY = 0x80010000, 0x800121D4
LOADER = 0x800A2F90; R1END = 0x800A338C     # tramo 1: cargador + comienzo del blob
R2SRC, R2MAX = 0x800A3804, 0x800A486C       # tramo 2
R3SRC, R3MAX = 0x800A9C60, 0x800AA000       # tramo 3: cola del ejecutable (BSS desde 0x800A9C70)
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

def asm(r1src, r3end):
    open('loader.ld', 'w').write('SECTIONS{ . = 0x%X; .text : { *(.text) } /DISCARD/ : { *(.MIPS.abiflags) *(.reginfo) *(.pdr) *(.gnu.attributes) } }\n' % LOADER)
    D = ['-DR1SRC=0x%X' % r1src, '-DR1END=0x%X' % R1END, '-DR2SRC=0x%X' % R2SRC, '-DR2END=0x%X' % R2MAX,
         '-DR3SRC=0x%X' % R3SRC, '-DR3END=0x%X' % r3end, '-DDST=0x%X' % DST,
         '-DDSTEND=0x%X' % (DST + len(blob)), '-DGAMEENTRY=0x%X' % GAMEENTRY]
    subprocess.check_call(['mipsel-linux-gnu-gcc', '-march=r3000', '-mabi=32', '-msoft-float', '-mno-abicalls',
                           '-fno-pic', '-c', 'loader2.S', '-o', 'loader2.o'] + D)
    subprocess.check_call(['mipsel-linux-gnu-ld', '-T', 'loader.ld', '-o', 'loader2.elf', 'loader2.o'])
    subprocess.check_call(['mipsel-linux-gnu-objcopy', '-O', 'binary', '-j', '.text', 'loader2.elf', 'loader2.bin'])
    return open('loader2.bin', 'rb').read()

# el largo del cargador fija donde empieza el tramo 1; iterar hasta que no cambie
CAP2 = R2MAX - R2SRC
r1src, r3end = LOADER + 0x100, R3SRC + 4
for _ in range(4):
    ld = asm(r1src, r3end)
    n1 = (LOADER + len(ld) + 3) & ~3
    cap1 = R1END - n1
    rest = len(c) - cap1 - CAP2
    assert rest > 0, 'el blob entra en dos tramos: el cargador de tres no hace falta'
    new3 = R3SRC + ((rest + 3) & ~3)
    if (n1, new3) == (r1src, r3end): break
    r1src, r3end = n1, new3
else: die('el cargador no converge')
if r3end > R3MAX: die('no entra: %d bytes de mas' % (r3end - R3MAX))
p1, p2, p3 = c[:cap1], c[cap1:cap1 + CAP2], c[cap1 + CAP2:]

exe = bytearray(exe0)
def put(a, data, expect=None):
    o = off(a)
    if expect is None: assert not any(exe[o:o + len(data)]), hex(a)
    else: assert exe[o:o + len(data)] == expect, 'original distinto en %X' % a
    exe[o:o + len(data)] = data
for a, b in ((LOADER, R1END), (R2SRC, R2MAX), (R3SRC, R3MAX)):
    assert not any(exe0[off(a):off(b)]), 'el tramo %X no esta en cero' % a
put(LOADER, ld); put(r1src, p1); put(R2SRC, p2); put(R3SRC, p3)
for a, orig, new in L['hooks']:
    put(a, struct.pack('<%dI' % len(new), *new), struct.pack('<%dI' % len(orig), *orig))
assert struct.unpack('<I', exe[0x10:0x14])[0] == GAMEENTRY
exe[0x10:0x14] = struct.pack('<I', LOADER)
stream = bytes(exe[off(r1src):off(R1END)]) + bytes(exe[off(R2SRC):off(R2MAX)]) + bytes(exe[off(R3SRC):off(r3end)])
assert decompress(stream, len(blob)) == blob

# control opcional: ejecutar el cargador (Unicorn)
try:
    from unicorn import Uc, UC_ARCH_MIPS, UC_MODE_MIPS32, UC_MODE_LITTLE_ENDIAN, UC_HOOK_CODE
    from unicorn.mips_const import UC_MIPS_REG_SP
    mu = Uc(UC_ARCH_MIPS, UC_MODE_MIPS32 + UC_MODE_LITTLE_ENDIAN)
    mu.mem_map(0, 0x200000); mu.mem_write(0x10000, bytes(exe[0x800:]))
    mu.mem_write(DST & 0x1FFFFF, b'\xAA' * len(blob)); mu.reg_write(UC_MIPS_REG_SP, 0x801FFF00)
    mu.emu_start(LOADER, GAMEENTRY, count=20000000)
    ram = bytes(mu.mem_read(0, 0x200000))
    want = bytearray(exe0[0x800:])
    want[LOADER - BASE:LOADER - BASE + len(ld)] = ld
    for a, orig, new in L['hooks']:
        want[a - BASE:a - BASE + 4 * len(new)] = struct.pack('<%dI' % len(new), *new)
    assert ram[DST & 0x1FFFFF:(DST & 0x1FFFFF) + len(blob)] == blob, 'el cargador no dejo el blob'
    assert ram[0x10000:0x10000 + len(want)] == bytes(want), 'el cargador dejo la RAM distinta'
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
print('cargador %d B; tramos 1/2/3: %d/%d/%d B; libres %d B' % (len(ld), len(p1), len(p2), len(p3), R3MAX - r3end))
print('blob %d -> comprimido %d' % (len(blob), len(c)))
print('%d sectores: %s' % (len(changed), changed))
print('escrito %s\n  SHA-1 %s' % (out, hashlib.sha1(img).hexdigest()))
