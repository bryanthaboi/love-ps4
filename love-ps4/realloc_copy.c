/* realloc_copy.c -- realloc como "nuevo + copia + libera", sin tocar el realloc de musl.
 *
 * ES EL ARREGLO DEL IMPORT. Empezo como experimento de biseccion (22-sep): Con el allocator con canarios encendido, el import de
 * gen1recomp paso 2 de 2 veces sin que el guard reportara un solo desborde; sin el guard
 * fallo en todas las corridas. El guard reemplaza tres cosas: la disposicion de los
 * bloques, memalign y realloc. Este archivo reemplaza SOLO realloc, del mismo modo que el
 * guard (nuevo + copia + libera), para aislar esa pieza.
 *
 * Sospecha: Lua 5.1 arma las cadenas grandes (las tablas serializadas que aparecian
 * pisando la free-list) en un buffer que agranda con realloc, y los registros del crash
 * (0x68000 -> 0x6c000) son ese buffer creciendo.
 *
 * RESULTADO: con este archivo y nada mas, el import pasa. El problema esta en el realloc de
 * musl sobre esta plataforma (mremap es un stub y los mapeos grandes vienen de orbis_mmap),
 * no en quien escribe. El POR QUE todavia no esta probado: ver tasks/todo.md.
 */

#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <malloc.h>

void *__wrap_realloc(void *p, size_t n)
{
	if (!p) return malloc(n);
	if (!n) { free(p); return NULL; }
	size_t old = malloc_usable_size(p);
	void *q = malloc(n);
	if (!q) return NULL;              /* el viejo sigue vivo, como manda realloc */
	memcpy(q, p, old < n ? old : n);
	free(p);
	return q;
}
