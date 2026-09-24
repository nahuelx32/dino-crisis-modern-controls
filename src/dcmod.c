/*
 * dcmod.c  --  Dino Crisis (SLES-02211): control moderno, version 6 (MIPS)
 *
 * v6.10: con la camara al hombro: sin buffer de corte, cortes de camara sin
 *        la pausa de 6 cuadros, y se ven las mallas que esconde la CAMARA (no
 *        las que esconde el estado: laseres apagados, puzzles) y
 *        todos los personajes activos (los dinos fuera del encuadre fijo).
 *        HUD: sin balas (cargador 0 y reserva 0) dice VACIO. Fondo negro con
 *        la camara al hombro (sin "salon de espejos" donde no hay modelo).
 *        Con la camara al hombro lo semitransparente del escenario (laseres)
 *        se ve de los dos lados (stubNclipQ).
 * v6.9: Start saltea todos los videos (tambien los de la intro).
 * v6.8: modo analogico automatico (PadSetMainMode de libpad, ya enlazado).
 * v6.7: reserva del inventario, camara al apuntar, Cuadrado = correr si/no.
 * v6.6: HUD (arma, balas, barra de vitalidad; Triangulo lo oculta; posiciones
 *       en vivo; oculto en cinematicas). Cinematicas con la camara original.
 * v6.5: remapeo L2=apuntar/R2=disparar, correr siempre (R1=caminar), L3 recentra, disparo agil (cancelar + enfriamiento). v6.4: apuntado solo con +3C=01 (mordidas). v6.3: acciones especiales (empujar) sin giro. v6.2: arranca en camara original. v6.1: bloqueo en cinematicas. Port directo del prototipo dc_test.lua. Todo lo verificado en el emulador
 * esta en DINO_CRISIS_MOD.md; aca solo se traduce.
 *
 *   hookPlayer  (0x80045378)  movimiento analogico relativo a camara,
 *                             buffer de corte, apuntado de doble stick
 *   hookCamera  (0x8001F3D8)  camara al hombro, R3/L3 alterna con la original
 *   hookStrafe  (0x8005B29C)  gira el desplazamiento del paso (colision intacta)
 *   sortOn                    lo leen los stubs de 0x8006B81C (orden de dibujo),
 *                             stubMeshSet (mallas que esconde la camara) y los
 *                             de personajes (0x8006B074 / 0x8006C194)
 *   hookFrame   (0x80015268)  una vez por vuelta del bucle principal, desde
 *                             el arranque: Start saltea los videos
 *
 * Sin punto flotante, sin libc, sin gp. Se compila igual para el host
 * (HOST_TEST) con una RAM falsa, para probar la matematica.
 */

#include "tables.h"

#ifdef HOST_TEST
#include <stdint.h>
extern uint8_t hostRam[0x200000];
extern uint8_t hostScratch[0x400];
static inline void *P(unsigned a) {
    if ((a & 0xFFFFFC00u) == 0x1F800000u) return hostScratch + (a - 0x1F800000u);
    return hostRam + (a & 0x1FFFFF);
}
#define S16(a) (*(short *)P(a))
#define U16(a) (*(unsigned short *)P(a))
#define U8(a)  (*(unsigned char *)P(a))
#define U32(a) (*(unsigned int *)P(a))
#define PTR(a) ((char *)P(a))
#else
#define S16(a) (*(short *)(a))
#define U16(a) (*(unsigned short *)(a))
#define U8(a)  (*(unsigned char *)(a))
#define U32(a) (*(unsigned int *)(a))
#define PTR(a) ((char *)(a))
#endif

/* ------------------------------------------------------------ direcciones */
#define PLAYER   0x800B1E14u
#define CAMOBJ   0x800B048Cu
#define PAD      0x800AE288u
#define BTN_ROT  0x1F800008u      /* palabra de botones que lee la rotacion  */
#define BTN_MOV  0x1F80000Au      /* palabra de botones que lee el movimiento */

/* ------------------------------------------------------------ ajustes */
#define DEAD        30
#define DEAD2       (DEAD * DEAD)
#define TURN        280
#define CUTTHRESH   300
#define AIMTURN     90
#define AIMTURNSIGN 1
#define STRAFESIGN  (-1)

#define SH_HEIGHT   1300
#define SH_DIST     2200
#define SH_SIDE     (-350)
#define SH_UP       0
#define SH_PITCH    120
#define SH_YAWOFF   0
#define SH_SPEED    70
#define SH_PMIN     (-500)
#define SH_PMAX     600
#define SH_INVERTY  1

#define NONE 0x7FFF

/* disparo agil (prototipo dct.shotCut/shotCool, valores elegidos a gusto) */
#define SHOT_CUT    2             /* desde este frame de la animacion se puede cancelar */
#define PUMP_CUT    2             /* idem para el bombeo de la escopeta (+3E = 03)      */
#define SHOT_COOL   20            /* frames de juego entre disparos (PAL: 25 = 1 s)     */

/* banderas del juego: set_flag/check_flag (0x80042B48 / 0x80042BDC), tabla de
 * grupos 0x800952E8; grupo 2 = palabra 0x800B0414 (G+0x3C), bit 20 = objetos
 * congelados (lo mira 0x8004285C) */
#define FREEZE_WORD 0x800B0414u
#define FREEZE_BIT  0x00100000u

/* ------------------------------------------------------------ estado */
int   sortOn;                 /* 1 = camara al hombro activa: orden de dibujo por Z
                               (stubSort) y todas las mallas del cuarto (stubVis) */
int   callerSp;               /* sp del juego al entrar al stub             */
int   inCam;                  /* != 0 mientras corre el guion de la camara  */

static short cutLast = NONE, cutHeld = NONE, cutHeldStick;
static short strafeOn, strafeM, strafeB;

/* shNative = 1: se arranca con la camara ORIGINAL; R3/L3 pasa al hombro.
 * (Muchas partidas empiezan con una cinematica encuadrada por el juego.) */
