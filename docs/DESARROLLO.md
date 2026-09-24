# Dino Crisis (PS1) — control moderno. Estado del proyecto y guía de continuación

Documento de traspaso. Si arrancás una sesión nueva, esto es lo que hay que
saber para no volver a pisar los mismos pozos.

**Copia objetivo:** SLES-02211, versión PAL española, `Dino Crisis (Spain)`.
Imagen de 2 pistas: `Track 1` (datos) + `Track 2` (audio) + `.cue` + `.sbi`.
Protección **LibCrypt** — esto condiciona todo el método de parcheo.


> **ESTADO ACTUAL: v6.12, VALIDADA** (septiembre 2026). Publicada en GitHub
> (`nahuelx32/dino-crisis-modern-controls`) con parches xdelta/PPF en Releases.
> Ejecutable armado por `src/mkdisc.py` del repositorio (saca el original de la
> imagen limpia). Resumen: **sección 20** (v6.8), **21** (v6.9: videos), **22**
> (v6.10: la cámara al hombro ve toda la sala), **23** (v6.11: tope del buffer
> de dibujo + cargador de tres tramos) y **24** (v6.12: encuadre de los puzles +
> repositorio). Las secciones 1–14 son historia; donde contradigan a 20–24,
> valen 20–24.

---

## 1. Qué está terminado

Los controles tanque están reemplazados por control relativo a cámara: Regina
camina hacia donde apuntás y gira sola hacia ese rumbo. Funciona parcheado
sobre la imagen del disco, sin ayudas externas, probado en PCSX-Redux y en
DuckStation.

**Versión actual: v6.5**, probada en RAM con `dc6.install()`. El grabador
`v6/grabar_v65.ps1` está al día; si `C:\dc\disco_v65` se generó antes del
último cambio, hay que volver a correrlo. Falta la pasada larga de juego en el
disco. El detalle de cada cosa está en la sección 11; el resumen:

- Movimiento analógico 360° relativo a la cámara, giro de 280 por frame
  (4096 = una vuelta) y "buffer de corte de cámara" para que no se dé vuelta
  sola al cruzar un encuadre.
- Cámara al hombro: **R3** alterna con la original (arranca en la original),
  **L3** recentra detrás de Regina. Orden de dibujo corregido mientras el
  hombro está activo.
- Apuntado de doble stick, bloqueo en cinemáticas, acciones especiales
  (empujar) sin giro, y el apuntado no actúa en mordidas.
- **Disparo cancelable:** la animación se corta desde el frame 2 si movés el
  stick o soltás el apuntado (también el bombeo de la escopeta), con un
  enfriamiento de 20 frames entre disparos para no perder la cadencia
  original.
- **Esquema de botones:** L2 apunta, R2 dispara, R1 camina, y **corre siempre**
  el resto del tiempo. X y Cuadrado siguen haciendo lo suyo. R2 ya no da la
  media vuelta.
- El botón "atrás" (marcha atrás tanque) queda anulado como efecto secundario.

---

## 2. Mapa de memoria (verificado, no deducido)

### Objeto del jugador — base `0x800B1E14`

| Offset | Dirección | Contenido |
|---|---|---|
| +0x00 | 0x800B1E14 | matriz de rotación 3×3 (9 × int16) — **salida**, no escribir |
| +0x14 | 0x800B1E28 | traslación en mundo (3 × int32) — **salida** |
| +0x20 | 0x800B1E34 | posición X (int16) — escribible |
| +0x22 | 0x800B1E36 | posición Y (int16) |
| +0x24 | 0x800B1E38 | posición Z (int16) — escribible |
| +0x2A | 0x800B1E3E | **ángulo** (int16, 4096 = una vuelta) — escribible |
| +0x4C | 0x800B1E60 | puntero al nodo hijo (0x800B2074) |
| +0xA4 | 0x800B1EB8 | escala (4096 = 1.0) |

### Otros

- **Matriz de vista de la cámara:** `0x800B048C`, formato `MATRIX` de PSY-Q
  (`short m[3][3]` en +0x00, 2 bytes de relleno, `long t[3]` en +0x14).
  Punto fijo, 4096 = 1.0. **yaw = atan2(m02, m00) = atan2([+4], [+0])**.
- **Estado del juego:** `0x800BAF32` y `0x800BAF3E`. Valor 10 = gameplay;
  28 = menú o transición. Hay que mirar los dos: en las puertas uno se queda
  en 10 mientras el otro parpadea.
- **Botones, en el SCRATCHPAD:** `0x1F800008` (los lee el código de rotación)
  y `0x1F80000A` (los lee el de movimiento). Son dos palabras distintas y hay
  que escribir **las dos**; escribir solo una deja arriba/abajo en modo vanilla.
  Bits: `0x1000` arriba, `0x2000` derecha, `0x4000` abajo, `0x8000` izquierda,
  `0x0008` R1.
- El juego usa el scratchpad (`0x1F800000`, 1 KB) como pila.

### Código relevante

- `0x8004538C` — `sh $v0, 0x2A($s0)`, el normalizador (`andi $v0, 0x0FFF`).
- `0x80046480` — rutina de control.
- `0x8004652C` — bloque de control tanque (9 instrucciones, ±0x5A por frame).
- `0x8005E598`, `0x8005E610` — tocan la cámara.

### Los diez escritores del ángulo

Encontrados con un breakpoint de escritura en `0x800B1E3E` haciendo **todas**
las acciones (caminar, correr, con pistola y sin, girar parado):

```
0x8004538C  0x8004655C  0x80045F94  0x80046970  0x800462A4  0x80046288
0x8017ACD8  0x8017B060  0x8017B34C  0x8017B368   <- estos cuatro en overlays del disco
```

Por eso **no se parchea cada sitio**. Ver la sección de arquitectura.

---

## 3. Arquitectura del parche

Un solo enganche, y a los diez manejadores se les quita la entrada.

**Enganche en `0x80045378`**, reemplazando 4 instrucciones por `jal payload` +
3 `nop`:

```
80045378: addiu $a0, $s0, 0x0028     <- reemplazada
8004537c: lhu   $v0, 0x002a($s0)     <- reemplazada
80045380: move  $a1, $s0             <- reemplazada
80045384: andi  $v0, 0x0fff          <- reemplazada
80045388: jal   0x80087ba8           (se conserva)
8004538c: sh    $v0, 0x002a($s0)     (se conserva, delay slot)
```

Palabras originales, para verificar antes de parchear:
`26040028 9602002A 02002821 30420FFF`.

**Contrato de salida** — antes de volver, el payload tiene que dejar:

```
$v0 = ángulo & 0x0FFF      $a0 = $s0 + 0x28      $a1 = $s0
```

**Filtro:** el payload solo actúa si `$s0 == 0x800B1E14` (el jugador). Con
cualquier otro objeto salta directo al epílogo.

**Qué hace:** calcula `objetivo = ánguloDelStick − yawDeCámara`, gira el ángulo
del jugador hacia ahí con tope de ±TURN por frame, y después deja las dos
palabras de botones del scratchpad con **solo "adelante"** encendido. Ningún
manejador ve izquierda, derecha ni abajo, así que ninguno toca el ángulo, y los
de movimiento caminan de frente.

El payload es **position independent**: ni un solo salto absoluto propio. Usa
`bal pic; nop; pic:` y `addiu $tX, $ra, (etiqueta - pic)`. Se puede mover a
cualquier dirección sin reensamblar.

### Ubicación final

**`0x800A2F88`**, 928 bytes, `jal 0x0C028BE2`.

Offsets internos del payload (para retocar sin reensamblar):

| Offset | Qué es |
|---|---|
| 0x178 | `sltiu $t7, $t0, CUTREL` — frames para soltar el buffer (3) |
| 0x1E4 | `sltiu $t1, $t0, CUTTHRESH` — umbral de corte de cámara (300) |
| 0x234 | `li $t4, TURN` — velocidad de giro (280) |
| 0x240 | `li $t1, -TURN` — el negativo, en `$t1`, no en `$t4` |
| 0x2E0 | `dirTab` |
| 0x300 | `asinTab` |
| 0x38C | `dat` — área de estado en tiempo de ejecución, **no verificar** |

---

## 4. Ejecutable e imagen

### Cabecera PS-X EXE

```
pc0      0x800121D4
t_addr   0x80010000
t_size   0x0009A000      -> la imagen termina en 0x800AA000
b_addr   0x00000000      \  la BIOS NO limpia ninguna zona al arrancar:
b_size   0x00000000      /  esto es lo que hace viable agrandar el ejecutable
s_addr   0x801FFFF0
```

Archivo: 632832 bytes = 309 sectores exactos, sin holgura.
**offset en el archivo = 0x800 + (dirección − 0x80010000)**.

### Imagen

- `Track 1` en sectores crudos de 2352 bytes, Mode 2 Form 1.
- 164676 sectores. El ejecutable arranca en el sector **164216** y ocupa hasta
  el 164524.
- Quedan 151 sectores después. **Cuidado:** 150 es exactamente el pregap
  estándar de la pista de audio, así que probablemente solo uno esté libre
  de verdad.

### Por qué se parchea in-place y no con mkpsxiso

El `.sbi` de LibCrypt está atado a posiciones exactas de sectores. Rearmar la
imagen los mueve y la protección deja de validar: el juego arranca, pasa menús
y cinemáticas, y se cuelga al empezar el gameplay 3D. Parcheando en el lugar,
el disco queda idéntico salvo por unos bytes y el `.cue` y el `.sbi` originales
siguen sirviendo.

---

## 5. Espacio libre

Corridas de ceros de ≥64 bytes en el ejecutable original (11 en total, 6937
bytes, casi todo en el segmento de datos — **no hay relleno en el código**):

```
0x800A3801  4203   el juego le hace memset ANTES de la pantalla de título. INUTILIZABLE.
0x800A2F6C  1057   usado: SOLO 0x800A2F7C/80/84 (3 palabras). El resto está muerto.
                   -> aquí vive el payload, en 0x800A2F88. Quedan 101 bytes libres.
0x800A9C60   928   0x800A9C70 tiene un puntero a la BIOS. Usada.
0x800A9A0C   129 ; 0x800A4F85 119 ; 0x800A4E43 113 ; 0x8009E48D  91
0x800A9BB3    85 ; 0x800A34D2  82 ; 0x80091A52  66 ; 0x80093BEA  64
```

Sumando las corridas chicas hay ~750 bytes más, sin verificar, servibles para
parches de pocas instrucciones.

### Agrandar el ejecutable

Está implementado en `patch_bin.py` y **nunca se llegó a usar**. Como
`b_addr = b_size = 0`, la BIOS no limpia nada, así que subiendo `t_size` el
cargador trae sectores de más y los deja después de `0x800AA000`. El script:

1. comprueba que los sectores a anexar estén vacíos y aborta si no,
2. sube `t_size` en la cabecera,
3. corrige el tamaño del archivo en el directorio del ISO (busca el registro,
   valida que el LBA coincida con dónde encontró el ejecutable).

No mueve ningún sector, así que LibCrypt aguanta. Uso:

```
python patch_bin.py "Track 1.bin" 800AA400 probe 928
```

Sondeos hechos en esa zona: `0x800AA000` se pisa después del título;
`0x800AA400` sobrevivió, pero **la sonda se escribió tarde** (desde Lua, ya en
juego), así que no está probada contra el arranque. Antes de confiar en ella,
sondearla desde el disco.

---

## 6. Herramientas

| Archivo | Para qué |
|---|---|
| `payload5.s` + `tables5.inc` | fuente del payload (928 bytes) |
| `dc_patch.lua` | instalar/verificar en vivo en PCSX-Redux, y todo el instrumental de diagnóstico |
| `patch_bin.py` | parchear el `Track 1.bin` in-place, con EDC/ECC y crecimiento |
| `patch_exe.py` | parchear un `SLES_022.11` suelto |
| `dc_hack.lua` | el prototipo original en Lua y el escáner de RAM |

### Ensamblar

```
mips-linux-gnu-as -EL -mips1 -O0 -o payload5.o payload5.s
mips-linux-gnu-objcopy -O binary -j .text payload5.o payload5.bin
```

`-j .text` **no es opcional**: sin eso, objcopy mete 8 bytes de secciones ELF
(`.MIPS.abiflags`) al principio del binario.

### Funciones de `dc_test.lua` (banco de pruebas actual)

```
Diagnosticos: padShow padWho camInfo camWho camObj otWho moveWho stateShow
              inputWho probeMap bootProbe/bootMap
              biteWho    quien toca el angulo/posicion en una mordida
              shotWho    que campos del jugador frenan a Regina al disparar
              shotState  estados +3D/+3E y largo de animacion por arma
              aimOut     que pasa al soltar el apuntado con el stick tirado
              btnMap     que bit de las palabras de botones pone cada boton
Prototipos:   analog shoulder sortFix orbit
              shotCut(n) shotFast(n) shotSlide(f) shotCool(n) shotOff()
Apagar todo:  dct.off()
```

### Funciones de `v6/dc6.lua` (instalar el parche MIPS en RAM)

```
dc6.install()   escribe el blob en 0x800D8000 y los 4 enganches (acepta
                enganches de otra version del parche y los sobrescribe)
dc6.remove()    restaura los enganches originales
dc6.verify()    ¿el codigo sigue intacto?
dc6.cut(n) / dc6.pump(n) / dc6.cuts()   umbrales de cancelacion, en vivo
```

Hace falta `dofile('C:/dc/v6/dc6.lua')` al abrir el emulador o cuando cambia el
archivo, y `dc6.install()` después de cada Reset o savestate.

### Funciones de `dc_patch.lua` (payload v5, histórico)

```
dcp.free()                  huecos de ceros en RAM
dcp.install(base)           instalar el payload y el enganche
dcp.verify()                ¿el código sigue intacto?
dcp.check()                 estado del enganche
dcp.remove()                restaurar el original
dcp.flush()                 vaciar la caché de instrucciones
dcp.turn(n) / cut(n) / cutrel(n)   retocar constantes sin reensamblar
dcp.zone(a, n)              ¿cuántas palabras no-cero hay en una zona?
dcp.watch() / dcp.watchStop()      vigilancia continua (OJO: ver error #9)
dcp.probe() / dcp.probeCheck()     sondas de supervivencia
dcp.probeAt(a, n)           revisar una sonda escrita desde el disco
```

---

## 7. Errores cometidos, y qué aprendimos

Esta es la sección importante. Cada uno costó horas.

**1. Escanear la RAM por "valores que cambian mucho".** Devuelve rotaciones de
huesos, coordenadas de pantalla y traslaciones del grafo de escena — datos de
render, no de estado. Tres intentos perdidos. Lo que funcionó fue **breakpoints
de escritura + desensamblado**: poner un breakpoint en el valor y mirar quién
lo escribe.

