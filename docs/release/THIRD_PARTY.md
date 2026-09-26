# Third-party components

`tools/third-party-notices.sh` assembles the full license texts into `THIRD_PARTY_NOTICES.txt`,
which ships inside the `.pkg`, inside the runtime zip and next to them in every release. This
table is the summary.

| Component | License | What it asks of a binary release |
|---|---|---|
| LÖVE 11.5 and its bundled libraries (Box2D, PhysFS, glslang, lodepng, lz4, stb...) | zlib and similar (`love/license.txt`) | the notice; modified versions are marked as such |
| LuaJIT 2.1 | MIT | the notice |
| **openal-soft 1.23.1** | **LGPL-2.1+** | **linked statically: users must be able to relink it.** This repository is the complete source and build recipe for every release (`tools/build-from-scratch.sh`, `tools/release.sh`), and `patches/openal-soft-1.23.1.diff` is our full change to it |
| SDL2 (orbis-ports) | zlib | the notice |
| FreeType | FTL | the notice and a credit in the documentation |
| libogg, libvorbis | BSD-3-Clause | the notice |
| zlib | zlib | — |
| Mesa (mesa-ps4), Khronos headers | MIT, Apache-2.0 | the notice |
| musl (OpenOrbis fork), orbis-compat | MIT | the notice |
| LLVM libc++ / libc++abi / libunwind / compiler-rt 11 | Apache-2.0 with LLVM exception | the notice |
| OpenOrbis toolchain (crt, stubs, `libc.prx`, `libSceFios2.prx`) | GPL-3.0 in its repository | see `LICENSING.md` §5 in the orbis-sdk bundle: this applies to all PS4 homebrew built with it |

Games are not part of the runtime. A game fused into its own package with `fuse-pkg.sh` keeps
its own license, and whoever distributes that package follows it.
