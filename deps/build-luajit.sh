#!/usr/bin/env bash
# Compila LuaJIT 2.1 para PS4 (M8). Traduccion de src/ps4build.bat (la receta de Sony que trae
# LuaJIT) al toolchain de OpenOrbis. Lo llama deps/build-deps.sh; tambien corre solo.
#
# Como se arma LuaJIT (y por que hay dos compiladores):
#   1. minilua  (HOST)  un Lua minimo para correr DynASM, el generador de LuaJIT.
#   2. DynASM   (HOST)  convierte vm_x64.dasc (el interprete, escrito a mano en assembler x86-64
#                       con macros) en buildvm_arch.h.
#   3. buildvm  (HOST)  con eso emite lj_vm.S (el interprete en assembler ELF) y las tablas
#                       generadas (lj_bcdef.h, lj_ffdef.h, lj_libdef.h, lj_recdef.h, lj_folddef.h).
#   4. TARGET: lj_vm.S + ljamalg.c (todo LuaJIT en una sola unidad) con el clang de Orbis.
# buildvm corre en la Mac (arm64) pero genera para x86-64: el destino se fija con
# -DLUAJIT_TARGET=LUAJIT_ARCH_X64. Lo unico que exige es un host de 64 bits, como el destino.
#
# ⚠ Los -D de buildvm y los del target TIENEN que describir la misma VM (sin JIT, sin FFI, sin
# unwinding de C++, GC64). Si difieren, el interprete generado y el C no coinciden en el layout
# de las estructuras y el fallo aparece en la consola, no al compilar. Por eso viven en VM_FLAGS.
#
# Configuracion (la de ps4build.bat, salvo lo marcado):
#   - Sin JIT: la PS4 no deja escribir y ejecutar la misma memoria (LuaJIT ya lo apaga solo con
#     __ORBIS__: LJ_OS_NOJIT). Solo interprete.
#   - Sin FFI (como Sony). gen1recomp no la usa; LOVE la pide con pcall y cae a Lua sin ella.
#   - LUAJIT_USE_SYSMALLOC: la memoria de Lua pasa por malloc/realloc -> por nuestro realloc
#     propio (love-ps4/realloc_copy.c, el arreglo de M6). ps4build.bat solo se lo pasa a
#     buildvm; aca va a los dos. LUAJIT_ALLOC=OWN lo saca: LuaJIT usa su allocator (lj_alloc,
#     un dlmalloc) sobre mmap. ⚠ Ese mmap es el de libkernel, NO el __mmap de musl que
#     orbis-compat manda a memoria direct: la memoria de Lua sale del pool FLEXIBLE.
#   - GC64 (el default en x64): punteros de 64 bits en la VM, sin el limite de 2 GB.
set -euo pipefail
B="${ORBIS_SDK_BUNDLE:-$HOME/.local/opt/orbis-sdk-v1}"
D="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${DEPS_PREFIX:-$D/out}"
SRC="$D/luajit/src"
BLD="${DEPS_BUILD:-$D}/b-luajit"
HOST_CC=/usr/bin/clang   # el de Apple: el clang de Homebrew no encuentra el SDK de macOS solo

[ -d "$SRC" ] || { echo "!! falta $SRC: correr tools/restore-trees.sh"; exit 1; }
grep -q 'love-ps4: la PS4 homebrew si tiene getenv' "$SRC/lib_os.c" \
  || { echo "!! LuaJIT sin parchear: correr patches/luajit.py (sin eso os.getenv devuelve nil)"; exit 1; }

LUAJIT_ALLOC="${LUAJIT_ALLOC:-SYS}"   # SYS = malloc de musl (M8, probado) | OWN = lj_alloc
VM_FLAGS=(-DLUAJIT_DISABLE_JIT -DLUAJIT_DISABLE_FFI -DLUAJIT_NO_UNWIND)
case "$LUAJIT_ALLOC" in
  SYS) VM_FLAGS+=(-DLUAJIT_USE_SYSMALLOC) ;;
  OWN) ;;
  *) echo "!! LUAJIT_ALLOC=$LUAJIT_ALLOC: tiene que ser SYS u OWN"; exit 1 ;;
