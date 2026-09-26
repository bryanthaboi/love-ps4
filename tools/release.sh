#!/usr/bin/env bash
# Arma una release del runtime DESDE CERO y la deja en dist/love-ps4-<version>/:
#
#   love-ps4-<v>.pkg            el runtime solo (corre /data/love/game.love); title id FIJO
#   love-ps4-<v>-runtime.zip    lo que necesita quien fusiona un juego (eboot.bin, los .prx,
#                               fuse-pkg.sh, make-pkg-plus.sh, icono, avisos): lo baja la CI de
#                               gen1recomp, como baja love-nx para la Switch
#   THIRD_PARTY_NOTICES.txt     licencias de todo lo enlazado (tambien va dentro del pkg y del zip)
#   sha256sums.txt
#
#   tools/release.sh 1.0.0                  # exige arbol limpio y diffs de terceros al dia
#   tools/release.sh 1.0.0 --allow-dirty    # para ensayar el script; NO para publicar
#
# Diferencias con el build de desarrollo (build/love), todas a proposito:
#   - build/release se configura de cero en cada corrida: nada heredado de un cache tocado a mano.
#   - netlog APAGADO (LOVE_PS4_NETLOG_HOST vacio): el de desarrollo manda UDP a la IP de la Mac.
#   - diagnosticos (GUARD_*, CRASHTRACE) apagados y VERIFICADOS en el cache, no supuestos.
#   - title id fijo y APP_VER derivado de la version: una release nueva se instala ENCIMA de la
#     anterior (actualizacion) en vez de ser otra app. ⚠ Sin probar en consola todavia.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

die() { echo "release: FALLO - $*" >&2; exit 1; }
say() { echo "release: $*"; }

VER="${1:-}"; shift || true
ALLOW_DIRTY=0
TITLE_ID="${LOVE_PS4_TITLE_ID:-LOVE00001}"
TITLE="${LOVE_PS4_TITLE:-LÖVE for PS4}"
ICON="${LOVE_PS4_ICON:-gl/icon-love.png}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    *) die "argumento desconocido: $1" ;;
  esac
done

# X.Y.Z -> APP_VER "0X.YZ" (el formato de la PS4 es NN.NN). Por eso Y y Z van de 0 a 9.
[[ "$VER" =~ ^([0-9]{1,2})\.([0-9])\.([0-9])$ ]] \
  || die "version '$VER': tiene que ser X.Y.Z con Y y Z de un digito (APP_VER de la PS4 es NN.NN)"
APP_VER="$(printf '%02d.%d%d' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")"

export PATH="/opt/homebrew/bin:/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin:$PATH"
# shellcheck disable=SC1090
SDK_BUNDLE="${ORBIS_SDK_BUNDLE:-$HOME/.local/opt/orbis-sdk-v1}"
. "$SDK_BUNDLE/env.sh" >/dev/null
BASH5=/opt/homebrew/bin/bash
[[ -x "$BASH5" ]] || die "falta bash 5 en $BASH5 (el empaquetador usa \${VAR^^})"

# ---------------------------------------------------------------- 1. el arbol
if [[ $ALLOW_DIRTY -eq 0 ]]; then
  [[ -z "$(git status --porcelain)" ]] || die "hay cambios sin commitear (o --allow-dirty para ensayar)"
fi
tools/snapshot-trees.sh --check || die "un diff de terceros quedo viejo: tools/snapshot-trees.sh y commitear"
COMMIT="$(git rev-parse --short HEAD)"
[[ $ALLOW_DIRTY -eq 1 && -n "$(git status --porcelain)" ]] && COMMIT="$COMMIT-dirty"
say "version $VER (APP_VER $APP_VER), title id $TITLE_ID, commit $COMMIT"

# ---------------------------------------------------------------- 2. build de cero
B=build/release
rm -rf "$B"
CM=(-S love-ps4 -B "$B" -G Ninja
    "-DCMAKE_TOOLCHAIN_FILE=$SDK_BUNDLE/toolchain/orbis-sdk.cmake"
    -DLOVE_PS4_REALLOC_COPY=ON -DLOVE_PS4_OPENAL=SOFT -DLOVE_PS4_LUA=LUAJIT
    -DLOVE_PS4_GUARD_ALLOC=OFF -DLOVE_PS4_GUARD_MALLOC=OFF -DLOVE_PS4_CRASHTRACE=OFF
    "-DLOVE_PS4_NETLOG_HOST=")
