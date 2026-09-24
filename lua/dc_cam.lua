-- dc_cam.lua : compara el objeto de camara y las banderas de las mallas entre dos momentos
--   dofile('C:/dc/dc_cam.lua')
--   dcc.snap('bien')   foto: objeto de camara (0x800B048C, 0x100 bytes) + banderas de las 36 mallas
--   dcc.snap('mal')
--   dcc.diff('bien','mal')   solo lo que cambia, en palabras de 16 bits
--   dcc.put('bien', 0x28, 0x3E)   escribe en la camara los valores de la foto 'bien' en ese rango
local ffi = require('ffi')
local band, rshift = bit.band, bit.rshift
local m8 = ffi.cast('uint8_t*', PCSX.getMemPtr())
local sp32 = ffi.cast('uint32_t*', PCSX.getScratchPtr())
local function u16(a) a = band(a, 0x1FFFFF); return m8[a] + m8[a + 1] * 256 end
local function w16(a, v) a = band(a, 0x1FFFFF); m8[a] = band(v, 0xFF); m8[a + 1] = band(rshift(v, 8), 0xFF) end
local function s16(v) if v >= 0x8000 then v = v - 0x10000 end return v end
local CAM, CSZ = 0x800B048C, 0x100
local function G()
  local g = tonumber(sp32[0]); if g < 0 then g = g + 0x100000000 end
  if g < 0x80000000 or g >= 0x80200000 then g = 0x800B03D8 end
  return g
end
local dcc = {}
_G.dcc = dcc
local S = {}
function dcc.snap(n)
  local t = { cam = {}, mesh = {} }
  for o = 0, CSZ - 2, 2 do t.cam[o] = u16(CAM + o) end
  local base = G() + 0x7CDC
  for i = 0, 35 do t.mesh[i] = u16(base + i * 0x88 + 0x30) end
  S[n] = t
  print(string.format('[dcc] foto "%s": manejador cam+70=%d  cam+72=%02X  cam+73=%d  jugador+3C=%02X',
    n, m8[band(CAM + 0x70, 0x1FFFFF)], m8[band(CAM + 0x72, 0x1FFFFF)], m8[band(CAM + 0x73, 0x1FFFFF)],
    m8[band(0x800B1E14 + 0x3C, 0x1FFFFF)]))
end
function dcc.diff(a, b)
  local A, B = S[a], S[b]
  if not A or not B then print('[dcc] falta una foto') return end
  local n = 0
  for o = 0, CSZ - 2, 2 do
    if A.cam[o] ~= B.cam[o] then
      n = n + 1
      print(string.format('[dcc] cam+%02X: %6d -> %6d   (%04X -> %04X)', o, s16(A.cam[o]), s16(B.cam[o]), A.cam[o], B.cam[o]))
    end
  end
  local mm = {}
  for i = 0, 35 do
    if band(A.mesh[i], 3) ~= band(B.mesh[i], 3) then
      mm[#mm + 1] = string.format('%d:%X->%X', i, band(A.mesh[i], 0xF), band(B.mesh[i], 0xF))
    end
  end
  print(string.format('[dcc] camara: %d palabras distintas | mallas con bit0/bit1 distinto: %s', n,
    #mm > 0 and table.concat(mm, ' ') or 'ninguna'))
end
function dcc.put(n, lo, hi)
  local T = S[n]; if not T then print('[dcc] no hay foto ' .. tostring(n)) return end
  lo = lo or 0x28; hi = hi or 0x3E
  for o = lo, hi, 2 do w16(CAM + o, T.cam[o]) end
  print(string.format('[dcc] camara +%02X..+%02X repuesta desde "%s"', lo, hi, n))
end
print('[dcc] listo: dcc.snap(n)  dcc.diff(a,b)  dcc.put(n[,desde,hasta])')
