/* guardalloc.c -- canarios alrededor de cada bloque, para localizar QUIEN desborda.
 *
 * DOS NIVELES
 *
 *   LOVE_PS4_GUARD_ALLOC    envuelve solo el allocator de Lua (lua_newstate).
 *   LOVE_PS4_GUARD_MALLOC   envuelve malloc/free/realloc/calloc del proceso entero,
 *                           via -Wl,--wrap. Incluye lo que pide LOVE, PhysFS,
 *                           libc++ (operator new) y cualquier decoder.
 *
 * POR QUE EL SEGUNDO NIVEL
 *
 * El primero ya corrio en hardware y NO detecto nada, con el crash intacto en
 * malloc+0x5c3. Eso descarta que el desborde pase por el allocator de Lua: una
 * cadena que se saliera de su bloque habria pisado 32 bytes de franja antes de
 * llegar a la cabecera del chunk de musl. El texto nace en Lua pero lo escribe
 * codigo C, y hay que bajar un nivel para verlo.
 *
 * LAYOUT
 *
 *     [ Blk ][ RED_PRE ][ ..... payload ..... ][ RED_POST ]
 *       32b     32b         lo que se pidio        32b
 *
 * MEMORIA ALINEADA -- LA REGLA QUE ROMPI
 *
 * Un bloque del guard NO es un chunk de musl, y nada de musl puede verlo nunca.
 * --wrap redirige toda referencia externa a malloc, incluida la de memalign.lo:
 * __memalign llamaba a __wrap_malloc, recibia un bloque nuestro, leia MI franja
 * roja (0xBEBE...) como cabecera de chunk y se lo daba a __bin_chunk. Medido en
 * el binario (`call <__wrap_malloc>` y `call <__bin_chunk>` dentro de
 * __memalign), 49 call sites, y la firma del crash era esa: r12=0xbebebebebebec000
 * es 0xbebe...beae redondeado a pagina por musl. Por eso memalign y
 * posix_memalign tambien se envuelven y se resuelven aca, y realloc nunca le
 * pasa un bloque nuestro a __real_realloc: copia y libera por su cuenta.
 *
 * PUNTEROS AJENOS
 *
 * Con --wrap, a __wrap_free pueden llegar punteros que no asignamos nosotros:
 * los devuelve una .sprx del sistema, que tiene su propio heap. Por eso free y
 * realloc comprueban el magic primero y derivan al real si no es nuestro. La
 * comprobacion lee 32 bytes antes del puntero; es seguro para todo lo que venga
 * de un heap real, y esto es un build de diagnostico.
 *
 * COSTE Y EL BARRIDO RODANTE
 *
 * 96 bytes por bloque. El barrido completo seria O(bloques vivos) y con el heap
 * entero envuelto eso son cientos de miles: inviable por operacion. Se barre un
 * TRAMO acotado por vez, avanzando un cursor que da la vuelta. Coste por barrido
 * constante, cobertura completa en varias rondas.
 */

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>
#include <pthread.h>

#include <ps4_app.h>

#define GUARD_MAGIC        0xA110C8EDu
#define GUARD_DEAD         0xDEADC8EDu
#define GUARD_RED          32u     /* a cada lado; multiplo de 16 por alineacion */
#define GUARD_PAT_PRE      0xBE
#define GUARD_PAT_POST     0xAF

#ifndef GUARD_SWEEP_EVERY
#define GUARD_SWEEP_EVERY  8192u   /* operaciones entre barridos */
#endif
#ifndef GUARD_SWEEP_SPAN
#define GUARD_SWEEP_SPAN   4096u   /* bloques mirados en cada barrido */
#endif

typedef struct Blk {
	uint32_t     magic;
	uint32_t     serial;
	size_t       size;
	struct Blk  *prev;
	struct Blk  *next;
	void        *raw;     /* lo que devolvio __real_malloc: es lo que se libera */
	uintptr_t    _pad;    /* mantiene sizeof(Blk) multiplo de 16 */
} Blk;