**2. El load delay slot del R3000.** Un registro cargado con `lw`/`lh`/`lhu`
**no está disponible en la instrucción siguiente** bajo `.set noreorder`. Sin
el `nop`, el payload leía valores viejos: la traza mostraba `stick = 11`
(obsoleto) y `cur = 188` (que era `|m00|`). Hacen falta ~19 `nop`. Si una
variable sale con un valor que "pertenece a otro cálculo", es esto.

**3. `addiu` extiende el signo del inmediato de 16 bits.** `addiu $t0, $zero,
0xFFFF` deja `0xFFFFFFFF`, mientras que `lhu` devuelve `0x0000FFFF`: la
comparación nunca coincide y el buffer de corte no se soltaba jamás. Para
constantes de 16 bits sin signo, **`ori`**. Se cazó leyendo el desensamblado
antes de enviar, no probando.

**4. La caché de instrucciones.** Escribir código por FFI no la invalida: el
parche está en RAM, el breakpoint de ejecución dispara, y la CPU sigue
ejecutando lo viejo. Se arregla con una ida y vuelta por savestate
(`dcp.flush()`), que conserva la RAM ya parcheada y reinicia las cachés.
Antes de dar con esto perdí tiempo con dos hipótesis equivocadas.

**5. Los breakpoints no disparan con el dynarec.** Hay que activar el
depurador y el intérprete — y hacer **Emulation → Reset** para que el cambio de
CPU tenga efecto.

**6. Parchear un solo sitio de rotación no alcanza.** Lo delató una
observación del usuario ("cuando hago otras acciones sí se mide"): DC1 tiene un
manejador de entrada por estado, diez en total, cuatro de ellos en overlays que
se cargan del disco y no están en el ejecutable. De ahí el diseño de
**un enganche + hambrear la entrada**.

**7. Dos palabras de botones.** La rotación lee `0x10($sp)` y el movimiento
lee `0x12($sp)`. Escribir solo una deja arriba y abajo en vanilla.

**8. Herramientas no verificadas envenenan el diagnóstico.** El modo `nohook`
de `patch_bin.py` escribía el enganche igual (la línea estaba fuera del `if`).
El bisect que "demostró" que la zona de datos rompía el arranque no demostró
nada. **Antes de sacar una conclusión de una herramienta, verificá la
herramienta.** El mismo script también escribía `PAYLOAD` en vez de `blob` en
modo sonda.

**9. Vigilar valores NO detecta un memset a cero.** El detector marcaba "sucio"
cuando una palabra dejaba de ser cero. El juego escribe **ceros sobre ceros**,
y eso es invisible: `0x800A386C` pasó cuatro minutos y medio de vigilancia sin
una sola marca, y después nos borró el payload. La única prueba honesta es
**escribir un patrón reconocible y ver qué sobrevive**.

**10. Las sondas escritas desde Lua llegan tarde.** El borrado de
`0x800A386C` ocurre **antes de la pantalla de título**. Una sonda escrita desde
la consola ya llega después, y vuelve intacta dando un falso positivo — el
control del experimento lo demostró. Para probar una zona de verdad, el patrón
tiene que estar **en el disco** (`patch_bin.py ... probe N`).

**11. Atribuir un fallo a la causa cómoda.** Cuando la versión armada con
mkpsxiso se colgaba al entrar al 3D, lo di por LibCrypt. Era plausible y
resultó falso: el parche in-place, que no mueve un solo sector, fallaba en el
mismo punto exacto. Dos métodos opuestos fallando igual señalan lo único que
comparten. Lo que lo resolvió fue **comparar dos caminos independientes**, no
razonar más sobre uno solo.

### Reglas de trabajo que salieron de todo esto

- Breakpoints antes que escaneo estadístico.
- Leer el desensamblado antes de enviar nada.
- Verificar la herramienta antes de creerle al experimento.
- Toda prueba de "zona libre" se hace escribiendo y mirando qué sobrevive,
  desde el arranque, con un control que **sepamos** que tiene que fallar.
- Si dos caminos independientes fallan igual, el culpable es lo que comparten.

---

## 8. Próximo: stick analógico

Es la continuación natural y la de mejor relación esfuerzo/resultado. Hoy el
payload saca el rumbo de un nibble de 8 direcciones; con los ejes analógicos
tendría 360° reales. El resto de la cadena (objetivo, giro, hambrear la
entrada) ya está y no se toca.

### Estado (prototipo en Lua, `dc_test.lua`): FUNCIONA

- **Buffer crudo del pad 1: `0x800AE288`** (pasado el final de la imagen,
  0x800AA000: es BSS del juego, dirección estática). Formato estándar:
  `+0` estado (00), `+1` id (0x73 analógico / 0x41 digital), `+2..3` botones
  activos en bajo, `+4` RX, `+5` RY, `+6` LX, `+7` LY (128 = centro).
  Encontrado por firma `00 73` + ejes en reposo y confirmado moviendo LX a 0
  (`dct.padFind()` / `dct.padPick()`). Hubo 15 falsos positivos más; la firma
  sola no alcanza, hace falta la confirmación con el stick.
- El juego NO fuerza el pad a digital: con el pad en analógico el id queda en 0x73.
- Rumbo: `atan2(LX−128, −(LY−128))` en unidades de 4096, mismo convenio que
  `dirTab` (arriba 0, derecha 1024). Zona muerta 30. Probado y a gusto.
- Pendiente: confirmar que la dirección no cambia entre reinicios y portarlo a MIPS.

**Lo que había que averiguar:** dónde deja el juego el buffer crudo del pad.
`0x1F800008` y `0x1F80000A` son ya una copia procesada de los botones; los
ejes analógicos (4 bytes: RX, RY, LX, LY) tienen que estar en el buffer que
el juego le pide al kernel. Método: breakpoint de escritura sobre
`0x1F800008` para encontrar quién la rellena, y de ahí subir hasta el buffer
original.

**Lo que hay que escribir:**

- Zona muerta (radio ~30 sobre 128 de rango) — sin esto el personaje tiembla.
- `atan2(LX − 128, LY − 128)`. La rutina de octantes que ya está en el payload
  asume una fila normalizada de la matriz de vista (|x| y |y| con módulo
  conocido). Con el stick eso no se cumple, así que hace falta normalizar por
  la componente mayor antes de indexar `asinTab`, o hacer una división.
- Dejar el camino digital como respaldo, para cuando el pad no está en modo
  analógico.

**Costo estimado:** 200–300 bytes. En el hueco actual quedan 101, así que
hay que comprimir (la `asinTab` de 65 entradas puede bajar a 33 sin que se
note, son 64 bytes) o usar el crecimiento del ejecutable.

**No hace falta** implementar velocidad proporcional: el juego solo tiene
andar y correr.

---

## 9. Próximo: cámara libre

Es la ambiciosa. El escenario es 3D real en buena parte del juego, y la matriz
de vista está en `0x800B048C`, que ya leemos todos los frames. Escribirla en
vez de leerla da cámara sobre el hombro o primera persona.

### Estado (septiembre 2026, `dc_test.lua`)

- **Todo el escenario es 3D real.** Las "zonas prerenderizadas" eran ReShade
  que no tomaba la profundidad en DuckStation. El problema (b) no existe.
- **La MATRIX se reescribe cada frame de juego (30 fps).** Escribirla en Vsync
  no sirve: se pisa antes de dibujar. Escritores (`dct.camWho()`):
  - rotación: `0x80087C7C..0x80087E28` = `0x80087BA8` (RotMatrix), llamada
    desde `0x8001F424`, vuelve a `0x8001F42C`;
  - traslación: `0x8006B018..020`, dentro de `0x8006AFB8` (que además carga la
    matriz en la GTE), vuelve a `0x8006B3D4`.
- **Órbita con correa corta: FUNCIONA** enganchando esas dos vueltas y rotando
  solo la matriz (`R' = R·Ry(−δ)`, `t` intacta).
- **La cámara es un objeto como Regina**, base `0x800B048C`
  (`[0x1F800000] + 0xB4`):
  `+0x00` matriz, `+0x14` t, `+0x20` **no** es el punto mirado (probado: no sigue
  a Regina y escribirlo rompe la cámara), `+0x30` **punto mirado S** (int16 ×3),
  `+0x28` ángulos (RotMatrix de los ángulos negados), `+0x38` desplazamiento
  en vista (int16; hoy `0,0,6421` = distancia) que `0x8006B00C` copia a `t`.
- **Cámara al hombro (en prueba):** enganche en `0x8001F3D8`, después del
  manejador de la cámara y antes de RotMatrix; escribe ángulos, punto y
  desplazamiento, y el juego arma la matriz solo.
- **Transformación por objeto, leída del desensamblado** (`0x8006AE68`):
  `TR = R · (pos − S) + t`, con `S` copiado de cámara+0x30 al scratchpad
  `0x1F80002C` en `0x8006B044`. O sea: `S` queda en el centro de la imagen a
  profundidad `t.z`, y `t.x`/`t.y` corren la imagen de lado.

### Estado de la cámara al hombro (prototipo Lua): FUNCIONA

- Enganche en `0x8001F3D8` (objeto cámara, `$s0 == 0x800B048C`): escribe
  ángulos `+0x28..2C`, punto mirado `+0x30..34` = pies de Regina − altura, y
  desplazamiento en vista `+0x38..3C` = (side, up, dist).
- Valores a gusto: `dist 2200`, `height 1300`, `side −350` (Regina a la
  izquierda), `pitch 120`, `pmin −500`, `pmax 600`, eje vertical invertido,
  giro 70 por frame. R1 recentra detrás de Regina.
- **R3 (y L3) alterna con la cámara original**: pad crudo `+2`, bits `0x04`/`0x02`,
  activo en bajo. En modo original no se escribe nada.
- **Apuntado con stick:** con R1, LX/LY se traducen a bits de cruceta
  (umbral 60) en las dos palabras del scratchpad. El esquema original no se toca.

### Orden de dibujo (resuelto)

- El juego no ordena todo por Z. Por malla del escenario, `0x8006B7C0..B8B0`
  elige un modo desde la tabla del cuarto (registro de 0x88 bytes):
  0 = Z mínima por polígono (`E214`/`E250`), 1 = Z máxima (`E18C`/`E1C8`),
  **2 = prioridad FIJA de la tabla** (`lhu ($s1)` → `0x1F800060` → `0x8006E17C`),
  3 = Z del pivote.
- `dct.otWho()` midió 5850 de 5915 polígonos del cuarto en modo 2. Esa
  prioridad está hecha a mano para los encuadres originales: desde otro lado
  pone cajas de atrás encima de Regina.
- **Arreglo (2 palabras):** `0x8006B81C: 3C068007 24C6E17C` →
  `0801ADFE 00000000` (`j 0x8006B7F8` = modo 1). Probado: queda perfecto.
  Solo mientras la cámara al hombro está activa.
- OT doble en `0x800AE3D8` / `0x800AF3D8` (una por frame), 1024 entradas.

### Cámara en puertas (prototipo Lua): FUNCIONA

- En la animación de puerta `0x800BAF3E` alterna `0A`/`1C` **cada 2 Vsync**, y
  el enganche de cámara corre a 30 fps: si cae siempre en la fase `0A` nunca
  ve el `1C`. Hay que muestrear el estado en cada Vsync (o buscar una variable
  que no parpadee, pendiente para MIPS).
- Regla usada: si en los últimos 6 Vsync hubo estado ≠ 10, cámara original sin
  tocar; se vuelve al hombro tras 10 frames de juego, detrás de Regina.

### Apuntado moderno de doble stick (prototipo Lua): FUNCIONA

- Escritores de posición medidos con R1 + movimiento (`dct.moveWho()`):
  solo `0x8005B2AC` (X) y `0x8005B2D4` (Z) mueven de verdad. Orden por frame:
  matriz (`0x80045388`) → ángulo (`0x8004538C`, apuntado `0x8017B060` en overlay)
  → posición → colisiones (`0x800454F0`, `0x8005C810`, `0x8005C764`).
- `0x8005B284`: `pos += ApplyMatrixSV(matriz del objeto, velocidad local)`; en
  `0x8005B29C` el desplazamiento en mundo está en la pila (`sp+0x10/12/14`,
  int16). Girarlo ahí desvía el paso **con colisión intacta**.
- Con R1: stick der X gira el ángulo antes de la matriz (90/frame, signo +1);
  a los manejadores les llega la cruceta sin izq/der. Stick izq: mitad de atrás
  → bit abajo, mitad de adelante → bit arriba, y el desplazamiento se gira
  `d = wrap(M − base) · STRAFESIGN`, con `STRAFESIGN = −1` (probado).
  `M = ánguloStick − yawCámara`, `base = F` (adelante) o `F + 2048` (atrás).
- Con R1 el stick derecho no mueve la cámara al hombro (la cámara recentra).

### Los tres problemas, en orden de dificultad

**a) Enganchar la escritura de la matriz.** Breakpoint de escritura en
`0x800B048C` para encontrar la rutina que la calcula, y meterse **después** de
que escriba. La `MATRIX` tiene la rotación en +0x00 y la traslación en +0x14,
así que se puede orbitar y hacer dolly sin tocar nada más.

**b) Las zonas prerenderizadas.** El juego **ya sabe cuáles son** — tiene que
saberlo, porque dibuja un fondo plano en lugar de geometría. O sea que el
"aquí cámara bloqueada" no hay que inventarlo, hay que encontrarlo:

- Breakpoint en la rutina que sube el fondo a la VRAM, o
- diff del descriptor de sala entre una sala 3D y una prerenderizada. El byte
  que cambia es el candado, automático y sin lista a mano.

Plan B si no aparece: el identificador de sala es de lo más fácil de localizar
(cambia justo al cruzar una puerta, que es el patrón que mejor detecta nuestro
método), y un **bitmap de una sala por bit** cuesta 25 bytes para 200 salas.
Lo tedioso es armar la lista, y eso también se automatiza: una versión de
prueba donde un botón marque la sala actual y la escriba en un buffer.

**c) Lo que la cámara deja ver.** Este no tiene truco. Los escenarios están
construidos para unos pocos encuadres fijos: apenas movés la cámara aparecen
paredes sin cara interior, techos que no existen y geometría recortada porque
el culling está calculado para mirar desde donde miraba el diseñador. No se
arregla con un flag, se arregla modelando, y para eso no alcanza la RAM.

### Recomendación

Empezar por **cámara sobre el hombro con correa corta**: cerca del personaje,
a la altura original, con rango de giro acotado (±30° o así) y sin alejarse.
Se queda dentro de la zona que los artistas construyeron. Es el 20% del trabajo
y el 80% de la sensación.

---

## 11. Versión 6 en MIPS (C) — FUNCIONA en RAM

**Espacio (medido, no deducido):**
- El ejecutable NO puede crecer: el sector 164525, pegado a `SLES_022.11`, es
  `SYSTEM.CNF`. `patch_bin.py` aborta, y está bien que aborte.
