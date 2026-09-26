# LOVE 11.5 para PlayStation 4 (OpenOrbis / orbis-sdk bundle).
#
# Esto existe EN VEZ de parchear el CMakeLists.txt de LOVE, por la misma razon
# que el port de SDL2 de orbis-ports tiene su propio orbis/CMakeLists.txt:
# el de upstream son 1800 lineas que resuelven todo con find_package sobre
# librerias del sistema, y este target es Generic con triple
# x86_64-pc-freebsd12-elf sobre musl. Una rama ahi seria un conflicto en cada
# rebase; aqui el arbol de LOVE queda intacto salvo los parches de plataforma.
cmake_minimum_required(VERSION 3.16)
project(love_ps4 CXX C)

if(NOT PS4)
  message(FATAL_ERROR "configurar con -DCMAKE_TOOLCHAIN_FILE=<bundle>/toolchain/orbis-sdk.cmake")
endif()

# Raiz del repo, desde este archivo: el build no depende de donde este clonado.
get_filename_component(LOVE_PS4_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(LOVE_DIR   "${LOVE_PS4_ROOT}/love"        CACHE PATH "checkout de love2d/love 11.5")
set(DEPS_DIR   "${LOVE_PS4_ROOT}/deps/out"    CACHE PATH "freetype/ogg/vorbis compiladas")
set(SDL2_DIR_  "${LOVE_PS4_ROOT}/SDL2"        CACHE PATH "checkout de orbis-ports/SDL2")
set(SDL2_BUILD "${LOVE_PS4_ROOT}/build/sdl2"  CACHE PATH "libSDL2.a ya construida")
set(AL_SHIM    "${LOVE_PS4_ROOT}/love-ps4/al" CACHE PATH "shim de OpenAL")
set(MESA_SRC   "$ENV{ORBIS_MESA_SRC}"           CACHE PATH "bundle de Mesa")
set(MESA_BUILD "$ENV{ORBIS_MESA_BUILD}"         CACHE PATH "archivos de Mesa")
set(ZLIB_INC   "${LOVE_PS4_ROOT}/deps/zlib"   CACHE PATH "headers de zlib")

# ---------------------------------------------------------------- fuentes
# Un backend por modulo en 11.5 (audio tiene null + openal, y los dos van:
# LOVE cae a null por su propio camino cuando alcOpenDevice devuelve NULL).
file(GLOB_RECURSE LOVE_SRC CONFIGURE_DEPENDS
  "${LOVE_DIR}/src/common/*.cpp"
  "${LOVE_DIR}/src/modules/*.cpp")
# main() vive suelto en src/, fuera de common/ y modules/.
list(APPEND LOVE_SRC "${LOVE_DIR}/src/love.cpp")
# Lua: LUAJIT (M8) o PUC (Lua 5.1.5, la vuelta atras). Como LOVE_PS4_OPENAL, la opcion controla
# HEADERS, BIBLIOTECA y bit.c juntos: mezclarlos compila y falla en la consola.
set(LOVE_PS4_LUA "LUAJIT" CACHE STRING "LUAJIT = LuaJIT 2.1 (solo interprete), PUC = Lua 5.1.5")
set_property(CACHE LOVE_PS4_LUA PROPERTY STRINGS LUAJIT PUC)
if(LOVE_PS4_LUA STREQUAL "LUAJIT")
  set(LOVE_PS4_LUA_INC "${DEPS_DIR}/include/luajit")
  set(LOVE_PS4_LUA_LIB "${DEPS_DIR}/lib/libluajit.a")
  # lj_prng.c siembra math.random con sceRandomGetRandomNumber en PS4.
  set(LOVE_PS4_LUA_SYSLIBS -lSceRandom)
  # love.cpp carga libSceRandom con sceSysmodule antes del primer lua_State (parche 16): el
  # sistema no la carga solo, y enlazarla no alcanza.
  set(LOVE_PS4_LUA_DEFS LOVE_PS4_LUAJIT=1)
elseif(LOVE_PS4_LUA STREQUAL "PUC")
  set(LOVE_PS4_LUA_INC "${DEPS_DIR}/include/lua51")
  set(LOVE_PS4_LUA_LIB "${DEPS_DIR}/lib/liblua.a")
  set(LOVE_PS4_LUA_SYSLIBS "")
  set(LOVE_PS4_LUA_DEFS "")
  # Lua BitOp: el `bit` de LuaJIT como modulo para Lua 5.1. ⚠ SOLO con PUC: LuaJIT trae su
  # propio luaopen_bit, y el link usa --allow-multiple-definition, asi que dos definiciones no
  # darian error: ganaria una en silencio. Los registros de `bit` en love.cpp y LuaThread.cpp
  # sirven para los dos (llaman a luaopen_bit, sea cual sea).
  list(APPEND LOVE_SRC "${LOVE_PS4_ROOT}/love-ps4/bit.c")
else()
  message(FATAL_ERROR "LOVE_PS4_LUA tiene que ser LUAJIT o PUC, no '${LOVE_PS4_LUA}'")
endif()
if(NOT EXISTS "${LOVE_PS4_LUA_LIB}")
  message(FATAL_ERROR "falta ${LOVE_PS4_LUA_LIB}: correr deps/build-deps.sh")
endif()
message(STATUS "love-ps4: Lua = ${LOVE_PS4_LUA} (${LOVE_PS4_LUA_LIB})")
# Activa el lock del allocator de musl: `pthread_create` aca es el shim de
# orbis-compat y no pone libc.threaded, asi que sin esto malloc corre sin lock
# entre los hilos de LOVE y se corrompe la free-list.
list(APPEND LOVE_SRC "${LOVE_PS4_ROOT}/love-ps4/libc_threaded.c")
# El libc++abi del SDK llama a __cxa_thread_atexit_impl, que musl no trae: sin esto no enlaza
# ningun thread_local con destructor (el primero fue openal-soft). Ver el archivo.
list(APPEND LOVE_SRC "${LOVE_PS4_ROOT}/love-ps4/cxa_thread_atexit.c")
# sem_* sobre pthread: los del libc del SDK le pasan al kernel el puntero al sem_t en vez del id
# (EINVAL siempre). Rompia openal-soft: hilo girando en vacio y crash al reiniciar LOVE. Ver el archivo.
list(APPEND LOVE_SRC "${LOVE_PS4_ROOT}/love-ps4/sem_pthread.c")

# Allocator de Lua con canarios. Herramienta de diagnostico, apagada por defecto:
# cuesta 96 bytes por bloque y un barrido O(bloques vivos) cada 4096 operaciones.
#   cmake -B build/love -DLOVE_PS4_GUARD_ALLOC=ON && cmake --build build/love
option(LOVE_PS4_GUARD_ALLOC  "canarios en el allocator de Lua (diagnostico)" OFF)
# Un nivel mas abajo: envuelve malloc/free/realloc/calloc del proceso entero, o
# sea tambien lo que piden LOVE, PhysFS y operator new. El nivel de Lua ya corrio
# en hardware sin detectar nada, lo que descarta que el desborde pase por ahi.
option(LOVE_PS4_GUARD_MALLOC "canarios en TODO el heap, via --wrap (diagnostico)" OFF)
if(LOVE_PS4_GUARD_ALLOC OR LOVE_PS4_GUARD_MALLOC)
  list(APPEND LOVE_SRC "${LOVE_PS4_ROOT}/love-ps4/guardalloc.c")
  message(STATUS "love-ps4: canarios ACTIVADOS (build de diagnostico)"
                 " lua=${LOVE_PS4_GUARD_ALLOC} malloc=${LOVE_PS4_GUARD_MALLOC}")
endif()

# El canal de log de la consola. Vive en optional/ del overlay y NO en
# liborbis-compat.a a proposito: obliga al link a cargar -lSceNet, y no todo
# consumidor quiere esa dependencia. Aqui si: sin netlog, un fallo antes de
# love.graphics es invisible.
set(ORBIS_COMPAT "$ENV{ORBIS_COMPAT_DIR}" CACHE PATH "overlay")
list(APPEND LOVE_SRC
  "${ORBIS_COMPAT}/optional/ps4_app.cpp"
  "${ORBIS_COMPAT}/optional/orbis_netlog.cpp")

# ⚠ HEAP QUE CRECE BAJO DEMANDA, Y NO ES GRATIS.
# libSceLibcInternal toma el tamano del heap de un simbolo que define la
# APLICACION; el default fijo no alcanza para el import de ROM de gen1recomp,
# que murio DENTRO de malloc (+0x5c3) con los registros llenos de Lua generado.
# El precio, documentado en el propio archivo: compite con la arena de memoria
# directa de RADV, que se toma de un saque al crear el device. Aqui el orden
# juega a favor -- el contexto GL se crea mucho antes de que el import haga
# crecer el heap -- pero si el driver empieza a reportar una arena chica, este
# es el primer lugar donde mirar. OpenGothic deliberadamente NO lo enlaza.
list(APPEND LOVE_SRC "${ORBIS_COMPAT}/optional/orbis_bigheap.c")

# Solo video/theora/ necesita libtheora. VideoStream y graphics/Video son la
# base abstracta, y wrap_Graphics.cpp las referencia siempre: sacarlas deja
# simbolos sin resolver aunque LOVE_ENABLE_VIDEO este apagado.
list(FILTER LOVE_SRC EXCLUDE REGEX "/modules/video/theora/")
list(FILTER LOVE_SRC EXCLUDE REGEX "/modules/video/wrap_")

set(LOVE_3P_DIRS Box2D Wuff ddsparse dr_flac glad glslang lodepng lua53
                 lz4 noise1234 physfs stb tinyexr utf8 xxHash)
foreach(d ${LOVE_3P_DIRS})
  file(GLOB_RECURSE _s CONFIGURE_DEPENDS
    "${LOVE_DIR}/src/libraries/${d}/*.c" "${LOVE_DIR}/src/libraries/${d}/*.cpp")
  list(APPEND LOVE_3P ${_s})
endforeach()
# Solo el ossource de Windows sobra. OGLCompilersDLL/ NO es codigo de Windows
# pese al nombre: es InitializeDll.cpp, que define glslang::InitProcess/InitThread
# para todas las plataformas.
list(FILTER LOVE_3P EXCLUDE REGEX "glslang/OSDependent/Windows/")
# lua53 trae su interprete y su compilador como ejecutables.
list(FILTER LOVE_3P EXCLUDE REGEX "lua53/src/(lua|luac)\\.c$")

add_executable(love ${LOVE_SRC} ${LOVE_3P})

target_include_directories(love PRIVATE
  "${LOVE_DIR}/src" "${LOVE_DIR}/src/modules" "${LOVE_DIR}/src/libraries"
  "${LOVE_PS4_LUA_INC}"         # LOVE NO vendoriza un Lua: lua53/ son solo
                                # backports de lstrlib/lutf8lib para LuaJIT.
  "${LOVE_DIR}/src/libraries/enet/libenet/include"
  "${SDL2_DIR_}/include"
  "${DEPS_DIR}/include" "${DEPS_DIR}/include/freetype2"
  "${ZLIB_INC}"
  "${MESA_SRC}/include"
  "${ORBIS_COMPAT}/include")

# OpenAL. SOFT (M7): openal-soft 1.23.1 sobre el driver de audio de SDL2, audio real y la API
# completa (fuentes, streaming, colas, EFX). SHIM (M5): alcOpenDevice devuelve NULL y LOVE cae
# a su backend nulo; queda como vuelta atras.
# ⚠ La opcion controla HEADERS Y BIBLIOTECA juntos: deps/out/include ya contiene los AL/*.h
# reales de openal-soft y esta en el include path. Si el shim no va BEFORE, un build "con shim"
# compila contra los headers reales y enlaza contra el stub, sin que nada avise.
set(LOVE_PS4_OPENAL "SOFT" CACHE STRING "SOFT = openal-soft (audio real), SHIM = sin audio")
set_property(CACHE LOVE_PS4_OPENAL PROPERTY STRINGS SOFT SHIM)
if(LOVE_PS4_OPENAL STREQUAL "SOFT")
  set(LOVE_PS4_OPENAL_LIB "${DEPS_DIR}/lib/libopenal.a")
  if(NOT EXISTS "${LOVE_PS4_OPENAL_LIB}")
    message(FATAL_ERROR "falta ${LOVE_PS4_OPENAL_LIB}: correr deps/build-deps.sh")
  endif()
elseif(LOVE_PS4_OPENAL STREQUAL "SHIM")
  target_include_directories(love BEFORE PRIVATE "${AL_SHIM}")
  set(LOVE_PS4_OPENAL_LIB "${AL_SHIM}/libopenal-stub.a")
else()
  message(FATAL_ERROR "LOVE_PS4_OPENAL tiene que ser SOFT o SHIM, no '${LOVE_PS4_OPENAL}'")
endif()
message(STATUS "love-ps4: OpenAL = ${LOVE_PS4_OPENAL} (${LOVE_PS4_OPENAL_LIB})")

# Destino del netlog (UDP). Default VACIO = netlog apagado (para desarrollo:
# -DLOVE_PS4_NETLOG_HOST=<ip de la PC que corre logs/udplog.py>): sceNetInetPton
# falla con "" y orbis_netlog_init() cierra el socket sin mandar nada (orbis_netlog.cpp). Es lo que
# usa tools/release.sh: un paquete publico no manda datagramas a una IP de la LAN de nadie.
# Solo en orbis_netlog.cpp (el unico que lo lee): cambiarlo recompila un archivo, no LOVE entero.
set(LOVE_PS4_NETLOG_HOST "" CACHE STRING "IP que recibe el netlog; vacio = apagado")
message(STATUS "love-ps4: netlog -> '${LOVE_PS4_NETLOG_HOST}'")
set_source_files_properties("${ORBIS_COMPAT}/optional/orbis_netlog.cpp" PROPERTIES
  COMPILE_DEFINITIONS "NETLOG_HOST=\"${LOVE_PS4_NETLOG_HOST}\";NETLOG_PORT=18194")
target_compile_definitions(love PRIVATE
  PS4_APP_STAMP="love-11.5-ps4"
  ${LOVE_PS4_LUA_DEFS}
  LOVE_ENABLE_LUA53=1          # backports de 5.3 (utf8, string.pack): con LuaJIT y con PUC
  # Offset de `threaded` dentro de la struct `__libc` de musl. MEDIDO sobre el
  # binario (el musl de upstream lo tiene en otro lado; este libc es un fork).
  # Unico lugar donde vive el numero; verify-libc-threaded.sh lo re-deriva del
  # .oelf despues de linkear y hace fallar el build si dejo de coincidir.
  LOVE_PS4_LIBC_THREADED_OFFSET=0x0c)

if(LOVE_PS4_GUARD_ALLOC)
  target_compile_definitions(love PRIVATE LOVE_PS4_GUARD_ALLOC=1)
endif()

# EL ARREGLO DEL IMPORT (22-sep): realloc como nuevo+copia+libera, sin el de musl. Con el
# realloc de musl el import de gen1recomp corrompia el heap en todas las corridas; con este,
# pasa. Encendido por defecto. Ver love-ps4/realloc_copy.c.
option(LOVE_PS4_REALLOC_COPY "realloc propio: nuevo + copia + libera" ON)
if(LOVE_PS4_REALLOC_COPY)
  if(LOVE_PS4_GUARD_MALLOC OR LOVE_PS4_CRASHTRACE)
    message(FATAL_ERROR "REALLOC_COPY, GUARD_MALLOC y CRASHTRACE envuelven realloc: elegir uno")
  endif()
  target_sources(love PRIVATE "${LOVE_PS4_ROOT}/love-ps4/realloc_copy.c")
  target_link_options(love PRIVATE -Wl,--wrap=realloc)
endif()

# Deja en los registros del volcado quien llamo a memcpy y a realloc: musl no tiene
# .eh_frame y usa rbp como registro comun, asi que ningun backtrace lo atraviesa.
# Instrumentacion pura: no cambia como se asigna la memoria. Ver love-ps4/crashtrace.c.
option(LOVE_PS4_CRASHTRACE "registros con el llamador de memcpy/realloc (diagnostico)" OFF)
if(LOVE_PS4_CRASHTRACE)
  if(LOVE_PS4_GUARD_MALLOC)
    message(FATAL_ERROR "CRASHTRACE y GUARD_MALLOC envuelven realloc los dos: elegir uno")
  endif()
  target_sources(love PRIVATE "${LOVE_PS4_ROOT}/love-ps4/crashtrace.c")
  target_link_options(love PRIVATE -Wl,--wrap=memcpy -Wl,--wrap=realloc)
endif()

if(LOVE_PS4_GUARD_MALLOC)
  target_compile_definitions(love PRIVATE LOVE_PS4_GUARD_MALLOC=1)
  # --wrap redirige las REFERENCIAS a estos simbolos hacia __wrap_*; las llamadas
  # internas de musl entre malloc y free viven en el mismo objeto y no se tocan,
  # que es justo lo que hace falta para que su heap siga siendo coherente.
  target_link_options(love PRIVATE
    -Wl,--wrap=malloc -Wl,--wrap=free -Wl,--wrap=realloc -Wl,--wrap=calloc
    # Y las alineadas. Sin esto, __memalign de musl llama a __wrap_malloc, recibe un
    # bloque del guard y trata su franja roja como cabecera de chunk (medido: 49 call
    # sites, y el crash del arranque con r12=0xbebebebebebec000 era eso).
    -Wl,--wrap=memalign -Wl,--wrap=posix_memalign)
endif()

target_compile_definitions(love PRIVATE
  __PS4__ PS4 __ORBIS__ _BSD_SOURCE=1
  SDL_ORBIS_ENABLE_AUDIO=1 SDL_ORBIS_ENABLE_JOYSTICK=1 SDL_ORBIS_ENABLE_VIDEO=1)

target_compile_options(love PRIVATE -O2 -fPIC -funwind-tables
  -Wno-everything)   # el arbol de LOVE es limpio en gcc/clang de escritorio;
                     # aqui solo agrega ruido sobre musl

# ---------------------------------------------------------------- enlace
# Orden: nuestro codigo, luego SDL2, luego las dependencias, luego Mesa en
# --start-group (EGL, GLES, gallium y el ICD se referencian en ambos sentidos)
# con --whole-archive SOLO sobre el ICD: sus tablas de dispatch usan referencias
# debiles, que no extraen miembros de un archivo y resuelven a cero.
file(GLOB GALLIUM_A "${MESA_BUILD}/src/gallium/targets/dri/libgallium-*.a")
file(GLOB MESA_ZLIB "${MESA_BUILD}/subprojects/zlib-*/libz.a")

target_link_libraries(love PRIVATE
  # ⚠ Y HAY QUE FORZARLOS A LA TABLA DINAMICA. Definirlos como globales no
  # alcanza: libSceLibcInternal los busca POR NOMBRE al cargar, a traves de
  # .dynsym, y el enlazador solo exporta ahi lo que alguien referencia desde
  # afuera -- nadie lo hace. Sin esto quedan en .symtab, nm los muestra en
  # mayuscula, y el heap sigue siendo el default: el arreglo correcto e invisible.
  -Wl,--export-dynamic-symbol=sceLibcHeapSize
  -Wl,--export-dynamic-symbol=sceLibcHeapExtendedAlloc
  "${LOVE_PS4_OPENAL_LIB}"          # antes que SDL2: openal-soft llama a SDL_OpenAudioDevice
  "${SDL2_BUILD}/libSDL2.a"
  "${LOVE_PS4_LUA_LIB}"
  "${DEPS_DIR}/lib/libfreetype.a"
  "${DEPS_DIR}/lib/libvorbisfile.a"
  "${DEPS_DIR}/lib/libvorbis.a"
  "${DEPS_DIR}/lib/libogg.a"
  -Wl,--allow-multiple-definition
  -Wl,--start-group
  "${MESA_BUILD}/src/egl/libEGL.a"
  "${MESA_BUILD}/src/mesa/glapi/es2api/libGLESv2.a"
  "${MESA_BUILD}/src/mesa/glapi/es1api/libGLESv1_CM.a"
  "${GALLIUM_A}"
  -Wl,--whole-archive "${MESA_BUILD}/src/amd/vulkan/libvulkan_radeon.a" -Wl,--no-whole-archive
  "${MESA_ZLIB}"
  -Wl,--end-group
  -lSceNet -lSceGnmDriver -lSceVideoOut -lScePad -lSceUserService
  -lSceAudioOut -lSceSysmodule -lSceSystemService ${LOVE_PS4_LUA_SYSLIBS})

# Un offset equivocado escribe un 1 en cualquier campo de la struct de musl y no
# se nota hasta que corrompe memoria en la consola. Se comprueba contra el .oelf
# ya linkeado, no contra la cabecera, y rompe el build si no da.
add_custom_command(TARGET love POST_BUILD
  COMMAND "${LOVE_PS4_ROOT}/tools/verify-libc-threaded.sh"
          "$<TARGET_FILE:love>" 0x0c
  VERBATIM COMMENT "verificando el offset de libc.threaded")

if(COMMAND ps4_create_eboot)
  ps4_create_eboot(love)
endif()