_Static_assert(sizeof(Blk) % 16 == 0, "Blk desalinearia el payload");
_Static_assert(GUARD_RED % 16 == 0,   "la franja roja desalinearia el payload");

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static Blk            *g_live;
static Blk            *g_cursor;        /* por donde va el barrido rodante */
static uint32_t        g_serial;
static uint32_t        g_ops;
static uint32_t        g_violations;
static size_t          g_live_count;
static int             g_armed;         /* no loguear antes de que el netlog exista */
static uintptr_t       g_lo = (uintptr_t)-1;    /* rango de bloques nuestros: */
static uintptr_t       g_hi;                    /* filtro barato para punteros ajenos */

/* REENTRADA. ps4_log() asigna memoria, y desde el guard se loguea. Sin esto:
 * __wrap_malloc toma g_lock -> check_blk -> ps4_log -> malloc -> __wrap_malloc ->
 * toma g_lock otra vez, que no es recursivo => cuelgue. Y aunque lo fuera, esa
 * asignacion anidada modificaria la lista justo cuando la estamos recorriendo.
 * Estando dentro del guard, se va directo al allocator real. */
static __thread int    g_reentry;
static int             g_on;      /* el guard no hace nada hasta armarse */

/* Toda entrada publica pasa por aca. Si ya estabamos dentro del guard, la
 * llamada es una asignacion que hizo ps4_log desde dentro: se deriva al
 * allocator real y no se toca ni el lock ni la lista. */
static inline int guard_enter(void)
{
	/* APAGADO HASTA ps4_guard_arm(). Con malloc envuelto hay ~500 asignaciones
	 * antes de main, y ahi no se puede confiar en nada: el TLS todavia no esta
	 * montado -- musl lo arma asignando memoria y copiando su plantilla con
	 * memcpy, que es exactamente donde reventaba -- y el mutex estatico tampoco
	 * esta garantizado tan temprano. Antes de armar, cada llamada va derecho al
	 * allocator real; esos bloques quedan como "ajenos" y is_ours() los deriva.
	 * Perdemos visibilidad sobre el arranque, que no es donde esta el bug. */
	if (!g_on) return 0;
	if (g_reentry) return 0;
	g_reentry = 1;
	pthread_mutex_lock(&g_lock);
	return 1;
}
static inline void guard_leave(void)
{
	pthread_mutex_unlock(&g_lock);
	g_reentry = 0;
}

#define BLK_OF(p)      ((Blk *)((char *)(p) - GUARD_RED - sizeof(Blk)))
#define PAYLOAD_OF(b)  ((void *)((char *)(b) + sizeof(Blk) + GUARD_RED))
#define TOTAL(n)       (sizeof(Blk) + GUARD_RED + (n) + GUARD_RED)
#define HDR            (sizeof(Blk) + GUARD_RED)   /* del inicio de Blk al payload */
#define RED_PRE(b)     ((unsigned char *)(b) + sizeof(Blk))
#define RED_POST(b)    ((unsigned char *)PAYLOAD_OF(b) + (b)->size)

void *__real_malloc(size_t);
void  __real_free(void *);
void *__real_realloc(void *, size_t);
void *__real_calloc(size_t, size_t);

/* Hasta 48 bytes como texto imprimible. La carga util que corrompe es ASCII, asi
 * que verla en claro identifica al que escribio mucho mas rapido que un hexdump. */
static void dump_ascii(const char *label, const unsigned char *p, size_t n)
{
	char out[64];
	size_t i, max = n < 48 ? n : 48;
	for (i = 0; i < max; i++)
		out[i] = (p[i] >= 0x20 && p[i] < 0x7f) ? (char)p[i] : '.';
	out[max] = '\0';
	ps4_log("guardalloc:   %s [%s]", label, out);
}