- crt0 (`0x800121D4`) limpia la BSS `0x800A9C70..0x800C28F0` y deja el heap en
  `0x800C28F0..0x801FEFF8`. Todo lo que había "después del ejecutable" es BSS.
- Sonda de arranque (`dct.bootProbe()`, patrón escrito en `0x80012268`, jal main,
  solo sobre el heap; la BSS no se puede sondear porque el juego depende de que
  quede en cero). Dos sesiones distintas (intro, partida cargada, inventario,
  mapa, pelea, cinemática, guardado): **`0x800C28F0..0x800E8000` intacto en las
  dos**, 150 KB.
- Código en **`0x800D8000`**, pila propia en `0x800E0000`.
- El `SLES_022.11` suelto de la carpeta YA estaba parcheado; el original se sacó
  de la imagen limpia.

**Código:** `v6/` — `dcmod.c` (lógica), `stubs.S` (puentes), `link.ld`,
`build.sh` (gcc mipsel `-march=r3000 -G0 -Os`), `gen.py` → `dc6.lua`.
3024 bytes. atan2 por tabla de 65 entradas (error ≤1/4096), seno por tabla
(error ≤2/4096). Probado también compilado para PC con RAM simulada.

**Enganches:**
| Dirección | Original | Nuevo |
|---|---|---|
| `0x80045378` | `26040028 9602002A 02002821 30420FFF` | `jal stubPlayer` + 3 nop |
| `0x8001F3D8` | `96020028 9603002A` | `jal stubCamera` + nop |
| `0x8005B29C` | `96020020 97A30010` | `jal stubStrafe` + nop |
| `0x8006B81C` | `3C068007 24C6E17C` | `j stubSort` + nop |

**Probado en RAM (`dc6.install()`):** movimiento, apuntado doble stick, cámara al
hombro, R3, orden de dibujo: igual que el Lua.

**v6.1 — bloqueo en cinemáticas (probado en disco):** los bytes de estado de
Regina NO distinguen una cinemática (+3D: 00 quieta, 01 camina, 05 corre,
06 apunta; +3C=04 solo en puertas). La señal real está en el lector de botones
`0x80015E94`: si `(*[0x1F800000] + 0x40) & 4`, escribe CERO en `0x1F800008/0A`
(`0x80015EB8/EC0`); si no, los botones normales (`0x80015EE4/EC`). El parche
mira esa misma bandera y no toca ángulo ni botones; la cámara sigue libre.

**v6.2 — arranca en cámara original (probado en disco):** `shNative = 1` por
defecto; R3/L3 pasa al hombro. El estado vive en RAM (no vuelve a original al
cargar partida sin Reset).

**Grabado en disco:** `v6/grabar_v6.ps1` verifica 8 sectores de la imagen
original por SHA-256, copia todo a `C:\dc\disco_v6\` y reemplaza los sectores
(164216, 164247, 164323, 164367, 164400, 164510, 164512, 164513). Cargador de
64 bytes en `0x800A2F90` (= pc0), blob en `0x800A3804`. Probar SIEMPRE
arrancando desde cero: un savestate restaura la RAM sin parche.

**v6.3 — acciones especiales (probado en disco):** empujar un estante se
trababa. Medido: acción `+3D = 07`, ángulo alineado por el juego (1024), la
bandera `+0x40` valía `0x800` (bit 4 apagado: no era cinemática). El giro del
parche desalineaba a Regina. Ahora el control moderno solo actúa con `+3D` en
{00 quieta, 01 camina, 05 corre} (y R1 aparte). En cualquier otra acción no se
toca el ángulo: el stick se traduce a cruceta relativa a hacia donde mira
Regina (±45° adelante, ±135° atrás, resto giro); sin stick la cruceta pasa tal
cual. OJO: la línea de diagnóstico que leía `[0x1F800000]` con el puntero de
RAM crasheó el emulador (fuera de los 2 MB): el scratchpad va por
`PCSX.getScratchPtr()`.

**v6.4 — L2 para correr: FALLÓ y se revirtió a v6.3.** Se copió el bit
`0x0001` (supuesto L2) sobre `0x0080` (supuesto Cuadrado) en las dos palabras
de botones, sin medir. Resultado: al apretar L2 Regina caminaba sola y no
paraba hasta volver a apretar L2, en los dos modos de cámara. Lección (la de
siempre): **el mapa de bits de botones del scratchpad no está medido** más allá
de cruceta y R1. Solución adoptada: keybind en el emulador (gatillo L2 →
Cuadrado). Si se retoma, medir primero con `dct.inputWho()` qué bits pone cada
botón.

**v6.5 — mordidas, disparo agil, remapeo y L3 (probado en RAM con `dc6.install()`;
grabado pendiente de probar).** Blob 4064 bytes (quedan 136 libres en la tira de ceros).

*Apuntado bloqueado en mordidas.* Bug: con R1 apretado durante una mordida, el stick
derecho giraba a Regina y el empujón del dinosaurio (`0x8005B2AC`, mueve según
el ángulo) la arrastraba en círculos. Pasaba con las dos cámaras. Medido con
`dct.biteWho()`:
- `+3C` = estado general: `01` normal (TODO el apuntado: quieta, giro, caminar,
  disparar), `05` mordida (`+3D` = `0C` o `0E`), `04` puertas.
- Sin R1 el parche ya iba a la rama de acciones y no escribía el ángulo; con R1
  la rama de apuntado se saltaba ese filtro (`PATCH+4B8` escribía el ángulo).
- Arreglo: la rama de apuntado exige `+3C == 01`; si no, cae en el filtro de
  acciones (el botón de apuntar y la cruceta pasan tal cual). Toolchain
  verificado: el fuente v6.3 recompilado sale idéntico byte a byte al
  `dcmod.bin` v6.3.
- Respaldo: `v6/dcmod_v6.3.c`, `v6/dc6_v6.3.lua`. `SLES_022.11.v6` y
  `grabar_v6.ps1` siguen siendo v6.3.
- Visto al pasar (sin medir cuál es cuál): apuntando aparecen los bits `0x0080`
  y `0x0040` en las palabras de botones.
- Savestates: sirven para probar con `dc6.install()` si se instala DESPUÉS de
  cargar el estado (y se reinstala cada vez que se recarga).

*Disparo ágil* (medido con `dct.shotWho()`, prototipado con `dct.shotCut`/`shotCool`):
- Apuntando (`+3D = 06`), `+3E` es la sub-acción: `01` quieta, `02` disparo,
  `05` caminar apuntando. `+3F` = fase (00 inicio, 01 corriendo).
- **`+078` = largo de la animación** (pistola 26 frames ≈ 0,87 s; caminar 33 en
  bucle) y **`+079` = frame actual** (lo avanza `0x800495E4`). El juego suelta a
  Regina recién cuando `+079` llega a `+078`: el frenazo ES la animación.
- Cancelación: desde el frame **2** (disparo y bombeo; valores elegidos
  probando en vivo), si hay dirección (stick o cruceta) o se suelta el botón de
  apuntar, el parche escribe `+079 = +078 − 1`. Probado hasta 2: el disparo
  sigue haciendo daño, sonando y gastando bala.
- Los dos umbrales son variables del blob (`shotCut`, `pumpCut`) y se retocan
  en vivo con `dc6.cut(n)`, `dc6.pump(n)` y `dc6.cuts()`, sin recompilar.
- **Sub-acciones de `+3E` apuntando (medidas con `dct.shotState()`):** `00`
  levantar arma, `01` quieta apuntando, `02` disparo, `03` bombeo (solo
  escopeta), `04` bajar arma. Largos: pistola disparo `1A`; escopeta disparo
  `17` y bombeo `10`. Se cancelan `02` y `03`; el enfriamiento arranca solo con
  `02`.
- **Al soltar el apuntado**, `+3D` se queda en `06` unos frames y, si el stick
  sigue tirado, pasa a `02` (caminar de espaldas). Los dos, con el botón de
  apuntar suelto, se tratan como estado normal: si no, Regina seguía de
  espaldas mientras no soltaras el stick (medido con `dct.aimOut()`).
- `dc6.install()` ahora acepta enganches de OTRA versión del parche (cualquier
  `jal`/`j` al bloque `0x800D8000..0x800E0000`), así se puede reinstalar sobre
  un disco ya parcheado sin que aborte.
- Enfriamiento: **20 frames** desde que empieza cada disparo con el bit de
  disparo borrado (con el apuntado apretado). Mantiene la cadencia cerca del original
  (26) y evita que el juego se vuelva de acción.
- Descartado: disparar caminando de verdad. Las animaciones son de cuerpo
  entero; `dct.shotSlide()` quedó en el banco de pruebas por si se quiere ver.

*Mapa de bits de los botones (MEDIDO con `dct.btnMap()`, era el pendiente de v6.4):*
las dos palabras son el pad crudo en activo alto, y **`0x1F800008` son los
botones MANTENIDOS y `0x1F80000A` los recién APRETADOS**.

```
L2 0x0001  R2 0x0002  L1 0x0004  R1 0x0008  Circulo 0x0010
Cuadrado 0x0040  X 0x0080  L3 0x0200  R3 0x0400
cruceta arriba 0x1000  der 0x2000  abajo 0x4000  izq 0x8000
```
(Triángulo quedó sin medir limpio: la lectura se solapó con Cuadrado.)

*Remapeo y cámara:*
- Esquema final (probado): **L2 apunta** (se copia sobre el bit de R1),
  **R2 dispara** (se copia sobre el bit de X) y **R1 camina**. Los bits físicos
  de L2, R2 y R1 se apagan, así que ya no hay media vuelta de R2. X y Cuadrado
  siguen funcionando como siempre.
- **Correr siempre activado:** el parche mantiene puesto el bit de correr
  (Cuadrado, `0x0040`) y R1 lo suelta mientras se mantiene. Solo con
  `+3C = 01` y sin bloqueo de cinemática, para no meter ese botón en menús ni
  en el inventario; la palabra de "recién apretados" recibe el bit solo en el
  frame del cambio.
- OJO al leer el pad CRUDO después del remapeo: "apuntar" es L2 (`0x01` de +3)
  y "caminar" es R1 (`0x08`). Lo usan `hookCamera` (recentrar apuntando) y la
  cancelación del disparo. En el scratchpad, en cambio, el bit de apuntar sigue
  siendo `0x0008`.
- Ya no hace falta el keybind del emulador para correr.
- **L3 recentra** la cámara detrás de Regina mientras se mantiene (sirve
  corriendo, sin apuntar); **R3 sigue alternando** hombro / original.

*Herramienta nueva:* `v6/comprobar_imagen.ps1 -Path <Track 1.bin>` dice si una
imagen está limpia, ya parcheada (v6.3 o v6.5) o si es otra versión, y compara
tamaño, MD5 y SHA-1 con la huella de referencia. `grabar_v65.ps1` acepta
`-Src <carpeta>` para tomar la imagen limpia de otra ubicación sin moverla.

*Para consola real:* en un CD-R o en POPStarter no hay subcanal, así que el
`.sbi` no sirve: primero hay que quitar LibCrypt del `Track 1.bin`
(libcrypt-patcher de Alex Free) y después grabar el control moderno encima.
Comprobar con `comprobar_imagen.ps1` que los 8 sectores sigan limpios tras
quitar LibCrypt; si alguno cambió, los dos parches se pisan. En consola hay que
apretar Analog en el DualShock: el parche necesita el pad en analógico.

*Grabado v6.5:* `v6/SLES_022.11.v65` y `v6/grabar_v65.ps1` (escribe en
`C:\dc\disco_v65\`, los mismos 8 sectores, verificando las huellas
originales). Reconstrucción y controles hechos en esta sesión:
- el ejecutable original se recuperó de `SLES_022.11.v6` revirtiendo loader,
  blob, `pc0` y los 4 enganches (SHA-256
  `e9fc4f360c3c178eb76f14a8d196ef6df8050c57a69fb17bd2a0657c44c090f0`);
- control: reconstruir v6.3 desde ese original da un archivo **idéntico** al
  `SLES_022.11.v6` que ya existía;
- control: el recálculo de EDC/ECC reproduce los 8 sectores de v6.3 **y** las
  8 huellas `Orig` que el script trae de la imagen limpia;
- los datos de usuario de los sectores nuevos son byte a byte el ejecutable
  v6.5.

**Pendiente:**
1. El pad tiene que estar en modo analógico (id 0x73). El juego nunca lo pide:
   en consola real hay que apretar Analog; en Redux,
   `PCSX.SIO0.slots[1].pads[1].setAnalogMode(true)`. Opcional: que el parche
   lo active solo.
2. Puertas: RESUELTO sin hacer nada; en disco la cámara queda clavada en la animación.
3. HECHO (ver arriba). Plan original: grabarlo en el disco: blob en la tira de ceros `0x800A3804` (4200 bytes, el
   juego la limpia antes del título, así que se copia antes), cargador de
   12 instrucciones en `0x800A2F88` (copia a `0x800D8000`, pone la tira en
   cero, `j 0x800121D4`), `pc0` del header → cargador. Sin mover sectores.

## 10. Lo que está fuera de alcance

Todo lo que pida RAM para contenido: modelos, animaciones o texturas nuevas no
entran en los 2 MB de la consola con el presupuesto que ya usa el juego.
60 fps es reescribir el motor, no parchearlo.

## 12. Ideas para más adelante

- Modo analógico automático (que el parche lo pida al pad).
- Cruceta como atajos de objetos: buscar variable de objeto equipado y la
  función que equipa (breakpoint al cambiar de arma en el menú); asignar desde
  el inventario. Hoy la cruceta es respaldo del movimiento: habría que sacarlo
  o dejarlo solo con el pad en digital.
- Volver a cámara original al cargar partida / game over.
- Revisar si otras ramas del parche deberían exigir `+3C == 01` (hoy solo la de
  apuntado).
- Medir el bit de Triángulo y de Select/Start (el resto ya está en la sección 11).
- **Regenerar los parches publicables (`xdelta`/PPF) para v6.5** y actualizar
  `LEEME.txt` con el esquema de botones nuevo.
- Comparar la huella del Track 1 con la ficha de Redump (sección 13).
- Probar v6.5 en consola real (LibCrypt + CD-R, o POPStarter en PS2).
- **Espacio:** quedan 136 bytes libres en la tira de ceros. Lo próximo que
  crezca obliga a comprimir una tabla (la `asinTab`/`atanTab` de 65 entradas
  baja a 33 sin que se note) o a mover datos.

## 13. Publicación del parche

**Nunca** distribuir la imagen parcheada, `SLES_022.11.v6` ni `grabar_v6.ps1`:
los dos últimos contienen sectores del ejecutable original de Capcom. Se
publica solo la diferencia.

Los parches publicables siguen siendo los de **v6.3**: regenerarlos para v6.5
está pendiente (ver sección 12).

Archivos en `C:\dc\release\` (v6.3):

| Archivo | Tamaño | Herramienta | Nota |
|---|---|---|---|
| `DinoCrisis_Spain_ControlesModernos_v6.3.xdelta` | 4973 B | Delta Patcher / xdelta UI | **recomendado**: verifica la huella de origen y no aplica si no coincide |
| `DinoCrisis_Spain_ControlesModernos_v6.3.ppf` | 9278 B | PPF-O-Matic | PPF 3.0, sin verificación: sobre otra imagen la rompe en silencio |
| `LEEME.txt` | | | qué hace, imagen requerida, cómo aplicar, avisos |

Los dos se probaron aplicándolos sobre la imagen limpia: el resultado es
idéntico byte a byte a v6.3. Se aplican **solo al Track 1**; Track 2, `.cue` y
`.sbi` quedan tal cual (el `.sbi` sigue valiendo porque no se mueve ningún
sector).

**Huella de la imagen de origen (Track 1):**

```
Dino Crisis (Spain) (Track 1).bin
Tamaño : 387317952 bytes
CRC-32 : BE3BC2EA
MD5    : e271ee223eda1c8bcf12e8a9873ec3dc
SHA-1  : 29cda9847ddfb85e0b8c4f016654d171741798b7
```

Por qué importa: el serial SLES-02211 identifica el juego, no el archivo.
Otras copias pueden diferir por formato (`.iso` 2048, `.bin` de pista única,
`.chd`/`.pbp`/`.ecm`), por venir con LibCrypt ya parcheado (tocan justo el
ejecutable), por dumps defectuosos o por revisiones del disco.

**Redump:** ficha `http://redump.org/disc/27940/`. PENDIENTE: comparar a mano
la fila del Track 1 (y del Track 2) con la huella de arriba. La herramienta web
no pudo abrir la página (Redump redirige HTTPS→HTTP en bucle). Si coincide,
agregar "compatible con Redump" y el enlace al `LEEME.txt` y al post.

