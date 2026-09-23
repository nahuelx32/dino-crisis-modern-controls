/*
 * stubs.S -- puentes entre el codigo del juego y dcmod.c
 *
 * Cada stub: guarda el sp del juego, cambia a una pila propia (la del juego
 * a veces es el scratchpad de 1 KB), guarda TODOS los registros que un
 * llamado de C puede pisar, llama al C, restaura, y ejecuta las instrucciones
 * originales que el enganche reemplazo. $at no esta vivo en ningun sitio de
 * enganche (verificado en el desensamblado).
 */
    .set noreorder
    .set noat
    .text

    .equ OURSTACK, 0x800E0000

    .macro ENTER
    lui     $at, %hi(callerSp)
    sw      $sp, %lo(callerSp)($at)
    lui     $sp, %hi(OURSTACK)
    addiu   $sp, $sp, %lo(OURSTACK)
    addiu   $sp, $sp, -0x60
    sw      $ra, 0x10($sp)
    sw      $v0, 0x14($sp)
    sw      $v1, 0x18($sp)
    sw      $a0, 0x1C($sp)
    sw      $a1, 0x20($sp)
    sw      $a2, 0x24($sp)
    sw      $a3, 0x28($sp)
    sw      $t0, 0x2C($sp)
    sw      $t1, 0x30($sp)
    sw      $t2, 0x34($sp)
    sw      $t3, 0x38($sp)
    sw      $t4, 0x3C($sp)
    sw      $t5, 0x40($sp)
    sw      $t6, 0x44($sp)
    sw      $t7, 0x48($sp)
    sw      $t8, 0x4C($sp)
    sw      $t9, 0x50($sp)
    .endm

    .macro LEAVE
    lw      $ra, 0x10($sp)
    lw      $v0, 0x14($sp)
    lw      $v1, 0x18($sp)
    lw      $a0, 0x1C($sp)
    lw      $a1, 0x20($sp)
    lw      $a2, 0x24($sp)
    lw      $a3, 0x28($sp)
    lw      $t0, 0x2C($sp)
    lw      $t1, 0x30($sp)
    lw      $t2, 0x34($sp)
    lw      $t3, 0x38($sp)
    lw      $t4, 0x3C($sp)
    lw      $t5, 0x40($sp)
    lw      $t6, 0x44($sp)
    lw      $t7, 0x48($sp)
    lw      $t8, 0x4C($sp)
    lw      $t9, 0x50($sp)
    lui     $at, %hi(callerSp)
    lw      $sp, %lo(callerSp)($at)
    .endm

/* ---------------------------------------------------------------------------
 * 0x80045378  (jal stubPlayer + 3 nop)
 * reemplaza: addiu a0,s0,0x28 / lhu v0,0x2A(s0) / move a1,s0 / andi v0,0xFFF
 */
    .globl stubPlayer
stubPlayer:
    ENTER
    jal     hookPlayer
    move    $a0, $s0
    LEAVE
    lhu     $v0, 0x2A($s0)
    addiu   $a0, $s0, 0x28
    move    $a1, $s0
    jr      $ra
    andi    $v0, $v0, 0x0FFF

/* ---------------------------------------------------------------------------
 * 0x8001F3D8  (jal stubCamera + nop)
 * reemplaza: lhu v0,0x28(s0) / lhu v1,0x2A(s0)
 */
    .globl stubCamera
stubCamera:
    ENTER
    jal     hookCamera
    move    $a0, $s0
    LEAVE
    lhu     $v0, 0x28($s0)
    jr      $ra
    lhu     $v1, 0x2A($s0)

/* ---------------------------------------------------------------------------
 * 0x8005B29C  (jal stubStrafe + nop)
 * reemplaza: lhu v0,0x20(s0) / lhu v1,0x10(sp)
 * El desplazamiento esta en la pila DEL JUEGO: le pasamos su sp.
 */
    .globl stubStrafe
stubStrafe:
    ENTER
    move    $a0, $s0
    lui     $at, %hi(callerSp)
    jal     hookStrafe
    lw      $a1, %lo(callerSp)($at)
    LEAVE
    lhu     $v0, 0x20($s0)
    jr      $ra
    lhu     $v1, 0x10($sp)

/* ---------------------------------------------------------------------------
 * 0x8006B81C  (j stubSort + nop)   entrada del modo 2 (prioridad fija)
 * sortOn = 1 -> modo 1 (Z real, 0x8006B7F8); si no, el camino original.
 * $a2 se pisa en los dos caminos, se puede usar de temporal.
 */
    .globl stubSort
stubSort:
    /* v6.10: el modo con la camara al hombro sale de sortTgt (dc6.sort(n)):
     *   0 = Z minima por poligono      -> 0x8006B7D8 (necesita a2 = 0x80070000)
     *   1 = Z maxima (el de siempre)   -> 0x8006B7F8
     *   2 = prioridad fija (original)  -> 0x8006B820 (a2 = 0x80070000)
     *   3 = Z del pivote de la malla   -> 0x8006B840 (necesita t0 = 0x1F800000)
     * a2, v0 y t0 se pisan en todos esos caminos antes de usarse. */
    lui     $a2, %hi(sortOn)
    lw      $a2, %lo(sortOn)($a2)
    nop
    beqz    $a2, 1f
    lui     $v0, %hi(sortTgt)
    lw      $v0, %lo(sortTgt)($v0)
    lui     $a2, 0x8007
    jr      $v0
    lui     $t0, 0x1F80