static short shInit, shNative = 1, shPrevR3, shYaw, shPitch;
/* Cinematicas: se pasa a la camara original mientras dura la escena y al
 * terminar se vuelve al modo que tenia el jugador (con el mismo encuadre). */
static char shLocked, shSaved;
/* v6.12: cam+0x38 = desplazamiento lateral de la camara. La camara al hombro lo
 * pone en -450; la camara fija (manejador 0) no lo usa, pero la vista de los
 * puzles (manejador 2) si (medido con dc_cam.lua: solo +0x38 quedaba distinto
 * y reponerlo arreglaba el encuadre). Se guarda al entrar al hombro y se repone
 * al salir (R3, cinematica) o cuando la camara pasa a otro manejador. */
static short sideSave;
static char sideHeld;
static void __attribute__((noinline)) sideRestore(void)
{
    if (sideHeld) { S16(CAMOBJ + 0x38) = sideSave; sideHeld = 0; }
}
/* Parametros de la camara al hombro, ajustables en vivo (dc6.cam):
 *   [0] alto del punto mirado sobre los pies  [1] distancia  [2] lado
 *   [3] inclinacion al recentrar (L3/R3)
 *   [4..6] alto, distancia y lado APUNTANDO (L2); la camara se desliza de
 *   un juego al otro (1/4 del camino por frame). */
short camP[7] = { 1500, 1700, -450, 40, 1500, 1000, -400 };   /* elegidos por Nahuel */
static int camCur[3];             /* alto, distancia, lado actuales, x16 */
static char camSnap = 1;

/* ------------------------------------------------------------ matematica */
static int wrapS(int d) { return ((d + 2048) & 0xFFF) - 2048; }
static int iabs(int v) { return v < 0 ? -v : v; }

/* atan2(y, x) en unidades de 4096 por vuelta, 0..4095 */
static int atan2i(int y, int x)
{
    int ax = iabs(x), ay = iabs(y), a, lo, hi, t, i, f;
    if (ax == 0 && ay == 0) return 0;
    lo = ay < ax ? ay : ax;
    hi = ay < ax ? ax : ay;
    t = (lo << 12) / hi;                  /* 0..4096 */
    i = t >> 7;                           /* 0..32   */
    f = t & 127;
    a = (i >= 32) ? atanTab[32]
                  : atanTab[i] + (((atanTab[i + 1] - atanTab[i]) * f) >> 7);
    if (ay > ax) a = 1024 - a;
    if (x < 0) a = 2048 - a;
    if (y < 0) a = -a;
    return a & 0xFFF;
}

/* seno en unidades 4096, angulo 0..4095 */
static int isin(int a)
{
    int q, i, f, v;
    a &= 0xFFF;
    q = a >> 10;
    a &= 1023;
    if (q & 1) a = 1024 - a;
    i = a >> 5; f = a & 31;
    v = (i >= 32) ? sinTab[32] : sinTab[i] + (((sinTab[i + 1] - sinTab[i]) * f) >> 5);
    return (q & 2) ? -v : v;
}
static int icos(int a) { return isin(a + 1024); }

static int camYaw(void) { return atan2i(S16(CAMOBJ + 4), S16(CAMOBJ)); }

static int padAnalog(void) { return U8(PAD + 1) == 0x73; }

/* Cinematicas: 0x80015EAC mira (*[0x1F800000] + 0x40) & 4 y, si esta
 * encendido, le entrega CERO botones a Regina (0x80015EB8/EC0). El juego
 * esta manejando la escena: no tocamos ni angulo ni botones. */
static int inputLocked(void)
{
    unsigned g = U32(0x1F800000u);
    if ((g & 0xFFE00000u) != 0x80000000u) g = 0x800B03D8u;
    return (U32(g + 0x40) & 4) != 0;
}

/* ============================================================ remapeo
 * Mapa de bits medido con dct.btnMap() (las dos palabras del scratchpad son el
 * pad crudo en activo alto; 0x1F800008 = botones MANTENIDOS, 0x1F80000A = recien
 * APRETADOS, por eso se copia bit a bit en cada una):
 *   L2 0x0001  R2 0x0002  L1 0x0004  R1 0x0008  Circulo 0x0010
 *   Cuadrado 0x0040  X 0x0080  L3 0x0200  R3 0x0400
 *   cruceta arriba 0x1000  der 0x2000  abajo 0x4000  izq 0x8000
 * Con el control moderno la media vuelta de R2 no hace falta, asi que:
 *   L2 -> R1 (apuntar), R2 -> X (disparar).
 * Correr: el parche deja el boton de correr SIEMPRE apretado y R1 pasa a ser
 * "caminar" (lo suelta mientras lo mantenes). Solo en
 * juego normal (+3C = 01 y sin bloqueo de cinematica), para no meter el boton
 * de correr en menus ni en el inventario. La palabra de "recien apretados"
 * recibe el bit solo en el frame del cambio.
 * Los bits fisicos de L2 y R2 se apagan para que no disparen su accion vieja.
 * X y Cuadrado siguen funcionando como siempre.
 * OJO: despues de esto, "apuntar" en el resto del parche es el bit B_AIM del
 * scratchpad (lo pone L2); donde se lee el pad CRUDO hay que mirar L2 (0x01 de
 * +3, PAD_AIM), no R1. R1 crudo (0x08) es "caminar" (PAD_WALK).
 * Triangulo tambien llega como 0x0040 (= B_RUN, medido): con el correr
 * automatico apagado, mantener Triangulo deberia hacer correr a Regina
 * (deducido, SIN PROBAR). */
#define B_L2   0x0001
#define B_R2   0x0002
#define B_AIM  0x0008             /* el bit que el juego entiende como R1 */
#define B_RUN  0x0040
#define B_FIRE 0x0080
#define PAD_AIM  0x01             /* pad crudo +3: L2 = apuntar, activo en bajo */
#define PAD_WALK 0x08             /* pad crudo +3: R1 = caminar                */

