----------------------------------------------------------------------
-- dc_intro.lua  --  Medir las cinematicas de apertura (logos y videos)
-- Dino Crisis SLES-02211, PCSX-Redux.  Independiente de dct y dc6.
--
-- Antes: Debug -> depurador + interprete.
--   dofile('C:/dc/dc_intro.lua')
--   dci.log()          prender (y despues Emulation -> Reset); otra vez = parar
--   dci.mark('texto')  marca en el registro
--   dci.dump('nombre') RAM (2 MB) + scratchpad + registros en C:/dc/dump_<nombre>.*
--
-- v2, menos ruido. Mide QUIEN llama a VSync (0x8007FA28, la espera de
-- cuadro de libetc: el juego pasa ahi casi todo el tiempo, por eso la v1 solo
-- veia esa pagina). Cada bucle de escena (logo, video, titulo) llama a VSync
-- desde su propio lugar, asi que la cadena de llamadas identifica la escena.
-- Se imprime UNA linea cuando cambia la escena (o los estados), no por Vsync:
--
--   [v   330  6.6s] esc 80014FEC<80015... | lect 25/s jug 0/s | s32 0A s3e 0A cine 00000000 cd 00
--
--   esc   cadena de retorno al entrar a VSync (la del medio y la de arriba)
--   lect  veces por segundo que corre el lector de botones 0x80015E94
--   jug   veces por segundo que corre el enganche del jugador
--   cd    byte 0x800BBCE2 (estado del gestor de CD / carga)
-- Start: se avisa al apretarlo, con la escena en la que estaba.
----------------------------------------------------------------------

local ffi = require('ffi')
local band, rshift = bit.band, bit.rshift
local mem = PCSX.getMemPtr()
local ram8  = ffi.cast('uint8_t*', mem)
local ram32 = ffi.cast('uint32_t*', mem)
local sp32
do
  local ok, p = pcall(function() return PCSX.getScratchPtr() end)
  if ok and p ~= nil then sp32 = ffi.cast('uint32_t*', p) end
end

local function phys(a) return band(a, 0x1FFFFF) end
local function rd8(a) return ram8[phys(a)] end
local function rd32(a) return tonumber(ram32[rshift(phys(a), 2)]) end
local function u32(v) v = tonumber(v); if v < 0 then v = v + 0x100000000 end; return v end
local function regs() return PCSX.getRegisters() end
local function gpr(n) return u32(ffi.cast('uint32_t', regs().GPR.n[n])) end
local function pcv() return u32(ffi.cast('uint32_t', regs().pc)) end

-- lectura de 32 bits de RAM principal o del scratchpad (el juego usa el
-- scratchpad como pila)
local function mrd32(a)
  if a >= 0x1F800000 and a < 0x1F800400 then
    return sp32 and u32(sp32[rshift(a - 0x1F800000, 2)]) or 0
  end
  if a >= 0x80000000 and a < 0x80200000 then return u32(rd32(a)) end
  return 0
end

local dci = {}
_G.dci = dci
dci.PLAYER = 0x800B1E14
dci.PAD    = 0x800AE288
dci.VSYNC  = 0x8007FA28
dci.WIN    = 25          -- Vsync por ventana (PAL: medio segundo)
dci.DEPTH  = 3           -- eslabones de la cadena de llamadas

local L, B = {}, {}
local function onVsync(key, fn)
  if L[key] then L[key]:remove() end
  L[key] = fn and PCSX.Events.createEventListener('GPU::Vsync', fn) or nil
end
local function bpOff() for k, b in pairs(B) do b:remove(); B[k] = nil end end

-- direccion de retorno plausible: codigo, alineada, y la instruccion 8 bytes
-- antes es jal o jalr
local function isRet(w)
  if band(w, 3) ~= 0 then return false end
  if not (w >= 0x80010000 and w < 0x801FF000) then return false end
  local i = mrd32(w - 8)
  local op = rshift(i, 26)
  return op == 3 or (op == 0 and band(i, 0x3F) == 9)
end

