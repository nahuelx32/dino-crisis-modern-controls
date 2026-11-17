#!/usr/bin/env python3
"""menutest.py -- prueba de integracion: el codigo REAL del menu OPCIONES del
juego (ejecutable sacado de la imagen limpia) + blob + enganches, ejecutado con
Unicorn.

    python3 menutest.py "ruta/Dino Crisis (Spain) (Track 1).bin"
 Se cortan sonido, dibujo y
color; se captura cada texto dibujado (decodificando los codigos de la fuente)."""
import struct, json, sys
from unicorn import *
from unicorn.mips_const import *
FIRST, NSEC, RAW = 164216, 309, 2352
if len(sys.argv) < 2: sys.exit('uso: python3 menutest.py "ruta/Dino Crisis (Spain) (Track 1).bin"   (despues de build.sh y gen.py)')
img=open(sys.argv[1],'rb'); exe=b''
for k in range(NSEC):
    img.seek((FIRST+k)*RAW+24); exe+=img.read(2048)
import hashlib
assert hashlib.sha256(exe).hexdigest()=='e9fc4f360c3c178eb76f14a8d196ef6df8050c57a69fb17bd2a0657c44c090f0', 'ejecutable inesperado'
blob=open('dcmod.bin','rb').read()
L=json.load(open('layout.json'))
S=L['syms']
mu=Uc(UC_ARCH_MIPS,UC_MODE_MIPS32+UC_MODE_LITTLE_ENDIAN)
mu.mem_map(0,0x200000); mu.mem_map(0x1F800000,0x1000)
mu.mem_write(0x10000,exe[0x800:])
mu.mem_write(0xD8000,blob)
for a,orig,new in L['hooks']:
    p=a-0x80000000
    assert bytes(mu.mem_read(p,4*len(orig)))==struct.pack('<%dI'%len(orig),*orig), hex(a)
    mu.mem_write(p,struct.pack('<%dI'%len(new),*new))
G=0x800B03D8
mu.mem_write(0x1F800000,struct.pack('<I',G))
OBJ=0x800BBD30; BTN=0x800AE270; OPT=0x800BA6AD
STOP=0x80001000
def w8(a,v): mu.mem_write(a-0x80000000,bytes([v&255]))
def r8(a): return mu.mem_read(a-0x80000000,1)[0]
def w16(a,v): mu.mem_write(a-0x80000000,struct.pack('<H',v))
def font(a):
    out=''
    while True:
        c=struct.unpack('<H',mu.mem_read(a-0x80000000,2))[0]; a+=2
        if c==0xA000: break
        g=c>>1
        if c==0: out+=' '
        elif c==0x4000: out+='\n'
        elif c==0x82: out+='?'
        elif c==0x88: out+=':'
        elif c==0x9A: out+='.'
        elif c==0x96: out+='/'
        elif 1<=g<=26: out+=chr(g+0x40)
        elif 27<=g<=52: out+=chr(g+0x46)
        elif 53<=g<=62: out+=chr(g-5)
        else: out+='<%X>'%c
    return out
log=[]
STUBS={0x80054C94:'snd',0x8005F884:'draw',0x80069F84:'pulse',0x80043A40:'h_config',0x800442A0:'h_sonido',0x80044A8C:'h_monitor',0x80044DE8:'h_reiniciar',0x80043930:'h_salir'}
def hk(uc,addr,size,ud):
    if addr==STOP: uc.emu_stop(); return
    n=STUBS.get(addr)
    if not n: return
    a0,a1,a2,a3=[uc.reg_read(r) for r in (UC_MIPS_REG_A0,UC_MIPS_REG_A1,UC_MIPS_REG_A2,UC_MIPS_REG_A3)]
    if n=='snd': log.append(('snd',a1))
    elif n=='draw': log.append(('txt',a0,a1,'%06X'%a2,font(a3)))
    elif n=='pulse': uc.reg_write(UC_MIPS_REG_V0,0xFFFFFF)
    else: log.append((n,))
    uc.reg_write(UC_MIPS_REG_PC,uc.reg_read(UC_MIPS_REG_RA))