static int red_intact(const unsigned char *p, unsigned char pat)
{
	for (size_t i = 0; i < GUARD_RED; i++)
		if (p[i] != pat) return 0;
	return 1;
}

/* 0 si esta sano. Sin lock: los llamadores ya lo tienen. */
static int check_blk(const Blk *b, const char *when)
{
	int bad = 0;
	if (b->magic != GUARD_MAGIC) {
		if (g_armed)
			ps4_log("guardalloc: !! CABECERA PISADA en %s - magic=0x%08x blk=%p",
			        when, b->magic, (const void *)b);
		return 1;   /* size no es de fiar: no se puede seguir mirando este bloque */
	}
	if (!red_intact(RED_PRE(b), GUARD_PAT_PRE)) {
		if (g_armed) {
			ps4_log("guardalloc: !! DESBORDE POR ABAJO en %s - bloque #%u de %zu bytes",
			        when, b->serial, b->size);
			dump_ascii("franja previa", RED_PRE(b), GUARD_RED);
			dump_ascii("payload      ", (const unsigned char *)PAYLOAD_OF(b), b->size);
		}
		bad = 1;
	}
	if (!red_intact(RED_POST(b), GUARD_PAT_POST)) {
		if (g_armed) {
			ps4_log("guardalloc: !! DESBORDE POR ARRIBA en %s - bloque #%u de %zu bytes",
			        when, b->serial, b->size);
			dump_ascii("franja post  ", RED_POST(b), GUARD_RED);
			dump_ascii("payload      ", (const unsigned char *)PAYLOAD_OF(b), b->size);
		}
		bad = 1;
	}
	return bad;
}

/* Barrido rodante: un tramo acotado por vez, el cursor da la vuelta. */
static void sweep_locked(const char *when, size_t span)
{
	size_t n = 0, bad = 0;
	Blk *b = g_cursor ? g_cursor : g_live;
	while (b && n < span) {
		if (check_blk(b, when)) bad++;
		b = b->next;
		n++;
	}
	g_cursor = b;   /* NULL al llegar al final: la proxima arranca de g_live */
	if (bad) {
		g_violations += (uint32_t)bad;
		if (g_armed)
			ps4_log("guardalloc: %s - %zu bloques mirados, %zu ROTOS (acumulado %u, vivos %zu)",
			        when, n, bad, g_violations, g_live_count);
	}
}

static void maybe_sweep_locked(void)
{
	if (++g_ops % GUARD_SWEEP_EVERY) return;
	sweep_locked("barrido rodante", GUARD_SWEEP_SPAN);
}

static void link_locked(Blk *b)
{
	b->prev = NULL;
	b->next = g_live;
	if (g_live) g_live->prev = b;
	g_live = b;
	g_live_count++;
}

static void unlink_locked(Blk *b)
{
	if (g_cursor == b) g_cursor = b->next;   /* el cursor no puede quedar colgando */
	if (b->prev) b->prev->next = b->next; else g_live = b->next;
	if (b->next) b->next->prev = b->prev;
	g_live_count--;
}

/* align es potencia de 2 y >= 16. El payload queda alineado; el Blk queda
 * justo HDR bytes antes, asi BLK_OF(p) vale para cualquier alineacion. */
static void *alloc_aligned_locked(size_t n, size_t align)
{
	if (n > SIZE_MAX - TOTAL(0) - align) return NULL;
	unsigned char *raw = (unsigned char *)__real_malloc(TOTAL(n) + align);
	if (!raw) return NULL;
	uintptr_t pay = ((uintptr_t)raw + HDR + (align - 1)) & ~(uintptr_t)(align - 1);
	Blk *b = (Blk *)(pay - HDR);
	b->magic  = GUARD_MAGIC;
	b->serial = ++g_serial;
	b->size   = n;
	b->raw    = raw;
	memset(RED_PRE(b),  GUARD_PAT_PRE,  GUARD_RED);
	memset(RED_POST(b), GUARD_PAT_POST, GUARD_RED);
	if ((uintptr_t)b < g_lo) g_lo = (uintptr_t)b;
	if ((uintptr_t)b > g_hi) g_hi = (uintptr_t)b;
	link_locked(b);
	return (void *)pay;
}

