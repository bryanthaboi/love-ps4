/* crashtrace.c -- deja en los registros del volcado del kernel QUIEN llamo.
 *
 * El import muere en un memcpy que escribe pasado el final de un buffer de ~400-800 KB.
 * El volcado del kernel no trae backtrace, y medido sobre el binario el porque es este:
 * memcpy, realloc y malloc de musl NO tienen .eh_frame (el desenrollador por tablas se
 * corta ahi) y el allocator de musl usa rbp como registro comun (el recorrido por rbp
 * tambien se corta). musl es un agujero negro para los dos metodos.
 *
 * No se intenta desenrollar a traves de musl. Se envuelven las dos funciones del camino:
 *
 *   __wrap_realloc   anota en globales quien lo llamo y cuanto pidio, y sigue a musl.
 *   __wrap_memcpy    hace la copia EL MISMO con `rep movsb`, asi la instruccion que
 *                    falla queda dentro de una funcion con frame pointer, y antes de
 *                    copiar carga en registros que el volcado imprime:
 *                        r13 = tamaño del ultimo realloc
 *                        r14 = quien llamo a este memcpy
 *                        r15 = quien llamo al ultimo realloc
 *
 * Lectura: simbolizar r14. Si es realloc de musl, el culpable es r15, y r13 tiene que
 * coincidir con el tamaño que se ve en los otros registros; si no coincide, otro hilo
 * piso las globales y r15 no es de fiar.
 *
 * Restricciones, todas aprendidas hoy: sin TLS (memcpy corre antes de main, mientras
 * musl arma el TLS), sin locks, sin asignar memoria, sin llamar a nada. `rep movsb`
 * solo usa rdi/rsi/rcx; la ABI garantiza DF=0 al entrar. La semantica es la de memcpy:
 * regiones solapadas son UB igual que antes.
 */

#include <stddef.h>

static void *volatile g_realloc_caller;
static size_t volatile g_realloc_n;

void *__real_realloc(void *, size_t);

__attribute__((noinline, disable_tail_calls))
void *__wrap_realloc(void *p, size_t n)
{
	g_realloc_caller = __builtin_return_address(0);
	g_realloc_n      = n;
	return __real_realloc(p, n);
}

__attribute__((noinline))
void *__wrap_memcpy(void *dst, const void *src, size_t n)
{
	void *ret = dst;
	register void  *caller  asm("r14") = __builtin_return_address(0);
	register void  *rcaller asm("r15") = g_realloc_caller;
	register size_t rn      asm("r13") = g_realloc_n;
	__asm__ volatile("rep movsb"
	                 : "+D"(dst), "+S"(src), "+c"(n)
	                 : "r"(caller), "r"(rcaller), "r"(rn)
	                 : "memory");
	return ret;
}
