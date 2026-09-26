#!/usr/bin/env bash
# Fuses a LÖVE game with the LÖVE for PS4 runtime into its own .pkg: the game travels as
# /app0/game.love and the runtime starts it before any /data/love/game.love.
#
# Ships inside love-ps4-<version>-runtime.zip, next to eboot.bin, sce_module/, icon0.png and
# make-pkg-plus.sh. Run it from there:
#
#   ./fuse-pkg.sh --love game.love --title-id ABCD12345 --title "My game" \
#       [--version 01.00] [--icon icon-512x512.png] [--content-label MYGAME] [--out-dir dist]
#
# Needs the OpenOrbis SDK packaging tools (PkgTool.Core and create-gp4, from its v0.5.4
# release): OO_PS4_TOOLCHAIN pointing at the folder that holds bin/linux or bin/macos.
# On Linux, PkgTool.Core needs OpenSSL 1.1; make-pkg-plus.sh takes care of it (see that file).
# And bash 4+.
#
# The title id belongs to the GAME (4 letters + 5 digits) and must stay the same across
# versions: same id and a higher --version installs over the old one (an update) and keeps its
# data. Changing it creates a second app.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
die() { echo "fuse-pkg: $*" >&2; exit 1; }

LOVE=""; TITLE_ID=""; TITLE=""; VERSION="01.00"; ICON="$HERE/icon0.png"; LABEL=""; OUT="$PWD"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --love)          LOVE="$2";     shift 2 ;;
    --title-id)      TITLE_ID="$2"; shift 2 ;;
    --title)         TITLE="$2";    shift 2 ;;
    --version)       VERSION="$2";  shift 2 ;;
    --icon)          ICON="$2";     shift 2 ;;
    --content-label) LABEL="$2";    shift 2 ;;
    --out-dir)       OUT="$2";      shift 2 ;;
    -h|--help)       sed -n '2,19p' "$0"; exit 0 ;;
    *)               die "unknown argument: $1" ;;
  esac
done
[[ -f "$LOVE" ]]  || die "--love: '$LOVE' does not exist"
[[ -n "$TITLE_ID" && -n "$TITLE" ]] || die "--title-id and --title are required"
[[ "$VERSION" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || die "--version is NN.NN (the PS4 APP_VER format), not '$VERSION'"
[[ -f "$HERE/eboot.bin" ]] || die "eboot.bin is not next to this script: run it from the unpacked runtime"
for prx in libc libSceFios2; do
  [[ -f "$HERE/sce_module/$prx.prx" ]] || die "sce_module/$prx.prx is missing (without it the console fails with PRX_SCE_MODULE_LOAD_ERROR)"
done
# A .love is a zip with main.lua at its ROOT; inside a folder, LÖVE does not find it.
if command -v unzip >/dev/null 2>&1; then
  # Whole listing into a variable first: `unzip | grep -q` under pipefail gives a FALSE negative
  # (grep -q exits on the first match, unzip dies of SIGPIPE and the pipe counts as failed).
  LISTING="$(unzip -Z1 "$LOVE")" || die "$LOVE is not a readable zip"
  grep -qx "main.lua" <<<"$LISTING" || die "$LOVE has no main.lua at the root of the zip"
fi
BASH5="$(command -v bash)"
"$BASH5" -c '[[ ${BASH_VERSINFO[0]} -ge 4 ]]' || BASH5=/opt/homebrew/bin/bash
[[ -x "$BASH5" ]] || die "bash 4+ is required (on macOS: brew install bash)"

mkdir -p "$OUT"
EXTRA=(--extra "$LOVE:game.love")
[[ -f "$HERE/THIRD_PARTY_NOTICES.txt" ]] && EXTRA+=(--extra "$HERE/THIRD_PARTY_NOTICES.txt:THIRD_PARTY_NOTICES.txt")
"$BASH5" "$HERE/make-pkg-plus.sh" --eboot "$HERE/eboot.bin" --out-dir "$OUT" \
  --title-id "$TITLE_ID" --title "$TITLE" --version "$VERSION" \
  --content-label "${LABEL:-$TITLE_ID}" --icon "$ICON" --modules "$HERE/sce_module" "${EXTRA[@]}"