static void *alloc_locked(size_t n) { return alloc_aligned_locked(n, 16); }

/* El filtro de punteros ajenos. Leer el magic implica leer 64 bytes ANTES del
 * puntero, y si viene del heap de una .sprx eso puede estar sin mapear: el
 * chequeo de seguridad se convertiria en el fallo. El rango descarta la mayoria
 * sin tocar memoria. */
static int is_ours(const void *p)
{
	uintptr_t b = (uintptr_t)p - GUARD_RED - sizeof(Blk);
	if (b < g_lo || b > g_hi) return 0;
	return ((const Blk *)b)->magic == GUARD_MAGIC;
}

/* Devuelve 1 si lo manejo, 0 si el puntero es ajeno y hay que derivar al real. */
static int free_locked(void *p)
{
	if (!is_ours(p)) return 0;
	Blk *b = BLK_OF(p);
	check_blk(b, "free");
	unlink_locked(b);
	b->magic = GUARD_DEAD;
	__real_free(b->raw);
	return 1;
}

static void *realloc_locked(void *p, size_t n, int *handled)
{
	if (!is_ours(p)) { *handled = 0; return NULL; }
	*handled = 1;
	Blk *old = BLK_OF(p);
	check_blk(old, "realloc");
	/* Nuevo + copia + libera. __real_realloc leeria nuestra cabecera como si fuera
	 * de musl. Pierde la extension en el lugar; en un build de diagnostico da igual. */
	void *q = alloc_locked(n);
	if (!q) return NULL;                      /* el viejo sigue vivo, como manda realloc */
	memcpy(q, p, old->size < n ? old->size : n);
	free_locked(p);
	return q;
}

/* Estando fuera del guard (reentrada desde ps4_log, o todavia apagado) puede
 * llegar un puntero NUESTRO. Darselo a musl es exactamente el error de memalign:
 * leeria nuestra cabecera como suya. Sin el lock no se puede tocar la lista, asi
 * que el bloque viejo se FILTRA a proposito. Perder unos bytes en un build de
 * diagnostico es barato; corromper el heap que estamos vigilando, no. */
static void bypass_free(void *p)
{
	if (!p || is_ours(p)) return;
	__real_free(p);
}
static void *bypass_realloc(void *p, size_t n)
{
	if (!is_ours(p)) return __real_realloc(p, n);
	void *q = __real_malloc(n);
	if (q) { size_t o = BLK_OF(p)->size; memcpy(q, p, o < n ? o : n); }
	return q;
}

/* ------------------------------------------------------------ allocator de Lua */

void *ps4_guard_alloc(void *ud, void *ptr, size_t osize, size_t nsize)
{
	(void)ud; (void)osize;
	if (!guard_enter()) {                       /* reentrada: al real */
		if (nsize == 0) { bypass_free(ptr); return NULL; }
		return ptr ? bypass_realloc(ptr, nsize) : __real_malloc(nsize);
	}
	void *ret = NULL;
	if (nsize == 0) {
		if (ptr && !free_locked(ptr)) __real_free(ptr);
	} else if (ptr == NULL) {
		ret = alloc_locked(nsize);
	} else {
		int handled;
		ret = realloc_locked(ptr, nsize, &handled);
		if (!handled) ret = __real_realloc(ptr, nsize);
	}
	maybe_sweep_locked();
	guard_leave();
	return ret;
}

/* ------------------------------------------------------- el heap entero (--wrap) */

#ifdef LOVE_PS4_GUARD_MALLOC