esac
echo "   allocator: $LUAJIT_ALLOC  (VM_FLAGS: ${VM_FLAGS[*]})"
LIBS=(lib_base.c lib_math.c lib_bit.c lib_string.c lib_table.c lib_io.c lib_os.c lib_package.c
      lib_debug.c lib_jit.c lib_ffi.c lib_buffer.c)

rm -rf "$BLD"; mkdir -p "$BLD/jit" "$PREFIX/lib" "$PREFIX/include/luajit"

echo "   host: minilua + DynASM"
"$HOST_CC" -O2 -o "$BLD/minilua" "$SRC/host/minilua.c" -lm
# Sin -D JIT ni -D FFI: la VM sin compilador ni FFI. P64 = punteros de 64 bits (GC64).
"$BLD/minilua" "$D/luajit/dynasm/dynasm.lua" -LN -D P64 -D NO_UNWIND \
  -o "$BLD/buildvm_arch.h" "$SRC/vm_x64.dasc"

echo "   host: version y buildvm"
( cd "$D/luajit" && git show -s --format=%ct ) > "$BLD/luajit_relver.txt"
# genversion.lua lee y escribe con rutas relativas al directorio actual.
cp "$SRC/luajit_rolling.h" "$BLD/"
( cd "$BLD" && ./minilua "$SRC/host/genversion.lua" luajit_rolling.h luajit_relver.txt luajit.h )
"$HOST_CC" -O1 -I"$BLD" -I"$SRC" -I"$D/luajit/dynasm" \
  -DLUAJIT_TARGET=LUAJIT_ARCH_X64 -DLUAJIT_OS=LUAJIT_OS_OTHER "${VM_FLAGS[@]}" \
  -o "$BLD/buildvm" "$SRC"/host/buildvm*.c

echo "   host: lj_vm.S y tablas generadas"
( cd "$SRC"
  "$BLD/buildvm" -m elfasm -o "$BLD/lj_vm.S"
  "$BLD/buildvm" -m bcdef  -o "$BLD/lj_bcdef.h"  "${LIBS[@]}"
  "$BLD/buildvm" -m ffdef  -o "$BLD/lj_ffdef.h"  "${LIBS[@]}"
  "$BLD/buildvm" -m libdef -o "$BLD/lj_libdef.h" "${LIBS[@]}"
  "$BLD/buildvm" -m recdef -o "$BLD/lj_recdef.h" "${LIBS[@]}"
  "$BLD/buildvm" -m vmdef  -o "$BLD/jit/vmdef.lua" "${LIBS[@]}"
  "$BLD/buildvm" -m folddef -o "$BLD/lj_folddef.h" lj_opt_fold.c )

echo "   target: lj_vm.S + ljamalg.c"
# Mismos flags de plataforma que Lua 5.1 en build-deps.sh. __ORBIS__ activa LJ_TARGET_PS4.
TFLAGS=(--target=x86_64-pc-freebsd12-elf --sysroot="$B/sdk" -fPIC -O2
        -D__PS4__ -DPS4 -D__ORBIS__ -D_BSD_SOURCE=1
        -isysroot "$B/sdk" -isystem "$B/orbis-compat/include" -isystem "$B/sdk/include")
# $BLD primero: los headers generados (y luajit.h) salen de ahi, no del arbol.
clang "${TFLAGS[@]}" "${VM_FLAGS[@]}" -I"$BLD" -I"$SRC" -c "$BLD/lj_vm.S"   -o "$BLD/lj_vm.o"
clang "${TFLAGS[@]}" "${VM_FLAGS[@]}" -I"$BLD" -I"$SRC" -c "$SRC/ljamalg.c" -o "$BLD/ljamalg.o"

rm -f "$PREFIX/lib/libluajit.a"
llvm-ar rcs "$PREFIX/lib/libluajit.a" "$BLD/lj_vm.o" "$BLD/ljamalg.o"
cp "$SRC"/lua.h "$SRC"/luaconf.h "$SRC"/lualib.h "$SRC"/lauxlib.h "$SRC"/lua.hpp "$BLD/luajit.h" \
   "$PREFIX/include/luajit/"
echo "   ok: $(grep -o 'LUAJIT_VERSION[[:space:]]*"[^"]*"' "$BLD/luajit.h" | cut -d'"' -f2)" \
     "-> $PREFIX/lib/libluajit.a ($(ls -lh "$PREFIX/lib/libluajit.a" | awk '{print $5}'))"
