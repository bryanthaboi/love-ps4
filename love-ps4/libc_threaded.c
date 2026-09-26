/* libc_threaded.c -- activa el lock del allocator de musl en Orbis.
 *
 * EL PROBLEMA
 *
 * musl protege malloc/free/realloc con un lock condicional:
 *
 *     if (libc.threaded) { while (a_swap(lk,1)) __wait(lk,lk+1,1,1); }
 *
 * El flag lo pone a 1 el `pthread_create` de musl la primera vez que el proceso
 * crea un hilo.  Pero en este binario `pthread_create` no es el de musl: es el
 * shim de orbis-compat sobre `scePthreadCreate`, que heredo el nombre y no esa
 * responsabilidad.  Resultado medido sobre el .oelf: las NUEVE referencias a
 * `__libc+0xc` en toda la imagen son `cmpl $0x0` -- lecturas.  Nadie lo escribe.
 *
 * Con el flag en 0 todos los locks del allocator son no-ops y los ocho hilos de
 * LOVE asignan memoria sin sincronizar.  El sintoma fue un SIGBUS dentro del
 * unlink de la free-list (malloc+0x5a4/0x5c3/0x5ea/0x643, offset distinto cada
 * vez) con los punteros del chunk pisados por texto ASCII: un hilo escribiendo
 * su string dentro de un chunk que el otro daba por libre.
 *
 * EL OFFSET
 *
 * `threaded` no esta en el offset que da el musl de upstream (ahi es 1, y 4 en
 * las versiones viejas): este libc es un fork y la estructura es otra.  0xc esta
 * MEDIDO sobre el binario, no deducido de la cabecera.
 *
 * Un numero magico contra un interno de libc es de las cosas que se rompen en
 * silencio, y aca romperse en silencio significa corromper el heap.  Por eso
 * `tools/verify-libc-threaded.sh` lo vuelve a derivar del binario despues de
 * linkear -- desensambla malloc, lee el operando del gate y le resta `__libc` --
 * y hace fallar el build si no coincide.  El valor vive en un solo lugar (el
 * -D del CMakeLists) y se verifica contra el artefacto que se termina enviando.
 */

#ifndef LOVE_PS4_LIBC_THREADED_OFFSET
#error "falta -DLOVE_PS4_LIBC_THREADED_OFFSET (ver tools/verify-libc-threaded.sh)"
#endif

/* `D __libc` en libc.lo: global, hidden.  Hidden se resuelve igual dentro de la
 * misma imagen enlazada, que es como los propios .c de musl lo comparten.  Se
 * declara como array de char para poder direccionarlo sin conocer la struct. */
extern char __libc[] __attribute__((visibility("hidden")));

/* Devuelve el valor ANTERIOR, para que quien llame lo pueda loguear y se vea en
 * hardware si el supuesto valia.  Hay que llamarla antes de crear ningun hilo. */
int ps4_libc_enable_malloc_locking(void)
{
	volatile int *threaded =
		(volatile int *)(void *)(__libc + LOVE_PS4_LIBC_THREADED_OFFSET);

	int before = *threaded;
	*threaded = 1;
	return before;
}
