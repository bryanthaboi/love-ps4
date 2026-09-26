#!/usr/bin/env bash
# Re-deriva del binario el offset de `libc.threaded` dentro de `__libc` y lo
# compara con el que se compilo.  Corre DESPUES de linkear, sobre el artefacto
# que se termina enviando a la consola.
#
#   tools/verify-libc-threaded.sh <love.oelf> <offset-esperado>
#
# Como: el gate del lock de musl compila a `cmpl $0x0, N(%rip)` y es lo primero
# que malloc consulta.  Se desensambla malloc, se toma ese primer gate, y como
# llvm-objdump ya anota la direccion absoluta del operando, se le resta `__libc`.
#
# Si esto falla NO hay que ajustar el numero sin mirar: significa que cambio el
# libc, y entonces hay que volver a leer el desensamblado y entender que paso.
# Un offset equivocado escribe un 1 en cualquier campo de la struct de musl.
#
# Nota: cada salida se materializa en una variable antes de filtrarla.  Un
# `grep -m1` o un `awk ...{exit}` sobre el pipe cierra la salida del productor,
# y el SIGPIPE resultante mata el script por pipefail -- lo que da un rc=141 que
# se confunde con "fallo la verificacion" y, peor, tambien con "paso".
set -euo pipefail

OELF="${1:?uso: verify-libc-threaded.sh <love.oelf> <offset-esperado>}"
WANT="${2:?falta el offset esperado}"

command -v llvm-objdump >/dev/null || { echo "verify-libc-threaded: falta llvm-objdump" >&2; exit 1; }
command -v llvm-nm      >/dev/null || { echo "verify-libc-threaded: falta llvm-nm" >&2; exit 1; }

SYMS=$(llvm-nm "$OELF")
MALLOC=$(printf '%s\n' "$SYMS" | awk '$3=="malloc" && tolower($2)=="t" {print $1}' | head -1)
LIBC=$(printf   '%s\n' "$SYMS" | awk '$3=="__libc"                     {print $1}' | head -1)
[[ -n "$MALLOC" ]] || { echo "verify-libc-threaded: no encontre 'malloc' en $OELF" >&2; exit 1; }
[[ -n "$LIBC"   ]] || { echo "verify-libc-threaded: no encontre '__libc' en $OELF" >&2; exit 1; }

START=$((0x$MALLOC))
DIS=$(llvm-objdump -d --start-address=$START --stop-address=$((START + 0x400)) \
        --no-show-raw-insn "$OELF")
GATE=$(printf '%s\n' "$DIS" \
       | grep -oE 'cmpl[[:space:]]+\$0x0,[^#]*#[[:space:]]*0x[0-9a-f]+' \
       | grep -oE '0x[0-9a-f]+$' | head -1)
[[ -n "$GATE" ]] || { echo "verify-libc-threaded: no hay gate 'cmpl \$0x0,...(%rip)' en los primeros 0x400 de malloc" >&2; exit 1; }

GOT=$(( GATE - 0x$LIBC ))
WANT_N=$(( WANT ))

if (( GOT != WANT_N )); then
  cat >&2 <<EOF
verify-libc-threaded: EL OFFSET NO COINCIDE

  __libc          0x$LIBC
  gate en malloc  $(printf '0x%x' "$GATE")
  offset real     $(printf '0x%x' "$GOT")
  compilado con   $(printf '0x%x' "$WANT_N")

Cambio el libc. NO ajustes el numero a ciegas: desensambla malloc y confirma que
ese gate sigue siendo el de \`libc.threaded\` antes de tocar el CMakeLists.
EOF
  exit 1
fi

echo "verify-libc-threaded: ok - libc.threaded en __libc+$(printf '0x%x' "$GOT")"
