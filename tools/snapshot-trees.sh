#!/usr/bin/env bash
# Guarda en patches/*.diff el diff COMPLETO de cada arbol de terceros contra su commit oficial,
# y lo VERIFICA: clona ese commit limpio, aplica el diff y compara archivo por archivo con el
# arbol que anda. Si algo no coincide, falla.
#
#   tools/snapshot-trees.sh           # regenera patches/*.diff y los verifica
#   tools/snapshot-trees.sh --check   # NO escribe nada: falla si algun diff quedo viejo
#                                     # respecto del arbol (o sea: faltaria un snapshot)
#
# Existe porque los scripts de parches (patches/*.py) resultaron INCOMPLETOS: el 22-sep, al
# aplicarlos sobre un LOVE 11.5 limpio, 14 archivos y 2 nuevos no se reproducian (ediciones a
# mano de la primera noche) y el script se detenia en un ancla que nunca se inserta. El diff es
# exacto por construccion: captura cualquier cambio, se haga como se haga.
#
# Regla: despues de tocar love/, gen1recomp/, deps/openal-soft/ o deps/luajit/ (a mano o con un script),
# correr esto y commitear los diffs. Los archivos NUEVOS de un arbol van por lista explicita
# en patches/TREES, para que no se cuele basura sin trackear.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
SCR=$(mktemp -d); trap 'rm -rf "$SCR"' EXIT
# ruta absoluta de la salida: relativa a la raiz del repo, o ya absoluta en modo --check
o() { [[ "$out" = /* ]] && echo "$out" || echo "$ROOT/$out"; }
fail=0
CHECK=0; [[ "${1:-}" == "--check" ]] && CHECK=1

while read -r dir url commit diff news; do
  [[ -z "${dir:-}" || "$dir" == \#* || "$diff" == "-" ]] && continue
  out="patches/$diff"
  committed="patches/$diff"
  [[ $CHECK -eq 1 ]] && out="$SCR/check-$diff"   # en --check se genera aparte y se compara
  [[ "$(git -C "$dir" rev-parse HEAD)" == "$commit" ]] || { echo "!! $dir no esta en $commit (patches/TREES)"; fail=1; continue; }

  # 1. el diff: cambios en archivos trackeados + los archivos nuevos listados
  # --full-index: el hash abreviado de las lineas "index" crece cuando el repo tiene mas objetos
  # (un git fetch lo paso de 7 a 8 el 25-sep) y --check daba "VIEJO" sin ningun cambio real.
  git -C "$dir" diff --binary --full-index "$commit" > "$(o)"
  newlist=()
  if [[ "$news" != "-" ]]; then IFS=',' read -r -a newlist <<< "$news"; fi
  for f in "${newlist[@]}"; do
    [[ -f "$dir/$f" ]] || { echo "!! $dir/$f listado en TREES pero no existe"; fail=1; continue; }
    (cd "$dir" && git diff --binary --full-index --no-index /dev/null "$f") >> "$(o)"
  done

  # 2. la verificacion: commit limpio + diff == arbol que anda
  c="$SCR/$(basename "$dir")"
  git clone -q --no-checkout "$ROOT/$dir" "$c" && git -C "$c" checkout -q "$commit" 2>/dev/null
  if ! (cd "$c" && git apply --binary "$(o)"); then
    echo "!! $dir: el diff NO aplica sobre $commit"; fail=1; continue
  fi
  changed=$( (git -C "$dir" diff --name-only "$commit"; printf '%s\n' "${newlist[@]}") | sed '/^$/d' | sort -u)
  bad=0
  while read -r f; do
    cmp -s "$dir/$f" "$c/$f" || { echo "!! $dir/$f: la copia rehecha NO coincide"; bad=1; }
  done <<< "$changed"
  extra=$(git -C "$c" status --short | awk '{print $2}' | sort -u | comm -23 - <(printf '%s\n' "$changed"))
  [[ -n "$extra" ]] && { echo "!! $dir: el diff toca archivos de mas: $extra"; bad=1; }
  n=$(printf '%s\n' "$changed" | sed '/^$/d' | wc -l | tr -d ' ')
  if [[ $CHECK -eq 1 && $bad -eq 0 ]]; then
    if cmp -s "$out" "$committed"; then echo "ok  $dir: $committed al dia"
    else echo "!! $dir: $committed quedo VIEJO respecto del arbol -> correr tools/snapshot-trees.sh"; fail=1; fi
    continue
  fi
  if [[ $bad -eq 0 ]]; then
    echo "ok  $dir -> $out  ($n archivos, $(wc -c < "$(o)" | tr -d ' ') bytes, verificado sobre ${commit:0:10})"
  else
    fail=1
  fi
done < patches/TREES

exit $fail