cmake "${CM[@]}" > "$B.configure.log" 2>&1 || { tail -20 "$B.configure.log"; die "cmake configure"; }
say "compilando (log: $B.build.log)"
cmake --build "$B" > "$B.build.log" 2>&1 || { tail -30 "$B.build.log"; die "cmake --build"; }

# ---------------------------------------------------------------- 3. verificar el artefacto
C="$B/CMakeCache.txt"
opt() { grep -E "^$1:" "$C" | sed -E 's/^[^=]*=//'; }
[[ "$(opt LOVE_PS4_GUARD_ALLOC)"  == "OFF" ]] || die "GUARD_ALLOC no esta OFF en $C"
[[ "$(opt LOVE_PS4_GUARD_MALLOC)" == "OFF" ]] || die "GUARD_MALLOC no esta OFF en $C"
[[ "$(opt LOVE_PS4_CRASHTRACE)"   == "OFF" ]] || die "CRASHTRACE no esta OFF en $C"
[[ "$(opt LOVE_PS4_REALLOC_COPY)" == "ON"  ]] || die "REALLOC_COPY no esta ON en $C"
[[ "$(opt LOVE_PS4_LUA)"          == "LUAJIT" ]] || die "LUA no es LUAJIT en $C"
[[ "$(opt LOVE_PS4_OPENAL)"       == "SOFT" ]] || die "OPENAL no es SOFT en $C"
[[ -z "$(opt LOVE_PS4_NETLOG_HOST)" ]] || die "NETLOG_HOST no esta vacio en $C"
[[ -f "$B/love.oelf" && -f "$B/eboot.bin" ]] || die "no estan $B/love.oelf y $B/eboot.bin"
# Sobre el .oelf, no sobre eboot.bin: el fSELF es otro contenedor (lessons.md).
if strings "$B/love.oelf" | grep -qE '192\.168\.[0-9]+\.[0-9]+'; then
  die "hay una IP de la LAN dentro de love.oelf: $(strings "$B/love.oelf" | grep -oE '192\.168\.[0-9]+\.[0-9]+' | sort -u | tr '\n' ' ')"
fi
say "artefacto verificado: opciones canonicas, netlog apagado, sin IPs de la LAN"

# ---------------------------------------------------------------- 4. dist
N="love-ps4-$VER"
D="dist/$N"
rm -rf "$D"; mkdir -p "$D"
NOTICES="$D/THIRD_PARTY_NOTICES.txt"
tools/third-party-notices.sh "$NOTICES"

# El pkg del runtime solo. Los avisos van DENTRO (la licencia pide acompanar cada copia).
"$BASH5" tools/make-pkg-plus.sh --eboot "$B/eboot.bin" --out-dir "$B" \
  --title-id "$TITLE_ID" --title "$TITLE" --version "$APP_VER" --content-label LOVEPS4 \
  --icon "$ICON" --extra "$NOTICES:THIRD_PARTY_NOTICES.txt" > "$B.pkg.log" 2>&1 \
  || { cat "$B.pkg.log"; die "make-pkg-plus"; }
PKG="$(ls "$B"/IV0000-"$TITLE_ID"_00-*.pkg)"
cp "$PKG" "$D/$N.pkg"

# El zip para fusionar juegos.
R="$D/$N-runtime"
mkdir -p "$R/sce_module"
cp "$B/eboot.bin" "$R/"
MODS="$SDK_BUNDLE/sdk/src/modules"
for prx in libc libSceFios2; do
  [[ -f "$MODS/$prx.prx" ]] || die "falta $MODS/$prx.prx (NOTAS.md: sacarlo del release de OpenOrbis)"
  cp "$MODS/$prx.prx" "$R/sce_module/"
done
cp tools/fuse-pkg.sh tools/make-pkg-plus.sh "$ICON" "$NOTICES" "$R/"
mv "$R/$(basename "$ICON")" "$R/icon0.png"
cp LICENSE "$R/LICENSE-love-ps4.txt"
cat > "$R/VERSION" <<EOF
love-ps4 $VER
app_ver $APP_VER
commit $COMMIT
love 11.5
built $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
(cd "$D" && zip -qr "$N-runtime.zip" "$N-runtime" && rm -rf "$N-runtime")

(cd "$D" && shasum -a 256 "$N.pkg" "$N-runtime.zip" THIRD_PARTY_NOTICES.txt > sha256sums.txt)
say "listo: $D"
ls -l "$D" | sed 's/^/   /'
cat "$D/sha256sums.txt" | sed 's/^/   /'
