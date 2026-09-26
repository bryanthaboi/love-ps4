/* Shim de ALC para PS4. alcOpenDevice devuelve NULL a proposito: es lo que
 * hace que LOVE caiga a nullaudio por su propio camino de excepcion. */
#ifndef AL_ALC_H
#define AL_ALC_H
#include <AL/al.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct ALCdevice ALCdevice;
typedef struct ALCcontext ALCcontext;
typedef char ALCboolean; typedef char ALCchar; typedef int ALCint;
typedef unsigned int ALCuint; typedef int ALCsizei; typedef int ALCenum;
typedef void ALCvoid;

#define ALC_FALSE 0
#define ALC_TRUE 1
#define ALC_NO_ERROR 0
#define ALC_INVALID_DEVICE 0xA001
#define ALC_INVALID_CONTEXT 0xA002
#define ALC_INVALID_ENUM 0xA003
#define ALC_INVALID_VALUE 0xA004
#define ALC_OUT_OF_MEMORY 0xA005
#define ALC_FREQUENCY 0x1007
#define ALC_REFRESH 0x1008
#define ALC_SYNC 0x1009
#define ALC_MONO_SOURCES 0x1010
#define ALC_STEREO_SOURCES 0x1011
#define ALC_DEFAULT_DEVICE_SPECIFIER 0x1004
#define ALC_DEVICE_SPECIFIER 0x1005
#define ALC_EXTENSIONS 0x1006
#define ALC_CAPTURE_DEVICE_SPECIFIER 0x310
#define ALC_CAPTURE_DEFAULT_DEVICE_SPECIFIER 0x311
#define ALC_CAPTURE_SAMPLES 0x312
#define ALC_ALL_DEVICES_SPECIFIER 0x1013

ALCdevice*  alcOpenDevice(const ALCchar*);
ALCboolean  alcCloseDevice(ALCdevice*);
ALCcontext* alcCreateContext(ALCdevice*, const ALCint*);
ALCboolean  alcMakeContextCurrent(ALCcontext*);
void        alcDestroyContext(ALCcontext*);
ALCcontext* alcGetCurrentContext(void);
ALCenum     alcGetError(ALCdevice*);
void        alcGetIntegerv(ALCdevice*, ALCenum, ALCsizei, ALCint*);
const ALCchar* alcGetString(ALCdevice*, ALCenum);
ALCboolean  alcIsExtensionPresent(ALCdevice*, const ALCchar*);
void*       alcGetProcAddress(ALCdevice*, const ALCchar*);
ALCdevice*  alcCaptureOpenDevice(const ALCchar*, ALCuint, ALCenum, ALCsizei);
ALCboolean  alcCaptureCloseDevice(ALCdevice*);
void        alcCaptureStart(ALCdevice*);
void        alcCaptureStop(ALCdevice*);
void        alcCaptureSamples(ALCdevice*, ALCvoid*, ALCsizei);

#ifdef __cplusplus
}
#endif
#endif