void *__wrap_malloc(size_t n)
{
	if (!guard_enter()) return __real_malloc(n);
	void *p = alloc_locked(n);
	maybe_sweep_locked();
	guard_leave();
	return p;
}

void *__wrap_calloc(size_t nmemb, size_t size)
{
	size_t n = nmemb * size;
	if (size && n / size != nmemb) return NULL;          /* desbordo el producto */
	if (!guard_enter()) return __real_calloc(nmemb, size);
	void *p = alloc_locked(n);
	if (p) memset(p, 0, n);
	maybe_sweep_locked();
	guard_leave();
	return p;
}

void __wrap_free(void *p)
{
	if (!p) return;
	if (!guard_enter()) { bypass_free(p); return; }
	int mine = free_locked(p);
	maybe_sweep_locked();
	guard_leave();
	if (!mine) __real_free(p);                            /* de una .sprx */
}

void *__wrap_realloc(void *p, size_t n)
{
	if (!p)  return __wrap_malloc(n);
	if (!n)  { __wrap_free(p); return NULL; }
	if (!guard_enter()) return bypass_realloc(p, n);
	int handled;
	void *r = realloc_locked(p, n, &handled);
	maybe_sweep_locked();
	guard_leave();
	return handled ? r : __real_realloc(p, n);
}

void *__real_memalign(size_t, size_t);
int   __real_posix_memalign(void **, size_t, size_t);

void *__wrap_memalign(size_t align, size_t n)
{
	if (align < 16) align = 16;
	if (align & (align - 1)) return NULL;                  /* no es potencia de 2 */
	if (!guard_enter()) return __real_memalign(align, n);  /* ajeno: musl lo maneja entero */
	void *p = alloc_aligned_locked(n, align);
	maybe_sweep_locked();
	guard_leave();
	return p;
}

int __wrap_posix_memalign(void **out, size_t align, size_t n)
{
	if (align < sizeof(void *) || (align & (align - 1))) return 22;   /* EINVAL */
	void *p = __wrap_memalign(align, n);
	if (!p) return 12;                                                 /* ENOMEM */
	*out = p;
	return 0;
}

#endif /* LOVE_PS4_GUARD_MALLOC */

/* ------------------------------------------------------------------- control */

/* ENCIENDE el guard. Hasta aca todo fue derecho al allocator real, porque antes
 * de main no hay TLS ni netlog. Llamarlo justo despues de ps4_app_init(), que es
 * el primer momento en que se puede loguear y el ultimo antes de que arranquen
 * los hilos. */
void ps4_guard_arm(void)
{
	/* Sin guard_enter(): con g_on en 0 devolveria "reentrada" y nos dejaria sin
	 * unlock. Aca no hay nadie dentro del guard todavia, por definicion. */
	g_armed = 1;
	ps4_log("guardalloc: ENCENDIDO - lo de antes de main va sin vigilar (sin TLS);"
	        " franja %u b, barrido %u bloques cada %u ops",
	        GUARD_RED, GUARD_SWEEP_SPAN, GUARD_SWEEP_EVERY);
	/* El log de arriba asigna memoria: encender DESPUES, para que esa asignacion
	 * salga por el camino real y no se cuente como bloque nuestro. */
	g_on = 1;
}

void ps4_guard_sweep(const char *when)
{
	if (!guard_enter()) return;            /* apagado, o ya estamos dentro */
	g_cursor = NULL;                       /* barrido COMPLETO, a pedido */
	sweep_locked(when ? when : "a pedido", (size_t)-1);
	ps4_log("guardalloc: barrido completo '%s' - %zu vivos, %u violaciones",
	        when ? when : "a pedido", g_live_count, g_violations);
	guard_leave();
}

void ps4_guard_report(void)
{
	if (!guard_enter()) return;
	ps4_log("guardalloc: %zu vivos, %u asignaciones, %u violaciones",
	        g_live_count, g_serial, g_violations);
	guard_leave();
}
