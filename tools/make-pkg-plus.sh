#!/usr/bin/env bash
# Build a fake-signed PS4 .pkg from an already-created eboot.bin.
#
#   scripts/ps4/make-pkg.sh --eboot <eboot.bin> --out-dir <dir> \
#       --title-id TMPS10001 --title "Tempest Hello" [--version 01.00] \
#       [--content-label TEMPESTHELLO0000] [--icon <png>] [--sdk <path>] \
#       [--modules <dir>] [--extra <src>:<targ_path>]...
#
# Derived from orbis-compat's scripts/ps4/make-pkg.sh (orbis-ports/orbis-compat):
#   Copyright (c) 2026 Mikołaj Mikołajczyk. MIT License: permission is hereby granted, free
#   of charge, to any person obtaining a copy of this software and associated documentation
#   files (the "Software"), to deal in the Software without restriction, including without
#   limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
#   sell copies of the Software, and to permit persons to whom the Software is furnished to do
#   so, subject to the following conditions: the above copyright notice and this permission
#   notice shall be included in all copies or substantial portions of the Software.
#   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
#   INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
#   PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
#   FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
#   OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
#   DEALINGS IN THE SOFTWARE.
# love-ps4 changes: --modules and --extra, and the FORMAT / PARENTAL_LEVEL keys (see below).
#
# --modules: where libc.prx and libSceFios2.prx come from. Default: $SDK/src/modules. The
# published runtime ships them in its zip, so fusing a game needs only the SDK packaging tools
# (PkgTool.Core, create-gp4), not the whole SDK.
#
# Recipe mirrors the OpenOrbis SDK sample rule (samples/hello_world/Makefile),
# which is the only normative description of the packaging steps:
#   PkgTool.Core sfo_new / sfo_setentry  -> sce_sys/param.sfo
#   create-gp4 --content-id --files      -> pkg.gp4
#   PkgTool.Core pkg_build               -> <CONTENT_ID>.pkg
#
# PkgTool.Core is an old self-contained .NET build with two host quirks:
#   * its crypto shim dlopen()s OpenSSL 1.x by soname and knows nothing of 3 -> see the probe
#   * it has no ICU in its closure -> DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
# The flake devShell exports both; outside it this script resolves the library itself.
set -euo pipefail

die() { echo "make-pkg: $*" >&2; exit 1; }

EBOOT=""
OUT_DIR=""
TITLE_ID=""
TITLE=""
VERSION="01.00"
CONTENT_LABEL=""
ICON=""
SDK="${OO_PS4_TOOLCHAIN:-$HOME/.local/opt/openorbis}"
EXTRAS=()
MODULES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --eboot)         EBOOT="$2";         shift 2 ;;
    --out-dir)       OUT_DIR="$2";       shift 2 ;;
    --title-id)      TITLE_ID="$2";      shift 2 ;;
    --title)         TITLE="$2";         shift 2 ;;
    --version)       VERSION="$2";       shift 2 ;;
    --content-label) CONTENT_LABEL="$2"; shift 2 ;;
    --icon)          ICON="$2";          shift 2 ;;
    --sdk)           SDK="$2";           shift 2 ;;
    --extra)         EXTRAS+=("$2");     shift 2 ;;
    --modules)       MODULES="$2";       shift 2 ;;
    -h|--help)       sed -n '2,16p' "$0"; exit 0 ;;
    *)               die "unknown argument: $1" ;;
  esac
done

[[ -n "$EBOOT"    ]] || die "--eboot is required"
[[ -n "$OUT_DIR"  ]] || die "--out-dir is required"
[[ -n "$TITLE_ID" ]] || die "--title-id is required"
[[ -n "$TITLE"    ]] || die "--title is required"
[[ -f "$EBOOT"    ]] || die "eboot not found: $EBOOT"

# TITLE_ID is 4 letters + 5 digits; param.sfo and the content ID both embed it.
[[ "$TITLE_ID" =~ ^[A-Z]{4}[0-9]{5}$ ]] || die "TITLE_ID must be AAAA00000, got '$TITLE_ID'"

if [[ "$(uname -s)" == "Darwin" ]]; then
  BINDIR="$SDK/bin/macos"
else
  BINDIR="$SDK/bin/linux"
fi
PKGTOOL="$BINDIR/PkgTool.Core"
CREATE_GP4="$BINDIR/create-gp4"
MODULES="${MODULES:-$SDK/src/modules}"
[[ -x "$PKGTOOL"    ]] || die "PkgTool.Core not found at $PKGTOOL (set OO_PS4_TOOLCHAIN)"
[[ -x "$CREATE_GP4" ]] || die "create-gp4 not found at $CREATE_GP4 (set OO_PS4_TOOLCHAIN)"

