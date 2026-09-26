/* Shim de OpenAL para PS4. NO implementa audio.
 *
 * LÖVE construye love::audio::openal::Audio en luaopen_love_audio y, si tira
 * excepcion, cae SOLO a su backend null (wrap_Audio.cpp ~603, "Fall back to
 * nullaudio"). openal/Audio.cpp lanza si alcOpenDevice devuelve NULL. Asi que
 * con devolver NULL alcanza: love.audio existe, todas sus funciones responden,
 * el juego corre sin sonido, y no hay que tocar config.h ni boot.lua.
 *
 * Deliberadamente NO se define ALC_EXT_EFX: eso compila fuera los 34 punteros
 * EFX de Audio.h y todos los bloques guardados de Source/Effect/Filter.
 * AL_EFFECT_NULL queda igual porque Effect.h lo usa sin guarda.
 */
#ifndef AL_AL_H
#define AL_AL_H
#ifdef __cplusplus
extern "C" {
#endif

typedef char ALboolean; typedef char ALchar; typedef signed char ALbyte;
typedef unsigned char ALubyte; typedef short ALshort; typedef unsigned short ALushort;
typedef int ALint; typedef unsigned int ALuint; typedef int ALsizei; typedef int ALenum;
typedef float ALfloat; typedef double ALdouble; typedef void ALvoid;

#define AL_NONE 0
#define AL_FALSE 0
#define AL_TRUE 1
#define AL_NO_ERROR 0
#define AL_INVALID_NAME 0xA001
#define AL_INVALID_ENUM 0xA002
#define AL_INVALID_VALUE 0xA003
#define AL_INVALID_OPERATION 0xA004
#define AL_OUT_OF_MEMORY 0xA005
#define AL_EFFECT_NULL 0            /* Effect.h lo usa SIN guarda de EFX */

#define AL_SOURCE_RELATIVE 0x202
#define AL_PITCH 0x1003
#define AL_POSITION 0x1004
#define AL_DIRECTION 0x1005
#define AL_VELOCITY 0x1006
#define AL_LOOPING 0x1007
#define AL_BUFFER 0x1009
#define AL_GAIN 0x100A
#define AL_MIN_GAIN 0x100D
#define AL_MAX_GAIN 0x100E
#define AL_ORIENTATION 0x100F
#define AL_SOURCE_STATE 0x1010
#define AL_INITIAL 0x1011
#define AL_PLAYING 0x1012
#define AL_PAUSED 0x1013
#define AL_STOPPED 0x1014
#define AL_BUFFERS_QUEUED 0x1015
#define AL_BUFFERS_PROCESSED 0x1016
#define AL_REFERENCE_DISTANCE 0x1020
#define AL_ROLLOFF_FACTOR 0x1021
#define AL_CONE_OUTER_GAIN 0x1022
#define AL_MAX_DISTANCE 0x1023
#define AL_SEC_OFFSET 0x1024
#define AL_SAMPLE_OFFSET 0x1025
#define AL_BYTE_OFFSET 0x1026
#define AL_SOURCE_TYPE 0x1027
#define AL_STATIC 0x1028
#define AL_STREAMING 0x1029
#define AL_UNDETERMINED 0x1030
#define AL_FORMAT_MONO8 0x1100
#define AL_FORMAT_MONO16 0x1101
#define AL_FORMAT_STEREO8 0x1102
#define AL_FORMAT_STEREO16 0x1103
#define AL_FREQUENCY 0x2001
#define AL_BITS 0x2002
#define AL_CHANNELS 0x2003
#define AL_SIZE 0x2004
#define AL_DOPPLER_FACTOR 0xC000
#define AL_SPEED_OF_SOUND 0xC003
#define AL_DISTANCE_MODEL 0xD000
#define AL_INVERSE_DISTANCE_CLAMPED 0xD002
#define AL_CONE_INNER_ANGLE 0x1001
#define AL_CONE_OUTER_ANGLE 0x1002
#define AL_INVERSE_DISTANCE 0xD001
#define AL_LINEAR_DISTANCE 0xD003
#define AL_LINEAR_DISTANCE_CLAMPED 0xD004
#define AL_EXPONENT_DISTANCE 0xD005
#define AL_EXPONENT_DISTANCE_CLAMPED 0xD006

void        alGenBuffers(ALsizei, ALuint*);
void        alDeleteBuffers(ALsizei, const ALuint*);
void        alBufferData(ALuint, ALenum, const ALvoid*, ALsizei, ALsizei);
void        alGetBufferi(ALuint, ALenum, ALint*);
void        alGenSources(ALsizei, ALuint*);
void        alDeleteSources(ALsizei, const ALuint*);
void        alSourcef(ALuint, ALenum, ALfloat);
void        alSourcefv(ALuint, ALenum, const ALfloat*);
void        alSourcei(ALuint, ALenum, ALint);
void        alGetSourcef(ALuint, ALenum, ALfloat*);
void        alGetSourcefv(ALuint, ALenum, ALfloat*);
void        alGetSourcei(ALuint, ALenum, ALint*);
void        alSourcePlay(ALuint);
void        alSourcePlayv(ALsizei, const ALuint*);
void        alSourcePause(ALuint);
void        alSourcePausev(ALsizei, const ALuint*);
void        alSourceStop(ALuint);
void        alSourceStopv(ALsizei, const ALuint*);
void        alSourceQueueBuffers(ALuint, ALsizei, const ALuint*);
void        alSourceUnqueueBuffers(ALuint, ALsizei, ALuint*);
void        alListenerf(ALenum, ALfloat);
void        alListenerfv(ALenum, const ALfloat*);
void        alGetListenerf(ALenum, ALfloat*);
void        alGetListenerfv(ALenum, ALfloat*);
void        alDistanceModel(ALenum);
void        alDopplerFactor(ALfloat);
ALfloat     alGetFloat(ALenum);
ALenum      alGetError(void);
ALboolean   alIsExtensionPresent(const ALchar*);
void*       alGetProcAddress(const ALchar*);

#ifdef __cplusplus
}
#endif
#endif