static void btnRemap(unsigned a)
{
    int w = U16(a), r2 = (w & B_R2) != 0, l2 = (w & B_L2) != 0;
    w &= ~(B_L2 | B_R2 | B_AIM);      /* R1 (0x0008) pasa a ser caminar */
    if (l2) w |= B_AIM;
    if (r2) w |= B_FIRE;
    U16(a) = w;
}

static char runPrev, runSqPrev;
/* Cuadrado alterna el correr automatico (arranca encendido). Apagado, el
 * parche no toca el bit de correr: Cuadrado corre mientras se mantiene, como
 * en el juego original. Pad crudo +3 bit 0x80 (Cuadrado), activo en bajo. */
unsigned char runAuto = 1;

static void runForce(void)
{
    int walk = (U8(PAD + 3) & PAD_WALK) == 0;    /* pad crudo: R1 = caminar */
    int sq = (U8(PAD + 3) & 0x80) == 0, want;
    if (sq && !runSqPrev && !inputLocked() && U8(PLAYER + 0x3C) == 0x01) runAuto ^= 1;
    runSqPrev = sq;
    if (!runAuto) { runPrev = 0; return; }
    want = !walk && U8(PLAYER + 0x3C) == 0x01 && !inputLocked();
    int w8 = U16(BTN_ROT), wA = U16(BTN_MOV);

    if (want) {
        w8 |= B_RUN;
        if (runPrev) wA &= ~B_RUN; else wA |= B_RUN;
    } else {
        w8 &= ~B_RUN;
        wA &= ~B_RUN;
    }
    U16(BTN_ROT) = w8;
    U16(BTN_MOV) = wA;
    runPrev = want;
}

/* ============================================================ disparo agil
 * Medido con dct.shotWho(): apuntando (+3D=06), +3E=02 es el disparo; +078 es
 * el largo de la animacion (pistola 26) y +079 el frame actual. El juego suelta
 * a Regina recien cuando +079 llega a +078.
 *  - Cancelar: desde el frame SHOT_CUT, si hay direccion (stick o cruceta) o se
 *    suelta el apuntado (L2), +079 = +078 - 1 y el juego termina la animacion.
 *  - Enfriamiento: desde que EMPIEZA un disparo, durante SHOT_COOL frames el
 *    bit de disparo 0x0080 no llega al juego mientras se apunta (bit B_AIM). */
static unsigned short shotFrame, shotStart;
static char shotValid, shotActive;

/* Ajustables en vivo desde Lua con dc6.cut(n) / dc6.pump(n): estan en el blob,
 * asi que se pueden retocar sin recompilar (igual que dcp.turn en v5). */
unsigned char shotCut = SHOT_CUT, pumpCut = PUMP_CUT;

static void shotAgile(void)
{
    int shooting, cancelable, a3d, a3e, len, f, b8;

    btnRemap(BTN_ROT);
    btnRemap(BTN_MOV);
    runForce();
    shotFrame++;
    if (shotValid) {
        if ((unsigned short)(shotFrame - shotStart) >= SHOT_COOL) shotValid = 0;
        else {
            b8 = U16(BTN_ROT);
            if ((b8 & 0x0088) == 0x0088) {
                U16(BTN_ROT) = b8 & 0xFF7F;
                U16(BTN_MOV) = U16(BTN_MOV) & 0xFF7F;
            }
        }
    }
    /* Medido con dct.shotState(): apuntando (+3D=06), +3E es la sub-accion.
     * Pistola: 02 = disparo (largo 1A) y listo. Escopeta: 02 = disparo (17) y
     * DESPUES 03 = bombeo (10), que es lo que la dejaba clavada medio segundo.
     * Se cancelan las dos; el enfriamiento arranca solo con el disparo (02). */
    a3d = U8(PLAYER + 0x3D);
    a3e = U8(PLAYER + 0x3E);
    shooting   = a3d == 0x06 && a3e == 0x02;
    cancelable = a3d == 0x06 && (a3e == 0x02 || a3e == 0x03);
    if (shooting && !shotActive) { shotStart = shotFrame; shotValid = 1; }
    shotActive = shooting;
    if (!cancelable) return;

    len = U8(PLAYER + 0x78);
    f = U8(PLAYER + 0x79);
    if (len < 2 || f < (a3e == 0x03 ? pumpCut : shotCut) || f >= len - 1) return;
    {
        int dir = (U16(BTN_ROT) & 0xF000) != 0, aim = (U8(PAD + 3) & PAD_AIM) == 0;
        if (padAnalog()) {
            int dx = U8(PAD + 6) - 128, dy = U8(PAD + 7) - 128;
            if (dx * dx + dy * dy > DEAD2) dir = 1;
        }
        if (dir || !aim) U8(PLAYER + 0x79) = len - 1;
    }
}


/* ============================================================ HUD
 * Port de dct.hudLive() + dct.bar() (dc_test.lua). Todo medido; ver la
 * seccion 15 del .md.
 *   texto: 0x8005F920(x, y, color, cadena ASCII), fuente chica 0x20..0x5F
 *   profundidad: [0x800BEC4C]; en 0 queda encima de todo. Se restaura.
 *   barra: dos TILE (0x60) colgados de la OT, ranura = [0x800AE280] + 0x70
 *   Triangulo (palabra de recien APRETADOS 0x1F80000A) oculta / muestra.
 * Buffers fuera del blob (se reescriben enteros antes de usarlos, no hace
 * falta que arranquen en cero): cadena en 0x800E4000, TILEs en 0x800E4400
 * (dos juegos, uno por cada OT, asi nunca se toca uno que la GPU esta
 * leyendo). */
#define HUD_TEXT   0x8005F920u
#define HUD_DEPTH  0x800BEC4Cu
#define OT_PTR     0x800AE280u
#define HUD_BUF    0x800E4000u
#define RECT_BUF   0x800E4400u