# CONTENT_ID layout, copied from every OpenOrbis sample:
#   <6-char publisher>-<TITLE_ID>_00-<16-char label>
if [[ -z "$CONTENT_LABEL" ]]; then
  CONTENT_LABEL="$TITLE_ID"
fi
CONTENT_LABEL="${CONTENT_LABEL^^}"
CONTENT_LABEL="${CONTENT_LABEL//[^A-Z0-9]/}"
CONTENT_LABEL="${CONTENT_LABEL}0000000000000000"
CONTENT_LABEL="${CONTENT_LABEL:0:16}"
CONTENT_ID="IV0000-${TITLE_ID}_00-${CONTENT_LABEL}"

export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# ⚠ WHAT PkgTool.Core ACTUALLY DLOPENS, measured with `strings bin/linux/PkgTool.Core`: five
# candidate sonames - libssl.so.1.1, libssl.so.1.0.2, libssl.so.1.0.0, libssl.so.10, libssl.so. -
# and libssl.so.3 is NOT among them. So every current distro and every GitHub runner, which ship
# OpenSSL 3 alone, build and link the port 100%, produce an eboot, and only THEN die in pkg_build
# with "No usable version of libssl was found" - core dumped, and make deletes the fresh .elf on
# its way out. bin/macos/PkgTool.Core names none of those sonames (no libssl/libcrypto string in
# the binary at all; `otool -L` lists libc++ and libSystem only) because the macOS .NET build uses
# Apple's crypto - nothing here is fatal on Darwin.
#
# ⚠ THIS PROBE USED TO BE THREE COPIES OF A WORKFLOW STEP - orbis-compat sdk-bundle.yml,
# OpenGothic ps4.yml, RetroArch frontend.yml - each unpacking the same .deb into a different
# directory and exporting PS4_PKGTOOL_OPENSSL_LIB. It belongs in the one place that runs
# PkgTool.Core. Order is by cost: what the caller already knows, then what the host already has,
# then the network.
openssl1x_dir() {
  local dir soname
  # 1.1 first because it is what the OpenOrbis samples were built against; the 1.0 sonames are
  # accepted by the same shim and are what an older or a compat package provides.
  local sonames=(
    libssl.so.1.1 libssl.so.1.0.2 libssl.so.1.0.0 libssl.so.10
    libssl.1.1.dylib libssl.1.0.0.dylib
  )
  # Linux first (the only platform where this is load-bearing), macOS after it. Homebrew's
  # openssl@1.1 is keg-only, so it is never on the default loader path and has to be named;
  # both prefixes are listed because `brew --prefix` is absent on a host without Homebrew.
  local dirs=(
    /nix/store/*-openssl-1.1*/lib
    /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/lib64 /usr/local/lib /usr/lib
    /opt/homebrew/opt/openssl@1.1/lib /usr/local/opt/openssl@1.1/lib
  )
  local brew_lib
  if command -v brew >/dev/null 2>&1; then
    brew_lib="$(brew --prefix openssl@1.1 2>/dev/null || true)"
    [[ -n "$brew_lib" ]] && dirs=("$brew_lib/lib" "${dirs[@]}")
  fi
  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue   # an unmatched /nix/store glob arrives here literally
    for soname in "${sonames[@]}"; do
      [[ -e "$dir/$soname" ]] && { printf '%s\n' "$dir"; return 0; }
    done
  done
  return 1
}

# Ubuntu dropped libssl1.1 from the archive at noble, so there is no package to apt-get install;
# the security pool still publishes the .deb and it gets unpacked by hand. The exact filename
# floats with the pool's latest security upload, so it is discovered rather than named. Cached
# under orbis-env.sh's work root, so a second package build in the same checkout refetches
# nothing. amd64 only - the .deb has no other arch and the tool is an x86-64 ELF anyway.
fetch_openssl1x() {
  local lib="${ORBIS_WORK:-${XDG_CACHE_HOME:-${HOME}/.cache}/orbis-ports}/openssl11/lib"
  if [[ ! -e "$lib/libssl.so.1.1" ]]; then
    local base=http://security.ubuntu.com/ubuntu/pool/main/o/openssl
    local tmp; tmp="$(mktemp -d)"
    command -v dpkg-deb >/dev/null 2>&1 \
      || die "no OpenSSL 1.x for PkgTool.Core and no dpkg-deb to unpack one; install your distro's OpenSSL 1.1 compat package or set PS4_PKGTOOL_OPENSSL_LIB"
    curl -sSfL --max-time 120 -o "$tmp/index.html" "$base/" \
      || die "cannot reach $base to fetch libssl1.1; set PS4_PKGTOOL_OPENSSL_LIB to a directory holding libssl.so.1.1"
    # Read the saved index rather than piping curl into grep: under `set -o pipefail` a grep that
    # matches nothing takes the whole pipeline's status and the die below would never be reached.
    local deb
    deb="$(LC_ALL=C grep -oE 'libssl1\.1_[^"]*_amd64\.deb' "$tmp/index.html" | LC_ALL=C sort -V | tail -1 || true)"
    [[ -n "$deb" ]] || die "no libssl1.1 .deb listed at $base; set PS4_PKGTOOL_OPENSSL_LIB instead"
    curl -sSfL --max-time 120 -o "$tmp/libssl.deb" "$base/$deb" || die "failed to download $base/$deb"
    dpkg-deb -x "$tmp/libssl.deb" "$tmp/x"
    mkdir -p "$lib"
    # libcrypto too: the shim resolves its symbols out of the same directory and a lone libssl
    # would dlopen and then fail on the first EVP call.
    cp -a "$tmp"/x/usr/lib/x86_64-linux-gnu/lib{ssl,crypto}.so.1.1 "$lib"/
    rm -rf "$tmp"
  fi
  printf '%s\n' "$lib"
}

