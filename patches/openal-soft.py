#!/usr/bin/env python3
"""Parches de openal-soft 1.23.1 para PS4. Idempotente: se puede correr varias veces.

Uno solo. `create-fself` falla con `missing library for symbol
(_ZTHN10ALCcontext13sLocalContextE)`: cuando un thread_local se accede desde otro archivo,
el compilador emite una referencia DEBIL a su funcion de inicializacion de TLS (_ZTH...),
que queda sin definir si no hace falta. En ELF es legal, pero create-fself intenta asignarle
una biblioteca del sistema a CADA simbolo sin definir. openal-soft ya resuelve exactamente
esto para MinGW: getThreadContext/setThreadContext se definen solo en context.cpp, donde
viven los thread_local. Se activa ese mismo camino en Orbis. Verificado: las 12 referencias
a sLocalContext/sThreadContext del arbol estan en context.cpp y context.h.
"""
import pathlib, sys

A = pathlib.Path(__file__).resolve().parent.parent / "deps/openal-soft"
applied, skipped = [], []

def patch(relpath, old, new, tag):
    p = A / relpath
    s = p.read_text()
    if new in s:
        skipped.append(tag); return
    if old not in s:
        print(f"!! ANCLA NO ENCONTRADA: {tag}  ({relpath})"); sys.exit(1)
    p.write_text(s.replace(old, new, 1))
    applied.append(tag)

patch("alc/context.h",
"#ifdef __MINGW32__\n    static ALCcontext *getThreadContext() noexcept;",
"#if defined(__MINGW32__) || defined(__ORBIS__)\n    static ALCcontext *getThreadContext() noexcept;",
"context.h: acceso al thread_local solo en context.cpp")

patch("alc/context.cpp",
"#ifdef __MINGW32__\nALCcontext *ALCcontext::getThreadContext() noexcept",
"#if defined(__MINGW32__) || defined(__ORBIS__)\nALCcontext *ALCcontext::getThreadContext() noexcept",
"context.cpp: acceso al thread_local solo en context.cpp")

print("APLICADOS:")
for a in applied: print("   +", a)
if skipped:
    print("YA ESTABAN:")
    for s in skipped: print("   =", s)
