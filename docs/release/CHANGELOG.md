# Changelog

## 0.9.3 — first public source release (26 Sep 2026)

- The same runtime as 0.9.2, built from scratch from this public repository
  (`tools/build-from-scratch.sh` + `tools/release.sh`).
- The build no longer assumes where the repository is cloned, and the orbis-sdk bundle can
  live anywhere (`ORBIS_SDK_BUNDLE`).
- Development builds no longer send their log to a hard-coded address by default: pass
  `-DLOVE_PS4_NETLOG_HOST=<ip>` to get it. Release builds never had it.

## 0.9.2 — shader cache on disk (25 Sep 2026)

- Mesa keeps compiled shaders in `/data/love/cache`: from the second launch on, the first draw
  with each shader no longer compiles it (in a voxel 3D mod, the first frame went from ~650 to
  ~390 ms). `MESA_SHADER_CACHE_DIR` in `env.txt` moves the folder and
  `MESA_SHADER_CACHE_DISABLE=true` turns it off.
- Tested on a console with an equivalent development build.

## 0.9.0 — first release candidate (23 Sep 2026)

LÖVE 11.5 for PS4 (GoldHEN), by Tomas Morello.

- All of LÖVE 11.5 except `love.video`: graphics on OpenGL 4.6 (Mesa zink/RADV), audio with
  openal-soft 1.23.1, LuaJIT 2.1 (interpreter), gamepads, file system in `/data/love`.
- Runs `/data/love/game.love`, or the game fused into a standalone package (`fuse-pkg.sh`),
  which takes precedence.
- `/data/love/env.txt`: environment variables set before the game starts.
- Quitting LÖVE returns to the PS4 home screen.
- Lua errors are logged even when the game installs its own `love.errorhandler`.
- Release builds: no network log, no diagnostics, third-party notices included.

Tested end to end with Gen1Recomp (ROM import, gameplay, audio at 44.1 kHz, mods, restarting
LÖVE, quitting) on an equivalent development build.