#define BAR_X 54
#define BAR_Y 40
#define BAR_W 50
#define BAR_H 6
#define BAR_B 1
#define BAR_MAX 1200
#define COL_FRAME 0x303030
#define COL_FULL  0x00FF00        /* BGR */
#define COL_MID   0x00FFFF
#define COL_LOW   0x0000FF

#define HUD_COL 0x808080          /* 0x80 = textura sin modular */

/* Posiciones, ajustables en vivo desde Lua (dc6.pos): estan en el blob.
 * {x, y} de: 0 arma, 1 municion, 2 "VIDA", 3 barra (esquina del relleno).
 * hudRight: bit n = el elemento de texto n se alinea a la DERECHA (x = borde
 * derecho). La fuente chica avanza 8 px fijos por caracter (0x8005FA10:
 * addiu $t1, $t1, 8), asi que el ancho es largo * 8, exacto. */
short hudPos[8] = { 16, 16,  16, 26,  260, 16,  260, 26 };   /* elegidas por Nahuel */
unsigned char hudRight;
unsigned char hudOff;             /* 1 = oculto (Triangulo) */
static unsigned char hudPrevTri;
/* Diagnostico (dc6.hudWhy): cuantas veces se llamo y por que no dibujo la
 * ultima vez: 0 dibujo, 1 OT invalida, 2 misma OT, 3 cinematica, 4 oculto. */
unsigned short hudCnt, camCnt;     /* camCnt: llamadas del enganche de camara */
static unsigned hudFlip;
static unsigned char camMiss;
static unsigned short hudLastCam;
unsigned char hudWhy;
/* v6.10: los contadores de diagnostico solo se compilan con -DDC_DIAG (en el
 * disco no entraban: 7 bytes libres). Sin eso dc6.hudWhy() no informa nada. */
#ifdef DC_DIAG
#define WHY(n) (hudWhy = (n))
#define HUDCNT() (hudCnt++)
#else
#define WHY(n) ((void)0)
#define HUDCNT() ((void)0)
#endif
static unsigned hudLastOt;

typedef void (*TextFn)(int, int, int, const char *);

/* Nombres del HUD, abreviaturas elegidas por Nahuel. Indice del arma =
 * (grupo-1)*4 + variante (el lanzagranadas solo tiene 30 y 31: se usa v & 1). */
static const char wName[] = "ESCOPETA\0ESC.PER.\0ESC.+CUL.\0ESC.PER.+CUL.\0"
                            "PISTOLA\0PIST.+MIRA\0PIST.PER.\0PIST.PER.+M\0"
                            "LANZAGR.\0LANZAGR.PER.";
/* Tipos de municion 00..0A (codigos globales; id de inventario = tipo + 0x10),
 * FF = VACIO. No hay otros codigos en la tabla de objetos. */
static const char ammoTx[] = "SG\0ESC\0SED.L\0SED.M\0SED.F\0VEN\0"
                             "9MM\0" "40SW\0GRAN\0CALOR\0G.INF\0VACIO";

/* Inventario REAL de Regina (medido: dct.track sobre las granadas, confirmado
 * con dct.poke -> el inventario mostro 9). Casillas de 4 bytes
 * [objeto][cantidad][flag][00] desde 0x800BA284, justo despues del ultimo
 * bloque "00 0A 00 00" + 10 casillas (0x800BA258). Son los SUMINISTROS: 10
 * casillas (dos pestanas de 5; los objetos clave van aparte). Se recorren las
 * 10 enteras: una casilla vacia o con cantidad 0 no suma. */
#define INV_REAL  0x800BA284u
#define INV_MAX   10

static unsigned invCount(int id)
{
    unsigned a = INV_REAL, n = 0;
    int i;
    for (i = 0; i < INV_MAX; i++, a += 4)
        if (U8(a) == id) n += U8(a + 1);
    return n;
}

static char *putNum(char *d, unsigned v)
{
    char t[5]; int n = 0;
    do { t[n++] = '0' + v % 10; v /= 10; } while (v);
    while (n) *d++ = t[--n];
    return d;
}

static __attribute__((noinline)) const char *nth(const char *s, int n)
{
    while (n-- > 0) while (*s++) ;
    return s;
}

static __attribute__((noinline)) char *put(char *d, const char *s)
{
    while ((*d = *s++)) d++;
    return d;
}

#ifdef HOST_TEST
extern void hostText(int x, int y, int c, const char *s);
#define TEXTFN hostText
#else
#define TEXTFN ((TextFn)HUD_TEXT)
#endif
static __attribute__((noinline)) void text(int el, const char *s)
{
    int x = hudPos[el * 2];
    if (hudRight & (1 << el)) { const char *e = s; while (*e) e++; x -= (e - s) * 8; }
    TEXTFN(x, hudPos[el * 2 + 1], HUD_COL, s);
}

/* TILE (0x60): +0 etiqueta, +4 comando|color BGR, +8 y|x, +C h|w */
static __attribute__((noinline)) void tile(unsigned a, unsigned slot, unsigned yx, unsigned hw, unsigned col)
{
    U32(a + 4)  = 0x60000000u | col;
    U32(a + 8)  = yx;
    U32(a + 12) = hw;
    U32(a)      = 0x03000000u | (U32(slot) & 0xFFFFFF);
    U32(slot)   = (U32(slot) & 0xFF000000u) | (a & 0xFFFFFF);
}
#define YX(x, y) (((unsigned)(y) << 16) | (x))