1:  lui     $a2, 0x8007
    j       0x8006B824
    addiu   $a2, $a2, -0x1E84

    .data
    .align 2
    .globl sortTgt
sortTgt: .word 0x8006B7F8
    .text

/* ---------------------------------------------------------------------------
 * 0x80015268  (jal stubFrame; el nop del delay slot queda como estaba)
 * reemplaza: jal 0x80015BBC (lectura del mando del bucle principal, sin
 * argumentos). Es un sitio de llamada: los temporales del juego ya estan
 * muertos, asi que no hace falta ENTER/LEAVE; hookFrame es una hoja y solo
 * se guarda $ra en la pila del bucle principal. Despues salta a 0x80015BBC
 * con el $ra original (0x80015270): vuelve directo al bucle.
 */
    .globl stubFrame
stubFrame:
    addiu   $sp, $sp, -24
    sw      $ra, 16($sp)
    jal     hookFrame
    nop
    lw      $ra, 16($sp)
    addiu   $sp, $sp, 24
    j       0x80015BBC
    nop

/* ---------------------------------------------------------------------------
 * Personajes (dinosaurios) fuera del encuadre de la camara fija. Medido con
 * dcr.dinoA/B: en los dos dinos, obj+0x30 bit 1 = 0 invisible / 1 visible
 * (bit 0 = el objeto esta activo: su logica corre, se lo oye y se le puede
 * disparar). Tabla de objetos G+0x27C, 11 de 0x260 (el 10 es Regina).
 * Dos lugares piden el bit 1, igual que con las mallas:
 *   0x8006B074  pasada previa (0x8006AFC0): matriz del objeto
 *   0x8006C194  lista de objetos a dibujar (0x8006C168, la ordena y la
 *               dibuja 0x8006C244)
 * Los dos son: andi v0,v0,2 / beqz v0,SALTEAR / nop, y v0 se pisa enseguida
 * en los dos caminos; $at no se usa en esas funciones y nada salta a esas
 * direcciones (verificado). Con la camara al hombro (sortOn) cuenta como
 * visible todo objeto activo (bit 0).
 */
    .macro VISBIT0 name, sigue, saltea
    .globl \name
\name:
    andi    $at, $v0, 1
    andi    $v0, $v0, 2
    bnez    $v0, 1f
    nop
    beqz    $at, 2f
    nop
    lui     $at, %hi(sortOn)
    lw      $at, %lo(sortOn)($at)
    nop
    beqz    $at, 2f
    nop
1:  j       \sigue
    nop
2:  j       \saltea
    nop
    .endm

    VISBIT0 stubObjP, 0x8006B080, 0x8006B128
    VISBIT0 stubObjL, 0x8006C1A0, 0x8006C1B4

/* ---------------------------------------------------------------------------
 * Mallas: la camara al hombro ya NO fuerza el bit 1 al dibujar (v6.10 lo
 * hacia con stubVis/stubVisM y mostraba laseres apagados y la bateria de mas:
 * el juego tambien esconde cosas por estado con ese bit). Medido con
 * dcr.visWho: los cortes de camara prenden/apagan mallas desde el GUION DE LA
 * CAMARA; los laseres, desde 0x80019A04/A24/A38/A94 (otro codigo).
 * Ahora: mientras corre el guion de la camara (0x8004DA48, que ejecuta el
 * contexto 9, el de la camara) y con la camara al hombro, lo que el guion
 * escriba en las banderas de una malla que existe (bit 0) se escribe con el
 * bit 1 prendido. Lo que esconda cualquier otro codigo queda escondido.
 *
 * 0x8004DA48 (j stubDA48 + nop): reemplaza addiu sp,sp,-0x20 / lui v0,0x800C.
 * El cuerpo corre por el trampolin; una sola salida (jr ra en 0x8004DAA4) y
 * nada salta a 0x8004DA4C (verificado).
 */
    .globl stubDA48
stubDA48:
    /* SIN pila: la del juego puede ser el scratchpad (1 KB) y ahi 24 bytes
     * de mas pisan datos (primer intento con pila: cuelgue en cada corte).
     * $ra va a una variable del blob (no es reentrante: el guion de la
     * camara no se llama a si mismo). $at es libre en el llamador (es un jal). */
    lui     $at, %hi(daRa)
    sw      $ra, %lo(daRa)($at)
    lui     $at, %hi(inCam)
    jal     tramDA48
    sw      $at, %lo(inCam)($at)        /* != 0 */
    lui     $at, %hi(inCam)
    sw      $zero, %lo(inCam)($at)
    lui     $at, %hi(daRa)
    lw      $ra, %lo(daRa)($at)
    nop
    jr      $ra
    nop
