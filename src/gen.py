import struct, subprocess, re
blob=open('dcmod.bin','rb').read()
blob+=b'\0'*((-len(blob))%4)
syms={}
for l in subprocess.check_output(['mipsel-linux-gnu-nm','dcmod.elf']).decode().split('\n'):
    p=l.split()
    if len(p)==3: syms[p[2]]=int(p[0],16)
BASE=0x800D8000
jal=lambda t: 0x0C000000|((t&0x3FFFFFF)>>2)
jmp=lambda t: 0x08000000|((t&0x3FFFFFF)>>2)
HOOKS=[ # (addr, originales, nuevas)
 (0x80045378,[0x26040028,0x9602002A,0x02002821,0x30420FFF],[jal(syms['stubPlayer']),0,0,0]),
 (0x8001F3D8,[0x96020028,0x9603002A],[jal(syms['stubCamera']),0]),
 (0x8005B29C,[0x96020020,0x97A30010],[jal(syms['stubStrafe']),0]),
 (0x8006B81C,[0x3C068007,0x24C6E17C],[jmp(syms['stubSort']),0]),
 (0x80015268,[0x0C0056EF],[jal(syms['stubFrame'])]),
 (0x8004DA48,[0x27BDFFE0,0x3C02800C],[jmp(syms['stubDA48']),0]),
 (0x8004DF20,[0x0801383F],[jmp(syms['stubMeshSet'])]),
 (0x8006B074,[0x30420002,0x1040002B],[jmp(syms['stubObjP']),0]),
 (0x8006C194,[0x30420002,0x10400006],[jmp(syms['stubObjL']),0]),
 (0x8006E364,[0x04400060],[jmp(syms['stubNclipQ'])]),
]
# v6.11: tope duro del buffer de paquetes (8 lazos: head, bltz original, stub)
PKCAP=[(0x8006D46C,0x04A000C8,'pkD46C'),(0x8006D7C8,0x04A00090,'pkD7C8'),(0x8006DAE4,0x04A0006D,'pkDAE4'),
       (0x8006DD14,0x04A0008A,'pkDD14'),(0x8006DFB8,0x04A00064,'pkDFB8'),(0x8006E2EC,0x04A0007F,'pkE2EC'),
       (0x8006E588,0x04A0005C,'pkE588'),(0x8006E79C,0x04A00072,'pkE79C')]
