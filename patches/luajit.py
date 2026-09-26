#!/usr/bin/env python3
"""Parches de LuaJIT 2.1 para el port de LOVE a PS4. Idempotente: se puede correr varias veces.

LuaJIT ya soporta PS4 de fabrica (con __ORBIS__: LJ_TARGET_PS4 + LJ_TARGET_CONSOLE), pensado
para el SDK oficial de Sony. Aca van solo las diferencias que necesita un homebrew con GoldHEN.
"""
import pathlib, sys, os

T = pathlib.Path(os.environ.get("LUAJIT_TREE") or pathlib.Path.home() / "Projects/love-ps4/deps/luajit")
applied, skipped = [], []

def patch(relpath, old, new, tag):
    p = T / relpath
    s = p.read_text()
    if new in s:
        skipped.append(tag); return
    if s.count(old) != 1:
        print(f"!! ANCLA NO ENCONTRADA O REPETIDA ({s.count(old)}): {tag}  ({relpath})")
        sys.exit(1)
    p.write_text(s.replace(old, new, 1))
    applied.append(tag)

# --- 1. os.getenv real. En consola LuaJIT lo deja devolviendo SIEMPRE nil (en el SDK de Sony no
#        hay entorno). Aca si lo hay: /data/love/env.txt lo llena al arrancar (parche 14 de
#        love-plataforma.py), y gen1recomp lee ~30 variables con os.getenv -- entre ellas
#        POKEPORT_AUDIO_RATE. Sin esto, env.txt dejaria de funcionar SIN AVISO: el juego no ve
#        las variables y vuelve a sus valores por defecto.
patch("src/lib_os.c",
"""LJLIB_CF(os_getenv)
{
#if LJ_TARGET_CONSOLE
  lua_pushnil(L);
#else""",
"""LJLIB_CF(os_getenv)
{
#if LJ_TARGET_CONSOLE && !LJ_TARGET_PS4  /* love-ps4: la PS4 homebrew si tiene getenv */
  lua_pushnil(L);
#else""",
"lib_os.c: os.getenv real en PS4")

print("APLICADOS:")
for a in applied: print("   +", a)
if skipped:
    print("YA ESTABAN:")
    for s in skipped: print("   =", s)