tramDA48:
    addiu   $sp, $sp, -0x20
    j       0x8004DA50
    lui     $v0, 0x800C

    .data
    .align 2
daRa: .word 0
    .text

/* 0x8004DF20 (j stubMeshSet; el delay slot sw s0,0x30(a0) queda y se ejecuta
 * antes): "poner banderas" del interprete de guiones (el que escribio las
 * mallas en los cortes, dcr.flagWho). Vuelve al epilogo 0x8004E0FC, que
 * restaura s0: se puede usar. */
    .globl stubMeshSet
stubMeshSet:
    lui     $at, %hi(inCam)
    lw      $at, %lo(inCam)($at)
    nop
    beqz    $at, 1f
    lui     $at, %hi(sortOn)
    lw      $at, %lo(sortOn)($at)
    nop
    beqz    $at, 1f
    andi    $at, $s0, 1
    beqz    $at, 1f
    ori     $s0, $s0, 2
    sw      $s0, 0x30($a0)
1:  j       0x8004E0FC
    nop

/* ---------------------------------------------------------------------------
 * 0x8006E364  (j stubNclipQ; el delay slot 0x8006E368 es nop)
 * Cuadrilateros de escenario (0x8006E29C): reemplaza bltz v0,0x8006E4E8 (v0 =
 * NCLIP: negativo = mira para atras = se saltea). La GPU no descarta nada:
 * si no se saltea, se ve de los dos lados.
 * Medido (dcr.model): los laseres son 22 cuadrilateros con comando 3E
 * (semitransparentes); las paredes, 3C (opacos) salvo unos pocos. Regla, con
 * la camara al hombro: lo SEMITRANSPARENTE se dibuja de los dos lados.
 * $t0 tiene todavia la palabra de comando (+0x24 | 0x3C000000, 0x8006E330);
 * bit 0x02000000 = semitransparente. $at no se usa en la funcion (solo
 * lui/sw locales en 0x8006E4FC y 0x8006E700) y nada salta a 0x8006E364/368.
 */
    .globl stubNclipQ
stubNclipQ:
    bgez    $v0, 1f
    lui     $at, %hi(sortOn)
    lw      $at, %lo(sortOn)($at)
    nop
    beqz    $at, 2f
    srl     $at, $t0, 25
    andi    $at, $at, 1
    beqz    $at, 2f
    nop
1:  j       0x8006E36C
    nop
2:  j       0x8006E4E8
    nop

/* ---- v6.11: tope duro del buffer de paquetes GPU --------------------------
 * Medido (dc_pk.lua): con todo visible al hombro, una sala llego a 172 KB por
 * cuadro en buffers de 128 KB (0x801A0000 y 0x801C0000, pegados, sin tope).
 * El buffer 1 desbordado pisa el buffer 0 mientras la GPU lo dibuja -> cuelgue
 * en DuckStation / consola (Redux dibuja al instante y no lo nota).
 * Las 8 funciones que arman tris/quads/efectos tienen el mismo lazo:
 *     head:   addiu a1,a1,-1 ; bltz a1,EXIT ; <dly> ; cuerpo...  ; j head
 * Enganche: head = j stub, head+4 = nop. El stub decrementa, y si el puntero
 * entro en los ultimos PKRES bytes de su buffer de 128 KB sale del lazo (la
 * salida escribe el puntero y los contadores como siempre). Los buffers estan
 * alineados a 128 KB, asi que ((ptr+PKRES) & 0x1FFFF) < PKRES <=> ptr en la
 * franja final. $at no se usa en ningun lazo. Orden de dibujo (0x8006B3B8):
 * personajes/objetos primero, escenario despues -> lo que se corta es escenario
 * o efectos, nunca Regina ni dinosaurios. Nada salta a head+4/head+8. */
#define PKRES 0x2000
.macro PKCAP name, ptr, head, exit, dly:vararg
    .globl \name
\name:
    addiu   $at, \ptr, PKRES
    sll     $at, $at, 15
    srl     $at, $at, 15
    sltiu   $at, $at, PKRES
    bnez    $at, 1f
    addiu   $a1, $a1, -1
    bgez    $a1, 2f
    nop
1:  j       \exit
    \dly
2:  j       \head+8
    nop
.endm
    PKCAP pkD46C, $t9, 0x8006D46C, 0x8006D794, nop
    PKCAP pkD7C8, $t9, 0x8006D7C8, 0x8006DA10, nop
    PKCAP pkDAE4, $t9, 0x8006DAE4, 0x8006DCA0, nop
    PKCAP pkDD14, $t9, 0x8006DD14, 0x8006DF44, nop
    PKCAP pkDFB8, $t9, 0x8006DFB8, 0x8006E150, addiu $t7, $t7, 1
    PKCAP pkE2EC, $t9, 0x8006E2EC, 0x8006E4F0, addiu $t7, $t7, 1
    PKCAP pkE588, $a2, 0x8006E588, 0x8006E700, addiu $s5, $s5, 1
    PKCAP pkE79C, $a2, 0x8006E79C, 0x8006E96C, addiu $s5, $s5, 1
