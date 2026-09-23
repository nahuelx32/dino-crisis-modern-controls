"""LZSS del cargador v6.6. Formato:
  byte de banderas, 8 elementos, bit 0 primero: 1 = literal (1 byte),
  0 = copia (2 bytes b0 b1): distancia = b0 | (b1 & 0xF0) << 4  (1..4095),
                              largo = (b1 & 0x0F) + 3            (3..18).
  El descompresor para cuando llega al final del destino (lo conoce el cargador)."""
def compress(d):
    n=len(d); out=bytearray(); i=0
    # busqueda optima simple (programacion dinamica sobre el costo en bits)
    INF=1<<60; cost=[INF]*(n+1); cost[n]=0; choice=[None]*(n+1)
    matches=[None]*n
    for p in range(n):
        best=[]
        for dist in range(1,min(4095,p)+1):
            j=p-dist; l=0
            while l<18 and p+l<n and d[j+l]==d[p+l]: l+=1
            if l>=3: best.append((dist,l))
        matches[p]=best
    for p in range(n-1,-1,-1):
        c=cost[p+1]+9; ch=None
        for dist,l in matches[p]:
            for L in range(3,l+1):
                if cost[p+L]+17<c: c=cost[p+L]+17; ch=(dist,L)
        cost[p]=c; choice[p]=ch
    p=0; items=[]
    while p<n:
        ch=choice[p]
        if ch: items.append(ch); p+=ch[1]
        else: items.append(d[p]); p+=1
    for k in range(0,len(items),8):
        grp=items[k:k+8]; flags=0; body=bytearray()
        for b,it in enumerate(grp):
            if isinstance(it,int): flags|=1<<b; body.append(it)
            else:
                dist,L=it; body+=bytes([dist&0xFF,((dist>>4)&0xF0)|(L-3)])
        out.append(flags); out+=body
    return bytes(out)
def decompress(c,n):
    o=bytearray(); i=0
    while len(o)<n:
        f=c[i]; i+=1
        for b in range(8):
            if len(o)>=n: break
            if f>>b&1: o.append(c[i]); i+=1
            else:
                b0,b1=c[i],c[i+1]; i+=2
                dist=b0|(b1&0xF0)<<4; L=(b1&15)+3
                for _ in range(L): o.append(o[-dist])
    return bytes(o)
if __name__=='__main__':
    import sys
    d=open(sys.argv[1],'rb').read(); c=compress(d)
    assert decompress(c,len(d))==d
    open(sys.argv[2],'wb').write(c); print(len(d),'->',len(c))
