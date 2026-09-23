----------------------------------------------------------------------
-- dc_room.lua  --  ¿Que parte de la habitacion esta cargada / se dibuja?
-- Dino Crisis SLES-02211, PCSX-Redux.  Independiente de dct, dc6 y dci.
--
-- Antes: Debug -> depurador + interprete, Emulation -> Reset.
--   dofile('C:/dc/dc_room.lua')
--
-- Leido del desensamblado (0x8006B574, la rutina que dibuja el escenario):
--   tabla de mallas del escenario en G + 0x7CDC .. G + 0x8FFC
--   (G = [0x1F800000] = 0x800B03D8), 36 registros de 0x88 bytes.
--   Cada registro es un objeto (misma forma que el jugador: matriz en +0,
--   traslacion en +0x14, posicion en +0x20).
--                  +0x30 banderas: se dibuja SOLO si (banderas & 3) == 3
--                        (medido: el bit 1 se prende y apaga en cada corte
--                        de camara; el bit 0 queda fijo)
--                  +0x3C puntero al MODELO (0x8006B79C: lw $s0, -0xE($s1),
--                        con $s1 = registro + 0x4A); se pasa a 0x8006E29C
--                  +0x40 puntero al objeto PADRE (0 = sin padre; si tiene,
--                        se compone su matriz). v1 de la herramienta lo tomo
--                        por el modelo: error, por eso all() no hacia nada.
--                  +0x48 modo de orden de dibujo (0..3, seccion 9)
--   (lo que elige el modo de orden de dibujo, 0x8006B7C0, es de este mismo
--   bucle: seccion 9 del .md)
--
--   dcr.show()      tabla ahora: indice, banderas, puntero
--   dcr.watch()     una linea cada vez que cambia algun registro (banderas o
--                   puntero), con el Vsync; ademas avisa cada pedido de carga
--                   al CD (0x800221F0) con sus argumentos. Otra vez = parar.
--   dcr.flagWho()   quien escribe las banderas (+0x30) de los registros
--                   (breakpoint de escritura). Otra vez = parar y resumen.
--   dcr.all(modo)   EXPERIMENTO (guardar savestate antes): justo antes de
--                   dibujar, fuerza "se dibuja" en mallas que el juego tiene
--                   apagadas.  modo 1: solo pone el bit 1 donde el bit 0 ya
--                   esta (y hay puntero).  modo 3: pone los dos bits donde hay
--                   puntero.  dcr.all() = apagar y devolver las banderas.
----------------------------------------------------------------------

local ffi = require('ffi')
local band, bor, rshift = bit.band, bit.bor, bit.rshift
local mem = PCSX.getMemPtr()
local ram32 = ffi.cast('uint32_t*', mem)
local ram8  = ffi.cast('uint8_t*', mem)
local sp32
do
  local ok, p = pcall(function() return PCSX.getScratchPtr() end)
  if ok and p ~= nil then sp32 = ffi.cast('uint32_t*', p) end
end
local function u32(v) v = tonumber(v); if v < 0 then v = v + 0x100000000 end; return v end
local function rd32(a) return u32(ram32[rshift(band(a, 0x1FFFFF), 2)]) end
local function wr32(a, v) ram32[rshift(band(a, 0x1FFFFF), 2)] = u32(v) end   -- bit.* da con signo
local function gpr(n) return u32(ffi.cast('uint32_t', PCSX.getRegisters().GPR.n[n])) end
local function pcv() return u32(ffi.cast('uint32_t', PCSX.getRegisters().pc)) end

local dcr = {}
_G.dcr = dcr
dcr.N, dcr.SZ, dcr.OFF = 36, 0x88, 0x7CDC

local L, B = {}, {}
local function onVsync(key, fn)
  if L[key] then L[key]:remove() end
  L[key] = fn and PCSX.Events.createEventListener('GPU::Vsync', fn) or nil
end

local function G()
  local g = sp32 and u32(sp32[0]) or 0
  if g < 0x80000000 or g >= 0x80200000 then g = 0x800B03D8 end
  return g
end
local function rec(i) return G() + dcr.OFF + i * dcr.SZ end

local function snap()
  local t = {}
  for i = 0, dcr.N - 1 do
    local a = rec(i)
    t[i] = { fl = rd32(a + 0x30), p = rd32(a + 0x3C), par = rd32(a + 0x40), m = ram8[band(a + 0x48, 0x1FFFFF)] }
  end
  return t
end