__attribute__((noinline)) void hudDraw(void)
{
    char *b = PTR(HUD_BUF), *d;
    unsigned ot, rb, depth0;
    int cod, g, hp, w, col, t, m;

    ot = U32(OT_PTR);
    HUDCNT();                         /* diagnostico: dc6.hudWhy() */
    WHY(1);
    if (ot < 0x80010000u || ot >= 0x80200000u) return;
    WHY(2);
    /* Ya dibujado en ESTE frame: no re-enganchar (cadena circular en la OT).
     * Mismo frame = misma OT y el enganche de camara no volvio a correr. Solo
     * la OT no alcanza: hay dos y se alternan, asi que despues de un frame sin
     * dibujar la OT vuelve a ser la del ultimo dibujo. */
    if (ot == hudLastOt && camCnt == hudLastCam) return;
    hudLastOt = ot; hudLastCam = camCnt;

    /* Cinematicas: sin HUD (misma bandera que corta los botones). */
    WHY(3);
    if (inputLocked()) return;

    /* Triangulo, del pad CRUDO (+3 bit 0x10, activo en bajo; medido con
     * dct.btnMap). En las palabras del scratchpad Triangulo sale como 0x0040,
     * que es el bit que el juego entiende como correr segun su configuracion
     * de botones: el pad crudo no depende de esa configuracion. Flanco propio,
     * evaluado despues del filtro de OT: cuenta una vez por frame. */
    {
        /* Solo en estado normal (+3C == 01): para zafarse de una mordida se
         * aprietan todos los botones y el HUD se prendia y apagaba solo. */
        int tri = (U8(PAD + 3) & 0x10) == 0;
        if (tri && !hudPrevTri && U8(PLAYER + 0x3C) == 0x01) hudOff ^= 1;
        hudPrevTri = tri;
    }
    WHY(4);
    if (hudOff) return;
    WHY(0);

    depth0 = U32(HUD_DEPTH);
    U32(HUD_DEPTH) = 0;

    /* linea 1: nombre del arma; linea 2: "<balas> - <tipo>" */
    cod = U8(PLAYER + 0x240);
    g = cod >> 4;
    if (g < 1 || g > 3) {
        text(0, "NADA");
    } else {
        text(0, nth(wName, (g - 1) * 4 + (cod & (g == 3 ? 1 : 3))));

        /* Formato B (elegido por Nahuel): "<cargador>/<reserva> <tipo>",
         * ej. "17/17 9MM". La cantidad del inventario (objeto tipo + 0x10) es
         * el TOTAL: incluye lo que esta en el arma (al disparar bajan los
         * dos). Reserva = total - cargador. Nada cargado (tipo FF): "VACIO". */
        t = U8(PLAYER + 0x242 + g * 2);
        m = U8(PLAYER + 0x243 + g * 2);
        {
            /* v6.10: sin balas (cargador 0 y nada en el inventario) tambien
             * dice VACIO, como sin municion cargada (tipo FF). Con el cargador
             * en 0 pero reserva, sigue "0/<reserva> <tipo>" (hay que recargar). */
            unsigned tot = m == 0xFF ? 0 : invCount(m + 0x10);
            if (m == 0xFF || (t == 0 && tot == 0)) {
                put(b, nth(ammoTx, 11));
            } else {
                d = putNum(b, t);
                *d++ = '/';
                d = putNum(d, tot > (unsigned)t ? tot - t : 0);
                *d++ = ' ';
                put(d, m <= 0x0A ? nth(ammoTx, m) : "?");
            }
        }
        text(1, b);
    }
    text(2, "VIDA");
    U32(HUD_DEPTH) = depth0;

    /* linea 3: barra. Se engancha primero el relleno y despues el marco: la
     * cabeza de la ranura (lo ultimo enganchado) se dibuja primero. */
    hp = U16(PLAYER + 0x118);
    if (hp > BAR_MAX * 2) hp = 0;         /* basura de la pantalla de muerte */
    else if (hp > BAR_MAX) hp = BAR_MAX;
    w = BAR_W * hp / BAR_MAX;
    col = COL_FULL;
    if (hp * 2 < BAR_MAX) col = COL_MID;
    if (hp * 4 < BAR_MAX) col = COL_LOW;
    ot += 0x70;                           /* ranura de profundidad 0 */
    /* Dos juegos de TILE alternados en cada dibujo (el filtro de OT garantiza
     * que cada dibujo va a una OT distinta de la anterior). La cuenta vieja por
     * bit 12 no servia: [0x800AE280] vale 0x800AE2D0 / 0x800AE354 (medido con
     * dc6.hudWhy), los dos con el bit 12 en 0. */
    hudFlip ^= 0x20;
    rb = RECT_BUF + hudFlip;
    {
        int bx = hudPos[6], by = hudPos[7];
        if (w > 0) tile(rb + 16, ot, YX(bx & 0xFFFF, by), YX(w, BAR_H), col);
        tile(rb, ot, YX((bx - BAR_B) & 0xFFFF, by - BAR_B),
             YX(BAR_W + 2 * BAR_B, BAR_H + 2 * BAR_B), COL_FRAME);
    }
}

/* ============================================================ modo analogico
 * El juego usa libpad (PadInitDirect en 0x8008FC38 con los buffers
 * 0x800AE288/+0x22) y tiene PadSetMainMode enlazado pero NUNCA lo llama
 * (leido del desensamblado, sin llamadas a 0x8008DB9C):
 *   0x8008D824  PadGetState(port)          6 = estable (el juego lo usa asi
 *                                          en 0x80015D50 antes de PadSetAct)
 *   0x8008DB9C  PadSetMainMode(port, offs, lock)  -> 0x8008F410: arma el
 *               comando 0x44 con {offs, lock} (+81/+82 de la estructura)
 * Si el pad esta estable y no esta en analogico (id != 0x73), se pide
 * analogico con el boton Analog BLOQUEADO (lock 3). Una vez por segundo como
 * maximo, mientras no lo consiga; un pad digital de verdad no cambia. */
#ifdef HOST_TEST
extern int hostPadGetState(int);
extern int hostPadSetMainMode(int, int, int);
#define PadGetState    hostPadGetState
#define PadSetMainMode hostPadSetMainMode
#else
#define PadGetState    ((int (*)(int))0x8008D824u)
#define PadSetMainMode ((int (*)(int, int, int))0x8008DB9Cu)
#endif
static unsigned char anaWait;