mu.hook_add(UC_HOOK_CODE,hk)
def call(fn,a0,btn=0):
    global log; log=[]
    w16(BTN,btn)
    mu.reg_write(UC_MIPS_REG_SP,0x801FFF00); mu.reg_write(UC_MIPS_REG_RA,STOP); mu.reg_write(UC_MIPS_REG_A0,a0)
    for r in (UC_MIPS_REG_S0,UC_MIPS_REG_S1,UC_MIPS_REG_S2,UC_MIPS_REG_S3,UC_MIPS_REG_S4): mu.reg_write(r,0x5A5A0000+r)
    mu.emu_start(fn,STOP,count=200000)
    assert mu.reg_read(UC_MIPS_REG_PC)==STOP, hex(mu.reg_read(UC_MIPS_REG_PC))
    assert mu.reg_read(UC_MIPS_REG_SP)==0x801FFF00
    for r in (UC_MIPS_REG_S0,UC_MIPS_REG_S1,UC_MIPS_REG_S2,UC_MIPS_REG_S3,UC_MIPS_REG_S4): assert mu.reg_read(r)==0x5A5A0000+r, 'registro s pisado'
    return log
MAIN=0x800437F0
UP,RIGHT,DOWN,LEFT,OK,CANCEL=0x1000,0x2000,0x4000,0x8000,0x0080,0x0040
def show(t,l):
    print('--',t,' obj=%s opt=%02X'%(bytes(mu.mem_read(OBJ-0x80000000,4)).hex(),r8(OPT)))
    for e in l: print('    ',e)
mu.mem_write(OBJ-0x80000000,bytes(8)); w8(OPT,0)
show('menu principal, sin botones',call(MAIN,OBJ))
for i in range(6): l=call(MAIN,OBJ,DOWN)
show('abajo x6 (tiene que frenar en 5)',l); assert r8(OBJ)==5
show('aceptar en SALIR -> estado 1',call(MAIN,OBJ,OK))
show('estado 1 con cursor 5 -> manejador',call(MAIN,OBJ)); assert log==[('h_salir',)]
names=['h_config',None,'h_sonido','h_monitor','h_reiniciar','h_salir']
for i,n in enumerate(names):
    w8(OBJ,i); w8(OBJ+1,1); l=call(MAIN,OBJ)
    if n: assert l==[(n,)],(i,l)
print('despacho de los 5 submenus originales: OK')
w8(OBJ,1); w8(OBJ+1,0); w8(OBJ+2,0)
show('cursor en CONTROL Y CAMARA, aceptar',call(MAIN,OBJ,OK)); assert r8(OBJ+1)==1
show('submenu propio, primer cuadro',call(MAIN,OBJ))
show('derecha (control -> tanque)',call(MAIN,OBJ,RIGHT)); assert r8(OPT)==0x01
call(MAIN,OBJ,DOWN); show('abajo, derecha (camara -> hombro)',call(MAIN,OBJ,RIGHT)); assert r8(OPT)==0x03
show('derecha (-> espalda)',call(MAIN,OBJ,RIGHT)); assert r8(OPT)==0x05
call(MAIN,OBJ,RIGHT); assert r8(OPT)==0x01, hex(r8(OPT))
call(MAIN,OBJ,LEFT); assert r8(OPT)==0x05
call(MAIN,OBJ,DOWN); call(MAIN,OBJ,OK); assert r8(OPT)==0x0D
call(MAIN,OBJ,DOWN); call(MAIN,OBJ,LEFT); assert r8(OPT)==0x1D
show('todo cambiado',call(MAIN,OBJ))
call(MAIN,OBJ,DOWN); call(MAIN,OBJ,DOWN); assert r8(OBJ+2)==4
show('aceptar en SALIR',call(MAIN,OBJ,OK)); assert r8(OBJ+1)==0 and r8(OBJ+2)==0
show('de vuelta en el menu principal',call(MAIN,OBJ))
w8(OBJ+1,1); call(MAIN,OBJ,UP); show('cancelar dentro del submenu',call(MAIN,OBJ,CANCEL)); assert r8(OBJ+1)==0
print('TODO OK')