HOOKS+=[(a,[0x24A5FFFF,b],[jmp(syms[n]),0]) for a,b,n in PKCAP]
HOOKS+=[
 # v6.10: enganches QUITADOS (stubVis/stubVisM). Se reponen los originales por
 # si se instala en RAM sobre un disco v6.10 anterior (si no, quedarian saltos
 # a un blob con otra disposicion).
 (0x8006B5C4,[0x30420003,0x144300BE],[0x30420003,0x144300BE]),
 (0x8006B174,[0x30420002,0x1040001E],[0x30420002,0x1040001E]),
]
words=struct.unpack('<%dI'%(len(blob)//4),blob)
L=[]
L.append('-- dc6.lua: GENERADO por gen.py. Instala el parche MIPS v6.6 (con HUD) en RAM para probarlo')
L.append('-- sin tocar el disco.  dc6.install()  dc6.remove()  dc6.verify()')
L.append("local ffi=require('ffi') local m=ffi.cast('uint32_t*',PCSX.getMemPtr())")
L.append('local function rd(a) return m[bit.rshift(bit.band(a,0x1FFFFF),2)] end')
L.append('local function wr(a,v) m[bit.rshift(bit.band(a,0x1FFFFF),2)]=v end')
L.append("local m8=ffi.cast('uint8_t*',PCSX.getMemPtr())")
L.append('local function rd8(a) return m8[bit.band(a,0x1FFFFF)] end')
L.append('local function wr8(a,v) m8[bit.band(a,0x1FFFFF)]=bit.band(v,0xFF) end')
L.append('dc6={BASE=0x%08X, SORTON=0x%08X}'%(BASE,syms['sortOn']))
L.append('local BLOB={'+','.join('0x%08X'%w for w in words)+'}')
L.append('local HOOKS={'+','.join('{0x%08X,{%s},{%s}}'%(a,','.join('0x%08X'%x for x in o),','.join('0x%08X'%x for x in n)) for a,o,n in HOOKS)+'}')
L.append('''local function flush() pcall(function() local s=PCSX.createSaveState() PCSX.loadSaveState(s) end) end
-- dc6.hookOff(0x8004DA48): repone el original de UN enganche (para aislar un
-- problema: instalar, sacar uno, probar). dc6.hookOn(dir) lo vuelve a poner.
function dc6.hookOff(a) for _,h in ipairs(HOOKS) do if h[1]==a then for i,w in ipairs(h[2]) do wr(a+(i-1)*4,w) end flush() print(string.format('[dc6] enganche %08X quitado',a)) return end end print('[dc6] no existe ese enganche') end
function dc6.hookOn(a) for _,h in ipairs(HOOKS) do if h[1]==a then for i,w in ipairs(h[3]) do wr(a+(i-1)*4,w) end flush() print(string.format('[dc6] enganche %08X puesto',a)) return end end print('[dc6] no existe ese enganche') end
-- dc6.cap(true/false): pone/quita el tope duro del buffer de paquetes (8 enganches)
local CAPS={0x8006D46C,0x8006D7C8,0x8006DAE4,0x8006DD14,0x8006DFB8,0x8006E2EC,0x8006E588,0x8006E79C}
function dc6.cap(on) for _,a in ipairs(CAPS) do for _,h in ipairs(HOOKS) do if h[1]==a then for i,w in ipairs(on and h[3] or h[2]) do wr(a+(i-1)*4,w) end end end end flush() print('[dc6] tope del buffer de paquetes: '..(on and 'PUESTO' or 'QUITADO')) end
-- dc6.sort(n): orden de dibujo del escenario con la camara al hombro, en vivo
-- (0 = Z minima, 1 = Z maxima, 2 = prioridad fija del juego, 3 = pivote de la malla)
local SORTT={[0]=0x8006B7D8,[1]=0x8006B7F8,[2]=0x8006B820,[3]=0x8006B840}
function dc6.sort(n) if n and SORTT[n] then wr(@SORTTGT@,SORTT[n]) end local c=rd(@SORTTGT@) for k,v in pairs(SORTT) do if v==c then print('[dc6] orden de dibujo al hombro: modo '..k) end end end
function dc6.install()
  if dct and dct.off then dct.off() end
  for _,h in ipairs(HOOKS) do
    for i,w in ipairs(h[2]) do
      local g=rd(h[1]+(i-1)*4)
      -- vale el original, el nuevo, o un enganche de OTRA version del parche
      -- (jal/j al bloque 0x800D8000..0x800E0000, o el nop que lo acompana)
      local op=bit.band(g,0xFC000000)
      local tgt=bit.band(g,0x03FFFFFF)*4
      local mine=(op==0x0C000000 or op==0x08000000) and tgt>=0x0D8000 and tgt<0x0E0000
      if g~=w and g~=h[3][i] and g~=0 and not mine then
        print(string.format('[dc6] %08X no es lo esperado (%08X): nada instalado',h[1]+(i-1)*4,g)) return
      end
    end
  end
  for i,w in ipairs(BLOB) do wr(dc6.BASE+(i-1)*4,w) end
  for _,h in ipairs(HOOKS) do for i,w in ipairs(h[3]) do wr(h[1]+(i-1)*4,w) end end
  flush()
  local n=0 for _,h in ipairs(HOOKS) do if h[2][1]~=h[3][1] then n=n+1 end end
  print(string.format('[dc6] instalado: %d bytes en 0x%08X, %d enganches',#BLOB*4,dc6.BASE,n))
end
function dc6.remove()
  for _,h in ipairs(HOOKS) do for i,w in ipairs(h[2]) do wr(h[1]+(i-1)*4,w) end end
  flush() print('[dc6] enganches restaurados')
end
function dc6.verify()
  local bad=0
  for i,w in ipairs(BLOB) do if i*4<=@CODEEND@-@BASE@ and rd(dc6.BASE+(i-1)*4)~=w then bad=bad+1 end end
  print(bad==0 and '[dc6] codigo intacto' or ('[dc6] '..bad..' palabras de codigo pisadas'))
end
function dc6.cut(n)  wr8(@SHOTCUT@, n) print('[dc6] cancelar el disparo desde el frame '..n) end
function dc6.pump(n) wr8(@PUMPCUT@, n) print('[dc6] cancelar el bombeo desde el frame '..n) end
function dc6.cuts() print(string.format('[dc6] disparo=%d bombeo=%d', rd8(@SHOTCUT@), rd8(@PUMPCUT@))) end
local function rd16(a) return m8[bit.band(a,0x1FFFFF)] + m8[bit.band(a+1,0x1FFFFF)]*256 end
local function wr16(a,v) wr8(a,v) wr8(a+1,bit.rshift(v,8)) end
-- HUD: posiciones en vivo (pixeles de pantalla; la fuente avanza 8 px por letra).
--   dc6.pos()                       lista
--   dc6.pos('arma', x, y)           texto alineado a la izquierda: x = borde izquierdo
--   dc6.pos('balas', 300, 16, 'der')  alineado a la DERECHA: x = borde derecho
--   dc6.pos('vida', x, y)           la palabra VIDA ('izq' vuelve a alinear a la izquierda)
--   dc6.pos('barra', x, y)          esquina sup. izq. del relleno (50x6, marco de 1 px)
local POSN={arma=0,balas=1,vida=2,barra=3}
local function rds16(a) local v=rd16(a) if v>=0x8000 then v=v-0x10000 end return v end
function dc6.pos(k,x,y,al)
  if k then
    local i=POSN[k] if not i then print('[dc6] elementos: arma balas vida barra') return end
    if x then wr16(@HUDPOS@+i*4, bit.band(x,0xFFFF)) end
    if y then wr16(@HUDPOS@+i*4+2, bit.band(y,0xFFFF)) end
    if i<3 then
      local r=rd8(@HUDRIGHT@)
      if al=='der' then r=bit.bor(r,bit.lshift(1,i)) elseif al=='izq' then r=bit.band(r,bit.bnot(bit.lshift(1,i))) end
      wr8(@HUDRIGHT@, r)
    end
  end
  local out={}
  for _,n in ipairs({'arma','balas','vida','barra'}) do
    local i=POSN[n]
    local der=i<3 and bit.band(rd8(@HUDRIGHT@),bit.lshift(1,i))~=0
    out[#out+1]=string.format('%s=%d,%d%s',n,rds16(@HUDPOS@+i*4),rds16(@HUDPOS@+i*4+2),der and ' der' or '')
  end
  print('[dc6] HUD: '..table.concat(out,'  ')..(rd8(@HUDOFF@)==0 and '' or '  (oculto)'))
end
function dc6.hud(on) if on ~= nil then wr8(@HUDOFF@, on and 0 or 1) end dc6.pos() end
-- CAMARA AL HOMBRO en vivo (unidades del juego; 4096 = una vuelta en la inclinacion).
--   dc6.cam()                    lista
--   dc6.cam('alto', 1300)        punto mirado sobre los pies (mas = mira mas arriba)
--   dc6.cam('dist', 2200)        distancia (menos = mas cerca)
--   dc6.cam('lado', -350)        corrimiento lateral (negativo = Regina a la izquierda)
--   dc6.cam('incl', 120)         inclinacion al recentrar con L3 / R3
--   dc6.cam('a_alto', v) dc6.cam('a_dist', v) dc6.cam('a_lado', v)   lo mismo APUNTANDO (L2)
-- Alto, distancia y lado se ven al instante; la inclinacion, al apretar L3.
local CAMN={alto=0,dist=1,lado=2,incl=3,a_alto=4,a_dist=5,a_lado=6}
local CAMO={'alto','dist','lado','incl','a_alto','a_dist','a_lado'}
function dc6.cam(k,v)
  if k then
    local i=CAMN[k] if not i then print('[dc6] parametros: '..table.concat(CAMO,' ')) return end
    if v then wr16(@CAMP@+i*2, bit.band(v,0xFFFF)) end
  end
  local out={}
  for _,n in ipairs(CAMO) do out[#out+1]=string.format('%s=%d',n,rds16(@CAMP@+CAMN[n]*2)) end
  print('[dc6] camara: '..table.concat(out,'  '))
end
-- CORRER: Cuadrado alterna el correr automatico. dc6.run() dice el estado.
function dc6.run(on) if on ~= nil then wr8(@RUNAUTO@, on and 1 or 0) end
  print('[dc6] correr automatico: '..(rd8(@RUNAUTO@)~=0 and 'SI' or 'NO')) end
-- DIAGNOSTICO del HUD: registra por Vsync cuando el HUD NO se dibujo y por que.
--   dc6.hudWhy()  -> jugar / cruzar el cambio de camara   dc6.hudWhy() otra vez = cortar
local WHY={[0]='dibujo',[1]='OT invalida',[2]='misma OT que el frame anterior',[3]='cinematica (bandera de bloqueo)',[4]='oculto con Triangulo'}
local whyL=nil
function dc6.hudWhy()
  if whyL then whyL:remove() whyL=nil print('[dc6] hudWhy cortado') return end
  local lastCnt, still, v, lastMsg = rd16(@HUDCNT@), 0, 0, ''
  local lastCam, camStill = rd16(@CAMCNT@), 0
  whyL=PCSX.Events.createEventListener('GPU::Vsync', function()
    v=v+1
    local c=rd16(@HUDCNT@)
    local msg
    if c==lastCnt then
      still=still+1
      msg = still>=3 and 'el jugador NO se actualiza (no corre el enganche)' or nil
    else
      still=0; lastCnt=c
      local w=rd8(@HUDWHY@)
      msg = w~=0 and ('no dibujo: '..(WHY[w] or w)) or 'dibujo'
    end
    local cc=rd16(@CAMCNT@)
    if cc==lastCam then camStill=camStill+1 else camStill=0; lastCam=cc end
    if msg then msg=msg..(camStill>=3 and ' | camara: NO corre' or ' | camara: corre') end
    if msg and msg~=lastMsg then
      print(string.format('[hud] v%-5d %-72s estado %02X/%02X  3C=%02X 3D=%02X  OT=%08X',v,msg,
        rd8(0x800BAF32),rd8(0x800BAF3E),rd8(0x800B1E50),rd8(0x800B1E51),rd(0x800AE280)))
      lastMsg=msg
    end
  end)
  print('[dc6] hudWhy: solo imprime cuando cambia. Cruza un cambio de camara y despues dc6.hudWhy() para cortar.')
end
print('[dc6] listo: dc6.install()  dc6.remove()  dc6.verify()  dc6.cut(n)  dc6.pump(n)  dc6.cuts()  dc6.pos(k,x,y[,\"der\"])  dc6.hud(true/false)  dc6.cam(k,v)  dc6.run()  dc6.hudWhy()')'''.replace('@CODEEND@','0x%X'%syms['_etext']).replace('@HUDPOS@','0x%X'%syms['hudPos']).replace('@HUDRIGHT@','0x%X'%syms['hudRight']).replace('@HUDOFF@','0x%X'%syms['hudOff']).replace('@CAMP@','0x%X'%syms['camP']).replace('@RUNAUTO@','0x%X'%syms['runAuto']).replace('@HUDCNT@','0x%X'%syms['hudCnt']).replace('@HUDWHY@','0x%X'%syms['hudWhy']).replace('@CAMCNT@','0x%X'%syms['camCnt']).replace('@BASE@','0x%X'%BASE).replace('@SORTTGT@','0x%X'%syms['sortTgt'])
  .replace('@SHOTCUT@','0x%X'%syms['shotCut']).replace('@PUMPCUT@','0x%X'%syms['pumpCut']))
open('dc6.lua','w').write('\n'.join(L)+'\n')
import json; json.dump({'syms':syms,'hooks':HOOKS,'size':len(blob)},open('layout.json','w'),indent=1)
print('blob',len(blob),'datos desde',hex(min(v for k,v in syms.items() if k in('cutHeld','callerSp','dirTab'))))
