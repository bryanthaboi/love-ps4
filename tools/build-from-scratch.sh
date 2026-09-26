#!/usr/bin/env bash
# Everything a fresh clone needs before tools/release.sh, in order:
#
#   1. tools/restore-trees.sh   third-party trees at their pinned commits + our diffs
#   2. SDL2 (orbis-ports)       -> build/sdl2/libSDL2.a
#   3. deps/build-deps.sh       Lua 5.1.5, ogg, vorbis, freetype, openal-soft -> deps/out
#   4. deps/build-luajit.sh     LuaJIT 2.1 (interpreter) -> deps/out
#
# Then:  tools/release.sh X.Y.Z   (LÖVE itself, the .pkg, the runtime zip and the notices)
#
# Needs: the orbis-sdk-v1 bundle (ORBIS_SDK_BUNDLE, default ~/.local/opt/orbis-sdk-v1),
# cmake, ninja, git, curl, python3, and bash 5 at /opt/homebrew/bin/bash for the packager.
# Host tested: macOS arm64 with Homebrew LLVM/LLD. Existing trees and builds are reused.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK_BUNDLE="${ORBIS_SDK_BUNDLE:-$HOME/.local/opt/orbis-sdk-v1}"
export ORBIS_SDK_BUNDLE="$SDK_BUNDLE"
export PATH="/opt/homebrew/bin:/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin:$PATH"
[[ -f "$SDK_BUNDLE/env.sh" ]] || { echo "build-from-scratch: no orbis-sdk bundle at $SDK_BUNDLE" >&2; exit 1; }
# shellcheck disable=SC1091
. "$SDK_BUNDLE/env.sh" >/dev/null

echo "== 1/4 third-party trees"
tools/restore-trees.sh

echo "== 2/4 SDL2"
mkdir -p build
cmake -S SDL2/orbis -B build/sdl2 -G Ninja \
  "-DCMAKE_TOOLCHAIN_FILE=$SDK_BUNDLE/toolchain/orbis-sdk.cmake" \
  -DSDL_ORBIS_AUDIO=ON -DSDL_ORBIS_JOYSTICK=ON -DSDL_ORBIS_VIDEO=ON > build/sdl2.configure.log
cmake --build build/sdl2 > build/sdl2.build.log

echo "== 3/4 deps (Lua 5.1.5, ogg, vorbis, freetype, openal-soft)"
deps/build-deps.sh > deps/build-deps.log 2>&1 || { tail -30 deps/build-deps.log; exit 1; }

echo "== 4/4 LuaJIT"
deps/build-luajit.sh > deps/build-luajit.log 2>&1 || { tail -30 deps/build-luajit.log; exit 1; }

echo "done: now tools/release.sh X.Y.Z"
