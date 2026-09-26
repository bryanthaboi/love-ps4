/* Cuerpos del shim. Todo no-op; el unico que importa es alcOpenDevice. */
#include <AL/al.h>
#include <AL/alc.h>

ALCdevice*  alcOpenDevice(const ALCchar *n){ (void)n; return 0; }  /* <-- la pieza clave */
ALCboolean  alcCloseDevice(ALCdevice *d){ (void)d; return ALC_TRUE; }
ALCcontext* alcCreateContext(ALCdevice *d, const ALCint *a){ (void)d;(void)a; return 0; }
ALCboolean  alcMakeContextCurrent(ALCcontext *c){ (void)c; return ALC_FALSE; }
void        alcDestroyContext(ALCcontext *c){ (void)c; }
ALCcontext* alcGetCurrentContext(void){ return 0; }
ALCenum     alcGetError(ALCdevice *d){ (void)d; return ALC_NO_ERROR; }
void        alcGetIntegerv(ALCdevice *d, ALCenum p, ALCsizei s, ALCint *v){
                (void)d;(void)p; for (ALCsizei i=0;i<s;i++) v[i]=0; }
const ALCchar* alcGetString(ALCdevice *d, ALCenum p){ (void)d;(void)p; return ""; }
ALCboolean  alcIsExtensionPresent(ALCdevice *d, const ALCchar *e){ (void)d;(void)e; return ALC_FALSE; }
void*       alcGetProcAddress(ALCdevice *d, const ALCchar *n){ (void)d;(void)n; return 0; }
ALCdevice*  alcCaptureOpenDevice(const ALCchar *n, ALCuint f, ALCenum m, ALCsizei s){
                (void)n;(void)f;(void)m;(void)s; return 0; }
ALCboolean  alcCaptureCloseDevice(ALCdevice *d){ (void)d; return ALC_TRUE; }
void        alcCaptureStart(ALCdevice *d){ (void)d; }
void        alcCaptureStop(ALCdevice *d){ (void)d; }
void        alcCaptureSamples(ALCdevice *d, ALCvoid *b, ALCsizei n){ (void)d;(void)b;(void)n; }

void      alGenBuffers(ALsizei n, ALuint *b){ for (ALsizei i=0;i<n;i++) b[i]=0; }
void      alDeleteBuffers(ALsizei n, const ALuint *b){ (void)n;(void)b; }
void      alBufferData(ALuint b, ALenum f, const ALvoid *d, ALsizei s, ALsizei r){
              (void)b;(void)f;(void)d;(void)s;(void)r; }
void      alGetBufferi(ALuint b, ALenum p, ALint *v){ (void)b;(void)p; *v=0; }
void      alGenSources(ALsizei n, ALuint *s){ for (ALsizei i=0;i<n;i++) s[i]=0; }
void      alDeleteSources(ALsizei n, const ALuint *s){ (void)n;(void)s; }
void      alSourcef(ALuint s, ALenum p, ALfloat v){ (void)s;(void)p;(void)v; }
void      alSourcefv(ALuint s, ALenum p, const ALfloat *v){ (void)s;(void)p;(void)v; }
void      alSourcei(ALuint s, ALenum p, ALint v){ (void)s;(void)p;(void)v; }
void      alGetSourcef(ALuint s, ALenum p, ALfloat *v){ (void)s;(void)p; *v=0.f; }
void      alGetSourcefv(ALuint s, ALenum p, ALfloat *v){ (void)s;(void)p; v[0]=v[1]=v[2]=0.f; }
void      alGetSourcei(ALuint s, ALenum p, ALint *v){
              (void)s; *v = (p == AL_SOURCE_STATE) ? AL_STOPPED : 0; }
void      alSourcePlay(ALuint s){ (void)s; }
void      alSourcePlayv(ALsizei n, const ALuint *s){ (void)n;(void)s; }
void      alSourcePause(ALuint s){ (void)s; }
void      alSourcePausev(ALsizei n, const ALuint *s){ (void)n;(void)s; }
void      alSourceStop(ALuint s){ (void)s; }
void      alSourceStopv(ALsizei n, const ALuint *s){ (void)n;(void)s; }
void      alSourceQueueBuffers(ALuint s, ALsizei n, const ALuint *b){ (void)s;(void)n;(void)b; }
void      alSourceUnqueueBuffers(ALuint s, ALsizei n, ALuint *b){ (void)s; for (ALsizei i=0;i<n;i++) b[i]=0; }
void      alListenerf(ALenum p, ALfloat v){ (void)p;(void)v; }
void      alListenerfv(ALenum p, const ALfloat *v){ (void)p;(void)v; }
void      alGetListenerf(ALenum p, ALfloat *v){ (void)p; *v=0.f; }
void      alGetListenerfv(ALenum p, ALfloat *v){ (void)p; v[0]=v[1]=v[2]=0.f; }
void      alDistanceModel(ALenum m){ (void)m; }
void      alDopplerFactor(ALfloat f){ (void)f; }
ALfloat   alGetFloat(ALenum p){ (void)p; return 0.f; }
ALenum    alGetError(void){ return AL_NO_ERROR; }
ALboolean alIsExtensionPresent(const ALchar *e){ (void)e; return AL_FALSE; }
void*     alGetProcAddress(const ALchar *n){ (void)n; return 0; }
