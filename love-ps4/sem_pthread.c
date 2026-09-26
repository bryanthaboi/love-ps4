/*
 * sem_* de POSIX sobre pthread (mutex + variable de condicion), en lugar de los del libc del SDK.
 *
 * ⚠ LOS DEL SDK NO FUNCIONAN (22-sep, M8). En su libc.a, sem_init(sem, 0, v) llama a
 * ksem_init(sem, v): el kernel crea el semaforo y escribe su id DENTRO del sem_t (medido: 17).
 * Pero sem_post(sem), sem_wait(sem) y compania le pasan al kernel el PUNTERO al sem_t, no ese
 * id: ksem_post(sem) -> EINVAL. sem_init "anda" (rc=0) y todo lo demas falla, siempre.
 *
 * Sintomas que produjo, los dos con openal-soft (su al::semaphore es el unico usuario de sem_*
 * en este binario, medido con objdump):
 *  - sem_wait volvia al instante con EINVAL: el hilo de eventos de openal-soft GIRABA EN VACIO
 *    desde el arranque, comiendose un nucleo entero (asi desde M7).
 *  - al cerrar el contexto (el reinicio de LOVE), sem_post fallaba, openal-soft tiraba
 *    std::system_error("Value too large..." -- mensaje fijo, no el errno real), el desarme
 *    destruia el contexto con su std::thread todavia vivo y ~thread llamaba a std::terminate.
 *
 * Por que pthread y no "arreglar" el wrapper pasandole el id al kernel: la firma real de
 * ksem_* en libkernel no esta documentada, y mutex+cond es lo que SDL y LOVE ya usan todo el
 * tiempo en esta consola.
 *
 * El sem_t del SDK mide 32 bytes; aca guarda un puntero a un bloque propio. Solo semaforos sin
 * nombre y de un solo proceso (pshared=0), que es lo unico que hay en la PS4.
 * Enlazado ANTES que libc.a: con --allow-multiple-definition gana la primera definicion, y
 * ademas los miembros sem_*.lo de libc.a dejan de hacer falta. Verificado post-link en el .oelf.
 */
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <semaphore.h>
#include <stdlib.h>
#include <time.h>

typedef struct {
	pthread_mutex_t mtx;
	pthread_cond_t cond;
	unsigned value;
} psem;

_Static_assert(sizeof(sem_t) >= sizeof(psem *), "sem_t no alcanza para guardar un puntero");

static psem *get(sem_t *sem)
{
	return sem ? *(psem **)sem : NULL;
}

int sem_init(sem_t *sem, int pshared, unsigned value)
{
	if (!sem || value > SEM_VALUE_MAX) { errno = EINVAL; return -1; }
	if (pshared) { errno = ENOSYS; return -1; }
	psem *s = calloc(1, sizeof *s);
	if (!s) { errno = ENOSPC; return -1; }
	if (pthread_mutex_init(&s->mtx, NULL) != 0) { free(s); errno = ENOSPC; return -1; }
	if (pthread_cond_init(&s->cond, NULL) != 0) {
		pthread_mutex_destroy(&s->mtx); free(s); errno = ENOSPC; return -1;
	}
	s->value = value;
	*(psem **)sem = s;
	return 0;
}

int sem_destroy(sem_t *sem)
{
	psem *s = get(sem);
	if (!s) { errno = EINVAL; return -1; }
	pthread_cond_destroy(&s->cond);
	pthread_mutex_destroy(&s->mtx);
	free(s);
	*(psem **)sem = NULL;
	return 0;
}

int sem_post(sem_t *sem)
{
	psem *s = get(sem);
	if (!s) { errno = EINVAL; return -1; }
	pthread_mutex_lock(&s->mtx);
	if (s->value >= SEM_VALUE_MAX) { pthread_mutex_unlock(&s->mtx); errno = EOVERFLOW; return -1; }
	s->value++;
	pthread_cond_signal(&s->cond);
	pthread_mutex_unlock(&s->mtx);
	return 0;
}

int sem_trywait(sem_t *sem)
{
	psem *s = get(sem);
	if (!s) { errno = EINVAL; return -1; }
	pthread_mutex_lock(&s->mtx);
	const int ok = s->value > 0;
	if (ok) s->value--;
	pthread_mutex_unlock(&s->mtx);
	if (!ok) { errno = EAGAIN; return -1; }
	return 0;
}

/* abstime == NULL: espera sin limite (asi llama sem_wait). */
int sem_timedwait(sem_t *__restrict sem, const struct timespec *__restrict abstime)
{
	psem *s = get(sem);
	if (!s) { errno = EINVAL; return -1; }
	int rc = 0;
	pthread_mutex_lock(&s->mtx);
	while (s->value == 0 && rc == 0)
		rc = abstime ? pthread_cond_timedwait(&s->cond, &s->mtx, abstime)
		             : pthread_cond_wait(&s->cond, &s->mtx);
	if (s->value > 0) { s->value--; rc = 0; }
	pthread_mutex_unlock(&s->mtx);
	if (rc) { errno = rc; return -1; }   /* ETIMEDOUT */
	return 0;
}

int sem_wait(sem_t *sem)
{
	return sem_timedwait(sem, NULL);
}

int sem_getvalue(sem_t *__restrict sem, int *__restrict valp)
{
	psem *s = get(sem);
	if (!s || !valp) { errno = EINVAL; return -1; }
	pthread_mutex_lock(&s->mtx);
	*valp = (int)s->value;
	pthread_mutex_unlock(&s->mtx);
	return 0;
}
