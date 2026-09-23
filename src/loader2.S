/* loader2.S -- cargador v6.6 (pc0). El blob viaja COMPRIMIDO (LZSS, ver
 * lzss.py) en dos tramos de ceros del ejecutable:
 *   tramo 1: la zona del payload v5, desde el final de este cargador hasta R1END
 *   tramo 2: la tira que el juego limpia antes del titulo (0x800A3804..)
 *   tramo 3 (v6.11): la cola en cero del ejecutable (0x800A9C60..0x800AA000)
 * Descomprime en DST..DSTEND, deja los dos tramos en cero (como estaban en el
 * original) y salta al arranque del juego. Nunca vuelve: $ra se usa libre.
 * Constantes: R1SRC R1END R2SRC R2END R3SRC R3END DST DSTEND (las pone el script). */
    .set noreorder
    .set noat
    .text
    .globl loader
loader:
    la      $t0, R1SRC          /* puntero de lectura      */
    la      $t1, DST            /* puntero de escritura    */
    la      $t2, DSTEND
    la      $t8, R1END
    la      $t9, R2SRC
    la      $a0, R2END          /* fin del tramo 2         */
    la      $a1, R3SRC          /* comienzo del tramo 3    */
grupo:
    beq     $t1, $t2, fin
    nop
    bal     getb
    nop
    move    $t3, $v0            /* banderas                */
    li      $t4, 8
elem:
    beq     $t1, $t2, fin
    nop
    beqz    $t4, grupo
    andi    $t5, $t3, 1
    srl     $t3, $t3, 1
    beqz    $t5, copia
    addiu   $t4, $t4, -1
    bal     getb                /* literal                 */
    nop
    sb      $v0, 0($t1)
    b       elem
    addiu   $t1, $t1, 1
copia:
    bal     getb
    nop
    move    $t6, $v0            /* b0                      */
    bal     getb
    nop
    andi    $t7, $v0, 0xF0
    sll     $t7, $t7, 4
    or      $t6, $t6, $t7       /* distancia               */
    andi    $t7, $v0, 0x0F
    addiu   $t7, $t7, 3         /* largo                   */
    subu    $t6, $t1, $t6       /* origen de la copia      */
1:  lbu     $v0, 0($t6)
    addiu   $t6, $t6, 1
    addiu   $t7, $t7, -1
    sb      $v0, 0($t1)
    bnez    $t7, 1b
    addiu   $t1, $t1, 1
    b       elem
    nop

/* v0 = siguiente byte comprimido; al terminar el tramo 1 pasa al 2, y al
 * terminar el 2 pasa al 3 (t8/t9 avanzan a a0/a1; despues t8 = a0 queda
 * detras del puntero y no vuelve a coincidir) */
getb:
    lbu     $v0, 0($t0)
    addiu   $t0, $t0, 1
    bne     $t0, $t8, 2f
    nop
    move    $t0, $t9
    move    $t8, $a0
    move    $t9, $a1
2:  jr      $ra
    nop

fin:
    la      $t0, R1SRC          /* limpiar los tramos (en el original son ceros) */
    la      $t8, R1END          /* getb movio t8: volver a cargarlo */
3:  sw      $zero, 0($t0)
    addiu   $t0, $t0, 4
    bne     $t0, $t8, 3b
    nop
    la      $t0, R2SRC
    la      $t8, R2END
4:  sw      $zero, 0($t0)
    addiu   $t0, $t0, 4
    bne     $t0, $t8, 4b
    nop
    la      $t0, R3SRC
    la      $t8, R3END
5:  sw      $zero, 0($t0)
    addiu   $t0, $t0, 4
    bne     $t0, $t8, 5b
    nop
    j       GAMEENTRY
    nop