local function line(t)
  local on, off, empty = {}, {}, 0
  for i = 0, dcr.N - 1 do
    local r = t[i]
    if r.p < 0x80010000 or r.p >= 0x80200000 then empty = empty + 1
    elseif band(r.fl, 3) == 3 then on[#on + 1] = tostring(i)
    else off[#off + 1] = string.format('%d(%X)', i, band(r.fl, 0xF)) end
  end
  return string.format('dibuja [%s]  con modelo pero apagadas [%s]  sin modelo %d',
    table.concat(on, ' '), table.concat(off, ' '), empty)
end

function dcr.show()
  local t = snap()
  print(string.format('[dcr] tabla en %08X (G=%08X)', rec(0), G()))
  for i = 0, dcr.N - 1 do
    local r = t[i]
    if r.p ~= 0 or r.fl ~= 0 then
      print(string.format('  %2d  %08X  banderas %08X  modelo %08X  padre %08X  orden %d  %s', i, rec(i),
        r.fl, r.p, r.par, r.m, band(r.fl, 3) == 3 and 'SE DIBUJA' or ''))
    end
  end
  print('[dcr] ' .. line(t))
end

function dcr.watch()
  if L.watch then
    onVsync('watch', nil)
    if B.load then B.load:remove(); B.load = nil end
    print('[dcr] watch apagado') return
  end
  local v, prev = 0, snap()
  print('[dcr] ' .. line(prev))
  B.load = PCSX.addBreakpoint(0x800221F0, 'Exec', 4, 'dcr carga', function()
    print(string.format('[v%6d] >>> carga CD: a0=%08X a1=%08X a2=%08X  ra=%08X',
      v, gpr('a0'), gpr('a1'), gpr('a2'), gpr('ra')))
  end)
  onVsync('watch', function()
    v = v + 1
    local t = snap()
    local ch = {}
    for i = 0, dcr.N - 1 do
      local a, b = prev[i], t[i]
      if a.fl ~= b.fl or a.p ~= b.p then
        ch[#ch + 1] = string.format('%d: %X->%X%s', i, band(a.fl, 0xFFFF), band(b.fl, 0xFFFF),
          a.p ~= b.p and string.format(' ptr %08X->%08X', a.p, b.p) or '')
      end
    end
    if #ch > 0 then
      print(string.format('[v%6d] cambia %s', v, table.concat(ch, ', ')))
      print('         ' .. line(t))
    end
    prev = t
  end)
  print('[dcr] watch prendido: camina por la habitacion cruzando cortes de camara')
end

function dcr.flagWho()
  if B.flag then
    B.flag:remove(); B.flag = nil
    local t = {}
    for k, n in pairs(dcr._who) do t[#t + 1] = { k, n } end
    table.sort(t, function(a, b) return a[2] > b[2] end)
    print('[dcr] quien escribe las banderas (+0x30):')
    for _, e in ipairs(t) do print(string.format('  pc %08X  x%d', e[1], e[2])) end
    return
  end
  dcr._who = {}
  local lo = rec(0)
  B.flag = PCSX.addBreakpoint(lo, 'Write', dcr.N * dcr.SZ, 'dcr flag', function(addr)
    local off = (u32(addr or 0) - lo) % dcr.SZ
    if off >= 0x30 and off < 0x34 then
      local pc = pcv()
      dcr._who[pc] = (dcr._who[pc] or 0) + 1
    end
  end)
  print('[dcr] flagWho prendido: cruza un par de cortes de camara y volve a llamar')
end

local forced = {}
function dcr.all(modo)
  if B.all then B.all:remove(); B.all = nil end
  -- solo se sacan los bits que puso el experimento (el juego pudo haber
  -- cambiado el resto de la palabra mientras tanto)
  for a, added in pairs(forced) do wr32(a, band(rd32(a), bit.bnot(added))) end
  forced = {}
  if not modo then print('[dcr] all apagado, banderas devueltas') return end
  B.all = PCSX.addBreakpoint(0x8006B574, 'Exec', 4, 'dcr all', function()
    for i = 0, dcr.N - 1 do
      local a = rec(i)
      local fl, p = rd32(a + 0x30), rd32(a + 0x3C)
      if p >= 0x80010000 and p < 0x80200000 and band(fl, 3) ~= 3 and (modo == 3 or band(fl, 1) == 1) then
        forced[a + 0x30] = bor(forced[a + 0x30] or 0, band(bit.bnot(fl), 3))
        wr32(a + 0x30, bor(fl, 3))
      end
    end
  end)
  print(string.format('[dcr] all(%d) prendido. dcr.all() para apagar.', modo))
end

----------------------------------------------------------------------
-- DIAGNOSTICO del tiron en los cortes de camara (v2)
--   dcr.cut()   otra vez = parar
-- Por cada corte (cambian las banderas de las mallas) imprime una tira con
-- 30 Vsync antes y 12 despues. Cada Vsync es un grupo de letras:
--   P = corrio el jugador (0x80045378 con $s0 = jugador)
--   C = corrio la camara (0x8001F3D8 con $s0 = camara)
--   D = se dibujo el escenario (0x8006B574)
--   . = nada de eso
-- Medido en v1: las banderas las escribe 0x8004DF24, dentro de 0x8004DAFC,
-- que es un "poner campo = valor" de un interprete de guiones (tablas de
-- saltos por tipo y por campo): el corte de camara lo hace el guion del
-- cuarto. El tramo sin P esta ANTES del cambio de banderas.
-- Ademas compara la estructura del juego G (0x100 bytes desde G) entre los
-- cuadros de juego normal (con P) y los del hueco (con C y sin P): lista los
-- bytes que valen SIEMPRE una cosa en los normales y otra en el hueco.
----------------------------------------------------------------------
function dcr.cut()
  if L.cut then
    onVsync('cut', nil)
    for _, k in ipairs({ 'cP', 'cC', 'cD' }) do if B[k] then B[k]:remove(); B[k] = nil end end
    print('[dcr] cut apagado') return
  end
  local BEFORE, AFTER, GN = 30, 12, 0x100
  local v, cur, ring, after, prev, win = 0, '', {}, 0, snap(), nil
  B.cP = PCSX.addBreakpoint(0x80045378, 'Exec', 4, 'dcr cP', function()
    if gpr('s0') == 0x800B1E14 and not cur:find('P') then cur = cur .. 'P' end end)
  B.cC = PCSX.addBreakpoint(0x8001F3D8, 'Exec', 4, 'dcr cC', function()
    if gpr('s0') == 0x800B048C and not cur:find('C') then cur = cur .. 'C' end end)
  B.cD = PCSX.addBreakpoint(0x8006B574, 'Exec', 4, 'dcr cD', function()
    if not cur:find('D') then cur = cur .. 'D' end end)
  local function gsnap()
    local g, t = G(), {}
    for k = 0, GN - 1 do t[k] = ram8[band(g + k, 0x1FFFFF)] end
    return t
  end
  local function report(w)
    local s = {}
    for k, e in ipairs(w) do s[#s + 1] = (e.cut and '|' or '') .. e.l end
    print(string.format('[v%6d] corte: %s', v, table.concat(s, ' ')))
    -- hueco = cuadros con C y sin P, pegados antes del corte
    local cutAt
    for k, e in ipairs(w) do if e.cut then cutAt = k end end
    local gap, norm = {}, {}
    local k = cutAt
    if w[k].l:find('P') then k = k - 1 end   -- el cuadro del corte puede traer ya al jugador
    -- (a 25 cuadros por segundo hay Vsync sin nada, '.': se saltean)
    while k >= 1 and not w[k].l:find('P') do
      if w[k].l:find('C') then gap[#gap + 1] = w[k] end
      k = k - 1
    end
    for _, e in ipairs(w) do if e.l:find('P') then norm[#norm + 1] = e end end
    print(string.format('          hueco sin jugador: %d cuadros de camara%s', #gap, k < 1 and ' (o mas: empezo antes de la ventana)' or ''))
    if #gap == 0 or #norm == 0 then return end
    local cand = {}
    for o = 0, GN - 1 do
      local nv, ok = norm[1].g[o], true
      for _, e in ipairs(norm) do if e.g[o] ~= nv then ok = false break end end
      if ok then
        for _, e in ipairs(gap) do if e.g[o] == nv then ok = false break end end
      end
      if ok then
        local gv = {}
        for _, e in ipairs(gap) do gv[#gv + 1] = string.format('%02X', e.g[o]) end
        cand[#cand + 1] = string.format('G+%02X normal %02X / hueco %s', o, nv, table.concat(gv, ','))
      end
    end
    print('          candidatos: ' .. (#cand > 0 and table.concat(cand, '; ') or 'ninguno'))
  end
  onVsync('cut', function()
    v = v + 1
    local e = { l = cur == '' and '.' or cur, g = gsnap() }
    cur = ''
    local t, changed = snap(), false
    for i = 0, dcr.N - 1 do if band(t[i].fl, 3) ~= band(prev[i].fl, 3) then changed = true end end
    prev = t
    if win then
      win[#win + 1] = e
      after = after - 1
      if after == 0 then report(win); win = nil end
    elseif changed then
      e.cut = true
      win = {}
      for _, x in ipairs(ring) do win[#win + 1] = x end
      win[#win + 1] = e
      after = AFTER
    end
    ring[#ring + 1] = e
    if #ring > BEFORE then table.remove(ring, 1) end
  end)
  print('[dcr] cut v2 prendido: cruza cortes de camara (original y hombro)')
end

----------------------------------------------------------------------
-- La pausa del corte: bit 0x0800 de la palabra G+0x40 (= G+0x41 bit 3).
-- Medido con dcr.cut() v2: G+0x41 = 08 durante los 6 cuadros sin jugador,
-- 00 en juego normal, en los 4 cortes. (El bit 0x0004 de esa misma palabra
-- es la bandera de cinematica que usa el parche.)
--   dcr.pauseWho()  otra vez = parar y resumen
-- Anota quien ESCRIBE la palabra (con $ra, y si el bit 0x0800 se prende o se
-- apaga) y quien la LEE (con cuantas veces). Cruza 2 o 3 cortes.
----------------------------------------------------------------------
function dcr.pauseWho()
  if B.pw then
    B.pw:remove(); B.pw = nil; B.pr:remove(); B.pr = nil
    local t = {}
    for k, n in pairs(dcr._rd) do t[#t + 1] = { k, n } end
    table.sort(t, function(a, b) return a[1] < b[1] end)
    print('[dcr] lectores de G+0x40..43 (pc x veces):')
    local s = {}
    for _, e in ipairs(t) do s[#s + 1] = string.format('%08X x%d', e[1], e[2]) end
    print('  ' .. table.concat(s, '  '))
    return
  end
  local a = G() + 0x40
  local last = rd32(a)
  dcr._rd = {}
  B.pw = PCSX.addBreakpoint(a, 'Write', 4, 'dcr pw', function()
    -- el breakpoint salta ANTES de la escritura: se mira el valor en el
    -- proximo Vsync
    local pc, ra = pcv(), gpr('ra')
    dcr._pend = dcr._pend or {}
    dcr._pend[#dcr._pend + 1] = { pc = pc, ra = ra }
  end)
  B.pr = PCSX.addBreakpoint(a, 'Read', 4, 'dcr pr', function()
    local pc = pcv(); dcr._rd[pc] = (dcr._rd[pc] or 0) + 1
  end)
  onVsync('pw', function()
    local now = rd32(a)
    if dcr._pend and #dcr._pend > 0 then
      local s = {}
      for _, e in ipairs(dcr._pend) do s[#s + 1] = string.format('pc %08X ra %08X', e.pc, e.ra) end
      if band(now, 0x800) ~= band(last, 0x800) then
        print(string.format('[dcr] G+40: %08X -> %08X  (bit 0800 %s)  %s', last, now,
          band(now, 0x800) ~= 0 and 'SE PRENDE' or 'se apaga', table.concat(s, ', ')))
      end
      dcr._pend = {}
    end
    last = now
    if not B.pw then onVsync('pw', nil) end
  end)
  print('[dcr] pauseWho prendido: cruza 2 o 3 cortes y volve a llamar')
end

----------------------------------------------------------------------
-- ¿Quien deja de llamar al jugador en el corte?
-- Correccion: G+0x41 = 08 (bit 0x0800 de G+0x40) NO es la causa. Leido del
-- desensamblado: 0x8003FFE0 (el paso de juego de cada cuadro, tabla de modos
-- 0x800951C0) hace set_flag(1, 11) al empezar (0x80042B48(grupo, bit,
-- prender)) y el control del jugador lo apaga cuando corre (0x8004683C,
-- 0x80045D00). O sea: "el jugador todavia no corrio este cuadro". Es una
-- CONSECUENCIA del hueco.
--   dcr.gate()   otra vez = parar
-- 1) La primera vez que corre el jugador, lee la pila y arma la cadena de
--    llamadas (direcciones de retorno plausibles) y el comienzo de cada
--    funcion (addiu $sp, $sp, -N hacia atras).
-- 2) Pone un breakpoint en el comienzo de cada una y, en cada corte, imprime
--    una tira por Vsync: P = jugador, y los numeros de las funciones de la
--    cadena que corrieron. La mas profunda que SIGUE corriendo en el hueco
--    es la que decide no llamar a la siguiente.
----------------------------------------------------------------------
local function mrd32(a)
  if a >= 0x1F800000 and a < 0x1F800400 then return sp32 and u32(sp32[rshift(a - 0x1F800000, 2)]) or 0 end
  if a >= 0x80000000 and a < 0x80200000 then return rd32(a) end
  return 0
end
local function isRet(w)
  if band(w, 3) ~= 0 or w < 0x80010000 or w >= 0x801FF000 then return false end
  local i = mrd32(w - 8)
  local op = rshift(i, 26)
  return op == 3 or (op == 0 and band(i, 0x3F) == 9)
end
local function fnStart(a)
  for k = 0, 0x1000 do
    local w = rd32(a - k * 4)
    if rshift(w, 16) == 0x27BD and band(w, 0x8000) ~= 0 then return a - k * 4 end
  end
  return nil
end

function dcr.gate()
  if L.gate then
    onVsync('gate', nil)
    for k, b in pairs(B) do if k:sub(1, 2) == 'g_' then b:remove(); B[k] = nil end end
    print('[dcr] gate apagado') return
  end
  local fns, cur, v, ring, win, after, prev = nil, {}, 0, {}, nil, 0, snap()
  local function mark(c) cur[c] = true end
  local function arm()
    for i, f in ipairs(fns) do
      B['g_' .. i] = PCSX.addBreakpoint(f.start, 'Exec', 4, 'dcr g' .. i, function() mark(tostring(i)) end)
    end
  end
  B.g_P = PCSX.addBreakpoint(0x80045378, 'Exec', 4, 'dcr gP', function()
    if gpr('s0') ~= 0x800B1E14 then return end
    mark('P')
    if fns then return end
    fns = {}
    local sp, seen = gpr('sp'), {}
    local chain = { gpr('ra') }
    for k = 0, 255 do
      local w = mrd32(sp + k * 4)
      if isRet(w) and not seen[w] then seen[w] = true; chain[#chain + 1] = w end
      if #chain >= 8 then break end
    end
    local out = {}
    for i, r in ipairs(chain) do
      local st = fnStart(r - 8)
      if st then fns[#fns + 1] = { ret = r, start = st }; out[#out + 1] = string.format('%d: fn %08X (vuelve a %08X)', #fns, st, r) end
    end
    print('[dcr] cadena del jugador (1 = la que llama al jugador, despues hacia arriba):')
    for _, l in ipairs(out) do print('   ' .. l) end
    arm()
  end)
  onVsync('gate', function()
    v = v + 1
    local keys = {}
    if cur.P then keys[#keys + 1] = 'P' end
    if fns then for i = 1, #fns do if cur[tostring(i)] then keys[#keys + 1] = tostring(i) end end end
    local e = #keys > 0 and table.concat(keys) or '.'
    cur = {}
    local t, changed = snap(), false
    for i = 0, dcr.N - 1 do if band(t[i].fl, 3) ~= band(prev[i].fl, 3) then changed = true end end
    prev = t
    if win then
      win[#win + 1] = e; after = after - 1
      if after == 0 then print(string.format('[v%6d] corte: %s', v, table.concat(win, ' '))); win = nil end
    elseif changed and fns then
      win = {}
      for _, x in ipairs(ring) do win[#win + 1] = x end
      win[#win + 1] = '|' .. e; after = 8
    end
    ring[#ring + 1] = e
    if #ring > 18 then table.remove(ring, 1) end
  end)
  print('[dcr] gate prendido: primero camina un poco, despues cruza 2 o 3 cortes')
end

----------------------------------------------------------------------
-- La compuerta, medida con dcr.gate(): en el hueco corren 0x8003FFE0 y
-- 0x8004285C pero NO la lista de objetos 0x80042724. Leido del
-- desensamblado de 0x8004285C:
--   80042870  jal check_flag(2, 20)   (0x80042BDC; grupo 2 = palabra G+0x3C,
--   80042878  bnez -> 0x8004295C       bit 20 = byte G+0x3E bit 0x10)
--   si esta prendida saltea TODA la actualizacion de objetos.
-- dcr.cut() no la vio porque solo mira en el Vsync (puede prenderse y
-- apagarse dentro del cuadro). Esto la mide en el momento:
--   dcr.freezeWho()   otra vez = parar
-- * cada vez que alguien prende/apaga (2, 20) con set_flag (0x80042B48):
--   Vsync, prender/apagar y $ra (quien lo pide)
-- * en cada cuadro, el resultado de la consulta en 0x80042878 (1 = saltea)
----------------------------------------------------------------------
function dcr.freezeWho()
  if B.fzS then
    B.fzS:remove(); B.fzS = nil; B.fzC:remove(); B.fzC = nil; B.fzW:remove(); B.fzW = nil; onVsync('fz', nil)
    print('[dcr] freezeWho apagado') return
  end
  local v, run, lastRes = 0, {}, nil
  B.fzS = PCSX.addBreakpoint(0x80042B48, 'Exec', 4, 'dcr fzS', function()
    if gpr('a0') == 2 and gpr('a1') == 20 then
      print(string.format('[v%6d] set_flag(2,20,%d)  ra %08X', v, gpr('a2'), gpr('ra')))
    end
  end)
  -- escrituras DIRECTAS a la palabra G+0x3C (sin set_flag): se decodifica el
  -- sw/sh/sb para leer el valor nuevo del registro antes de que se escriba
  local RN = { [0]='r0','at','v0','v1','a0','a1','a2','a3','t0','t1','t2','t3','t4','t5','t6','t7',
               's0','s1','s2','s3','s4','s5','s6','s7','t8','t9','k0','k1','gp','sp','s8','ra' }
  local wa = G() + 0x3C
  B.fzW = PCSX.addBreakpoint(wa, 'Write', 4, 'dcr fzW', function(addr)
    local pc = pcv()
    local ins = rd32(pc)
    local op, rt = rshift(ins, 26), band(rshift(ins, 16), 31)
    local val = rt == 0 and 0 or gpr(RN[rt])
    local old = rd32(wa)
    local new
    addr = u32(addr or wa)
    if op == 0x2B then new = val
    elseif op == 0x29 then local sh = (addr - wa) * 8; new = bor(band(old, bit.bnot(bit.lshift(0xFFFF, sh))), bit.lshift(band(val, 0xFFFF), sh))
    elseif op == 0x28 then local sh = (addr - wa) * 8; new = bor(band(old, bit.bnot(bit.lshift(0xFF, sh))), bit.lshift(band(val, 0xFF), sh))
    else return end
    if band(old, 0x100000) ~= band(u32(new), 0x100000) then
      print(string.format('[v%6d] G+3C escrita directo: bit 20 %s  pc %08X ra %08X', v,
        band(u32(new), 0x100000) ~= 0 and 'SE PRENDE' or 'se apaga', pc, gpr('ra')))
    end
  end)
  B.fzC = PCSX.addBreakpoint(0x80042878, 'Exec', 4, 'dcr fzC', function()
    run[#run + 1] = gpr('v0') ~= 0 and '1' or '0'
  end)
  onVsync('fz', function()
    v = v + 1
    if #run > 0 then
      local r = table.concat(run)
      run = {}
      if r ~= lastRes then print(string.format('[v%6d] consulta (2,20): %s', v, r)); lastRes = r end
    end
  end)
  print('[dcr] freezeWho prendido: cruza 2 o 3 cortes')
end

----------------------------------------------------------------------
-- El tiron del corte, entero (medido con dcr.freezeWho + desensamblado):
--   0x8001EC34 (zona de camara), rama 0x8001EE10: si toca cambiar de camara
--     set_flag(2, 20, 1)        congela TODOS los objetos (0x8004285C lo mira)
--     cam+0x73 = 6              cuenta regresiva: 6 cuadros de juego
--     cam+0x72 |= 1             cambio pendiente
--   0x8001F43C (cada cuadro): si cam+0x72 & 1, cam+0x73--; al llegar a 0
--     corre el guion de la camara (0x8004D8C8(9, cam+0x68): prende/apaga las
--     mallas), toma la camara nueva (cam+0x5C) y set_flag(2, 20, 0).
--   O sea: es una espera A PROPOSITO de 6 cuadros con el mundo quieto, no un
--   limite de la consola (no carga nada del CD, la camara y el dibujo siguen).
-- PROTOTIPO:
--   dcr.fastcut(1)  justo despues de que el juego pone la cuenta en 6
--                   (0x8001EE3C), la pone en 1: el cambio se hace en el
--                   cuadro siguiente, por el camino normal del juego.
--   dcr.fastcut(2)  lo mismo y ademas descongela ya (bit 20 de G+0x3C en 0).
--   dcr.fastcut()   apagar.
-- Imprime el objeto de camara ($s0) la primera vez, para confirmarlo.
----------------------------------------------------------------------
function dcr.fastcut(modo)
  if B.fc then B.fc:remove(); B.fc = nil end
  if not modo then print('[dcr] fastcut apagado') return end
  local shown = false
  B.fc = PCSX.addBreakpoint(0x8001EE3C, 'Exec', 4, 'dcr fc', function()
    local cam = gpr('s0')
    -- solo con Regina en estado normal (+3C = 01): en las puertas (+3C = 04)
    -- el juego congela y descongela por su lado (0x8001E414), no se toca
    if ram8[band(0x800B1E14 + 0x3C, 0x1FFFFF)] ~= 1 then return end
    if not shown then shown = true; print(string.format('[dcr] fastcut: objeto de camara %08X, cuenta %d', cam, ram8[band(cam + 0x73, 0x1FFFFF)])) end
    ram8[band(cam + 0x73, 0x1FFFFF)] = 1
    if modo == 2 then
      local a = G() + 0x3C
      wr32(a, band(rd32(a), bit.bnot(0x100000)))
    end
  end)
  print(string.format('[dcr] fastcut(%d) prendido', modo))
end

----------------------------------------------------------------------
-- "Salon de espejos" en las zonas sin geometria (camara al hombro)
-- El juego NO borra la pantalla entre cuadros: con las camaras fijas la
-- geometria cubre siempre todo el encuadre. Con la camara libre, donde no hay
-- nada (lo que nunca se modelo) queda lo que habia en ese pixel en cuadros
-- anteriores (el "screenshot" del fondo), o negro si no se dibujo nunca desde
-- que se entro a la sala.
-- Leido del bucle principal: DrawOTag([0x800AE280] + 0x80) en 0x800150FC
-- (OT de 5 ranuras en +0x70..+0x80, al reves: +0x80 se dibuja PRIMERO; el HUD
-- va en +0x70, encima de todo). Lo que se engancha durante el cuadro se
-- dibuja en la vuelta siguiente, despues del cambio de buffer.
-- PROTOTIPO:
--   dcr.clear(color)  cada cuadro, con la camara al hombro, engancha un TILE
--                     de pantalla completa en la ranura +0x80 (el fondo de
--                     todo). color BGR, 0 = negro (por defecto).
--   dcr.clear()       apagar.
-- Lee sortOn de dc6 (dc6.SORTON, desde v6.10b) para saber si la camara al
-- hombro esta activa: hacer dofile de dc6.lua antes.
----------------------------------------------------------------------
-- la direccion de sortOn cambia con cada version: se toma de dc6 si esta cargado
dcr.SORTON = (rawget(_G, 'dc6') and dc6.SORTON) or 0x800D99DC
function dcr.clear(color)
  if B.clr then B.clr:remove(); B.clr = nil; print('[dcr] clear apagado') return end
  color = color or 0
  local buf, flip = 0x800E4480, 0
  if rawget(_G, 'dc6') and dc6.SORTON then dcr.SORTON = dc6.SORTON end
  print(string.format('[dcr] sortOn en %08X', dcr.SORTON))
  B.clr = PCSX.addBreakpoint(0x8001F3D8, 'Exec', 4, 'dcr clr', function()
    if gpr('s0') ~= 0x800B048C then return end
    if rd32(dcr.SORTON) == 0 then return end
    local base = rd32(0x800AE280)
    if base < 0x80010000 or base >= 0x80200000 then return end
    local slot = base + 0x80
    flip = bit.bxor(flip, 0x10)
    local t = buf + flip
    wr32(t + 4, bor(0x60000000, band(color, 0xFFFFFF)))  -- TILE, color
    wr32(t + 8, 0)                                          -- y|x = 0,0
    wr32(t + 12, bor(bit.lshift(511, 16), 1023))           -- h|w maximos (10 y 9 bits); lo recorta el area de dibujo
    wr32(t, bor(0x03000000, band(rd32(slot), 0xFFFFFF)))   -- 3 palabras, siguiente = lo que habia
    wr32(slot, bor(band(rd32(slot), 0xFF000000), band(t, 0xFFFFFF)))
  end)
  print(string.format('[dcr] clear prendido (color %06X)', color))
end

----------------------------------------------------------------------
-- Los dinosaurios invisibles fuera del encuadre de la camara fija
-- (Nahuel: existen, se los oye y se les puede disparar: no es que no
-- aparezcan, es que no se DIBUJAN.)
-- Leido del desensamblado: hay una SEGUNDA tabla con el mismo esquema de dos
-- pasadas que las mallas:
--   G + 0x5FCC .. G + 0x7CDC, 60 registros de 0x7C bytes (objeto: posicion
--   en +0x20, angulos en +0x28, banderas en +0x30)
--   pasada previa 0x8006B24C y dibujo 0x8006B978: los dos exigen bit 1 (& 2)
-- Hipotesis a medir: los dinos (o sus partes) estan en esta tabla y el bit 1
-- se apaga cuando no estan en la zona de la camara fija.
--   dcr.parts()       lista los registros usados (banderas, +0x3C, +0x40)
--   dcr.partsWatch()  una linea cada vez que cambian las banderas de alguno
--                     (otra vez = parar)
----------------------------------------------------------------------
dcr.P_OFF, dcr.P_N, dcr.P_SZ = 0x5FCC, 60, 0x7C
local function prec(i) return G() + dcr.P_OFF + i * dcr.P_SZ end
function dcr.parts()
  print(string.format('[dcr] tabla 0x7C en %08X', prec(0)))
  local n = 0
  for i = 0, dcr.P_N - 1 do
    local a = prec(i)
    local fl = rd32(a + 0x30)
    if fl ~= 0 then
      n = n + 1
      print(string.format('  %2d  %08X  banderas %08X  +3C %08X  +40 %08X  pos %d,%d,%d', i, a, fl,
        rd32(a + 0x3C), rd32(a + 0x40),
        bit.arshift(bit.lshift(rd32(a + 0x20), 16), 16), bit.arshift(bit.lshift(rd32(a + 0x20), 0), 16),
        bit.arshift(bit.lshift(rd32(a + 0x24), 16), 16)))
    end
  end
  print(string.format('[dcr] %d registros con banderas', n))
end
function dcr.partsWatch()
  if L.pw2 then onVsync('pw2', nil); print('[dcr] partsWatch apagado') return end
  local v, prev = 0, {}
  for i = 0, dcr.P_N - 1 do prev[i] = rd32(prec(i) + 0x30) end
  onVsync('pw2', function()
    v = v + 1
    local ch = {}
    for i = 0, dcr.P_N - 1 do
      local fl = rd32(prec(i) + 0x30)
      if fl ~= prev[i] then ch[#ch + 1] = string.format('%d: %X->%X', i, prev[i], fl); prev[i] = fl end
    end
    if #ch > 0 then print(string.format('[v%6d] %s', v, table.concat(ch, ', '))) end
  end)
  print('[dcr] partsWatch prendido')
end

----------------------------------------------------------------------
-- Dinos invisibles, segunda hipotesis. La tabla 0x7C resulto ser de efectos
-- (registros 52..59 que viven ~20 Vsync y van 0 -> 3 -> 0, al final de la
-- tabla: disparos/sangre), no de dinosaurios.
-- Los personajes estan en la tabla de OBJETOS que recorre 0x80042724:
--   G + 0x27C + i * 0x260, i = 0..10 (el 10 es Regina, 0x800B1E14);
--   corre el manejador si (obj+0x30 & 1).
-- Metodo (el de siempre: evento + ruido medido): tres fases de 1 segundo.
--   dcr.dinoA()  con el dino INVISIBLE (fuera del encuadre de camara fija)
--   dcr.dinoB()  con el dino VISIBLE
--   dcr.dinoA()  otra vez invisible   -> imprime el resultado
-- Por cada objeto 0..9 y cada BIT de sus 0x260 bytes: se queda con los que no
-- cambian dentro de cada fase, valen lo mismo en las dos fases A y distinto
-- en la B. (Por bits, no por bytes: la leccion de dcr.cut.)
----------------------------------------------------------------------
local OBJ0, OSZ, ON, OBYTES = 0x27C, 0x260, 10, 0x260
local phases = {}
local function takePhase(name, done)
  local vmin, vmax = {}, {}   -- por byte: AND y OR de las muestras
  local n = 0
  onVsync('dino', function()
    n = n + 1
    local g = G()
    for o = 0, ON - 1 do
      local base = g + OBJ0 + o * OSZ
      for k = 0, OBYTES - 1 do
        local idx = o * OBYTES + k
        local b = ram8[band(base + k, 0x1FFFFF)]
        if n == 1 then vmin[idx] = b; vmax[idx] = b
        else vmin[idx] = band(vmin[idx], b); vmax[idx] = bor(vmax[idx], b) end
      end
    end
    if n >= 25 then
      onVsync('dino', nil)
      phases[#phases + 1] = { name = name, a = vmin, o = vmax }
      print(string.format('[dcr] fase %s tomada (%d)', name, #phases))
      if done then done() end
    end
  end)
end
local function report()
  local A1, B, A2 = phases[1], phases[2], phases[3]
  local out = 0
  for o = 0, ON - 1 do
    for k = 0, OBYTES - 1 do
      local idx = o * OBYTES + k
      -- bits constantes dentro de cada fase: and == or en ese bit
      local const = band(bit.bnot(bit.bxor(A1.a[idx], A1.o[idx])),
                         bit.bnot(bit.bxor(B.a[idx], B.o[idx])),
                         bit.bnot(bit.bxor(A2.a[idx], A2.o[idx])))
      local same = bit.bnot(bit.bxor(A1.a[idx], A2.a[idx]))
      local diff = bit.bxor(A1.a[idx], B.a[idx])
      local m = band(const, same, diff, 0xFF)
      if m ~= 0 then
        out = out + 1
        if out <= 40 then
          print(string.format('  obj %d  +%03X  bits %02X   invisible %02X / visible %02X', o, k, m,
            band(A1.a[idx], m), band(B.a[idx], m)))
        end
      end
    end
  end
  print(string.format('[dcr] %d candidatos%s', out, out > 40 and ' (se muestran 40)' or ''))
  phases = {}
end
function dcr.dinoA()
  if #phases == 0 then takePhase('A (invisible)')
  elseif #phases == 2 then takePhase('A (invisible, otra vez)', report)
  else print('[dcr] ahora toca dcr.dinoB()') end
end
function dcr.dinoB()
  if #phases == 1 then takePhase('B (visible)') else print('[dcr] primero dcr.dinoA()') end
end
function dcr.dinoReset() phases = {}; onVsync('dino', nil); print('[dcr] fases borradas') end

----------------------------------------------------------------------
-- Excepciones de estado: laseres apagados y la bateria de mas del puzzle se
-- ven con la camara al hombro. O sea que el bit 1 de +0x30 no es SOLO "en la
-- zona de la camara fija": el juego tambien lo usa para esconder cosas por
-- estado. Para separar los dos usos hay que saber QUIEN apaga cada cosa.
-- Leido del desensamblado: el cambio de camara corre el guion de la camara
--   0x8001EE4C / 0x8001F480: jal 0x8004D8C8(9, cam+0x68)  (prepara el guion)
--   0x8001EE54 / 0x8001F488: jal 0x8004DA48               (lo corre)
-- Todo cambio del bit 1 entre esas llamadas es "de camara"; el resto es de
-- otro lado (logica de la sala: laseres, puzzles, eventos).
--   dcr.visWho()   otra vez = parar
-- Una linea por Vsync con cambios del bit 1 de mallas (M) y objetos (O):
--   CAMARA: M2+ M5- ...      OTRO pc/ra: M7- ...
-- Probar: cruzar cortes, entrar por una puerta, apagar/prender los laseres,
-- tocar el puzzle de las baterias.
----------------------------------------------------------------------
local RN2 = { [0]='r0','at','v0','v1','a0','a1','a2','a3','t0','t1','t2','t3','t4','t5','t6','t7',
              's0','s1','s2','s3','s4','s5','s6','s7','t8','t9','k0','k1','gp','sp','s8','ra' }
local function newVal(addr, word)
  local pc = pcv()
  local ins = rd32(pc)
  local op, rt = rshift(ins, 26), band(rshift(ins, 16), 31)
  local val = rt == 0 and 0 or gpr(RN2[rt])
  local old = rd32(word)
  if op == 0x2B then return u32(val), old end
  local sh = (addr - word) * 8
  if op == 0x29 then return u32(bor(band(old, bit.bnot(bit.lshift(0xFFFF, sh))), bit.lshift(band(val, 0xFFFF), sh))), old end
  if op == 0x28 then return u32(bor(band(old, bit.bnot(bit.lshift(0xFF, sh))), bit.lshift(band(val, 0xFF), sh))), old end
  return nil, old
end
function dcr.visWho()
  if L.vis then
    onVsync('vis', nil)
    for _, k in ipairs({ 'vM', 'vO', 'vc1', 'vc2', 'vc3', 'vc4' }) do if B[k] then B[k]:remove(); B[k] = nil end end
    print('[dcr] visWho apagado') return
  end
  local v, inCam, ev = 0, false, {}
  local function on() inCam = true end
  local function off() inCam = false end
  B.vc1 = PCSX.addBreakpoint(0x8001EE4C, 'Exec', 4, 'dcr vc1', on)
  B.vc2 = PCSX.addBreakpoint(0x8001EE5C, 'Exec', 4, 'dcr vc2', off)
  B.vc3 = PCSX.addBreakpoint(0x8001F480, 'Exec', 4, 'dcr vc3', on)
  B.vc4 = PCSX.addBreakpoint(0x8001F490, 'Exec', 4, 'dcr vc4', off)
  local function watch(key, lo, n, sz, tag)
    B[key] = PCSX.addBreakpoint(lo, 'Write', n * sz, 'dcr ' .. key, function(addr)
      addr = u32(addr or 0)
      local i = math.floor((addr - lo) / sz)
      local off = (addr - lo) - i * sz
      if off < 0x30 or off > 0x33 then return end
      local word = lo + i * sz + 0x30
      local new, old = newVal(addr, word)
      if not new then return end
      if band(new, 2) ~= band(old, 2) then
        local ctx = inCam and 'CAMARA' or string.format('OTRO pc %08X ra %08X', pcv(), gpr('ra'))
        ev[ctx] = ev[ctx] or {}
        local t = ev[ctx]
        t[#t + 1] = string.format('%s%d%s', tag, i, band(new, 2) ~= 0 and '+' or '-')
      end
    end)
  end
  local g = G()
  watch('vM', g + 0x7CDC, 36, 0x88, 'M')
  watch('vO', g + 0x27C, 11, 0x260, 'O')
  onVsync('vis', function()
    v = v + 1
    for ctx, t in pairs(ev) do print(string.format('[v%6d] %s: %s', v, ctx, table.concat(t, ' '))) end
    ev = {}
  end)
  print('[dcr] visWho prendido')
end

----------------------------------------------------------------------
-- Laseres de una sola cara (descarte de caras traseras). Leido del
-- desensamblado: el modelo de una malla (+0x3C) es
--   +0 lista de triangulos, +8 cantidad (u16)  -> 0x8006DF78 (0x28 c/u)
--   +4 lista de cuadrilateros, +0xA cantidad    -> 0x8006E29C (0x34 c/u)
-- y cada rutina hace NCLIP (GTE) y SALTEA el poligono si da negativo
-- (0x8006E008 triangulos, 0x8006E364 cuadrilateros). La GPU de la PS1 no
-- descarta nada: si no se saltea, se dibuja de los dos lados.
-- Palabra de comando: triangulo +0x1C, cuadrilatero +0x24 (el juego le hace
-- OR 0x3C000000); el bit 0x02000000 = semitransparente.
--   dcr.model(i)   modelo de la malla i: cantidades y, por poligono, el byte
--                  de comando (resumido: cuantos de cada uno)
----------------------------------------------------------------------
function dcr.model(i)
  local m = rd32(rec(i) + 0x3C)
  if m < 0x80010000 or m >= 0x80200000 then print('[dcr] esa malla no tiene modelo') return end
  local tp, qp = rd32(m), rd32(m + 4)
  local tn, qn = band(rd32(m + 8), 0xFFFF), rshift(rd32(m + 8), 16)
  print(string.format('[dcr] malla %d modelo %08X: %d triangulos en %08X, %d cuadrilateros en %08X', i, m, tn, tp, qn, qp))
  local function hist(p, n, sz, off, orv)
    local h, st = {}, 0
    for k = 0, math.min(n, 400) - 1 do
      local w = bor(rd32(p + k * sz + off), orv)
      local c = rshift(w, 24)
      h[c] = (h[c] or 0) + 1
      if band(c, 2) ~= 0 then st = st + 1 end
    end
    local s = {}
    for c, n2 in pairs(h) do s[#s + 1] = string.format('%02X x%d', c, n2) end
    return table.concat(s, '  '), st
  end
  if tn > 0 then local s, st = hist(tp, tn, 0x28, 0x1C, 0); print(string.format('   triangulos: comandos %s  (semitransparentes %d)', s, st)) end
  if qn > 0 then local s, st = hist(qp, qn, 0x34, 0x24, 0x3C000000); print(string.format('   cuadrilateros: comandos %s  (semitransparentes %d)', s, st)) end
end

print('[dcr] v2 listo: dcr.show()  dcr.watch()  dcr.flagWho()  dcr.all(1|3)  dcr.cut()  dcr.pauseWho()  dcr.gate()  dcr.freezeWho()  dcr.fastcut(1|2)  dcr.clear()  dcr.parts()  dcr.partsWatch()  dcr.dinoA/B()  dcr.visWho()  dcr.model(i)')