**Dónde subir:** RHDN/Romhacking.net (ficha con capturas, revisión) o GitHub
(parches en Releases, y el código de `v6/` en el repo). Probado solo en
PCSX-Redux; el ReShade del post corre en DuckStation, conviene probar la
imagen parcheada ahí antes de mostrar las dos cosas juntas.

---

## 14. Armas: lo medido, y por qué los atajos de la cruceta quedaron descartados

Sesión de septiembre 2026. Todo medido con `dct.equipWho()` (protocolo
A → B → A) y desensamblando el ejecutable; nada deducido.

### Lo que quedó firme (sirve para todo el juego: está en el ejecutable)

- **Arma equipada: objeto jugador +0x240 (`0x800B2054`)**, un byte con formato
  `(grupo << 4) | variante`. Lo escribe `0x8005EF18`.
- **Rutina que equipa: `0x800481D8(objetoJugador, código)`**. Adentro hace
  `$s1 = código >> 4`, `$s2 = código & 3`, y busca el bloque del arma en la
  tabla de grupos de `0x80095578`. El grupo 2 tiene un caso especial en
  `0x80048244` (la pistola y su mejora comparten bloque).
- Quien la llama al salir del inventario es `0x8005EEDC`:
  `8005ef18 sb $a0, 0x80($v1)` (→ +0x240) y `8005ef20 jal 0x800481d8`.
- Punteros del arma en mano: jugador **+0x21C** y **+0x220** (= +0x21C + 4).
- `0x80095588` guarda el id del último recurso de arma cargado.

**Códigos (verificados con `dct.equipTry`):**

| Grupo | Arma | Códigos |
|---|---|---|
| 1 | Escopeta | `10` base, `11` personalizada, `12` + culata, `13` personalizada + culata |
| 2 | Pistola | `20` base, `22` variante (mejora fusionada) |
| 3 | Lanzagranadas | `30`, `31` personalizado |

**Llamar a una función del juego desde Lua FUNCIONA.** `dct.equipTry(código)`
desvía el PC desde un breakpoint, pone `$a0`/`$a1` y deja `$ra` en el
enganche. Redux respeta el cambio de PC. Técnica reutilizable.

### Por qué no hay atajo de armas en la cruceta

- Cada variante tiene su propio modelo, y **en memoria entra uno solo**
  (destino `0x801E0000`). Cambiar de arma pide el recurso con
  `0x800221F0`, que marca `0x800BBCE2 = 1`, y los dos bucles de espera de la
  rutina que equipa (`0x80048344` y `0x8004836C`) ceden el control hasta que
  termina: **0,52 a 0,60 s de pantalla negra, medidos**.
- Tabla de recursos en `0x80091AA4`, registros de 12 bytes:
  `[0]` LBA, `[1]` tamaño en RAM, `[2]` tamaño comprimido. Las armas son
  **72 a 90 KB en RAM** y 11 a 14 KB en el disco:
  `0139` escopeta 90112/13362, `013B` escopeta+culata 88064/11491,
  `013D` pistola 73728/10621, `0141` lanzagranadas 90112/14044.
- No depende del inventario: `0x12`, que el personaje SÍ tiene, carga igual.
  La regla es: cambia el puntero +0x21C → hay carga; no cambia → instantáneo
  (por eso `20` ↔ `22` es gratis, comparten bloque).
- **Caché en RAM: PROBADO Y FALLA.** `dct.wpnCache()` guarda el bloque
  cargado y lo restaura interceptando `0x800221F0`. El cambio pasa a 0 Vsync,
  pero **el arma sale invisible y el juego crashea al apuntar**: la carga
  también sube texturas a la VRAM y registra cosas fuera de ese buffer.
  Replicar eso es reimplementar el cargador.
- Error cometido en el camino: la primera versión deducía el tamaño diffeando
  128 KB desde el destino. Esa ventana llega hasta la **pila**
  (`s_addr = 0x801FFFF0`) y al restaurar la pisó: cuelgue. El tamaño estaba
  en la tabla del juego. Otra vez lo mismo: **el dato está, no lo deduzcas**.

**Decisión:** el cambio de arma se queda en el inventario. La cruceta, si se
usa algún día, sería para cosas que no recarguen un modelo (tipo de bala,
medicamentos) y eso hay que medirlo antes con `dct.equipTry`/`dct.loadInfo`.

### Herramientas nuevas en `dc_test.lua`

```
dct.equipWho()   arma equipada, por fases A->B->A (inventario CERRADO)
dct.equipCheck() valor actual de los candidatos
dct.wpn()        codigo, punteros y tabla de grupos viva
dct.equipTry(c)  llamar a 0x800481D8 y medir la carga (Vsync, ids, espera)
dct.loadInfo(id) LBA, tamano en RAM y comprimido de un recurso
dct.wpnCache()   prototipo de cache (descartado, queda como evidencia)
dct.dump(a, n)   volcado hexadecimal
dct.ammoWho()    contador de balas (motor de diferencias por evento)
dct.hpWho()      vitalidad (evento: mordida)
dct.otDump()     primitivas de la OT por tipo; dct.textWho(a) quien las arma
```

El motor de esas búsquedas: evento concreto + máscara de ruido tomada antes +
breakpoint de escritura sobre los candidatos. La primera versión de
`equipWho` sacaba las fotos con el inventario ABIERTO y devolvió 72
candidatos de puro redibujo del menú; con las fotos tomadas con el inventario
CERRADO y el filtro `A1 == A2 ≠ B`, quedaron los tres campos buenos.

---

## 15. HUD: las tres variables y cómo escribir en pantalla

Misma sesión. El HUD estilo VMU de Dreamcast es viable: el juego ya sabe
escribir texto, y las tres variables están medidas.

### Las variables (todas en el objeto jugador, `0x800B1E14`)

| Dato | Offset | Dirección | Formato |
|---|---|---|---|
| **Vitalidad** | +0x118 | `0x800B1F2C` | 16 bits, **0..1000** |
| **Arma equipada** | +0x240 | `0x800B2054` | byte `(grupo << 4) \| variante` |
| **Balas** | +0x246 | `0x800B205A` | byte; lo escribe `0x8017A6BC` al disparar |

La vitalidad se confirmó escribiéndola: en 100 Regina camina herida, en 0 se
muere, en 1000 vuelve a la normalidad. **No hay barra en la versión PS1**, así
que no se puede confirmar mirando el inventario: hay que mirar la animación.

**PENDIENTE:** las balas de +0x246 son las del arma con la que se midió (la
pistola) y **no cambian al equipar otra arma**. Falta repetir `dct.ammoWho()`
con la escopeta para ver si hay una tabla por arma.

### Escribir texto: el juego ya lo hace

Encontrado tirando del cronómetro de las misiones (`dct.clockWho()` →
`dct.readWho()` → desensamblado) y de `dct.findText('OBJETIVOS')`, que apareció
en `0x80010544` como **cadena de formato** (`'OBJETIVOS: %d'`). El patrón del
juego, en `0x8003F758`:

```
jal 0x8008CCD8   sprintf(buffer, formato, valores...)
jal 0x8005F74C   a0 = buffer ASCII -> convierte a codigos de fuente
                 (' '->0, ':'->0x82, '.'->0x88), devuelve el puntero
jal 0x8005F884   a0 = x, a1 = y, a2 = color, a3 = ese puntero
                 -> 0x8006004C arma POLY_FT4 (codigo 0x2C) y los encola
```

Las tres están **en el ejecutable**, así que sirven en toda la campaña.
`dct.hudTry('HOLA')` y `dct.hudLive()` lo hacen desde Lua desviando el PC, y
funcionan. Buffer de conversión compartido con el juego en `0x800BEBC8`: el
parche real debería usar uno propio.

**PENDIENTE:** probar `dct.hudLive()` en la **campaña normal**. El riesgo es
que la página de la fuente solo esté en la VRAM durante las misiones y el
inventario.

### Falsos positivos que costaron tiempo (y cómo se cazaron)

1. **`0x800BE290` NO es una tabla de personajes: son los canales de sonido**
   (36 bytes por canal, `+0x1B` = volumen 0..127). Buscando vitalidad salió
   `0x800BE533` con 100 → 65 al recibir un golpe → 90 al curarse, y eran los
   volúmenes del golpe y del frasco. Lo delató `dct.hpWatch()`: los valores
   rebotaban solos, y `0x80054978` calcula `0x7E` y `0xBE - ángulo`, que son
   los volúmenes izquierdo y derecho.
2. **La OT vacía no está vacía.** `ClearOTagR` deja cada entrada apuntando a la
   anterior, así que el recorrido de `otDump` contaba 524802 "primitivas" que
   eran entradas de la tabla.
3. **La máscara de ruido tomada estando quieto no sirve**: al caminar cambia
   medio mundo. Hay que juntarla frame a frame jugando normal.
4. Zonas que nunca son estado de juego y hoy están en `dct.SKIP`: las dos OT
   (`0x800AE3D8..0x800B03D8`), los canales de sonido (`0x800BE290..0x800BE710`)
   y los buffers de primitivas (`0x801A0000..0x801E0000`).

### La herramienta que resolvió la vitalidad

`dct.track()` + `dct.menos()` / `dct.mas()` / `dct.igual()` / `dct.distinto()`:
descarte acumulativo sobre toda la RAM, sin asumir nada. Con el peor caso
posible (RAM entera cambiando al azar en cada paso) baja de 999184 candidatos
a 4 en cinco pasos, en 0,14 s.

La clave fue **no asumir el sentido**: alternar `igual()` estando quieta con
`distinto()` al recibir golpes y al curarse. Buscando solo "lo que baja" se
perdía, porque no sabíamos si el juego guarda vida o daño. `dct.trackUndo()`
deshace un paso equivocado sin perder el progreso.

Otras herramientas nuevas: `dct.hunt()` (por fases), `dct.pdiff()` (solo el
objeto jugador), `dct.findText()` (ASCII o por diferencias entre letras),
`dct.readWho()` (quién LEE una variable), `dct.clockWho()` (contadores que
bajan solos), `dct.peek()` / `dct.poke()`.

### Correcciones y datos finales del HUD (misma sesión, después de probarlo)

**El HUD anda en la campaña.** Era el riesgo que podía tirar todo abajo: la
fuente está en la VRAM también fuera de las misiones. `dct.hudLive()` muestra
arma, balas y vitalidad sobre el juego normal.

**Munición: hay un contador POR GRUPO de arma**, contiguos en el objeto
jugador. `+0x246` (que se midió con la pistola) no cambia al equipar otra:

```
municion del grupo G  =  jugador + 0x242 + G*2
   grupo 1 escopeta       +0x244   (medido con dct.pdiff)
   grupo 2 pistola        +0x246   (medido con dct.ammoWho)
   grupo 3 lanzagranadas  +0x248   (por la formula; anda en la practica)
```

**Vitalidad: el máximo cambia según el modo.** 1000 en la misión con
cronómetro, **1200 en la campaña**. Por eso el HUD muestra el valor crudo y no
un porcentaje. En la pantalla de muerte el campo toma valores fuera de rango
(visto 6551), así que conviene filtrarlos.

**Orden de dibujo del texto: es una variable, no está fijo.** El texto quedaba
tapado por la escenografía en algunos encuadres. En `0x8006004C`:

```
800601c4  lw $v0, -0x13b4($v0)   -> [0x800BEC4C] = indice de profundidad
800601c8  lw $a0, -0x1d80($t9)   -> [0x800AE280] = base de la OT actual
800601d0  addiu $v0, $v0, 0x70   -> ranura = base + 0x70 + indice*4
```

Poniendo `0x800BEC4C` en **0** antes de dibujar, el texto va por encima de
todo. Hay que devolverle su valor al juego después, o se le rompe su propio
texto.

**La fuente no tiene guión.** `0x8005F74C` mapea ' ' → 0, ':' → 0x82,
'.' → 0x88, 'A'-'Z' → código − 0x40, 'a'-'z' → − 0x46, dígitos → +5, y lo que
no conoce sale como otro glifo (los `-` salieron como `x`). Usar solo letras,
números, espacio, dos puntos y punto.

**Pendiente del HUD:** barra de bloques para la vitalidad en vez del número
(idea del usuario, queda para el final), y ver por qué la coordenada X no
parecía moverlo.

### Munición: cantidad y TIPO, por grupo de arma (medido con `dct.watch`)

El bloque de armas del objeto jugador quedó entero. Cada grupo tiene su
contador en el byte par y el **tipo cargado en el impar de al lado**:

```
jugador +0x240   arma equipada  (grupo << 4) | variante
        +0x244   cantidad escopeta        +0x245   tipo
        +0x246   cantidad pistola         +0x247   tipo
        +0x248   cantidad lanzagranadas   +0x249   tipo
   cantidad = +0x242 + grupo*2      tipo = +0x243 + grupo*2
```

Los códigos de tipo son **globales**, no por arma:

| Código | Munición |
|---|---|
| `00` | balas comunes (escopeta) |
| `02` | sedante ligero |
| `03` | sedante |
| `05` | veneno letal |
| `06` | 9mm |
| `07` | 40S&W |
| `08` | granada explosiva |
| `FF` | nada cargado |

Faltan `01`, `04` y de `09` en adelante (sedante fuerte, balas de calor y las
que no estaban disponibles al medir). El HUD muestra los desconocidos como
`Txx`, así que se completan jugando, sin volver a medir.

### Tabla de objetos completa (medida con la caja de emergencia)

Los códigos GameShark que aparecieron a mitad de camino explicaron por qué
escribir en `0x800B9F98` no cambiaba nada: **esa tabla no es el inventario de
Regina, es la caja de emergencia**, a la que el menú no deja entrar salvo que
se habilite la opción escondida.

```
0x8005ED54   cantidad de opciones del menu de EQUIP.: 4 -> 5 (zona de CODIGO,
             hay que vaciar la cache de instrucciones despues de escribir)
0x800B9F9C   9 ranuras de la caja, 4 bytes cada una: [id][cantidad][flag][00]
0x80062F80   lbu $a3, ($a2)  (90C70000)  lee la cantidad; si es 0 saltea la
             ranura. Cambiandolo por ori $a3, $zero, 0x100 (34070100) las
             muestra todas.
```

Truco que hizo la medición infalible: llenar las ranuras poniendo **el id como
cantidad**, así el número que se ve en pantalla ES el id y no hay que deducir
en qué orden las lista el juego (`dct.boxOn(desde)` sin cantidad).

| id | Objeto | id | Objeto |
|---|---|---|---|
| 01 | Escopeta | 13 | Sed.Medio |
| 02 | Escopeta Perso. | 14 | Sed.Fuerte |
| 03 | Escopeta+Culata | 15 | Veneno letal |
| 04 | Esc.Per.+Culata | 16 | Balas 9mm P. |
| 05 | Pistola | 17 | Balas 40S&W |
| 06 | Pistola+Mira | 18 | Granadas |
| 07 | Pistola Person. | 19 | Balas de calor |
| 08 | Pist.Per.+Mira | 1A | Granadas infin. |
| 09 | Lanzagranadas | 1B | Hemostático |
| 0A | Lanzagr.Person. | 1C | M. Pequeña |
| 0B | Piezas Escopeta | 1D | M. Grande |
| 0C | Culata Escopeta | 1E | M. Total |
| 0D | Mira de pistola | 1F | Resurrección |
| 0E | Desliz.Pistola | 20 | Sedante |
| 0F | Piezas Lanzagr. | 21 | Mat. Curativo |
| 10 | Balas SG | 22 | Intensificador |
| 11 | Balas Escoria | 23 | Multiplicador |
| 12 | Sed.Ligero | | |

**La relación entre las dos numeraciones:**

```
id de inventario  =  tipo de municion cargada + 0x10
```

Se verificó en los siete tipos medidos en el arma (00 SG, 02 Sed.Ligero,
03 Sed.Medio, 05 Veneno, 06 9mm, 07 40S&W, 08 Granadas) y completa solos los
cuatro que faltaban: 01 Balas Escoria, 04 Sed.Fuerte, 09 Balas de calor,
0A Granadas infinitas.

Las armas también siguen un patrón: id = 1 + variante para la escopeta
(grupo 1), 5 + variante para la pistola (grupo 2) y 9 + variante para el
lanzagranadas (grupo 3), o sea los mismos grupos de la tabla `0x80095578`.

Con esto quedan resueltos los nombres de toda la munición y la base para un
futuro atajo de curarse desde la cruceta (hay que buscar el inventario real,
que NO es esta tabla).

### La fuente chica del menú, y qué se puede dibujar con ella

Hay DOS rutinas de texto. La grande necesita convertir el ASCII primero; la
del menú dibuja directo y es la que sirve para el HUD:

```
0x8005F920(x, y, color, cadena ASCII)     fuente chica, terminador 0
   8005f970  v1 = caracter - 0x20
   8005f98c  u = (v1 % 32) * 8            columna en la textura
   8005f9b0  v = (v1 / 32) * 8 - 0x30     fila
   8005f940  sprites (codigo 0x74), paleta 0x7E32
Profundidad: la misma variable, [0x800BEC4C]; en 0 queda encima de todo.
```

**La fuente son solo DOS filas: `0x20..0x5F`.** De `0x60` en adelante la
coordenada v se sale de la tira y se dibuja VRAM de otra cosa (sale ruido de
colores). O sea:

- `0x20..0x3F` espacio, signos, dígitos, `: ; < = > ?`
- `0x40..0x5A` arroba y mayúsculas — **no hay minúsculas** (el inventario las
  muestra porque usa otra página)
- `0x5B..0x5F` **los iconos de los botones de PlayStation**: círculo,
  triángulo, cuadrado y equis, con su color propio de la paleta

**Consecuencia para el HUD:** no hay un bloque sólido neutro, así que la barra
de vitalidad no se puede armar repitiendo un carácter. Hay que dibujarla con
primitivas planas colgadas de la OT — lo que a cambio permite el degradado
verde-amarillo-rojo del diseño estilo Dreamcast. Los dos diseños que se
pensaron terminan necesitando lo mismo.

Y de regalo: con los iconos de botones el HUD puede mostrar ayudas de control
con los símbolos reales del mando, sin dibujar nada nuevo.

### El HUD terminado en Lua (diseño cerrado, listo para pasar a MIPS)

Tres líneas de texto con `0x8005F920` más dos rectángulos planos colgados de
la OT. Todo se dibuja UNA vez por frame; el estado se resetea en el Vsync.

**Datos, todos dentro del objeto jugador (`dct.PLAYER`):**

```
+0x118   vitalidad (16 bits)         lleno campana = 1200, misiones = 1000
+0x240   codigo de arma equipada     0 = ninguna -> se muestra "NADA"
+0x242   balas cargadas (16 bits)    +0x242 + grupo*2
+0x243   tipo de municion cargada    +0x243 + grupo*2
```

**Formato de las líneas** (el que pidió Nahuel):

```
linea 1   nombre del arma completo        ej. PISTOLA PERSONALIZADA
linea 2   "<balas> BALAS - <tipo>"        ej. 17 BALAS - 9MM
linea 3   la barra de vitalidad
```

**La barra** — dos primitivas TILE (`0x60`) por frame:

```
marco    (x-b, y-b, w+2b, h+2b)  color 0x303030
relleno  (x,   y,   w*hp/max, h) verde 0x00FF00 / amarillo 0x00FFFF / rojo 0x0000FF
umbrales  por debajo de 0.5 amarillo, por debajo de 0.25 rojo
```

Valores finales del diseño (`dct.BAR` en dc_test.lua):

```
x = 54,  y = 40,  w = 50,  h = 6,  borde = 1,  max = 1200
```

**Las dos trampas que costaron tiempo, para no repetirlas en MIPS:**

1. **Titileo.** Dibujar una línea por frame hace que parpadeen. Hay que
   encadenar las tres líneas DENTRO del mismo frame y recién ahí restaurar
   los registros.
2. **Cadena circular en la OT.** Si los rectángulos se re-enganchan más de
   una vez por frame (el breakpoint del texto se dispara 4 veces con 3
   líneas) la OT se cierra sobre sí misma y **la GPU deja de dibujar todo lo
   que sigue** — desaparecen las líneas de texto. Un flag por frame lo
   arregla. En MIPS esto no debería pasar si el enganche va en el propio
   bucle de dibujado, pero conviene tenerlo presente.

**Enganche a la OT:** puntero en `0x800AE280`, la ranura es
`base + 0x70 + profundidad*4`, y se engancha del número más alto al más bajo
para que el rectángulo 1 (el marco) quede de fondo. Profundidad en
`0x800BEC4C`; 0 = encima de todo, que es lo que resuelve el problema de que
el HUD quedaba por debajo de ciertas cámaras.

### Botón para ocultar el HUD: Triángulo (decidido, falta medir el bit)

El HUD se muestra siempre salvo que el jugador lo apague con **Triángulo**.
Triángulo está libre: no lo usa ni el esquema original ni el remapeo de v6.5.

**Lo único que falta medir antes de escribirlo:** cuál es el bit de Triángulo
en las palabras del scratchpad. En el mapa medido con `dct.btnMap()` quedaron
tres huecos: `0x0020`, `0x0100` y `0x0800`.

Hay una hipótesis fuerte, y conviene confirmarla en vez de creerle. Si se
comparan las dos palabras con la palabra estándar de botones del PSX
(`Select 0, L3 1, R3 2, Start 3, arriba 4, der 5, abajo 6, izq 7, L2 8, R2 9,
L1 10, R1 11, Triángulo 12, Círculo 13, X 14, Cuadrado 15`), lo que hay acá es
esa misma palabra **con los dos bytes dados vuelta**:

```
byteswap:  L2 0x0001  R2 0x0002  L1 0x0004  R1 0x0008
           Triangulo 0x0010  Circulo 0x0020  X 0x0040  Cuadrado 0x0080
           Select 0x0100  L3 0x0200  R3 0x0400  Start 0x0800
           arriba 0x1000  der 0x2000  abajo 0x4000  izq 0x8000
```

Eso encaja exacto con L2/R2/L1/R1, con L3/R3 y con la cruceta medidos. **Pero
choca con las etiquetas de los botones de cara**: en la medición quedaron
anotados Círculo `0x0010`, Cuadrado `0x0040` y X `0x0080`, y el byteswap dice
Triángulo `0x0010`, X `0x0040`, Cuadrado `0x0080`. Como la lectura de Triángulo
"se solapó con Cuadrado", lo más probable es que las tres etiquetas de cara
estén corridas y el byteswap sea lo correcto — pero **es exactamente el tipo de
suposición que ya salió mal antes** (el punto mirado de la cámara, los bits de
L2). Se resuelve en treinta segundos: `dct.btnMap()` apretando **solo**
Triángulo, sin tocar nada más, y después solo Círculo para confirmar el corrimiento.

Si el byteswap es correcto hay un detalle que importa: el bit de "correr
siempre" que el parche mantiene puesto (`0x0040`, anotado como Cuadrado) sería
en realidad **X**. Eso no cambia nada del comportamiento — el parche anda — pero
la etiqueta del documento estaría mal y hay que corregirla.

**Cómo funciona el interruptor:**

```
leer 0x1F80000A (recien APRETADOS, no los mantenidos: si no, parpadea)
si el bit de Triangulo esta puesto -> invertir el byte de "HUD oculto"
si el byte esta en 1 -> saltear el dibujado entero (texto y rectangulos)
```

El byte vive en la zona libre de `0x800C28F0`, no en la tira. Usar la palabra
de recién apretados y no la de mantenidos es lo que hace que sea un
interruptor y no un parpadeo a 50 Hz.

Queda para decidir cuando esté andando: si el estado se guarda entre partidas
(no hace falta, arrancar siempre con el HUD visible es más simple y no
sorprende) y si Triángulo también debería hacer algo dentro del inventario
(no: ahí el HUD no se dibuja de todos modos).

---

## 16. v6.6: el HUD en MIPS (probado en RAM: funciona)

Traducción directa de `dct.hudLive()` + `dct.bar()`. Respaldo de v6.5:
`v6/dcmod_v6.5.c`, `v6/dc6_v6.5.lua`, `v6/dcmod_v6.5.bin`.

- `hudDraw()` se llama al principio de `hookPlayer` (mismo punto que el
  prototipo Lua, `0x80045378`, solo con el jugador). Llama a `0x8005F920`
  directo desde C (tail call por `$t9`), con la pila propia del parche.
- Profundidad `[0x800BEC4C]` en 0 durante las tres líneas y restaurada después.
- Barra: dos TILE, primero el relleno y después el marco (el marco queda en la
  cabeza de la ranura `base + 0x70`). **Dos juegos de TILE** en `0x800E4400`,
  uno por OT (`0x800AE3D8` → +0, `0x800AF3D8` → +0x20), para no tocar nunca uno
  que la GPU está leyendo. Cadena en `0x800E4000`. Los dos buffers están fuera
  del blob y se reescriben enteros antes de usarse.
- Anti-ciclo en la OT: si la base de la OT es la misma que la última dibujada,
  no se hace nada (ni texto ni barra). El interruptor se evalúa después de ese
  filtro, así cuenta una vez por frame.
- Vitalidad > 2400 (basura de la pantalla de muerte) se toma como 0; > 1200 se
  recorta a 1200.
- Nombres completos armados con fragmentos: `ESCOPETA / PISTOLA /
  LANZAGRANADAS` + ` PERSONALIZADA/O` + ` + CULATA` / ` + MIRA`, según la
  variante (escopeta bit0 personalizada, bit1 culata; pistola bit1
  personalizada, bit0 mira). Tipo de munición desconocido → `?`.
- Texto en x=16, y=16/26/36, color 0x808080 (los valores por defecto de
  `dct.hud`). Línea 3 = `VIDA` + la barra.
- Bit de ocultar: variable `hudBtn` del blob, 0x0010 por defecto (hipótesis
  byteswap). Se cambia en vivo con `dc6.hudBtn(n)`; `dc6.hud(true/false)`
  muestra u oculta.
- Probado en el host (`v6/hosttest.c`, `gcc -DHOST_TEST hosttest.c dcmod.c`):
  cadenas, colores y umbrales, cadena de la OT, restauración de la
  profundidad, interruptor y anti-ciclo.
- `link.ld` exporta `_etext` y `dc6.verify()` compara el código hasta ahí.

**Blob: 5312 bytes. NO entra en el disco tal cual:** la tira de ceros tiene
4200. La RAM de destino sobra, pero el código tiene que viajar en el
ejecutable. Opciones: (A) comprimir el blob (LZSS da 3955 bytes) y que el
cargador lo descomprima, con el descompresor en la zona del payload v5
(`0x800A2F90..0x800A338C`, probada desde el disco); (B) partir el blob y llevar
~900 bytes sin comprimir en esa misma zona, que no alcanza sin recortar además
otras cosas. Las dos pasan de 8 a 9 sectores (el 164511, direcciones
`0x800A3000..0x800A37FF`).

### Triángulo, medido (`dct.btnMap()` apretando solo Triángulo, después solo Círculo)

```
Triangulo  pad+3 bit 10  ->  btn08 0040  btn0A 0040   (7 frames)
Circulo    pad+3 bit 20  ->  btn08 0010  btn0A 0010   (1 frame)
```

- **La hipótesis del byteswap era FALSA.** Triángulo no es `0x0010` (eso es
  Círculo, como decía la tabla vieja): sale como **`0x0040`**.
