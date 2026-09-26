#!/usr/bin/env bash
# Rehace desde cero los arboles de terceros: clona cada uno en su commit exacto (patches/TREES)
# y le aplica su diff (patches/*.diff). NO toca un arbol que ya existe.
#
#   tools/restore-trees.sh            # clona de las URLs de patches/TREES
#   tools/restore-trees.sh <destino>  # rehacer en otro lado (p. ej. para probar)
#
# Despues: deps/build-deps.sh, el build de SDL2 (build/sdl2) y cmake (ver README).
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
DEST="${1:-$ROOT}"
SRC_OVERRIDE="${RESTORE_FROM:-}"   # solo para pruebas: clonar de un checkout local
fail=0
while read -r dir url commit diff news; do
  [[ -z "${dir:-}" || "$dir" == \#* ]] && continue
  t="$DEST/$dir"
  if [[ -e "$t" ]]; then echo "=   $dir ya existe: no se toca"; continue; fi
  src="$url"; [[ -n "$SRC_OVERRIDE" ]] && src="$SRC_OVERRIDE/$dir"
  mkdir -p "$(dirname "$t")"
  git clone -q --no-checkout "$src" "$t" && git -C "$t" checkout -q "$commit" \
    || { echo "!!  $dir: no pude clonar $src @ $commit"; fail=1; continue; }
  if [[ "$diff" != "-" ]]; then
    (cd "$t" && git apply --binary "$ROOT/patches/$diff") \
      || { echo "!!  $dir: $diff no aplica"; fail=1; continue; }
  fi
  if [[ "$diff" != "-" ]]; then echo "ok  $dir @ ${commit:0:10} + $diff"; else echo "ok  $dir @ ${commit:0:10} (sin cambios)"; fi
done < patches/TREES
exit $fail