static void analogForce(void)
{
    if (anaWait) { anaWait--; return; }
    if (U8(PAD + 1) == 0x73) return;
    if (PadGetState(0) != 6) return;
    PadSetMainMode(0, 1, 3);
    anaWait = 30;                 /* frames de juego (PAL: 25 = 1 s) */
}

/* ============================================================ jugador */
static const short dirTab[16] = {
    NONE, 0, 1024, 512, 2048, NONE, 1536, NONE,
    3072, 3584, NONE, NONE, 2560, NONE, NONE, NONE
};

void hookPlayer(int s0)
{
    int b8, camNow, stick, cam, target, cur, d, dx, dy;

    if ((unsigned)s0 != PLAYER) return;
    camMiss = 0;
    analogForce();
    hudDraw();
    shotAgile();
    camNow = camYaw();
    if (inputLocked()) { strafeOn = 0; cutHeld = NONE; cutLast = camNow; return; }
    b8 = U16(BTN_ROT);

    /* ---------------- apuntado de doble stick (bit B_AIM = L2) ----------------
     * v6.4: solo en estado normal (+3C == 01). Medido con dct.biteWho():
     * todo el apuntado (quieta, giro, caminar, disparar) es +3C=01; una
     * mordida es +3C=05 (+3D 0C/0E). Sin este filtro, con R1 el stick
     * derecho giraba a Regina en plena mordida y el empujon del dinosaurio
     * la arrastraba en circulos. Fuera de 01 cae en el filtro de acciones. */
    if ((b8 & 0x0008) && U8(PLAYER + 0x3C) == 0x01) {
        cutHeld = NONE; cutLast = camNow;
        strafeOn = 0;
        if (padAnalog()) {
            int F = U16(PLAYER + 0x2A) & 0xFFF, rx, bits = 0;
            rx = U8(PAD + 4) - 128;
            if (iabs(rx) > DEAD) {
                F = (F + (rx * AIMTURN * AIMTURNSIGN) / 128) & 0xFFF;
                U16(PLAYER + 0x2A) = F;
            }
            dx = U8(PAD + 6) - 128; dy = U8(PAD + 7) - 128;
            if (dx * dx + dy * dy > DEAD2) {
                int M = (atan2i(dx, -dy) - camNow) & 0xFFF;
                if (iabs(wrapS(M - F)) > 1024) { bits = 0x4000; strafeB = (F + 2048) & 0xFFF; }
                else                           { bits = 0x1000; strafeB = F; }
                strafeM = M; strafeOn = 1;
            }
            U16(BTN_ROT) = (b8 & 0x0FFF) | bits;
            U16(BTN_MOV) = (U16(BTN_MOV) & 0x0FFF) | bits;
        }
        return;
    }

    /* ---------------- acciones especiales (empujar, etc.) ----------------
     * Solo quieta (00), caminar (01) y correr (05) usan el control moderno.
     * Medido: empujar un estante = accion 07; el juego alinea a Regina y el
     * giro del parche la desalineaba y trababa el empuje. En cualquier otra
     * accion no tocamos el angulo: el stick se traduce a cruceta RELATIVA a
     * hacia donde mira Regina (adelante/atras/giro), o sea tanque intuitivo.
     * Sin stick, la cruceta pasa tal cual. */
    {
        int act = U8(PLAYER + 0x3D);
        /* Al soltar el boton de apuntar, +3D se queda en 06 unos frames
         * (guardar el arma) y, si el stick sigue tirado hacia atras, pasa a 02
         * (caminar de espaldas). Medido con dct.aimOut(): tratados como accion
         * especial, el stick atras se traducia a la cruceta de atras y Regina
         * se quedaba caminando de espaldas para siempre. Con el boton de
         * apuntar SUELTO, 06 y 02 usan el control moderno: gira y corre. Con
         * el boton apretado no se toca nada, asi que retroceder apuntando
         * sigue funcionando igual. */
        if ((act == 0x06 || act == 0x02) && (U8(PAD + 3) & PAD_AIM) != 0) act = 0x01;
        /* v6.6: tambien exige +3C == 01 (estado normal). Habia otra mordida
         * (en el piso) con +3C != 01 donde el control moderno giraba a Regina
         * y el dinosaurio la arrastraba: fuera de 01 va por este filtro, igual
         * que la mordida medida. */
        if ((act != 0x00 && act != 0x01 && act != 0x05) || U8(PLAYER + 0x3C) != 0x01) {
            cutHeld = NONE; cutLast = camNow; strafeOn = 0;
            if (padAnalog()) {
                dx = U8(PAD + 6) - 128; dy = U8(PAD + 7) - 128;
                if (dx * dx + dy * dy > DEAD2) {
                    int F = U16(PLAYER + 0x2A) & 0xFFF, bits;
                    d = wrapS(((atan2i(dx, -dy) - camNow) & 0xFFF) - F);
                    if (iabs(d) <= 512)       bits = 0x1000;
                    else if (iabs(d) >= 1536) bits = 0x4000;
                    else                      bits = d > 0 ? 0x2000 : 0x8000;
                    U16(BTN_ROT) = (b8 & 0x0FFF) | bits;
                    U16(BTN_MOV) = (U16(BTN_MOV) & 0x0FFF) | bits;
                }
            }
            return;
        }
    }

    /* ---------------- rumbo: stick o cruceta ---------------- */
    stick = NONE;
    if (padAnalog()) {
        dx = U8(PAD + 6) - 128; dy = U8(PAD + 7) - 128;
        if (dx * dx + dy * dy > DEAD2) stick = atan2i(dx, -dy);
    }
    if (stick == NONE) stick = dirTab[(b8 >> 12) & 15];
    if (stick == NONE) { cutHeld = NONE; cutLast = camNow; return; }

    /* ---------------- buffer de corte de camara ---------------- */
    cam = camNow;
    /* v6.10: con la camara al hombro no hay cortes (la camara es nuestra y es
     * continua). Pero en un corte de las camaras FIJAS el enganche del jugador
     * deja de correr ~11 Vsync mientras la de hombro sigue girando (stick
     * derecho, apuntado, L3): al volver, el salto de yaw parecia un corte y
     * Regina seguia con el rumbo viejo. En hombro, sin buffer. */
    if (!shNative) cutHeld = NONE;
    else if (cutHeld != NONE) {
        if (iabs(wrapS(stick - cutHeldStick)) > 512) cutHeld = NONE;
        else cam = cutHeld;
    } else if (cutLast != NONE && iabs(wrapS(camNow - cutLast)) >= CUTTHRESH) {
        cutHeld = cutLast; cutHeldStick = stick; cam = cutLast;
    }
    cutLast = camNow;

    target = (stick - cam) & 0xFFF;
    cur = U16(PLAYER + 0x2A) & 0xFFF;
    d = wrapS(target - cur);
    if (d > TURN) d = TURN; else if (d < -TURN) d = -TURN;
    U16(PLAYER + 0x2A) = (cur + d) & 0xFFF;

    U16(BTN_ROT) = (b8 & 0x1FFF) | 0x1000;
    U16(BTN_MOV) = (U16(BTN_MOV) & 0x1FFF) | 0x1000;
}