- `0x0040` es el bit que el parche mantiene puesto para "correr siempre", y en el
  juego original **se corre con Cuadrado** (lo confirma Nahuel). O sea que
  Triángulo y Cuadrado llegarían al MISMO bit. Sin medir todavía el porqué.
  Una suposición mía de que "correr es Triángulo en esta configuración" era
  falsa y se sacó. PENDIENTE: `dct.btnMap()` limpio con solo Cuadrado, solo X
  y solo Triángulo, y ver en el juego sin parche si Triángulo también corre.
- Consecuencia: el HUD lee Triángulo del **pad crudo** (`+3` bit `0x10`, activo en
  bajo) con flanco propio, que no depende de cómo el juego traduzca los botones. En juego, lo que
  Triángulo pudiera hacer por el bit `0x0040` lo pisa `runForce` en los dos sentidos.

### Cambios después de la primera prueba

- Oculto en cinemáticas (`inputLocked()`, la misma bandera que corta los botones).
- **Cinemáticas con la cámara original:** al subir la bandera se guarda el modo
  (hombro/original) y se pasa a original; R3/L3 no hacen nada mientras dura;
  al bajar se vuelve al modo guardado con el mismo yaw/pitch.
- Posiciones en vivo: `hudPos[8]` ({x,y} de arma, balas, VIDA, barra) y
  `hudRight` (bit n = texto n alineado a la derecha; la fuente avanza 8 px fijos,
  medido en `0x8005FA10: addiu $t1, $t1, 8`). Desde Lua: `dc6.pos()`,
  `dc6.pos('balas', 304, 16, 'der')`, `dc6.pos('barra', x, y)`, `'izq'` para
  volver a la izquierda. Los valores finales se pasan después como defaults.
- `dc6.hudBtn` ya no existe (el bit no sale del scratchpad).
- Blob: 5648 bytes.

### Abreviaturas (elegidas por Nahuel) y formato final de la línea 2

Línea 2: `<balas> - <tipo>` (ej. `17 - 9MM`, `5 - SED M`); nada cargado (tipo FF) dice solo `VACIO`; con 0 balas dice `0 - 9MM`. Las balas son las del
cargador, no las totales: está bien así.

```
armas   10 ESCOPETA   11 ESC.PER.    12 ESC.+CUL.   13 ESC.PER.+CUL.
        20 PISTOLA    21 PIST.+MIRA  22 PIST.PER.   23 PIST.PER.+M
        30 LANZAGR.   31 LANZAGR.PER.        sin arma: NADA
municion 00 SG  01 ESCORIA  02 SED L  03 SED M  04 SED F  05 VENENO  06 9MM
         07 40S&W  08 GRANADA  09 CALOR  0A GRAN INF  FF VACIO  (otro: ?)
```

Blob: 5584 bytes. OJO herramienta: un commit por `stagedPath` volvió a copiar
una versión vieja (se detectó por el tamaño). Usar SIEMPRE SendUserFile + uuid.

### Posiciones finales (elegidas por Nahuel, ya fijas en el código)

`arma=16,16  balas=16,26  vida=260,16  barra=260,26`, todo alineado a la
izquierda. `dc6.pos()` sigue sirviendo para retocar en vivo.

## 17. v6.6 en el disco: blob COMPRIMIDO (opción A)

El blob con HUD (5584 bytes) no entra en la tira (4200). Se comprime con LZSS
y lo descomprime el cargador.

- **Formato** (`v6/lzss.py`): byte de banderas, 8 elementos, bit 0 primero;
  1 = literal; 0 = copia de 2 bytes, distancia `b0 | (b1 & 0xF0) << 4`
  (1..4095), largo `(b1 & 0x0F) + 3` (3..18). Se para al llenar el destino.
  5584 → 4049 bytes (compresor óptimo por programación dinámica).
- **Cargador nuevo** (`v6/loader2.S`, 280 bytes en `0x800A2F90` = pc0): lee el
  flujo comprimido de DOS tramos que en el original son ceros y quedan en cero
  al terminar:
  - tramo 1: la zona del payload v5, `0x800A30B0..0x800A338C` (732 bytes;
    probada desde el disco en v5);
  - tramo 2: la tira, `0x800A3804..0x800A44FC` (3317 bytes; quedan 880 libres).
  Capacidad comprimida total 4932 bytes (≈ 6,8 KB sin comprimir al ritmo
  actual).
- **9 sectores** (se suma el 164511, `0x800A3000..0x800A37FF`):
  164216, 164247, 164323, 164367, 164400, 164510, 164511, 164512, 164513.
- `v6/mkdisc66.py` (corre en la nube, no en Windows) arma todo con controles:
  original por SHA-256 (`e9fc4f36…`, recuperado de `SLES_022.11.v65`), zonas en
  cero, cabeceras de sector calculadas (MSF BCD, subcabecera `00000800`) que
  reproducen las 8 conocidas, reconstrucción de los 8 sectores originales que
  reproduce sus huellas `Orig`, y descompresión simulada leyendo el ejecutable
  armado. El descompresor MIPS se probó con qemu-mipsel (idéntico, tramos en
  cero) y con un control negativo (un byte corrupto → falla).
