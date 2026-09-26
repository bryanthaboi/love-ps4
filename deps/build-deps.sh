#!/usr/bin/env bash
# Compila las dependencias de LÖVE 11.5 para PS4 (OpenOrbis + orbis-sdk bundle).
set -euo pipefail
B="${ORBIS_SDK_BUNDLE:-$HOME/.local/opt/orbis-sdk-v1}"
TC="$B/toolchain/orbis-sdk.cmake"
D="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${DEPS_PREFIX:-$D/out}"   # DEPS_PREFIX: solo para probar el script sin pisar deps/out
mkdir -p "$PREFIX"

cm() { # cm <src> <builddir> [extra cmake args...]
  local src="$1" bld="$2"; shift 2
  cmake -S "$src" -B "$bld" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$TC" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    "$@" > "$bld.log" 2>&1 || { echo "!! configure falló: $src (ver $bld.log)"; tail -15 "$bld.log"; return 1; }
  cmake --build "$bld" >> "$bld.log" 2>&1 || { echo "!! build falló: $src"; tail -20 "$bld.log"; return 1; }
  cmake --install "$bld" >> "$bld.log" 2>&1 || { echo "!! install falló: $src"; tail -10 "$bld.log"; return 1; }
  echo "   ok: $(basename "$src")"
}

echo "== Lua 5.1.5 (PUC; LOVE NO vendoriza un Lua: src/libraries/lua53/ son solo backports)"
# C puro, sin assembler: cross-compila directo. lua.c y luac.c son los ejecutables; el resto es
# la biblioteca. Mismos flags que el toolchain; LUA_USE_POSIX por la rama posix de musl.
LUA_SRC="$D/lua51/src"
if [ ! -d "$D/lua51" ]; then
  curl -sL https://www.lua.org/ftp/lua-5.1.5.tar.gz -o "$D/lua515.tar.gz"
  tar -xzf "$D/lua515.tar.gz" -C "$D" && mv "$D/lua-5.1.5" "$D/lua51"
fi
LUA_B="${DEPS_BUILD:-$D}/b-lua"
mkdir -p "$LUA_B" "$PREFIX/lib" "$PREFIX/include/lua51"
rm -f "$LUA_B"/*.o
for f in "$LUA_SRC"/*.c; do
  case "$(basename "$f")" in lua.c|luac.c) continue;; esac
  clang --target=x86_64-pc-freebsd12-elf --sysroot="$B/sdk" -fPIC -O2 \
    -D__PS4__ -DPS4 -D__ORBIS__ -D_BSD_SOURCE=1 -DLUA_USE_POSIX \
    -isysroot "$B/sdk" -isystem "$B/orbis-compat/include" -isystem "$B/sdk/include" \
    -I"$LUA_SRC" -c "$f" -o "$LUA_B/$(basename "${f%.c}").o" || { echo "!! fallo $(basename "$f")"; exit 1; }
done
rm -f "$PREFIX/lib/liblua.a"
llvm-ar rcs "$PREFIX/lib/liblua.a" "$LUA_B"/*.o
cp "$LUA_SRC"/lua.h "$LUA_SRC"/luaconf.h "$LUA_SRC"/lualib.h "$LUA_SRC"/lauxlib.h "$PREFIX/include/lua51/"
echo "   ok: lua 5.1.5 ($(ls "$LUA_B"/*.o | wc -l | tr -d ' ') objetos)"

echo "== LuaJIT 2.1 (M8: interprete en assembler; Lua 5.1 queda como vuelta atras)"
"$D/build-luajit.sh"

echo "== libogg"
cm "$D/ogg" "$D/b-ogg" -DINSTALL_DOCS=OFF -DBUILD_TESTING=OFF

echo "== libvorbis (necesita ogg)"
cm "$D/vorbis" "$D/b-vorbis" \
  -DOGG_INCLUDE_DIR="$PREFIX/include" \
  -DOGG_LIBRARY="$PREFIX/lib/libogg.a" \
  -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
  -DBUILD_TESTING=OFF

echo "== freetype (sin harfbuzz/png/bzip2/brotli)"
cm "$D/freetype" "$D/b-freetype" \
  -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_PNG=ON \
  -DFT_DISABLE_BZIP2=ON   -DFT_DISABLE_BROTLI=ON \
  -DFT_DISABLE_ZLIB=ON

echo "== openal-soft 1.23.1 (M7: audio real sobre el driver de audio de SDL2)"
# 1.23.1 pide C++14; el libc++ del SDK es LLVM 11. Solo SDL2 + null + wave: el SDK trae
# sys/soundcard.h porque parece FreeBSD, y OSS se colaria solo si no se apaga a mano.
# SDL2 se encuentra por deps/sdl2-config/SDL2Config.cmake (nuestro SDL2 no se instala).
[ -d "$D/openal-soft" ] || git clone -q --depth 1 --branch 1.23.1 https://github.com/kcat/openal-soft.git "$D/openal-soft"
python3 "$D/../patches/openal-soft.py"   # thread_local sin _ZTH debiles: ver el script
AL_OFF=()
for b in PIPEWIRE PULSEAUDIO ALSA OSS SOLARIS SNDIO WINMM DSOUND WASAPI JACK COREAUDIO OBOE OPENSL PORTAUDIO; do
  AL_OFF+=("-DALSOFT_BACKEND_$b=OFF")
done
cm "$D/openal-soft" "$D/b-openal" \
  -DLIBTYPE=STATIC -DALSOFT_DLOPEN=OFF -DALSOFT_UTILS=OFF -DALSOFT_NO_CONFIG_UTIL=ON \
  -DALSOFT_EXAMPLES=OFF -DALSOFT_INSTALL_CONFIG=OFF -DALSOFT_INSTALL_HRTF_DATA=OFF \
  -DALSOFT_INSTALL_AMBDEC_PRESETS=OFF -DALSOFT_EAX=OFF -DALSOFT_RTKIT=OFF \
  -DALSOFT_EMBED_HRTF_DATA=ON -DALSOFT_UPDATE_BUILD_VERSION=OFF \
  "${AL_OFF[@]}" -DALSOFT_BACKEND_SDL2=ON -DALSOFT_REQUIRE_SDL2=ON -DALSOFT_BACKEND_WAVE=ON \
  -DSDL2_DIR="$D/sdl2-config" -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH
grep -A1 "following backends" "$D/b-openal.log" | tail -1

echo
echo "== resultado"
find "$PREFIX/lib" -name "*.a" 2>/dev/null | sort | while read -r f; do
  printf "   %-28s %s\n" "$(basename "$f")" "$(ls -lh "$f" | awk '{print $5}')"
done
