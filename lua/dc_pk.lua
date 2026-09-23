-- dc_pk.lua : mide cuanto se llena el buffer de paquetes GPU por cuadro (Dino Crisis PAL)
-- Uso en la consola Lua de Redux:
--   dofile('C:/dc/dc_pk.lua')
--   dcp.on()    -> empieza a medir; imprime solo cuando hay un maximo nuevo o un desborde
--   dcp.off()   -> para y muestra el resumen
--
-- Datos (medidos en el exe original):
--   puntero de paquetes = scratchpad +4 (0x1F800004); lo reinicia el lazo principal en 0x80015174
--   buffer 0 = 0x801C0000, buffer 1 = 0x801A0000 -> 0x20000 bytes (128 KB) cada uno, sin tope
--   tri = 40 bytes, quad = 52 bytes. Si el buffer 1 pasa de 0x801C0000 pisa el buffer 0,
--   que es el que la GPU puede estar dibujando en ese momento.
local ffi = require('ffi')
local band, rshift = bit.band, bit.rshift
local mem = PCSX.getMemPtr()
local ram32 = ffi.cast('uint32_t*', mem)
local sp32 = ffi.cast('uint32_t*', PCSX.getScratchPtr())
local sp16 = ffi.cast('uint16_t*', PCSX.getScratchPtr())
local function u32(v) v = tonumber(v); if v < 0 then v = v + 0x100000000 end; return v end
local function rd32(a) return u32(ram32[rshift(band(a, 0x1FFFFF), 2)]) end
local function gpr(n) return u32(ffi.cast('uint32_t', PCSX.getRegisters().GPR.n[n])) end

local SIZE = 0x20000
local dcp = {}
_G.dcp = dcp
local S

local function kb(n) return string.format('%.1f KB', n / 1024) end

function dcp.on()
  if S then dcp.off() end
  S = { base = nil, max = 0, maxPr = 0, n = 0, over75 = 0, over = 0, vs = 0, lastVs = 0,
        slow = 0, worstVs = 0, spMin = 0xFFFFFFFF }
  S.L = PCSX.Events.createEventListener('GPU::Vsync', function() S.vs = S.vs + 1 end)
  S.B = PCSX.addBreakpoint(0x80015174, 'Exec', 4, 'dcp reset', function()
    local fin = u32(sp32[1])            -- fin del cuadro que se acaba de mandar a dibujar
    local nuevo = gpr('v0')             -- base del cuadro que empieza
    local sp = gpr('sp')
    if sp < S.spMin then S.spMin = sp end
    local base = S.base
    S.base = nuevo
    local dv = S.vs - S.lastVs; S.lastVs = S.vs
    if not base then return end
    local uso = fin - base
    if uso < 0 or uso > 0x80000 then return end   -- lectura rara, se ignora
    S.n = S.n + 1
    if dv > 2 then S.slow = S.slow + 1 end
    if dv > S.worstVs then S.worstVs = dv end
    local pr = sp16[0x24 / 2]
    if uso * 4 > SIZE * 3 then S.over75 = S.over75 + 1 end
    if uso > SIZE then
      S.over = S.over + 1
      local que = (base == 0x801A0000) and 'PISA el buffer 0 (el que dibuja la GPU)'
                                       or string.format('pisa %08X.. (despues del buffer 0)', base + SIZE)
      print(string.format('[dcp] !!! DESBORDA: buffer %08X termino en %08X, %s bytes de mas -> %s (vsyncs %d)',
        base, fin, uso - SIZE, que, dv))
    end
    if uso > S.max then
      S.max = uso; S.maxPr = pr
      print(string.format('[dcp] maximo nuevo: %s de 128 KB (%d%%)  buffer %08X  prims %d  vsyncs %d',
        kb(uso), math.floor(uso * 100 / SIZE), base, pr, dv))
    end
  end)
  print('[dcp] midiendo. Mira hacia la zona pesada y despues dcp.off()')
end

function dcp.off()
  if not S then print('[dcp] no estaba midiendo') return end
  if S.B then S.B:remove() end
  if S.L then S.L:remove() end
  -- que hay despues del buffer 0 (lo que pisaria un desborde del buffer 0)
  local nz, first = 0, nil
  for a = 0x801E0000, 0x801FFFFC, 4 do
    if rd32(a) ~= 0 then nz = nz + 1; if not first then first = a end end
  end
  print(string.format('[dcp] cuadros %d | maximo %s (%d%%) prims %d | >75%%: %d | desbordes: %d',
    S.n, kb(S.max), math.floor(S.max * 100 / SIZE), S.maxPr, S.over75, S.over))
  print(string.format('[dcp] cuadros lentos (>2 vsyncs): %d, peor %d vsyncs | pila minima %08X',
    S.slow, S.worstVs, S.spMin))
  print(string.format('[dcp] 801E0000-801FFFFF: %d palabras no nulas%s', nz,
    first and string.format(', la primera en %08X', first) or ''))
  S = nil
end

print('[dcp] listo: dcp.on()  dcp.off()')
