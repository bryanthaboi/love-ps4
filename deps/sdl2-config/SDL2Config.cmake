# SDL2Config.cmake minimo para el SDL2 de orbis-ports compilado para PS4.
#
# openal-soft hace find_package(SDL2) en modo config y nuestro SDL2 no se instala: se
# compila en build/sdl2 y LOVE lo enlaza por ruta. Esto describe esa misma libSDL2.a como
# el target SDL2::SDL2 que openal-soft espera, con los MISMOS headers que usa LOVE.
#
# Los tres defines SDL_ORBIS_ENABLE_* son PUBLIC en el build de SDL2 (ver el plan original,
# M3): quien incluye SDL tiene que verlos igual que SDL, o compila contra un SDL distinto
# del que enlaza.
get_filename_component(_love_ps4 "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
if(NOT TARGET SDL2::SDL2)
  add_library(SDL2::SDL2 STATIC IMPORTED)
  set_target_properties(SDL2::SDL2 PROPERTIES
    IMPORTED_LOCATION "${_love_ps4}/build/sdl2/libSDL2.a"
    INTERFACE_INCLUDE_DIRECTORIES "${_love_ps4}/SDL2/include"
    INTERFACE_COMPILE_DEFINITIONS "SDL_ORBIS_ENABLE_AUDIO=1;SDL_ORBIS_ENABLE_JOYSTICK=1;SDL_ORBIS_ENABLE_VIDEO=1")
endif()
set(SDL2_FOUND TRUE)
set(SDL2_VERSION 2.32.0)
set(SDL2_INCLUDE_DIRS "${_love_ps4}/SDL2/include")
set(SDL2_LIBRARIES SDL2::SDL2)
