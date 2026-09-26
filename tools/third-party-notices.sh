#!/usr/bin/env bash
# Arma THIRD_PARTY_NOTICES.txt: la licencia de TODO lo que queda enlazado en eboot.bin o viaja en el
# paquete. Lo exigen las licencias mismas (MIT, zlib, BSD, FTL, LGPL: "incluir este aviso en toda
# copia"), y un paquete que se distribuye ES una copia.
#
#   tools/third-party-notices.sh <archivo-de-salida>
#
# Lee los textos de los arboles clonados y del bundle del SDK (que ya junto los que al SDK de
# OpenOrbis le faltan: ver $BUNDLE/LICENSING.md). Si falta uno, FALLA: un aviso incompleto no
# se publica.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?uso: tools/third-party-notices.sh <salida>}"
BUNDLE="${ORBIS_SDK_BUNDLE:-$HOME/.local/opt/orbis-sdk-v1}"
L="$BUNDLE/licenses"

# componente | que es / donde se usa | archivo con el texto
ENTRIES=(
  "LÖVE 11.5 (and its bundled libraries: Box2D, PhysFS, glslang, lodepng, lz4, stb, ...)|the engine|love/license.txt"
  "LuaJIT 2.1|Lua interpreter|deps/luajit/COPYRIGHT"
  "openal-soft 1.23.1|audio (LGPL: see the relinking note above)|deps/openal-soft/COPYING"
  "SDL2 (orbis-ports)|window, input, audio|SDL2/LICENSE.txt"
  "FreeType|fonts|deps/freetype/docs/FTL.TXT"
  "libogg|Ogg container|deps/ogg/COPYING"
  "libvorbis|Vorbis audio|deps/vorbis/COPYING"
  "zlib|compression|deps/zlib/LICENSE"
  "Mesa (mesa-ps4: zink + RADV)|OpenGL on the GPU|$L/MIT-mesa.txt"
  "Khronos headers|Vulkan/GL headers in Mesa|$L/Apache-2.0-Khronos.txt"
  "musl libc (OpenOrbis fork)|C library|$L/MIT-musl.txt"
  "orbis-compat|SDK compatibility layer; tools/make-pkg-plus.sh derives from it|$L/MIT-orbis-compat.txt"
  "FreeBSD sys/ioccom.h|a header in orbis-compat|$L/BSD-3-Clause-FreeBSD.txt"
  "LLVM libc++ 11|C++ library|$L/LLVM-libcxx-LICENSE.TXT"
  "LLVM libc++abi 11|C++ ABI|$L/LLVM-libcxxabi-LICENSE.TXT"
  "LLVM libunwind 11|C++ exceptions|$L/LLVM-libunwind-LICENSE.TXT"
  "LLVM compiler-rt 11|compiler runtime|$L/LLVM-compiler-rt-LICENSE.TXT"
  "OpenOrbis PS4 Toolchain v0.5.4|crt, system stubs, libc.prx and libSceFios2.prx|$BUNDLE/sdk/LICENSE"
)

for e in "${ENTRIES[@]}"; do
  f="${e##*|}"
  [[ -s "$f" ]] || { echo "third-party-notices: MISSING $f" >&2; exit 1; }
done

{
  echo "LÖVE for PS4 — third-party notices"
  echo "Port: Copyright (c) 2026 Tomas Morello, zlib license (LICENSE in the repository)."
  echo "Source: https://github.com/tomasmorello/love-ps4"
  echo
  echo "This package contains or links the components below, each under its own license,"
  echo "reproduced in full further down."
  echo
  echo "openal-soft (LGPL) is statically linked. The complete source and build recipe needed to"
  echo "relink it with another version are in the repository above (tools/build-from-scratch.sh,"
  echo "tools/release.sh, deps/build-deps.sh, patches/openal-soft-1.23.1.diff)."
  echo
  i=0
  for e in "${ENTRIES[@]}"; do
    i=$((i + 1))
    IFS='|' read -r name what _ <<<"$e"
    printf '  %2d. %s — %s\n' "$i" "$name" "$what"
  done
  i=0
  for e in "${ENTRIES[@]}"; do
    i=$((i + 1))
    IFS='|' read -r name _ f <<<"$e"
    echo
    echo "================================================================================"
    printf '%d. %s\n' "$i" "$name"
    echo "================================================================================"
    echo
    cat "$f"
  done
} > "$OUT"
echo "third-party-notices: ${#ENTRIES[@]} components -> $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
