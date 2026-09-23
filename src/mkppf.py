# PPF 3.0: cabecera 60 B (+1024 de blockcheck), registros: offset u64 LE, largo u8, datos
import struct,sys
def diffs(a,b):
    i=0;n=len(a);out=[]
    while i<n:
        if a[i]!=b[i]:
            j=i
            last=i
            while j<n and j-i<255:
                if a[j]!=b[j]: last=j
                elif j-last>8: break      # un hueco de mas de 8 iguales corta el registro
                j+=1
            out.append((i,b[i:last+1])); i=last+1
        else: i+=1
    return out
def make(orig,new,desc,block=True):
    a=open(orig,'rb').read(); b=open(new,'rb').read(); assert len(a)==len(b)
    h=b'PPF30'+bytes([2])+desc.encode('latin1').ljust(50,b' ')[:50]+bytes([0,1 if block else 0,0,0])
    if block: h+=a[0x9320:0x9320+1024]
    body=b''.join(struct.pack('<QB',o,len(d))+d for o,d in diffs(a,b))
    return h+body
def apply(img,ppf):
    img=bytearray(img); p=ppf; assert p[:5]==b'PPF30' and p[5]==2
    block=p[57]; k=60
    if block: assert img[0x9320:0x9320+1024]==p[60:1084], 'blockcheck'; k=1084
    while k<len(p):
        o,l=struct.unpack('<QB',p[k:k+9]); k+=9; img[o:o+l]=p[k:k+l]; k+=l
    return bytes(img)
if __name__=='__main__':
    o,n,out,desc=sys.argv[1:5]
    p=make(o,n,desc); open(out,'wb').write(p)
    r=apply(open(o,'rb').read(),p)
    print('ppf',len(p),'bytes; aplicado == parcheado:',r==open(n,'rb').read())
