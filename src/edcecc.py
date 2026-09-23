"""EDC/ECC de sectores CD-ROM (Mode 1 y Mode 2 Form 1)."""
import struct

_edc_lut = []
for i in range(256):
    e = i
    for _ in range(8):
        e = (e >> 1) ^ (0xD8018001 if e & 1 else 0)
    _edc_lut.append(e)

def edc(data):
    e = 0
    for b in data:
        e = (e >> 8) ^ _edc_lut[(e ^ b) & 0xFF]
    return e & 0xFFFFFFFF

_f_lut = [0] * 256
_b_lut = [0] * 256
for i in range(256):
    _f_lut[i] = ((i << 1) ^ (0x11D if i & 0x80 else 0)) & 0xFF
    _b_lut[i ^ _f_lut[i]] = i

def _ecc_block(src, major_count, minor_count, major_mult, minor_inc, dst, dst_off):
    size = major_count * minor_count
    for major in range(major_count):
        index = (major >> 1) * major_mult + (major & 1)
        a = b = 0
        for _ in range(minor_count):
            t = src[index]
            index += minor_inc
            if index >= size:
                index -= size
            a ^= t
            b ^= t
            a = _f_lut[a]
        a = _b_lut[_f_lut[a] ^ b]
        dst[dst_off + major] = a & 0xFF
        dst[dst_off + major + major_count] = (a ^ b) & 0xFF

def fix_sector(sec):
    """Recalcula EDC y ECC de un sector crudo de 2352 bytes (Mode 1 o Mode 2 Form 1)."""
    mode = sec[15]
    if mode == 2:
        # Mode 2 Form 1: EDC sobre subcabecera + datos (16..2071)
        struct.pack_into('<I', sec, 2072, edc(sec[16:2072]))
        saved = bytes(sec[12:16])
        sec[12:16] = b'\x00\x00\x00\x00'        # la cabecera cuenta como ceros
        _ecc_block(memoryview(sec)[12:], 86, 24, 2, 86, sec, 2076)
        _ecc_block(memoryview(sec)[12:], 52, 43, 86, 88, sec, 2076 + 172)
        sec[12:16] = saved
    elif mode == 1:
        struct.pack_into('<I', sec, 2064, edc(sec[0:2064]))
        sec[2068:2076] = b'\x00' * 8
        _ecc_block(memoryview(sec)[12:], 86, 24, 2, 86, sec, 2076)
        _ecc_block(memoryview(sec)[12:], 52, 43, 86, 88, sec, 2076 + 172)
    else:
        raise SystemExit('modo de sector desconocido: %d' % mode)

def sector_ok(sec):
    """Verifica que nuestro calculo reproduzca lo que ya hay en el sector."""
    orig = bytes(sec)
    tmp = bytearray(orig)
    fix_sector(tmp)
    return bytes(tmp) == orig