if [[ -z "${PS4_PKGTOOL_OPENSSL_LIB:-}" ]]; then
  PS4_PKGTOOL_OPENSSL_LIB="$(openssl1x_dir || true)"
fi
if [[ -z "$PS4_PKGTOOL_OPENSSL_LIB" && "$(uname -s)" == "Linux" && "$(uname -m)" == "x86_64" ]]; then
  PS4_PKGTOOL_OPENSSL_LIB="$(fetch_openssl1x)"
fi
if [[ -n "$PS4_PKGTOOL_OPENSSL_LIB" ]]; then
  # Both loader variables, not one per platform: the Linux tool reads LD_LIBRARY_PATH, dyld reads
  # DYLD_LIBRARY_PATH, and setting the one the host ignores costs nothing.
  export LD_LIBRARY_PATH="${PS4_PKGTOOL_OPENSSL_LIB}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export DYLD_LIBRARY_PATH="${PS4_PKGTOOL_OPENSSL_LIB}${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
elif [[ "$(uname -s)" != "Darwin" ]]; then
  die "no libssl.so.1.1 for PkgTool.Core on $(uname -s)/$(uname -m); install an OpenSSL 1.1 compat package (Fedora/RHEL: compat-openssl11, Arch: openssl-1.1, nix: nixpkgs#openssl_1_1) or set PS4_PKGTOOL_OPENSSL_LIB to the directory holding it"
fi

STAGE="$OUT_DIR/pkg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/sce_sys" "$STAGE/sce_module"

cp -f "$EBOOT" "$STAGE/eboot.bin"

# libc / libSceFios2 are the two PRXs every OpenOrbis title ships; the loader
# resolves them from /app0/sce_module before falling back to system modules.
for prx in libc libSceFios2; do
  if [[ -f "$MODULES/$prx.prx" ]]; then
    cp -f "$MODULES/$prx.prx" "$STAGE/sce_module/$prx.prx"
  fi
done

GP4_FILES=("eboot.bin" "sce_sys/param.sfo")
for prx in libc libSceFios2; do
  [[ -f "$STAGE/sce_module/$prx.prx" ]] && GP4_FILES+=("sce_module/$prx.prx")
done

if [[ -n "$ICON" && -f "$ICON" ]]; then
  cp -f "$ICON" "$STAGE/sce_sys/icon0.png"
  GP4_FILES+=("sce_sys/icon0.png")
fi

EXTRA_DIRS=()
for spec in ${EXTRAS+"${EXTRAS[@]}"}; do
  src="${spec%%:*}"
  targ="${spec#*:}"
  [[ -f "$src" ]] || die "extra file not found: $src"
  mkdir -p "$STAGE/$(dirname "$targ")"
  cp -f "$src" "$STAGE/$targ"
  GP4_FILES+=("$targ")
  # Every ancestor directory of the target, because of the .gp4 quirk below.
  d="$(dirname "$targ")"
  while [[ "$d" != "." && "$d" != "/" ]]; do
    EXTRA_DIRS+=("$d")
    d="$(dirname "$d")"
  done
done

# create-gp4 emits a FIXED <rootdir>: sce_sys (+about), sce_module and assets with five
# hard-coded children. LibOrbisPkg's PfsProperties.BuildFSTree then resolves every file's
# targ_path against that tree, and a file in a directory the tree does not declare dies in
# FindDir with "Sequence contains no elements" - so --extra has only ever worked for a
# target at the package root or inside one of those seven directories. ps4/gapi-suite is
# the first caller to pass --extra at all (it ships /app0/shader and /app0/assets/gapi, the
# paths Tests/tests/gapi's own bodies open), and it needs two directories create-gp4 does
# not know about.
#
# So the rootdir is REBUILT here from the union of what create-gp4 declared and what the
# extras need, rather than appended to: a second top-level <dir targ_name="assets"> would
# be a different node from the first, and FindDir would keep finding the one without the
# new child. Runs only when there are extras, so a package without them is byte-identical
# to what this script produced before.
gp4_patch_rootdir() {
  local gp4="$1"; shift
  [[ "$#" -gt 0 ]] || return 0
  local tmp; tmp="$(mktemp)"
  {
    sed -n '1,/<rootdir>/p' "$gp4"
    {
      # Directories create-gp4 declared, as full paths.
      awk '
        /<rootdir>/ { inr=1; next }
        /<\/rootdir>/ { inr=0 }
        !inr { next }
        {
          line=$0
          if(match(line,/targ_name="[^"]*"/)) {
            name=substr(line,RSTART+11,RLENGTH-12)
            path=(depth>0 ? stack[depth] "/" name : name)
            print path
            if(line ~ /\/>[[:space:]]*$/) next
            stack[++depth]=path
            next
          }
          if(line ~ /<\/dir>/) depth--
        }' "$gp4"
      printf '%s\n' "$@"
    } | LC_ALL=C sort -u | awk -F/ '
        {
          # Close deeper-or-equal levels, then open this one. Paths arrive sorted, so a
          # parent always precedes its children.
          while(open>0 && substr($0,1,length(cur[open])+1)!=(cur[open] "/")) {
            printf("%s</dir>\n",ind(open)); open--
          }
          cur[++open]=$0
          printf("%s<dir targ_name=\"%s\">\n",ind(open),$NF)
        }
        END { while(open>0) { printf("%s</dir>\n",ind(open)); open-- } }
        function ind(n,  s,i) { s="\t\t"; for(i=1;i<n;i++) s=s "\t"; return s }'
    sed -n '/<\/rootdir>/,$p' "$gp4"
  } > "$tmp"
  mv -f "$tmp" "$gp4"
}

SFO="$STAGE/sce_sys/param.sfo"
"$PKGTOOL" sfo_new "$SFO" > /dev/null
sfo_set() { "$PKGTOOL" sfo_setentry "$SFO" "$1" --type "$2" --maxsize "$3" --value "$4" > /dev/null; }
sfo_set APP_TYPE           Integer 4   1
sfo_set APP_VER            Utf8    8   "$VERSION"
sfo_set ATTRIBUTE          Integer 4   0
sfo_set CATEGORY           Utf8    4   gd
sfo_set CONTENT_ID         Utf8    48  "$CONTENT_ID"
sfo_set DOWNLOAD_DATA_SIZE Integer 4   0
sfo_set SYSTEM_VER         Integer 4   0
sfo_set TITLE              Utf8    128 "$TITLE"
sfo_set TITLE_ID           Utf8    12  "$TITLE_ID"
# --- love-ps4: two keys every real PS4 pkg carries and the original script left out.
# Without them the installer may reject the SFO (SCE_BGFT_ERROR_INVALID_ARGUMENT, 0x80990004).
sfo_set FORMAT             Utf8    4   obs
sfo_set PARENTAL_LEVEL     Integer 4   1
sfo_set VERSION            Utf8    8   "$VERSION"

# create-gp4 records orig_path verbatim, so it must run with the stage as cwd.
(
  cd "$STAGE"
  "$CREATE_GP4" -out pkg.gp4 --content-id="$CONTENT_ID" --files "${GP4_FILES[*]}" > /dev/null
  gp4_patch_rootdir pkg.gp4 ${EXTRA_DIRS+"${EXTRA_DIRS[@]}"}
  "$PKGTOOL" pkg_build pkg.gp4 . > pkg-build.log 2>&1 || {
    cat pkg-build.log >&2
    exit 1
  }
)

PKG="$STAGE/$CONTENT_ID.pkg"
[[ -f "$PKG" ]] || {
  sed -n '1,40p' "$STAGE/pkg-build.log" >&2 2>/dev/null || true
  die "PkgTool.Core produced no $CONTENT_ID.pkg"
}

mv -f "$PKG" "$OUT_DIR/$CONTENT_ID.pkg"
ln -sf "$CONTENT_ID.pkg" "$OUT_DIR/$TITLE_ID.pkg"
echo "pkg: $OUT_DIR/$CONTENT_ID.pkg ($(du -h "$OUT_DIR/$CONTENT_ID.pkg" | cut -f1))"