/* ============================================================ paso girado */
void hookStrafe(int s0, int sp)
{
    int dx, dz, t, c, s;
    if (!strafeOn || (unsigned)s0 != PLAYER) return;
    strafeOn = 0;
    dx = S16(sp + 0x10); dz = S16(sp + 0x14);
    t = wrapS(strafeM - strafeB) * STRAFESIGN;
    c = icos(t); s = isin(t);
    S16(sp + 0x10) = (dx * c - dz * s + 2048) >> 12;
    S16(sp + 0x14) = (dx * s + dz * c + 2048) >> 12;
}

/* ============================================================ fondo negro
 * v6.10: el juego no borra la pantalla (con las camaras fijas la geometria
 * cubre todo el encuadre). Con la camara al hombro, donde no hay modelo
 * quedaba lo del cuadro anterior ("salon de espejos"). Un TILE negro de
 * pantalla completa en la ranura +0x80 de la OT chica, que es la que se
 * dibuja PRIMERO (DrawOTag([0x800AE280] + 0x80) en 0x800150FC): todo lo
 * demas va encima. Tamano maximo (10 y 9 bits); lo recorta el area de dibujo.
 * Dos TILE alternados (nunca se toca el que la GPU puede estar leyendo) y,
 * si la ranura ya empieza con uno de los nuestros, ya se engancho en este
 * cuadro: no se repite (evita una cadena circular). Probado en Lua
 * (dcr.clear). */
static int visPrev;
#define CLR_BUF 0x800E4480u
static unsigned clrFlip;
static void bgClear(void)
{
    unsigned slot = U32(OT_PTR), h;
    if (slot < 0x80010000u || slot >= 0x80200000u) return;
    slot += 0x80;
    h = U32(slot) & 0xFFFFFF;
    if (h == (CLR_BUF & 0xFFFFFF) || h == ((CLR_BUF + 0x10) & 0xFFFFFF)) return;
    clrFlip ^= 0x10;
    tile(CLR_BUF + clrFlip, slot, 0, YX(1023, 511), 0);
}

