/* cxa_thread_atexit.c -- __cxa_thread_atexit_impl para musl en Orbis.
 *
 * Un `thread_local` de C++ con destructor hace que el compilador registre ese destructor
 * con __cxa_thread_atexit, para correrlo cuando el hilo termina. libc++abi implementa esa
 * funcion llamando a __cxa_thread_atexit_impl de la libc -- y el libc++abi del SDK fue
 * compilado SUPONIENDO que la libc la trae, como glibc. musl no la trae. El sintoma es un
 * link que falla con `undefined symbol: __cxa_thread_atexit_impl` en cuanto aparece el
 * primer thread_local con destructor. En este port aparecio con openal-soft (M7):
 * `ALCcontext::sThreadContext`, que suelta el contexto de audio de un hilo al terminar.
 *
 * Esta implementacion es la misma idea que libc++abi usa cuando la libc no la provee: una
 * lista por hilo de (destructor, objeto) guardada en una clave de pthread, cuyo destructor
 * de clave la recorre al terminar el hilo. Va en el runtime y no en openal-soft porque
 * cualquier C++ futuro del port la necesita igual.
 *
 * Detalles que importan:
 *  - LIFO: los thread_local se destruyen en orden inverso a su construccion.
 *  - POSIX pone la clave en NULL ANTES de llamar a su destructor y reintenta hasta
 *    PTHREAD_DESTRUCTOR_ITERATIONS veces si un destructor registra otro: queda cubierto.
 *  - Sin __thread: la lista vive en la clave de pthread, no en TLS.
 *  - El hilo principal de este port nunca termina (ps4_idle_forever), asi que sus
 *    thread_local no se destruyen; es lo esperado y no pierde nada.
 */

#include <pthread.h>
#include <stdlib.h>

struct dtor_node {
	void (*dtor)(void *);
	void *obj;
	struct dtor_node *next;
};

static pthread_key_t  g_key;
static pthread_once_t g_once = PTHREAD_ONCE_INIT;

static void run_dtors(void *head)
{
	struct dtor_node *n = (struct dtor_node *)head;
	while (n) {
		struct dtor_node *next = n->next;
		n->dtor(n->obj);
		free(n);
		n = next;
	}
}

static void make_key(void)
{
	pthread_key_create(&g_key, run_dtors);
}

int __cxa_thread_atexit_impl(void (*dtor)(void *), void *obj, void *dso_symbol)
{
	(void)dso_symbol;                /* un solo modulo: el eboot */
	pthread_once(&g_once, make_key);
	struct dtor_node *n = (struct dtor_node *)malloc(sizeof *n);
	if (!n)
		return -1;
	n->dtor = dtor;
	n->obj  = obj;
	n->next = (struct dtor_node *)pthread_getspecific(g_key);
	pthread_setspecific(g_key, n);
	return 0;
}
