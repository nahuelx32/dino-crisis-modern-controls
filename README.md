# Dino Crisis — Controles modernos (PS1, PAL España)

**[English below](#english)**

**IMPORTANTE este proyecto originalmente estaba destinado a ser de uso personal como un simple regalo a otra persona, no pretende ser una versión mejorada, reemplazar y/o ser un proyecto completo de dino crisis de ps1**

Parche para **Dino Crisis** (PlayStation, versión PAL española, **SLES-02211**) que reemplaza los controles tanque por un control moderno relativo a la cámara y agrega una cámara en tercera persona al hombro. Se aplica sobre tu propia imagen del juego; este repositorio **no incluye ninguna parte del juego**.

<!-- Capturas: agregarlas en docs/img/ y enlazarlas acá, por ejemplo:
![Cámara al hombro](docs/img/hombro.png) -->

**Descarga:** el parche (`.xdelta` y `.ppf`) está en [Releases](../../releases).

## Qué hace

- Movimiento libre en 360° con stick analógico, relativo a la cámara. El modo analógico se activa solo.
- Cámara en tercera persona al hombro (R3 alterna con las cámaras fijas originales):
  - se ve toda la sala y los dinosaurios, no solo lo que entra en la cámara fija;
  - los cambios de cámara no pausan el juego en cámara al hombro;
  - láseres y luces visibles desde los dos lados.
- Apuntado de doble stick: L2 apunta, R2 dispara, el stick derecho gira la mira.
- Disparo cancelable, con una espera entre disparos parecida a la del original.
- Correr automático (Cuadrado lo activa o desactiva; R1 camina). (inspirado en dino crisis 2)
- HUD con arma, cargador/reserva (`VACIO` sin balas) y vitalidad; Triángulo lo activa o desactiva. (inspirado en VMU de la versión de Dreamcast)
- Start saltea todos los videos de apertura. La pantalla de advertencia del inicio no se saltea: ahí el juego hace su chequeo de protección.
- Cinemáticas, empujar objetos y demás acciones funcionan como en el original.

## Controles

| Botón | Acción |
|---|---|
| Stick izquierdo | mover (360°, relativo a la cámara) |
| L2 / R2 | apuntar / disparar |
| R1 (mantenido) | caminar |
| Cuadrado | correr automático sí/no |
| X | acción |
| Stick derecho | cámara al hombro; apuntando, gira la mira |
| R3 | cámara al hombro ↔ cámaras originales |
| L3 | cámara detrás de Regina |
| Triángulo | mostrar/ocultar el HUD |

## Imagen necesaria

El volcado de [Redump (disc 27940)](http://redump.org/disc/27940/), en formato `.bin`/`.cue` con su `.sbi`:

| Archivo | Tamaño | SHA-1 |
|---|---|---|
| `Dino Crisis (Spain) (Track 1).bin` | 387.317.952 | `29cda9847ddfb85e0b8c4f016654d171741798b7` |
| `Dino Crisis (Spain) (Track 2).bin` | 37.396.800 | `d9f92af296360772e62caa4cb276de3fa74f5538` |

Resultado esperado (Track 1 parcheado): SHA-1 `a808e0f1b9988bf6bbb4f387080148c9ad7dcff1`.

## Cómo aplicarlo

Parcheá **solo el Track 1**, sobre una copia:

- **xdelta** (recomendado): Delta Patcher o xdelta UI. Si la imagen no es la correcta, no se aplica.
- **PPF**: PPF-O-Matic. Solo comprueba que sea el mismo disco, no el volcado exacto.

El Track 2, el `.cue` y el `.sbi` se usan tal cual: el parche no mueve ningún sector, así que el `.sbi` de LibCrypt sigue valiendo.

**Notas:**

- Probado en PCSX-Redux y DuckStation. No probado en consola real: para consola o PS2 (POPStarter) hay que quitar LibCrypt con otra herramienta antes de aplicar el parche.
- Las partidas de memory card sirven. Los savestates de otra versión no.
- En vistas al hombro muy cargadas puede faltar parte del escenario lejano: es el límite que evita que el juego se cuelgue. Algún marco de puerta u otros objetos del escenario en una menor medida ocasionalmente pueden verse a través de una pared (límite del orden de dibujo del motor).

Más detalles en [docs/LEEME.txt](docs/LEEME.txt).

## Compilar desde el código

Hace falta Linux o WSL con `gcc-mipsel-linux-gnu`, `binutils-mipsel-linux-gnu` y Python 3 (opcional: `pip install unicorn`, para ejecutar el cargador como prueba).

```sh
cd src
sh build.sh                       # compila el parche (dcmod.bin)
python3 gen.py                   # genera layout.json y dc6.lua
python3 mkdisc.py "/ruta/Dino Crisis (Spain) (Track 1).bin"
# -> build/Dino Crisis (Spain) (Track 1).bin  (SHA-1 a808e0f1… con este código)
```

`mkdisc.py` comprueba la imagen limpia, arma el ejecutable (blob comprimido con LZSS en tres zonas en cero, más un cargador propio) y reescribe solo los 18 sectores que cambian, con EDC/ECC recalculados. Para generar parches: `xdelta3 -e -9 -S djw -s original.bin parcheado.bin salida.xdelta` o `python3 mkppf.py original.bin parcheado.bin salida.ppf "descripción"`.

| Archivo | Qué es |
|---|---|
| `src/dcmod.c` | control, cámara, HUD, visibilidad (C, MIPS R3000) |
| `src/stubs.S` | enganches en ensamblador |
| `src/gen.py` | lista de enganches → `layout.json` y `dc6.lua` |
| `src/loader2.S` | cargador: descomprime el blob al arrancar |
| `src/mkdisc.py` | arma el Track 1 parcheado |
| `lua/dc6.lua` | instala el parche en RAM desde la consola Lua de PCSX-Redux (`dofile(...)`, `dc6.install()`) |
| `lua/dc_room.lua`, `dc_pk.lua`, `dc_intro.lua` | herramientas de investigación para PCSX-Redux |
| `docs/DESARROLLO.md` | notas de desarrollo (en español): direcciones, estructuras y cómo se midió cada cosa |

## Legal

El código de este repositorio es MIT (ver [LICENSE](LICENSE)). *Dino Crisis* es © Capcom. Acá no hay ninguna parte del juego: ni imágenes, ni ejecutables, ni sectores del disco. Necesitás tu propia copia.

---

<a name="english"></a>
# Dino Crisis — Modern controls (PS1, PAL Spain)

**IMPORTANT: this project was originally meant for personal use, as a simple gift for someone. It does not aim to be an improved version, to replace the original, or to be a complete Dino Crisis PS1 project.**

A patch for **Dino Crisis** (PlayStation, Spanish PAL release, **SLES-02211**) that replaces tank controls with modern camera-relative movement and adds an over-the-shoulder third-person camera. It is applied to your own copy of the game; this repository **does not include any part of the game**.

**Download:** the patch (`.xdelta` and `.ppf`) is in [Releases](../../releases).

## Features

- Free 360° analog movement, relative to the camera. Analog mode is enabled automatically.
- Over-the-shoulder third-person camera (R3 toggles it with the original fixed cameras):
  - the whole room and the dinosaurs are visible, not only what the fixed camera would show;
  - camera changes don't pause the game in shoulder view;
  - lasers and lights are visible from both sides.
- Twin-stick aiming: L2 aims, R2 fires, the right stick turns the aim.
- Cancelable shots, with a delay between shots similar to the original.
- Auto-run (Square toggles it; R1 walks). (Inspired by Dino Crisis 2)
- HUD with weapon, magazine/reserve (`VACIO` = out of ammo) and health; Triangle toggles it. (Inspired by the VMU display in the Dreamcast version)
- Start skips all opening videos. The warning screen at startup can't be skipped: that's where the game runs its copy-protection check.
- Cutscenes, pushing objects and other actions work as in the original.

## Controls

| Button | Action |
|---|---|
| Left stick | move (360°, camera-relative) |
| L2 / R2 | aim / fire |
| R1 (hold) | walk |
| Square | toggle auto-run |
| X | action |
| Right stick | shoulder camera; while aiming, turns the aim |
| R3 | shoulder camera ↔ original cameras |
| L3 | camera behind Regina |
| Triangle | show/hide HUD |

## Required image

The [Redump dump (disc 27940)](http://redump.org/disc/27940/), in `.bin`/`.cue` format with its `.sbi`:

| File | Size | SHA-1 |
|---|---|---|
| `Dino Crisis (Spain) (Track 1).bin` | 387,317,952 | `29cda9847ddfb85e0b8c4f016654d171741798b7` |
| `Dino Crisis (Spain) (Track 2).bin` | 37,396,800 | `d9f92af296360772e62caa4cb276de3fa74f5538` |

Expected result (patched Track 1): SHA-1 `a808e0f1b9988bf6bbb4f387080148c9ad7dcff1`.

## How to apply

Patch **Track 1 only**, on a copy:

- **xdelta** (recommended): Delta Patcher or xdelta UI. If the image isn't the right one, it won't apply.
- **PPF**: PPF-O-Matic. It only checks that it's the same disc, not the exact dump.

Use Track 2, the `.cue` and the `.sbi` as they are: the patch doesn't move any sectors, so the LibCrypt `.sbi` still works.

**Notes:**

- Tested on PCSX-Redux and DuckStation. Not tested on real hardware: for a console or PS2 (POPStarter), LibCrypt must be removed with a separate tool before applying the patch.
- Memory card saves work. Savestates from other versions don't.
- In very busy shoulder-camera views, some distant scenery may be missing: this is the limit that keeps the game from freezing. Occasionally a door frame, or to a lesser extent other scenery objects, can show through a wall (a limit of the engine's draw order).

More details (in Spanish) in [docs/LEEME.txt](docs/LEEME.txt).

## Building from source

You need Linux or WSL with `gcc-mipsel-linux-gnu`, `binutils-mipsel-linux-gnu` and Python 3 (optional: `pip install unicorn`, to run the loader as a test).

```sh
cd src
sh build.sh                       # builds the patch (dcmod.bin)
python3 gen.py                    # generates layout.json and dc6.lua
python3 mkdisc.py "/path/Dino Crisis (Spain) (Track 1).bin"
# -> build/Dino Crisis (Spain) (Track 1).bin  (SHA-1 a808e0f1… with this code)
```

`mkdisc.py` checks the clean image, builds the executable (an LZSS-compressed blob stored in three zero-filled areas, plus a custom loader) and rewrites only the 18 sectors that change, with EDC/ECC recalculated. To make patches: `xdelta3 -e -9 -S djw -s original.bin patched.bin output.xdelta` or `python3 mkppf.py original.bin patched.bin output.ppf "description"`.

| File | What it is |
|---|---|
| `src/dcmod.c` | controls, camera, HUD, visibility (C, MIPS R3000) |
| `src/stubs.S` | assembly hooks |
| `src/gen.py` | hook list → `layout.json` and `dc6.lua` |
| `src/loader2.S` | loader: decompresses the blob at boot |
| `src/mkdisc.py` | builds the patched Track 1 |
| `lua/dc6.lua` | installs the patch in RAM from the PCSX-Redux Lua console (`dofile(...)`, `dc6.install()`) |
| `lua/dc_room.lua`, `dc_pk.lua`, `dc_intro.lua` | research tools for PCSX-Redux |
| `docs/DESARROLLO.md` | development notes (in Spanish): addresses, structures and how everything was measured |

## Legal

The code in this repository is MIT licensed (see [LICENSE](LICENSE)). *Dino Crisis* is © Capcom. No part of the game is included here: no images, executables or disc sectors. You need your own copy.
