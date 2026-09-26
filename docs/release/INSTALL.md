# LÖVE for PS4 — install and run games

LÖVE 11.5 for jailbroken PlayStation 4 consoles. Port by **Tomas Morello**.

> You need a PS4 that runs homebrew (GoldHEN). This project does not help you set that up.
> 0.9.x is a pre-release. Steps marked *(to verify)* have not been checked on a console yet.

## 1. Install the package

1. Download `love-ps4-<version>.pkg` from the release and check it against `sha256sums.txt`.
2. Copy it to a USB drive formatted **exFAT** and plug it into the console.
3. On the PS4: **Settings → Debug Settings → Game → Package Installer**, pick the file.
   Installing over the network from a PC does not work on every console; USB always does.
4. A **LÖVE for PS4** tile appears on the home screen.

Updating: install the newer `.pkg` the same way. It replaces the old version and keeps your
games and saves, which live in `/data/love/`, outside the package.

## 2. Put a game on the console

LÖVE runs a `.love` file: a zip with `main.lua` at its root.

Copy it to **`/data/love/game.love`**. The easiest way is GoldHEN's FTP server (enable it in the
GoldHEN menu; port **2121**), with any FTP client:

    ftp://<console-ip>:2121/data/love/game.love

Then start **LÖVE for PS4**. It runs that game.

Search order: a game inside the package (`/app0/game.love`, used by standalone game packages),
then `/data/love/game.love`, then a folder with `main.lua` at `/data/love/`.

## 3. Per-game settings: `env.txt`

`/data/love/env.txt` sets environment variables before LÖVE starts (`KEY=value`, `#` for
comments). Games that read `os.getenv` pick them up. Runtime variables:

| Variable | Effect |
|---|---|
| `MESA_SHADER_CACHE_DIR=<dir>` | where compiled shaders are cached (default `/data/love/cache`) |
| `MESA_SHADER_CACHE_DISABLE=true` | no shader cache |

## 4. Controls and quitting

- Pads are standard SDL gamepads: the game sees `a` = Cross, `b` = Circle, `x` = Square,
  `y` = Triangle, `start` = Options.
- Quit with the **PS button** → close the application, like any PS4 app. A game that calls
  `love.event.quit()` returns to the home screen.
- ⚠ **START + SHARE** opens the GoldHEN menu; games do not receive that combination.

## 5. Limits

- Video is always 1920×1080; the window cannot change size.
- LuaJIT runs as an interpreter (no JIT). It is fast enough for 2D games at 60 fps.
- No `love.video` (Theora), no `ffi`, no `io.popen` / `os.execute`.
- Suspending the console with a game open: *(to verify)*.

## Credits and licenses

LÖVE (zlib), LuaJIT (MIT), openal-soft (LGPL), SDL2 (zlib), FreeType, libogg/libvorbis,
zlib, Mesa (MIT), OpenOrbis toolchain. Full texts: `THIRD_PARTY_NOTICES.txt` in the release and
inside the package.