-- cadena de llamadas: $ra, y despues lo que parezca direccion de retorno en
-- la pila (heuristica; solo sirve para distinguir escenas, no es exacta)
local function chain()
  local out = { gpr('ra') }
  local sp = gpr('sp')
  for k = 0, 127 do
    if #out >= dci.DEPTH then break end
    local w = mrd32(sp + k * 4)
    if w ~= out[#out] and isRet(w) then out[#out + 1] = w end
  end
  local s = {}
  for i = 1, #out do s[i] = string.format('%08X', out[i]) end
  return table.concat(s, '<')
end

local st

local function cineWord()
  if not sp32 then return nil end
  local p = u32(sp32[0])
  if p < 0x80000000 or p >= 0x80200000 then return nil end
  return u32(rd32(p + 0x40))
end

local function topKey(h)
  local best, n = nil, -1
  for k, v in pairs(h) do if v > n then best, n = k, v end end
  return best or 'sin VSync'
end

function dci.log()
  if L.log then
    onVsync('log', nil); bpOff()
    print(string.format('[dci] log apagado en Vsync %d', st.v))
    return
  end
  st = { v = 0, nR = 0, nJ = 0, esc = {}, last = '', lastEsc = nil, startPrev = false, cur = 'sin VSync' }
  B.vs = PCSX.addBreakpoint(dci.VSYNC, 'Exec', 4, 'dci vsync', function()
    -- VSync(1) y VSync(-1) son consultas del contador (la callback de Vsync
    -- del juego, 0x80014E10, llama VSync(1) en cada interrupcion): no esperan
    -- cuadro, no identifican escena. Solo cuentan VSync(0) y VSync(n >= 2).
    local a0 = gpr('a0')
    if a0 == 1 or a0 >= 0x80000000 then return end
    local c = chain()
    st.esc[c] = (st.esc[c] or 0) + 1
    st.cur = c
  end)
  B.rd = PCSX.addBreakpoint(0x80015E94, 'Exec', 4, 'dci lect', function() st.nR = st.nR + 1 end)
  B.pl = PCSX.addBreakpoint(0x80045378, 'Exec', 4, 'dci jug', function()
    if gpr('s0') == dci.PLAYER then st.nJ = st.nJ + 1 end
  end)
  onVsync('log', function()
    st.v = st.v + 1
    -- Start: pad crudo +2 bit 0x08, activo en bajo
    local down = rd8(dci.PAD) == 0 and band(rd8(dci.PAD + 2), 0x08) == 0
    if down and not st.startPrev then
      print(string.format('[v%6d %5.1fs] >>> START  (esc %s)', st.v, st.v / 50, st.cur))
    end
    st.startPrev = down
    if st.v % dci.WIN ~= 0 then return end
    local esc = topKey(st.esc)
    local per = 50 / dci.WIN
    local cw = cineWord()
    local rest = string.format('lect %d/s jug %d/s | s32 %02X s3e %02X cine %s cd %02X',
      math.floor(st.nR * per), math.floor(st.nJ * per), rd8(0x800BAF32), rd8(0x800BAF3E),
      cw and string.format('%08X', cw) or '--------', rd8(0x800BBCE2))
    -- clave sin los numeros exactos de lect/jug (solo corre / no corre)
    local key = esc .. (st.nR > 0 and 'R' or 'r') .. (st.nJ > 0 and 'J' or 'j') ..
      string.format('%02X%02X%s', rd8(0x800BAF32), rd8(0x800BAF3E), cw and string.format('%08X', cw) or '-')
    if key ~= st.last then
      print(string.format('[v%6d %5.1fs] esc %s | %s', st.v, st.v / 50, esc, rest))
      st.last = key
    end
    st.esc, st.nR, st.nJ = {}, 0, 0
  end)
  print('[dci] log v2 encendido. Ahora Emulation -> Reset.')
end

function dci.mark(txt)
  print(string.format('[v%6d %5.1fs] ==== MARCA: %s', st and st.v or 0, (st and st.v or 0) / 50, tostring(txt or '')))
end

function dci.dump(name)
  name = name or 'x'
  local base = 'C:/dc/dump_' .. name
  local f = assert(io.open(base .. '.ram', 'wb'))
  f:write(ffi.string(mem, 0x200000)); f:close()
  if sp32 then
    f = assert(io.open(base .. '.sp', 'wb'))
    f:write(ffi.string(ffi.cast('uint8_t*', sp32), 0x400)); f:close()
  end
  local names = { 'at','v0','v1','a0','a1','a2','a3','t0','t1','t2','t3','t4','t5','t6','t7',
                  's0','s1','s2','s3','s4','s5','s6','s7','t8','t9','k0','k1','gp','sp','s8','fp','ra' }
  f = assert(io.open(base .. '.txt', 'w'))
  f:write(string.format('pc %08X\n', pcv()))
  for _, n in ipairs(names) do
    local ok, v = pcall(gpr, n)
    if ok then f:write(string.format('%s %08X\n', n, v)) end
  end
  f:write(string.format('vsync %d\nesc %s\n', st and st.v or -1, st and st.cur or '-'))
  f:close()
  print('[dci] guardado ' .. base .. '.ram/.sp/.txt')
end

----------------------------------------------------------------------
-- PROTOTIPO: Start saltea TODOS los videos
-- Medido en los volcados (overlay de video, residente en 0x80149000..0x8015CEAC):
--   0x8014AAE0(x, y, mascara)  arranca un video; objeto M = 0x8015CED0,
--                              M+2 = mascara de botones que lo saltea
--   0x8014AB9C                 paso por cuadro (tabla 0x8014BD20 segun M+0)
--   0x8014B09C                 estado 1: si ([0x800AE270] & M+2) -> G+8 = 2 (fin)
--   G = [0x1F800000] (0x800B03D8): G+8 = video en curso (1) / terminado (2),
--                                  G+0xA = numero de video
-- Los videos del juego ya llaman con mascara 0x0800 (Start); los de la
-- intro con 0. El prototipo pone 0x0800 en M+2 justo antes de que el
-- estado 1 la lea, y el juego hace el resto por su camino normal.
--   dci.skip()   prender / apagar
----------------------------------------------------------------------
local function wr16(a, v) ffi.cast('uint16_t*', mem)[rshift(phys(a), 1)] = v end
local function rd16(a) return tonumber(ffi.cast('uint16_t*', mem)[rshift(phys(a), 1)]) end
dci.SKIPMASK = 0x0800

function dci.skip()
  if B.skip then B.skip:remove(); B.skip = nil; print('[dci] skip apagado') return end
  local seen = {}
  B.skip = PCSX.addBreakpoint(0x8014B09C, 'Exec', 4, 'dci skip', function()
    if u32(rd32(0x8014BD24)) ~= 0x8014B09C then return end   -- firma del overlay
    local m = gpr('a0')
    if m ~= 0x8015CED0 then return end
    local old = rd16(m + 2)
    local g = sp32 and u32(sp32[0]) or 0
    local id = (g >= 0x80000000 and g < 0x80200000) and rd16(g + 0xA) or -1
    if not seen[id] then
      seen[id] = true
      print(string.format('[dci] video %d: mascara original %04X%s', id, old,
        old == 0 and ' -> ahora 0800 (Start)' or ''))
    end
    if old == 0 then wr16(m + 2, dci.SKIPMASK) end
  end)
  print('[dci] skip prendido: Start corta cualquier video')
end

----------------------------------------------------------------------
-- DIAGNOSTICO: maquina de estados de la intro (overlay 0x80149000)
-- Objeto en 0x8015CEAC: [0] etapa, [1] paso, [2] sub-paso, [3] temporizador.
-- Medido en el desensamblado:
--   [0]=1 [1]=0  carga + chequeo inicial (0x80021684, bloquea) y fundido
--   [0]=1 [1]=1  pantalla con temporizador de 60 cuadros (0x801493CC);
--                Start (0x0800 en 0x800AE270) pone el temporizador en 0
--   [0]=1 [1]=2  videos (logo de Capcom, etc.)
--   [0]=2        fin de la intro, pasa al titulo
-- Imprime una linea cada vez que cambia algo, con el tiempo, el fundido
-- (G+0x6D) y si Start esta apretado en la palabra del juego.
--   dci.fe()   prender / apagar
----------------------------------------------------------------------
function dci.fe()
  if L.fe then onVsync('fe', nil); print('[dci] fe apagado') return end
  local v, last = 0, ''
  onVsync('fe', function()
    v = v + 1
    if u32(rd32(0x8014BD24)) ~= 0x8014B09C then return end   -- overlay cargado
    local g = sp32 and u32(sp32[0]) or 0
    local fade = (g >= 0x80000000 and g < 0x80200000) and rd8(g + 0x6D) or 0
    local s = string.format('etapa %d paso %d sub %d  fundido %02X  start %s',
      rd8(0x8015CEAC), rd8(0x8015CEAD), rd8(0x8015CEAE), fade,
      band(rd16(0x800AE270), 0x0800) ~= 0 and 'si' or 'no')
    if s ~= last then
      print(string.format('[v%6d %5.1fs] %s  tempo %d', v, v / 50, s, rd8(0x8015CEAF)))
      last = s
    end
  end)
  print('[dci] fe prendido (despues: Emulation -> Reset)')
end

print('[dci] v2 listo: dci.log()  dci.mark(txt)  dci.dump(nombre)  dci.skip()  dci.fe()')
