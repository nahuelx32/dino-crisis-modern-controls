/* loader3.S -- cargador v6.13 (pc0 del ejecutable).
 *
 * El blob viaja COMPRIMIDO (LZSS, ver lzss.py) repartido en tramos del
 * ejecutable que en el original son ceros. Hasta v6.12 eran tres tramos
 * fijos; ahora es una TABLA, asi se puede usar cualquier corrida de ceros
 * (mkdisc.py elige las que hagan falta y arma la tabla).
 *
 * Tabla (justo despues de este codigo, TAB..TABEND): por tramo, dos medias
 * palabras: (direccion - SEGBASE) / 4  y  largo / 4. Los tramos estan
 * alineados a 4 y se leen en el orden de la tabla.
 *
 * Descomprime en DST..DSTEND, vuelve a dejar TODOS los tramos en cero (como
 * estaban en el original: da igual que fueran relleno o variables) y salta al
 * arranque del juego. Nunca vuelve: $ra se usa libre. Solo toca temporales
 * ($at, $v0, $v1, $t0-$t9); el arranque no lee ninguno antes de escribirlo.
 * Constantes que pone mkdisc.py: TAB TABEND SEGBASE DST DSTEND GAMEENTRY. */
    .set noreorder
    .set noat
    .text
    .globl loader
loader:
    la      $t0, TAB            /* tramo siguiente en la tabla */
    la      $t1, DST            /* puntero de escritura        */
    la      $t2, DSTEND
    move    $t8, $zero          /* lectura: puntero y fin del tramo actual */
    move    $t9, $zero          /* iguales -> el primer getb abre el primer tramo */
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

/* v0 = siguiente byte comprimido. Si el tramo actual se termino, abre el
 * siguiente de la tabla. */
getb:
    bne     $t8, $t9, 2f
    nop
    lhu     $v0, 0($t0)
    lhu     $v1, 2($t0)
    addiu   $t0, $t0, 4
    sll     $v0, $v0, 2
    lui     $at, SEGBASE >> 16
    addu    $t8, $v0, $at
    sll     $v1, $v1, 2
    addu    $t9, $t8, $v1
2:  lbu     $v0, 0($t8)
    jr      $ra
    addiu   $t8, $t8, 1

fin:
    la      $t0, TAB            /* dejar en cero todos los tramos */
    la      $t2, TABEND
3:  lhu     $v0, 0($t0)
    lhu     $v1, 2($t0)
    addiu   $t0, $t0, 4
    sll     $v0, $v0, 2
    lui     $at, SEGBASE >> 16
    addu    $t8, $v0, $at
    sll     $v1, $v1, 2
    addu    $t9, $t8, $v1
4:  sw      $zero, 0($t8)
    addiu   $t8, $t8, 4
    bne     $t8, $t9, 4b
    nop
    bne     $t0, $t2, 3b
    nop
    j       GAMEENTRY
    nop