- Salidas: `v6/SLES_022.11.v66` (SHA-256 `050a8a7e…`), `v6/grabar_v66.ps1`
  (escribe `C:\dc\disco_v66\`), `v6/comprobar_imagen.ps1` ahora con 9
  sectores y columna v6.6.
- **PENDIENTE:** arrancar `disco_v66` desde cero (sin savestate) y comprobar
  controles + HUD.

**v6.6 PROBADA DESDE EL DISCO (`disco_v66`): arranca, menú, carga y todo funciona.**
Respaldo del fuente grabado: `v6/dcmod_v6.6.c`.

## 18. v6.7 (en RAM, falta probar): pendientes de la prueba en disco

Lo que salió de jugar `disco_v66`:

1. **El HUD desaparece ~0,5 s al pasar entre dos cámaras fijas** de la misma
   habitación (el cronómetro y OBJETIVOS del juego no). SIN MEDIR. Herramienta
   nueva: `hudDraw` cuenta llamadas (`hudCnt`) y deja el motivo de la última
   (`hudWhy`: 0 dibujó, 1 OT inválida, 2 misma OT, 3 bandera de cinemática,
   4 oculto). `dc6.hudWhy()` lo registra por Vsync y avisa también si el
   enganche del jugador deja de correr.
2. **Cámara al hombro más cerca, estilo RE2/RE4 remake**, y una cámara propia
   al apuntar. Parámetros en vivo `camP[7]` = alto, distancia, lado,
   inclinación, y alto/distancia/lado apuntando (L2). La cámara se desliza
   entre los dos juegos (1/4 por frame). `dc6.cam()`, `dc6.cam('dist', 1500)`,
   `dc6.cam('a_dist', 1000)`, etc. Valores iniciales: normal 1300/2200/-350/120
   (los de siempre), apuntando 1400/1300/-550 (propuesta, a ajustar).
3. **Otra mordida (en el piso) sin medir** donde el stick vuelve a girar a
   Regina. Cambio: el control moderno (girar hacia el stick) ahora también
   exige `+3C == 01`; fuera de eso va al filtro de acciones, como la mordida
   medida. Si sigue pasando: `dct.biteWho()` en esa mordida.
4. **Cuadrado alterna el correr automático** (arranca encendido). Apagado, el
   parche no toca el bit de correr y Cuadrado corre mantenido, como el
   original. Pad crudo `+3` bit `0x80`. `dc6.run()` dice el estado.
5. **Lanzagranadas: el HUD muestra siempre 1.** El contador del grupo 3
   (`+0x248`) salió de la fórmula, nunca se midió. Medir con `dct.pdiff()`
   antes y después de un disparo, y otra vez después de recargar.
6. Después: pasar el juego entero con el parche.

Blob 5920 bytes → comprimido 4294 (entra: capacidad 4932, quedan 636 en la
tira). El disco se regenera recién cuando esto esté probado en RAM.

### v6.7, segunda vuelta (medido con `dc6.hudWhy()`)

- **Por qué desaparece el HUD en los cortes de cámara:** en cada corte el
  enganche del jugador deja de correr ~11 Vsync (v104→v115, v244→v255,
  v350→v361), con `3C=01` y el estado en `0A/0A`. El juego sigue dibujando su
  cronómetro desde otro lado. Pendiente: ver si el enganche de la cámara sí
  corre en ese hueco (`camCnt`, ahora lo informa `dc6.hudWhy()`), para dibujar
  desde ahí sin arriesgar la OT.
- **`[0x800AE280]` vale `0x800AE2D0` / `0x800AE354`**, no `0x800AE3D8` /
  `0x800AF3D8`: el doble juego de TILE por bit 12 caía siempre en el mismo.
  Ahora se alternan en cada dibujo.
- La mordida en el piso quedó resuelta con el filtro `+3C == 01` (probado).
- Triángulo (HUD) y Cuadrado (correr automático) solo cambian con `+3C == 01`:
  al machacar botones para zafarse de una mordida se prendían y apagaban solos.
- Cámara elegida: `alto=1500 dist=1700 lado=-450 incl=40`, apuntando
  `a_alto=1500 a_dist=1000 a_lado=-400` (ya fija en el código).
- Blob 5968 → comprimido 4333 (quedan 596 en la tira).

### v6.7, tercera vuelta

- `dc6.hudWhy()` con `camCnt`: **en el hueco del corte la cámara SÍ corre**.
  Arreglo: el jugador pone `camMiss = 0` cada frame; el enganche de cámara lo
  incrementa y, con 2 frames de cámara sin jugador y los dos bytes de estado en
  10 (juego), dibuja el HUD él. En juego normal nunca dibuja la cámara.
- **Error de diseño encontrado al probar eso en el host:** el filtro "misma OT
  = ya dibujado" fallaba después de un frame sin dibujo, porque hay DOS OT y se
  alternan: la OT vuelve a ser la del último dibujo y se salteaba un frame de
  más. Ahora "mismo frame" = misma OT **y** `camCnt` sin cambiar.
- Lanzagranadas: `dct.pdiff()` antes del disparo / después de la recarga NO
  muestra cambios en `+0x248` (queda en 1: carga 1, recarga 1). Candidato
  nuevo: `+0x1C0` bajó 03 → 02 (¿reserva?). Falta `dct.watch(0x800B2050, 0x10)`
  frame a frame durante disparo y recarga.
- Blob 6112 → comprimido ~4400 (entra).

### Inventario REAL de Regina (encontrado)

- Lanzagranadas: `dct.watch` confirmó que `+0x248` vale 1 SIEMPRE (no baja ni
  un frame al disparar ni al recargar). `+0x1C0` NO es la reserva (00→03 con
  4→3 granadas): es un estado.
- `dct.track()` + `menos`/`igual` sobre las granadas: 2 candidatos,
  `0x800BA295` y `0x800BEC60`. **`dct.poke(0x800BA295, 9)` → el inventario
  mostró 9 granadas.**
- Formato: casillas de 4 bytes `[objeto][cantidad][flag][00]`, empezando en
  **`0x800BA284`**. Antes hay bloques de cabecera `00 0A 00 00` + 10 casillas
  cada 0x2C (`0x800BA1D4`, `0x800BA200`, `0x800BA22C`, `0x800BA258`); el
  inventario arranca justo después del último. Casilla vacía = `00 00 01 00`;
  después de la última viene `00 00 00 00` (flag 0) y ahí se corta.
  OJO: en `0x800BA260` hay OTRAS "Balas Escoria x10" (de un bloque anterior):
  no contarlas.
- Volcado de referencia (llevando 7 objetos):
  `1B 02` Hemostático x2, `16 22` 9mm x34, `13 03` Sed.Medio x3,
  `11 0A` Escoria x10, `18 01` Granadas, `1A 01` Granadas infin., `1F 01`
  Resurrección.
- Capacidad (dice Nahuel): 10 suministros (dos pestañas de 5) y 10 objetos
  aparte. Se recorren las 10 casillas desde `0x800BA284` (hasta `0x800BA2A8`);
  vacías o con cantidad 0 no suman. PENDIENTE confirmar con un poke en la
  casilla 10 (`0x800BA2A8`).

### Línea de munición, formato B (elegido por Nahuel)

`<cargador>/<reserva> <tipo>`. La cantidad del inventario (objeto `tipo +
0x10`) es el TOTAL e incluye lo cargado (al disparar bajan los dos, medido por
Nahuel): reserva = total − cargador. Ej. 9mm x34 con 17 cargadas → `17/17 9MM`;
granadas x9 → `1/8 GRAN`. Nombres: SG, ESC, SED.L, SED.M,
SED.F, VEN, 9MM, 40SW, GRAN, CALOR, G.INF; FF → `VACIO` solo. Probado en el
host con el volcado real (cuenta las Escoria una sola vez).
Blob 6192 → comprimido 4479 (capacidad 4932; quedan ~450).

### Reserva: verificada. v6.7 lista para el disco

- Poke en la casilla 10 (`0x800BA2A8` = `16 05`): el inventario mostró las 5
  balas (el menú compacta: las casillas 6–9 vacías, aparecieron arriba de la
  segunda pestaña) y el HUD pasó a **`17/22 9MM`** = 34 + 5 − 17 cargadas.
  Las 10 casillas desde `0x800BA284` son los suministros.
- Disco: `v6/mkdisc.py` (antes `mkdisc66.py`; ahora escribe
  `SLES_022.11.v67` y `sectors67.json`), `v6/grabar_v67.ps1` →
  `C:\dc\disco_v67\`, mismos 9 sectores. `comprobar_imagen.ps1` con columna
  v6.7. SHA-256 del ejecutable v6.7: `5d9e2aa7…`. Blob 6192 → 4484 comprimido,
  quedan 448 bytes.
- PENDIENTE: probar `disco_v67` desde cero y la pasada completa del juego.

**v6.7 PROBADA DESDE EL DISCO: todo en orden.** Fuente respaldado en
`v6/dcmod_v6.7.c`.

## 19. v6.8: modo analógico automático (en RAM, falta probar)

Leído del desensamblado del ejecutable original (nada supuesto):

- El juego usa **libpad**, no el pad de la BIOS: `0x8008FC38` es
  PadInitDirect(`0x800AE288`, `0x800AE288 + 0x22`), llamada desde `0x80015384`.
  Los stubs InitPAD/StartPAD de la BIOS están pero son de la librería.
- La máquina de estados de configuración del DualShock está enlazada (comandos
  `0x43`, `0x44`, `0x45`, `0x46`, `0x47`, `0x4C`, `0x4D` en `0x8008F4xx..F5xx`).
- **PadSetMainMode está enlazado y nadie lo llama**: `0x8008DB9C(port, offs,
  lock)` → `0x8008F410`, que guarda `offs`/`lock` en +81/+82 de la estructura
  del puerto y arma el comando `0x44` con esos dos bytes (`0x8008F4A8`).
- **PadGetState** = `0x8008D824(port)`; el propio juego espera el 6 (estable)
  antes de PadSetAct (`0x80015CF4..D64`).
- Parche: en cada frame de juego, si `PadGetState(0) == 6` y el id del pad
  (`0x800AE289`) no es `0x73`, llama `PadSetMainMode(0, 1, 3)` (analógico,
  botón Analog bloqueado). Como máximo una vez por segundo mientras no lo
  consiga. Solo corre en juego (desde `hookPlayer`): el título y los menús
  quedan como estén hasta el primer frame de juego.
- Blob 6304 bytes.


## 20. CIERRE: v6.8 validada (todo lo que hace el parche)

Probado en PCSX-Redux en RAM y desde el disco; Nahuel lo dio por validado.

**Controles**
- Movimiento analógico 360° relativo a la cámara, buffer de corte de cámara.
- L2 apunta (doble stick), R2 dispara, R1 camina, **Cuadrado alterna el correr
  automático** (arranca encendido; apagado, Cuadrado corre mantenido como el
  original). X como siempre. Disparo cancelable + enfriamiento de 20 frames.
- Bloqueo en cinemáticas, empujar sin giro, mordidas (de pie y en el piso):
  el control moderno solo actúa con `+3C == 01`.
- **Modo analógico automático**: `PadSetMainMode(0, 1, 3)` de libpad (ya
  enlazado en el juego), con el botón Analog bloqueado.

**Cámara**
- Original por defecto; R3 alterna con la de hombro; L3 recentra.
- Hombro: alto 1500, dist 1700, lado −450, incl 40. Apuntando (L2): alto 1500,
  dist 1000, lado −400, con transición suave. `dc6.cam()` para retocar en RAM.
- Cinemáticas: siempre cámara original; al terminar vuelve el modo del jugador.

**HUD** (fuente chica del menú + dos TILE)
- `arma=16,16  balas=16,26  vida=260,16  barra=260,26`.
- Línea 1: nombre abreviado del arma (tabla de la sección 15). Línea 2:
  `cargador/reserva tipo` (reserva = inventario − cargado), `VACIO` sin nada
  cargado. VIDA + barra 50×6 verde/amarillo/rojo, máx 1200.
- Triángulo lo oculta/muestra (solo con `+3C == 01`). Oculto en cinemáticas.
  En los cortes de cámara lo dibuja el enganche de cámara.

**Disco**
- Blob 6304 bytes → LZSS 4566, cargador `loader2.S` en pc0, dos tramos de
  ceros (quedan 364 bytes comprimidos libres). 9 sectores:
  164216, 164247, 164323, 164367, 164400, 164510, 164511, 164512, 164513.
- `mkdisc.py` (en la nube) arma exe + sectores; `comprobar_imagen.ps1`
  reconoce limpio / v6.3 / v6.5 / v6.6 / v6.7 / v6.8.

**Correcciones a secciones viejas**
- Botones (sección 11): **Triángulo pone `0x0040`** en las palabras del
  scratchpad (medido limpio), el mismo bit que correr; en el original se corre
  con Cuadrado. El byteswap era falso. Cuadrado y X siguen sin medir limpios.
  Por eso el parche lee Triángulo y Cuadrado del PAD CRUDO (+3 bits 0x10/0x80).
- `[0x800AE280]` vale `0x800AE2D0`/`0x800AE354`, no las OT de la sección 9.
- Munición del lanzagranadas `+0x248` = 1 fijo (cargador de 1); la reserva
  está en el inventario real (`0x800BA284`, 10 casillas de suministros).
- La tabla `0x800B9F98` es la caja de emergencia, no el inventario.

**Herramientas nuevas en `dc6.lua`**: `dc6.pos()`, `dc6.cam()`, `dc6.run()`,
`dc6.hud()`, `dc6.hudWhy()` (diagnóstico por Vsync: si el HUD no se dibujó,
por qué, y si corren los enganches del jugador y de la cámara).

**Trampa de herramientas (nueva):** el commit al dispositivo por
`stagedPath` copió versiones viejas; con SendUserFile + uuid anda, pero cuando
el tamaño no cambia hay que verificar con un hash (re-stage y sha256).

**Pendientes** (actualizados en la sección 21)
1. HECHO en v6.9: saltear las cinemáticas de apertura.
2. Regenerar los parches publicables (xdelta/PPF) para v6.8 y actualizar
   `LEEME.txt`.
3. Comparar la huella del Track 1 con Redump.
4. Probar en consola real (quitar LibCrypt primero; verificar con
   `comprobar_imagen.ps1` que los 9 sectores sigan limpios) y confirmar el
   modo analógico automático con un DualShock de verdad.
5. Pasada completa del juego con v6.8.


## 21. v6.9: Start saltea todos los videos (VALIDADA en RAM y desde el disco)

Pedido: saltear la intro (antes del título: advertencia, logos, videos).
Decidido con Nahuel: **con Start**, no automático. Todo medido con
`C:\dc\dc_intro.lua` (`dci`) y volcados de RAM desensamblados.

### La intro: máquina de estados del overlay `0x80149000..0x8015CEAC`

Overlay residente (el mismo en la intro y en juego; está en los tres volcados).
Bucle en `0x801490F0`; objeto en `0x8015CEAC`: `[0]` etapa, `[1]` paso,
`[2]` sub-paso, `[3]` temporizador. Tablas `0x8014BC64` / `BC70` / `BC7C`.

| Etapa/paso | Qué es | Rutina |
|---|---|---|
| 0 | inicio; si `G+0x22` bit 0 (intro ya vista) salta directo a la etapa 2 | `0x80149148` |
| 1/0 sub 0-1 | inicio del CD + fundido de entrada | `0x80149210`, `0x80149290` |
| 1/0 sub 2 | **ADVERTENCIA**: `0x80021684` bloquea ~9,5 s = **chequeo de LibCrypt** | `0x80149290` |
| 1/1 | **logo de Capcom**: temporizador de 60 cuadros; Start (0x0800) ya lo cortaba en el original | `0x801493CC` |
| 1/2 | videos (logos de empresas, etc.) | `0x80149500` |
| 2 | fin: pone `G+0x22 \|= 1` y pasa al título | `0x801495F0` |

(`G = [0x1F800000] = 0x800B03D8`.)

**La advertencia NO se toca.** `0x80021684` inicia el CD y el sonido, arma la
trampa de LibCrypt en COP0 (`0x80090818`: BPC/BDA/DCIC), espera la lectura de
los sectores protegidos (`0x800A49C4`/`C8`), carga el recurso `0x145` en
`0x801E0800`, lo descifra con XOR usando COP0 r3 y compara la suma con
`0x283FC505`; si no coincide, cuelga en `0x800217B0`. Acortarlo es quitar la
protección. Lo que rodea son dos fundidos de <1 s.

### El reproductor de video

- `0x8014AAE0(x, y, máscara)` arranca un video. Objeto `M = 0x8015CED0`
  (`+0` estado, `+2` **máscara de botones que corta**, `+4/+6` posición).
  Pone `G+8 = 1` (video en curso). `G+0xA` = número de video (tabla de
  videos `0x800957DC`, registros de 12 bytes).
- `0x8014AB9C` = un paso por vuelta del bucle principal (tabla `0x8014BD20`):
  estado 0 `0x8014AC18` (prepara y decodifica 2 cuadros), estado 1
  `0x8014B09C` (**si `[0x800AE270] & M+2` → `G+8 = 2`**; si `G+8 == 2` pasa
  al estado 2; si no, sigue decodificando), estado 2 `0x8014B140` (cierra y
  deja `G+8 = 0`).
- `0x8014A884` pone `G+8 = 2` al terminar (cuadro fuera de rango, vuelta atrás
  o 150 llamadas sin cuadro).
- Los videos del juego ya lo llaman con **máscara `0x0800` = Start**
  (`0x80041030`, `0x80071AA4`, y `0x800EB0A8` en un overlay de juego). Los de
  la intro, con **0**.
- `0x800AE270` = botones mantenidos que guarda el lector `0x80015E94`.
  **Start = `0x0800`** en esa palabra (medido: los videos del juego se cortan
  con Start). Aunque se chequea el mantenido, dejar Start apretado NO corta
  varios videos seguidos (probado por Nahuel): no hace falta flanco.
- `0x8007FA28` = `VSync()` de libetc; `0x80014E3C` = `main()`, bucle
  principal en `0x80014FD8`. `0x800BBCE2` es el gestor de CD/sonido (tabla
  `0x8009327C`), no la escena.

### El parche

- **Enganche nuevo `0x80015268`:** `jal 0x80015BBC` → `jal stubFrame` (el nop
  del delay slot queda). `stubFrame` guarda `$ra` en la pila del bucle,
  llama `hookFrame` (hoja) y salta a `0x80015BBC` con el `$ra` original. Es un
  sitio de llamada: los temporales ya están muertos, sin ENTER/LEAVE.
- `hookFrame`: si la firma `[0x8014BD24] == 0x8014B09C`, `G` válido,
  `G+8 == 1` y `M+2 == 0` → `M+2 = 0x0800`. El corte lo hace el juego.
- Blob **6432 bytes** → LZSS 4652 (capacidad 4932: **quedan 280**).
- **10 sectores**: se suma el **164227** (el del enganche nuevo):
  164216, 164227, 164247, 164323, 164367, 164400, 164510, 164511, 164512, 164513.
  La huella `Orig` del 164227 se calculó desde el original reconstruido
  (mismo método que reproduce los otros 9); el grabador la verificó contra
  la imagen limpia al grabar.
- Controles: recompilar v6.8 da `dcmod.bin` idéntico; `mkdisc.py` con el blob
  v6.8 reproduce `SLES_022.11.v68` byte a byte; original reconstruido
  `e9fc4f36…`; datos de los 10 sectores = `SLES_022.11.v69`.
- `dc6.install()` → 6432 bytes, 5 enganches. **Para probar en RAM hay que
  instalar durante la advertencia** (antes el ejecutable no está cargado y
  pisa los enganches).
- Archivos: `v6/dcmod.c` (fuente v6.9), `v6/stubs.S`, `v6/gen.py`,
  `v6/mkdisc.py` (escribe `SLES_022.11.v69` + `sectors69.json`),
  `v6/grabar_v69.ps1`, respaldo `v6/dc6_v6.8.lua`.

### Herramienta nueva: `C:\dc\dc_intro.lua` (`dci`)

```
dci.log()    quien llama a VSync (cadena de retorno) = que escena corre;
             una linea solo cuando cambia; lect/jug por segundo; avisa Start
dci.mark(t)  marca;  dci.dump(n)  RAM 2 MB + scratchpad + registros
dci.skip()   PROTOTIPO del salteo (ya pasado a MIPS)
dci.fe()     estados de la intro (etapa/paso/sub/temporizador/fundido/Start)
```

Lección: muestrear el PC en cada Vsync no sirve, el juego vive dentro de
`VSync()`. Lo que identifica la escena es **quién llama** a `VSync`, y hay que
ignorar `VSync(1)` (la callback de Vsync del juego la llama en cada
interrupción).

### Pendientes (actualizado)

1. `comprobar_imagen.ps1`: agregar la columna v6.9 y el sector 164227.
2. Regenerar los parches publicables (xdelta/PPF) para v6.9 y actualizar
   `LEEME.txt` (sumar: Start saltea los videos).
3. Comparar la huella del Track 1 con Redump.
4. Consola real (LibCrypt primero; verificar que los 10 sectores sigan limpios)
   y confirmar el modo analógico automático con un DualShock de verdad.
5. Pasada completa del juego con v6.9.

## 22. v6.10: la cámara al hombro ve toda la sala (VALIDADA)

Pedidos de Nahuel: en la cámara al hombro (R3) se veían solo las paredes y los
dinosaurios que entraban en la cámara fija del momento; los cortes de cámara
congelaban el juego; el rumbo guardado del corte seguía activo al hombro; HUD
sin balas; fondo con efecto espejo. Todo medido con `C:\dc\dc_room.lua` (`dcr`).

### Tablas del juego (G = `[0x1F800000]` = `0x800B03D8`)

| Qué | Dónde | Registro |
|---|---|---|
| Mallas de escenario | `G+0x7CDC`, 36 × `0x88` | `+0x30` banderas (bit0 existe, bit1 visible), `+0x3C` modelo, `+0x40` padre, `+0x48` modo de orden |
| Objetos | `G+0x27C`, 11 × `0x260` (el 10 es Regina) | `+0x30` bit0 activo, bit1 visible |
| Efectos | `G+0x5FCC`, 60 × `0x7C` | |
| Modelo | `{+0 tris, +4 quads, +8 n tris, +0xA n quads}` | tri 0x28 bytes (comando `+0x1C`), quad 0x34 (comando `+0x24 \| 0x3C000000`) |

- Dibujo: prepaso de matrices `0x8006AFC0` (chequeos de bit1: objetos
  `0x8006B074`, mallas `0x8006B174`, efectos `0x8006B24C`); escenario
  `0x8006B574` (chequeo `0x8006B5C4`); lista de objetos `0x8006C168`
  (chequeo `0x8006C194`). Todo lo llama `0x8006B3B8`, en este orden:
  prepaso, **objetos/personajes** (`0x8006C244`), **escenario**
  (`0x8006B574`), `0x8006B908`, `0x8006C710`.
- Tris `0x8006DF78`, quads `0x8006E29C`. Descarte de caras traseras (NCLIP)
  en `0x8006E008` (tris) y `0x8006E364` (quads). La GPU no descarta nada.
  Bit `0x02000000` del comando = semitransparente.
- Modos de orden (`+0x48`): 0 Z mínima `0x8006B7D8` (necesita
  a2 = `0x80070000`), 1 Z máxima `0x8006B7F8`, 2 prioridad fija `0x8006B820`,
  3 pivote `0x8006B840` (t0 = `0x1F800000`). **Se queda el modo 1** (probados
  los cuatro en vivo con `dc6.sort(n)`: el 1 es el mejor; los marcos de puerta
  que se ven a través de alguna pared son límite del orden por pintor).
- OT chica de 5 casillas en `[0x800AE280]+0x70..+0x80`; `DrawOTag` arranca en
  `+0x80` (`0x800150FC`), que se dibuja primero.

### Cámara y congelamiento

- Tabla de manejadores `0x80010440` indexada por `cam+0x70` (cámara en
  `0x800B048C` = G+0xB4); el 0 = `0x8001F43C` (cámaras fijas).
- `0x8001EC34` (chequeo de zona) pone `set_flag(2,20,1)`, `cam+0x73 = 6`,
  `cam+0x72 |= 1`. Cuando la cuenta llega a 0, F43C corre el **guion de la
  cámara** (`0x8004D8C8(9, cam+0x68)` + `0x8004DA48`, contexto 9 en
  `0x800BE1C8`) y descongela.
- Palabra de congelamiento `0x800B0414` (G+0x3C) bit `0x100000`, la mira
  `0x8004285C`. Banderas: `set_flag 0x80042B48(grupo,bit,on)`,
  `check_flag 0x80042BDC`, tabla de grupos `0x800952E8`.
- El guion escribe banderas de malla con "set field" `0x8004DAFC`, caso
  `0x8004DF20/24`. Los láseres son las mallas 9–12 de su sala y los prende y
  apaga OTRO código (`0x80019A04/A24/A38/A94`). La visibilidad de dinosaurios
  la pone `0x8005B3D8`.
- Lección: `G+0x41` bit `0x800` parecía la causa del congelamiento y era
  consecuencia. Comparar **bits**, no bytes (`dcr.cut` v1 se lo perdió).

### El parche (v6.10)

- **Corte rápido** (en `hookCamera`, al hombro): si `cam+0x72 & 1` y
  `cam+0x73 > 1` → `cam+0x73 = 1` y se limpia el bit de congelamiento.
- **Re-correr el guion** al cambiar de vista (`sortOn != visPrev`, jugador
  en control, `cam+0x70 == 0`, sin corte en curso): `cam+0x73 = 1`,
  `cam+0x72 |= 1`.
- **Paredes**: `stubDA48` (sin pila: guarda `$ra` en `daRa`, marca `inCam`,
  `jal tramDA48`) + `stubMeshSet` (en `0x8004DF20`: si `inCam && sortOn &&
  (s0 & 1)` → `s0 |= 2`). Así solo se fuerza lo que escribe **el guion de la
  cámara**; lo que esconde otro código (láseres apagados, la batería de más)
  sigue escondido. La primera versión forzaba el bit1 al dibujar y mostraba
  esas cosas; la segunda usaba 24 bytes de pila del juego y colgaba en los
  cortes.
- **Objetos/dinosaurios**: `stubObjP` (`0x8006B074`) y `stubObjL`
  (`0x8006C194`): al hombro, objeto activo (bit0) = visible.
- **Dos caras**: `stubNclipQ` (`0x8006E364`): al hombro, los quads
  semitransparentes (láseres, fuentes de luz) no se descartan por NCLIP.
- **Fondo negro**: `bgClear()` encadena un TILE negro 1023×511 (dos buffers
  alternados en `0x800E4480`) en la casilla `+0x80` de la OT chica.
- **Rumbo del corte**: al hombro no se guarda (`cutHeld = NONE`).
- **HUD**: `VACIO` si no hay arma o si cargador = 0 y reserva = 0.
- Espacio: tablas trigonométricas a 33 entradas (error 0,18°) y diagnóstico
  solo con `-DDC_DIAG`.
- Pendiente de esta parte: la posible 5.ª batería del puzle (si es un objeto
  escondido por estado, `stubObjP/L` la mostraría).

### Herramienta: `C:\dc\dc_room.lua` (`dcr`)

`show`, `watch`, `flagWho`, `all`, `cut`, `pauseWho`, `gate` (busca la
compuerta por cadena de llamadas), `freezeWho`, `fastcut`, `clear`, `parts`,
`partsWatch`, `dinoA/dinoB/dinoReset` (diferencia por bits), `visWho`
(guion de cámara vs. otros escritores del bit1), `model(i)`.

## 23. v6.11: tope del buffer de dibujo (VALIDADA en Redux y DuckStation)

### El cuelgue

En DuckStation (no en Redux) el juego se colgaba al hombro mirando hacia una
zona cargada; con la cámara clásica, nunca. No era ninguna opción de
DuckStation (probado: widescreen, parche NTSC y truco apagados, uno por vez).

- El juego arma los paquetes de la GPU en **dos buffers de 128 KB pegados**:
  buffer 0 = `0x801C0000`, buffer 1 = `0x801A0000`. Puntero actual en el
  **scratchpad +4** (`0x1F800004`); lo reinicia el bucle principal en
  `0x80015174` (justo después de `DrawOTag` y del cambio de buffer). OT grande:
  `0x800AE3D8 + buffer*0x1000` (1024 entradas). Ninguna función revisa el
  límite.
- Medido con `C:\dc\dc_pk.lua` (`dcp`): en esa vista cada cuadro ocupaba
  **172 KB** (134 %, 44 588 bytes de más). El buffer 1 desbordado pisa el
  buffer 0 mientras la GPU lo está dibujando; el buffer 0 desbordado pisa
  `0x801E0000..` (hay datos). Redux ejecuta la lista de un golpe en
  `DrawOTag` y no se entera; DuckStation (y la consola) dibujan en paralelo y
  leen paquetes pisados.

### La solución: tope duro

Las 8 funciones que escriben triángulos, quads y efectos tienen el mismo lazo
(`head: addiu a1,a1,-1 ; bltz a1,SALIDA ; <delay> ; cuerpo ; j head`):

| Cabeza | Salida | Puntero | Tamaño | Delay |
|---|---|---|---|---|
| `0x8006D46C` | `0x8006D794` | t9 | 52 | nop |
| `0x8006D7C8` | `0x8006DA10` | t9 | 40 | nop |
| `0x8006DAE4` | `0x8006DCA0` | t9 | 40 | nop |
| `0x8006DD14` | `0x8006DF44` | t9 | 52 | nop |
| `0x8006DFB8` | `0x8006E150` | t9 | 40 | `addiu t7,t7,1` |
| `0x8006E2EC` | `0x8006E4F0` | t9 | 52 | `addiu t7,t7,1` |
| `0x8006E588` | `0x8006E700` | a2 | 20 | `addiu s5,s5,1` |
| `0x8006E79C` | `0x8006E96C` | a2 | 24 | `addiu s5,s5,1` |

Enganche: `head = j pkXXXX`, `head+4 = nop`. El stub (`PKCAP` en `stubs.S`)
decrementa `a1` y, si el puntero entró en los últimos `PKRES = 0x2000` bytes
de su buffer, sale del lazo por la salida normal (que guarda puntero y
contadores como siempre). Como los buffers están alineados a 128 KB:
`((ptr + PKRES) & 0x1FFFF) < PKRES`. Usa solo `$at` (ninguno de los 8 lazos
lo usa) y nada salta a `head+4`/`head+8` (verificado en todo el ejecutable).
Está siempre activo; con la cámara clásica nunca se llega.

Como el juego dibuja **personajes y objetos antes que el escenario**, lo que
se recorta cuando se llena son mallas del final de la tabla o efectos; Regina
y los dinosaurios no. Otros escritores del puntero sin tope (HUD, textos:
`0x8003EFCC`, `0x8006585C`, `0x800664C0`, `0x8006CB98`) usan ~1,4 KB después
del escenario; la reserva de 8 KB los cubre. Resultado en la zona del cuelgue:
máximo 121,4 KB, 0 desbordes en 418 cuadros; en DuckStation pasa bien.

Para comparar en vivo: `dc6.cap(false)` / `dc6.cap(true)`.

### Espacio: cargador de tres tramos

Blob 7360 bytes → LZSS 5018. Tramo 3 = la cola en cero del ejecutable
`0x800A9C60..0x800AA000` (928 bytes; el BSS del juego empieza en
`0x800A9C70` y el arranque `0x800121D4` lo limpia igual). `getb` pasa del
tramo 1 al 2 y del 2 al 3 (usa `a0`/`a1`, que el arranque escribe antes de
leer). Capacidad comprimida 5796: **quedan 776 bytes**.

- Error atrapado antes de grabar: `getb` ahora mueve `t8`, y el borrado del
  tramo 1 lo usaba como límite → borraba ~1100 bytes de datos reales entre
  los tramos 1 y 2. Arreglo: `la t8, R1END` al empezar `fin`.
- Control nuevo: `emu.py` (Unicorn) **ejecuta el cargador** sobre el
  ejecutable armado y compara la RAM al llegar a `0x800121D4` con el
  original + cargador + enganches: 0 bytes distintos, blob exacto. Validado
  primero contra v6.10 (también 0).

### Sectores: el último del ejecutable es "fin de archivo"

El tramo 3 cae en el **sector 164524**, el último del ejecutable. Su
subcabecera tiene submodo **`0x89`** (fin de registro/archivo), no `0x08`
como el resto. `mkdisc.py` armaba todos con la subcabecera de un sector común
→ la huella `Orig` no coincidía y el grabador se negó (sin tocar nada). Ahora
`raw()` toma la subcabecera **del sector real de la imagen** y compara cada
huella `Orig` con la imagen limpia (hay que subir el Track 1: 387 MB, entra
en una sola subida).

**18 sectores**: 164216, 164227, 164247, 164323, 164340, 164367, 164399,
164400, 164401, 164403, 164404, 164405, 164510, 164511, 164512, 164513,
164514, 164524.

### Herramienta: `C:\dc\dc_pk.lua` (`dcp`)

`dcp.on()` / `dcp.off()`: uso del buffer por cuadro (punto de parada en
`0x80015174`: fin = scratchpad+4, base nueva = `v0`), avisa desbordes y a qué
pisan, cuenta cuadros lentos (>2 vsyncs) y muestra la pila mínima (`0x801FFFB8`).
El contador de primitivas de scratchpad `+0x24` es acumulativo (16 bits), no
por cuadro.

### Lección de entrega

Un `device_commit_files` con `stagedPath` sobre una ruta ya subida antes
escribió el contenido **viejo** (fecha nueva, bytes viejos). Con
`SendUserFile` + `file_uuid` salió bien. Siempre re-subir y comparar SHA-256.

### Archivos

`v6/dcmod.c`, `v6/stubs.S` (respaldo `stubs_v6.11.S`), `v6/gen.py`,
`v6/dc6.lua` (7360 bytes, 18 enganches), `v6/loader2.S`, `v6/mkdisc.py`,
`v6/SLES_022.11.v611`, `v6/grabar_v611.ps1`; respaldo `v6/dcmod_v6.10.c`.

### Pendientes

1. `comprobar_imagen.ps1`: columnas v6.10/v6.11 y los 18 sectores.
2. HECHO: `C:\dc\release\DinoCrisis_Spain_ControlesModernos_v6.11.{xdelta,ppf,zip}`
   + `LEEME_v6.11.txt` (en el zip como `LEEME.txt`). xdelta 9520 B (djw,
   rechaza otra imagen); PPF 3.0 10589 B con blockcheck (`v6/mkppf.py`,
   aplicador validado con el PPF v6.3). Los dos, aplicados al Track 1 limpio,
   dan el mismo Track 1 que `grabar_v611.ps1` en la PC de Nahuel:
   SHA-1 `a808e0f1…`, MD5 `3bd2aafe…`, CRC32 `530C2DC7`. Redump sigue sin
   verificar (la página no abre desde la nube).
   **Redump: VERIFICADO** (captura de Nahuel de redump.org/disc/27940): Track 1
   y Track 2 coinciden (Track 2 SHA-1 `d9f92af2…`, MD5 `2d7b5e8e…`,
   37 396 800 B). El LEEME lo dice.
3. Huella del Track 1 contra Redump.
4. Consola real (LibCrypt primero) y DualShock de verdad.
5. Pasada completa del juego con v6.11 (atento a zonas donde el tope recorte
   algo visible: si molesta, recortar primero lo más lejano).
6. La posible 5.ª batería del puzle.

## 24. v6.12: encuadre de los puzles + repositorio (VALIDADA)

### El problema

Probando con el widescreen de DuckStation, Nahuel vio que en los puzles (vista
de cerca, "Hay tres botones.") la imagen quedaba corrida después de haber usado
la cámara al hombro, aunque se volviera a la original con R3; solo se
arreglaba al salir y volver a entrar a la habitación. También pasaba entrando
al puzle con la cámara al hombro activa.

### Medido con `C:\dc\dc_cam.lua` (`dcc`)

Fotos del objeto de cámara (`0x800B048C`, 0x100 bytes) y de las banderas de
las 36 mallas en el puzle, sin haber usado R3 (`bien`) y después (`mal`). En
el puzle: manejador `cam+0x70 = 2`, jugador `+0x3C = 04`.

- Distinto: `cam+0x38` 0 → −450 (y `cam+0x14/16`, el mismo −450 ya calculado
  por el juego en 32 bits), más `+0x6A`, `+0x7C`, `+0x80` (estado del puzle).
- Mallas: ninguna distinta.
- `dcc.put('bien')` (repone `+0x28..+0x3E`) arregló la vista en el momento →
  la causa es **`cam+0x38`**, el desplazamiento lateral: la cámara al hombro
  lo pone en −450 (`camCur[2]`), la cámara fija (manejador 0) no lo usa y la
  vista de puzle (manejador 2) sí. `+0x14` se recalcula cada cuadro.
- Mi enganche de cámara (`0x8001F3D8`) está dentro del manejador 0: con el
  manejador 2 no corre.

### El arreglo

- `hookCamera`: el primer cuadro con la cámara al hombro guarda `cam+0x38`
  (`sideSave`, `sideHeld = 1`); al volver a la original (R3) o al empezar una
  cinemática se repone (`sideRestore`).
- `hookFrame` (corre todos los cuadros): si `sideHeld` y `cam+0x70 != 0`, se
  repone ahí (escrito en línea para que `hookFrame` siga siendo hoja, sin pila;
  llamando a la función, gcc le armaba un marco de pila y duplicaba código).
- Al volver del puzle con la cámara al hombro, se vuelve a guardar el valor.
- Blob 7504 bytes → LZSS 5112; quedan **684** bytes comprimidos. Siguen siendo
  18 sectores (los mismos).
- Validado por Nahuel en RAM: R3 y volver, puzle con la cámara al hombro
  activa, cinemática.

### Track 1 v6.12

SHA-1 `766c4da22e35777e3ba803022d001808c1f64a03`, MD5
`c52f7a1b610ce297c01102301fde3415`, CRC32 `11B1D2AB`. Parches:
`DinoCrisis_Spain_ControlesModernos_v6.12.xdelta` (9604 B) y `.ppf` (10681 B)
en `C:\dc\release\`, con `LEEME_v6.12.txt` y el zip.

### Repositorio en GitHub

`https://github.com/nahuelx32/dino-crisis-modern-controls` (MIT). `src/`
(código + `mkdisc.py`, `edcecc.py`, `lzss.py`, `mkppf.py`), `lua/`, `docs/`
(`DESARROLLO.md` = este documento, `LEEME.txt`). `mkdisc.py` del repositorio
recibe el Track 1 limpio, comprueba SHA-1 del volcado de Redump y SHA-256 del
ejecutable, arma todo y (con `unicorn`) ejecuta el cargador; compilado desde
cero reproduce el Track 1 de la release byte a byte. Revisado: ningún bloque de
64 bytes del ejecutable original aparece en los archivos del repositorio.
El `.gitignore` bloquea imágenes, ejecutables, `grabar_*.ps1`, `sectors*.json`
y volcados. Esta sesión no puede subir al repositorio (no está entre los
repositorios autorizados); Nahuel sube con GitHub Desktop.