/* ============================================================ camara */
void hookCamera(int s0)
{
    int pa, rx, ry, r3, aiming, v;

    if ((unsigned)s0 != CAMOBJ) return;
    camCnt++;
    /* En los cortes de camara el juego deja de actualizar a Regina ~11 Vsync
     * (medido con dc6.hudWhy) pero la camara sigue corriendo. Si pasaron 2
     * frames de camara sin jugador, el HUD se dibuja desde aca. En juego
     * normal esto nunca dispara (el jugador lo pone en 0 cada frame). */
    if (++camMiss >= 2) {
        camMiss = 2;
        /* solo en juego (los dos bytes de estado en 10, medido: 0A/0A en el
         * corte), para no dibujar nunca sobre menus ni transiciones */
        if (U8(0x800BAF32u) == 10 && U8(0x800BAF3Eu) == 10) hudDraw();
    }
    pa = U16(PLAYER + 0x2A) & 0xFFF;
    if (!shInit) { shInit = 1; shYaw = (pa + SH_YAWOFF) & 0xFFF; shPitch = camP[3]; }

    /* v6.10: al cambiar entre hombro y original (R3, cinematicas) se vuelve a
     * correr el guion de la camara actual, asi las mallas quedan como
     * corresponde al modo nuevo (con el hombro, stubMeshSet prende las que la
     * camara escondia). Mismo camino que un corte: cuenta 1 y pendiente; el
     * guion corre en el cuadro siguiente (0x8001F43C). Solo en juego normal y
     * sin otro cambio pendiente; si no, se reintenta el cuadro siguiente. */
    /* Solo con el manejador de camara 0 (0x8001F43C, camaras fijas: tabla
     * 0x80010440 por cam+0x70): los otros 9 usan cam+0x72/0x73 a su manera. */
    if (sortOn != visPrev && U8(PLAYER + 0x3C) == 0x01 && !inputLocked()
        && U8(CAMOBJ + 0x70) == 0 && !(U8(CAMOBJ + 0x72) & 1)) {
        U8(CAMOBJ + 0x73) = 1;
        U8(CAMOBJ + 0x72) |= 1;
        visPrev = sortOn;
    }
    sortOn = 0;
    /* Cinematica (misma bandera que corta los botones, ver inputLocked): camara
     * original mientras dure, sin atender R3/L3; al terminar, el modo que tenia
     * el jugador con el mismo yaw/pitch. */
    {
        int lk = inputLocked();
        if (lk && !shLocked) { shSaved = shNative; shNative = 1; }
        if (!lk && shLocked) shNative = shSaved;
        shLocked = lk;
        if (lk) { sideRestore(); shPrevR3 = (U8(PAD + 2) & 0x04) == 0; return; }
    }
    /* R3 alterna con la camara original; L3 recentra detras de Regina (sirve
     * corriendo, sin tener que apuntar con R1). Bits del pad crudo +2,
     * activos en bajo: R3 0x04, L3 0x02. */
    if (padAnalog()) {
        int l3;
        r3 = (U8(PAD + 2) & 0x04) == 0;
        l3 = (U8(PAD + 2) & 0x02) == 0;
        if (r3 && !shPrevR3) {
            shNative = !shNative;
            if (!shNative) { shYaw = (pa + SH_YAWOFF) & 0xFFF; shPitch = camP[3]; camSnap = 1; }
        }
        shPrevR3 = r3;
        if (l3) { shYaw = (pa + SH_YAWOFF) & 0xFFF; shPitch = camP[3]; }
    }
    if (shNative) { sideRestore(); return; }
    /* Puertas: resuelto sin codigo (en el disco la camara queda en la animacion). */

    /* v6.10: cortes de camara sin la pausa. Medido (dcr.freezeWho + desensamblado):
     * el manejador de camara (0x8001EC34, llamado por la tabla 0x80010440 justo
     * antes de este enganche) al cambiar de camara hace set_flag(2, 20, 1)
     * -> 0x8004285C saltea TODOS los objetos; cam+0x73 = 6 (cuenta) y
     * cam+0x72 |= 1 (pendiente). 0x8001F43C resta la cuenta y en 0 corre el
     * guion de la camara (mallas), toma la camara nueva y descongela.
     * Aca: cuenta a 1 (el cambio se hace en el cuadro siguiente por el camino
     * del juego) y se descongela ya. Probado en Lua (dcr.fastcut(2)). Solo con
     * Regina en estado normal: en las puertas el juego maneja la bandera solo. */
    if ((U8(CAMOBJ + 0x72) & 1) && U8(CAMOBJ + 0x73) > 1 && U8(PLAYER + 0x3C) == 0x01) {
        U8(CAMOBJ + 0x73) = 1;
        U32(FREEZE_WORD) &= ~FREEZE_BIT;
    }

    aiming = 0;
    if (padAnalog()) {
        rx = U8(PAD + 4) - 128;
        ry = U8(PAD + 5) - 128;
        aiming = (U8(PAD + 3) & PAD_AIM) == 0;   /* L2 despues del remapeo */
        if (iabs(rx) > DEAD && !aiming) shYaw += (rx * SH_SPEED) / 128;
        if (SH_INVERTY) ry = -ry;
        if (iabs(ry) > DEAD) shPitch += (ry * SH_SPEED) / 256;
        if (aiming) shYaw += wrapS(pa + SH_YAWOFF - shYaw) / 4;
    }
    if (shPitch < SH_PMIN) shPitch = SH_PMIN;
    else if (shPitch > SH_PMAX) shPitch = SH_PMAX;
    shYaw &= 0xFFF;

    if (!sideHeld) { sideSave = S16(CAMOBJ + 0x38); sideHeld = 1; }
    S16(CAMOBJ + 0x28) = shPitch;
    S16(CAMOBJ + 0x2A) = shYaw;
    S16(CAMOBJ + 0x2C) = 0;
    v = S16(PLAYER + 0x20); S16(CAMOBJ + 0x30) = v;
    {
        int i;
        for (i = 0; i < 3; i++) {
            int t = camP[(aiming ? 4 : 0) + i] << 4;
            if (camSnap) camCur[i] = t;
            else camCur[i] += (t - camCur[i]) / 4;
        }
        camSnap = 0;
    }
    v = S16(PLAYER + 0x22); S16(CAMOBJ + 0x32) = v - (camCur[0] >> 4);
    v = S16(PLAYER + 0x24); S16(CAMOBJ + 0x34) = v;
    S16(CAMOBJ + 0x38) = camCur[2] >> 4;
    S16(CAMOBJ + 0x3A) = SH_UP;
    S16(CAMOBJ + 0x3C) = camCur[1] >> 4;
    sortOn = 1;
    bgClear();
}

/* ------------------------------------------------------------ v6.9: videos
 * Reproductor de video: overlay residente en 0x80149000..0x8015CEAC (medido
 * en tres volcados: intro, video de la intro, video de juego).
 *   0x8014AAE0(x, y, mascara) arranca un video. Objeto M = 0x8015CED0,
 *   M+2 = mascara de botones que lo corta.
 *   0x8014B09C (estado 1, un cuadro por vuelta del bucle principal):
 *   si ([0x800AE270] & M+2) -> G+8 = 2 y el video se cierra solo.
 *   G = [0x1F800000]; G+8 = 1 mientras el video corre.
 * Los videos del juego ya llaman con 0x0800 (Start); los de la intro con 0.
 * Aca se pone 0x0800 si vino en 0: el corte lo hace el propio juego.
 * Firma del overlay: la tabla de estados del video en 0x8014BD24.
 */
#define VID_SIG_AT   0x8014BD24u
#define VID_SIG      0x8014B09Cu
#define VID_MASK     0x8015CED2u
#define BTN_START    0x0800u

void hookFrame(void)
{
    unsigned g;
    /* el enganche de camara solo corre con el manejador 0: si la camara pasa a
     * otro (puzles), la reposicion del desplazamiento lateral se hace aca */
    if (sideHeld && U8(CAMOBJ + 0x70) != 0) { S16(CAMOBJ + 0x38) = sideSave; sideHeld = 0; }
    if (U32(VID_SIG_AT) != VID_SIG) return;
    g = U32(0x1F800000u);
    if (g < 0x80000000u || g >= 0x80200000u) return;
    if (U16(g + 8) != 1) return;
    if (U16(VID_MASK) == 0) U16(VID_MASK) = BTN_START;
}
