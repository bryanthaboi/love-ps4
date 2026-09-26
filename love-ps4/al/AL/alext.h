/* Extensiones de OpenAL: DELIBERADAMENTE VACIO.
 *
 * LOVE incluye este header junto a al.h/alc.h (Pool.h, Audio.h, Source.h,
 * Effect.h, Filter.h, RecordingDevice.h). Su contenido real definiria
 * ALC_EXT_EFX, y ESO es lo que queremos evitar: con EFX indefinido, LOVE
 * compila fuera los 34 punteros de efectos de Audio.h y todos los bloques
 * guardados de Source/Effect/Filter. Son ~34 funciones que el shim no tiene
 * que implementar.
 *
 * La unica excepcion es AL_EFFECT_NULL, que Effect.h usa SIN guarda de EFX;
 * esta definido en al.h.
 */
#ifndef AL_ALEXT_H
#define AL_ALEXT_H
#include <AL/al.h>
#include <AL/alc.h>
/* sin ALC_EXT_EFX a proposito */
#endif
