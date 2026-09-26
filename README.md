# LÖVE for PS4

[LÖVE](https://love2d.org) 11.5 for PlayStation 4 homebrew (GoldHEN). One `.pkg` that runs any
`.love` game, and a runtime zip to turn a game into its own installable package.

Port by **Tomas Morello** ([@tomasmorello](https://github.com/tomasmorello)).

> You need a PS4 that runs homebrew (GoldHEN). This project does not help you set that up.

## Status: 0.9.x pre-release

Runs [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) end to end on real hardware
(Pokemon Red, Blue and Yellow: ROM import, gameplay, audio, mods, restarting LÖVE, quitting to
the home screen). Other games have not been tried yet; reports are welcome.

| Module | On PS4 |
|---|---|
| `love.graphics` | OpenGL 4.6 Core through Mesa (zink on RADV), GLSL compiled at run time, shader cache on disk. Always 1920×1080 |
| `love.audio`, `love.sound` | openal-soft 1.23.1 over SDL2 (`sceAudioOut`); Ogg Vorbis, WAV and FLAC (no MP3, no tracker modules) |
| Lua | LuaJIT 2.1 as an interpreter (no JIT, no `ffi`) |
| `love.joystick` | DualShock 4 as a standard SDL gamepad (Cross = `a`, Circle = `b`) |
| `love.filesystem` | save directory under `/data/love/` |
| `love.thread`, `love.image`, `love.font`, `love.data`, `love.math`, `love.physics` | built in; all but `love.physics` exercised by Gen1Recomp |
| `love.video` | no |
| `io.popen`, `os.execute` | no (no child processes on the console) |

Quitting a game (`love.event.quit()`) returns to the PS4 home screen.

## Play a game

1. Install `love-ps4-<version>.pkg` from the [releases](../../releases) (USB drive formatted
   exFAT → **Settings → Debug Settings → Game → Package Installer**).
2. Copy your game to `/data/love/game.love` (GoldHEN's FTP server, port 2121).
3. Start **LÖVE for PS4**.

Details, `env.txt` and limits: [docs/release/INSTALL.md](docs/release/INSTALL.md).

## Ship your game as its own package

The release also has `love-ps4-<version>-runtime.zip`: the runtime without a game, plus
`fuse-pkg.sh`. It produces a package with its own title, icon and saves:

```bash
unzip love-ps4-<version>-runtime.zip && cd love-ps4-<version>-runtime
OO_PS4_TOOLCHAIN=/path/to/OpenOrbis-PS4-Toolchain ./fuse-pkg.sh --love game.love \
  --title-id ABCD12345 --title "My Game" --version 01.00 --icon icon-512.png --out-dir out
```

It needs the packaging tools (PkgTool.Core, create-gp4) from the
[OpenOrbis PS4 Toolchain](https://github.com/OpenOrbis/OpenOrbis-PS4-Toolchain) v0.5.4, and
bash 4+. Keep the title id fixed across versions and raise `--version`: the console then
installs the new package over the old one and keeps its data.

Downstream builds can pin a release by tag and SHA-256 (see `sha256sums.txt` in each release).

## Build from source

Host: macOS arm64 (Homebrew `llvm`, `lld`, `cmake`, `ninja`, `bash`). Toolchain: the
[orbis-sdk-v1 bundle](https://github.com/orbis-ports/orbis-porting-kit/releases/tag/orbis-sdk-v1)
(OpenOrbis v0.5.4 + orbis-compat + Mesa for PS4, pinned together), unpacked at
`~/.local/opt/orbis-sdk-v1` or wherever `ORBIS_SDK_BUNDLE` points.

```bash
tools/build-from-scratch.sh   # third-party trees at pinned commits + our diffs, SDL2, deps, LuaJIT
tools/release.sh 0.9.3        # LÖVE, the .pkg, the runtime zip, notices, sha256 -> dist/
```

Every release is built this way from a clean checkout of this repository.

### Layout

| Path | What |
|---|---|
| `love-ps4/` | the CMake build of LÖVE for the console, and the fixes that live outside third-party trees (`realloc`, POSIX semaphores, `thread_local`, the OpenAL shim) |
| `patches/TREES` | every third-party tree: URL and exact commit |
| `patches/*.diff` | all our changes to LÖVE, LuaJIT and openal-soft. The source of truth |
| `deps/` | build scripts for Lua, LuaJIT, Ogg, Vorbis, FreeType, openal-soft |
| `tools/` | from-scratch build, release, packaging (`fuse-pkg.sh`, `make-pkg-plus.sh`), tree snapshots |
| `testgame/` | a minimal `.love` that exercises graphics, shaders, canvases, audio and input |
| `logs/udplog.py` | receiver for the development log (see below) |

### Development builds

A development build can send `print()` output and Lua errors over UDP to a PC:
configure with `-DLOVE_PS4_NETLOG_HOST=<pc-ip>` and run `python3 logs/udplog.py` there.
Release builds never send anything.

## Credits and licenses

The port's own code is under the zlib license, like LÖVE: see [LICENSE](LICENSE).
Third-party components keep theirs; summary in
[docs/release/THIRD_PARTY.md](docs/release/THIRD_PARTY.md), full texts in
`THIRD_PARTY_NOTICES.txt` inside every package and release.

Built on [LÖVE](https://love2d.org), [LuaJIT](https://luajit.org),
[openal-soft](https://openal-soft.org), [SDL2 for PS4](https://github.com/orbis-ports/SDL2),
[OpenOrbis](https://github.com/OpenOrbis), [orbis-compat](https://github.com/orbis-ports/orbis-compat)
and [Mesa for PS4](https://github.com/orbis-ports/mesa-ps4).

LÖVE for PS4 is not affiliated with the LÖVE project or with Sony Interactive Entertainment.
