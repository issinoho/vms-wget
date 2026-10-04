#!/usr/bin/env bash
# prepare.sh - build a VMS-ready source tree in staging/<name>-<version>/
#
#   1. fetch + verify the upstream tarball
#   2. extract it, apply patches/series, lay overlay/ over the top
#   3. run the upstream configure on this host, with every platform answer
#      taken from VMS probe results (probed.site) or hand-settled values
#      (vms-manual.site) instead of from Linux
#   4. generate gnulib's headers and config.h, copy them into the tree
#   5. write the MMS source lists and the configuration snapshot
#
# Nothing in staging/ is ever edited by hand: fix things in patches/ or overlay/.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"
name=$UPSTREAM_NAME-$UPSTREAM_VERSION
tarball=$top/cache/$(basename "$UPSTREAM_URL")
stage=$top/staging/$name
hostcfg=$top/cache/hostcfg-$name
cfgdir=$top/overlay/vms/config
snapshot=$top/snapshot
# Configuration answers come from this node's VSI C run; both architectures
# share one CRTL feature set (see docs/vms-environment.md).
PRIMARY_NODE=${PRIMARY_NODE:-ia64}
PRIMARY_TRIPLET=ia64-hp-openvms

step() { echo "prepare: $*"; }
die() { echo "prepare: error: $*" >&2; exit 1; }

"$top/tools/fetch.sh" >/dev/null

# --- 2. extract, patch, overlay -------------------------------------------
step "extracting $name"
rm -rf "$stage"
mkdir -p "$top/staging"
tar -xzf "$tarball" -C "$top/staging"
[ -d "$stage" ] || die "tarball did not unpack to $stage"

while read -r p; do
    case $p in ''|'#'*) continue ;; esac
    step "patch $p"
    patch -d "$stage" -p1 -s --no-backup-if-mismatch -F0 < "$top/patches/$p" ||
        die "patch $p does not apply cleanly"
done < "$top/patches/series"

# overlay/ may only add files; changes to upstream files belong in patches/.
(cd "$top/overlay" && find . -type f) | while read -r f; do
    [ -e "$stage/$f" ] && die "overlay/$f would replace an upstream file; use a patch"
    true
done
cp -a "$top/overlay/." "$stage/"

# --- 3. host configure with VMS answers ----------------------------------
step "configure (host, VMS answers)"
rm -rf "$hostcfg"
mkdir -p "$hostcfg"
site=$hostcfg/vms.site
# Answers: the VSI C configure run (vms_configure.sh) if there is one, else the
# function/header probes; vms-manual.site last so it always wins.
answers=$cfgdir/configure-$PRIMARY_NODE.cache
if [ ! -f "$answers" ]; then
    # First pass of a new release: stage the tree for vms_configure.sh, which
    # writes the answers.  The result is not buildable on VMS yet.
    answers=$hostcfg/no-answers.site; : > "$answers"
    step "WARNING: no $(basename "$cfgdir")/configure-$PRIMARY_NODE.cache yet:" \
         "Linux answers (run tools/vms_configure.sh, then prepare again)"
fi
step "answers from $(basename "$answers")"
python3 "$top/tools/nextheaders_site.py" "$stage/configure" "$cfgdir/crtl_modules.txt" \
    > "$cfgdir/next-headers.site"
cat "$answers" "$cfgdir/next-headers.site" "$cfgdir/vms-manual.site" > "$site"
mapfile -t cfgargs < <(grep -v -e '^#' -e '^$' "$cfgdir/configure.args")
# Same --host as vms_configure.sh so configure takes the same code paths.
# The library flags as in vms_configure.sh, so configure takes the same paths.
(cd "$hostcfg" && CONFIG_SITE=$site \
    ZLIB_CFLAGS=-I/zlib/include ZLIB_LIBS=-lz \
    OPENSSL_CFLAGS=-I/ssl3 OPENSSL_LIBS='-lssl -lcrypto' \
    PCRE2_CFLAGS=-I/pcre2/include PCRE2_LIBS=-lpcre2-8 \
    "$stage/configure" -q -C \
    --build="$("$stage/build-aux/config.guess")" --host=$PRIMARY_TRIPLET CC=gcc "${cfgargs[@]}" \
    > configure.out 2>&1) || { tail -20 "$hostcfg/configure.out"; die "configure failed"; }

# --- 4. generated headers and config.h -------------------------------------
printvar() {  # printvar <dir> <make variable>
    make -s -C "$hostcfg/$1" -f Makefile -f "$top/tools/printvar.mk" "print-$2"
}
built=$(printvar lib BUILT_SOURCES)
step "generating $(echo $built | wc -w) gnulib headers"
make -s -C "$hostcfg/lib" $built >/dev/null
for h in $built; do
    # Some are shipped in the source tree and not rebuilt (unicase tables).
    [ -f "$hostcfg/lib/$h" ] || { [ -f "$stage/lib/$h" ] && continue; die "no generated $h"; }
    mkdir -p "$stage/lib/$(dirname "$h")"
    cp "$hostcfg/lib/$h" "$stage/lib/$h"
done
cp "$hostcfg/src/config.h" "$stage/src/config.h"   # wget: AC_CONFIG_HEADERS([src/config.h])
# VSI C cannot #include a name with two dots: generated lib/malloc/*.gl.h
# become *_gl.h (patch 0003 includes them by that name on VMS).
for f in "$stage"/lib/malloc/*.gl.h; do
    [ -e "$f" ] || continue
    sed 's|<malloc/\([a-z_-]*\)\.gl\.h>|<malloc/\1_gl.h>|g' "$f" > "${f%.gl.h}_gl.h"
    rm "$f"
done

# --- 5. MMS source lists ---------------------------------------------------
# Objects for libgnu: automake sources after conditionals, plus LIBOBJS.
lib_srcs=$( { printvar lib libgnu_a_SOURCES
              printvar lib libgnu_a_LIBADD | tr ' ' '\n' | sed -n 's/^libgnu_a-//; s/\.o$/.c/p'
            } | tr ' ' '\n' | grep '\.c$' | sort -u)
# Leave out what cannot work on VMS (overlay/vms/lib-exclude.txt, with reasons).
while read -r pat; do
    case $pat in ''|'#'*) continue ;; esac
    lib_srcs=$(echo "$lib_srcs" | while read -r f; do
        case $(basename "$f") in $pat) ;; *) echo "$f" ;; esac; done)
done < "$top/overlay/vms/lib-exclude.txt"
# wget's sources after conditionals, plus version.c, which src/Makefile writes
# at build time (below, with the VMS compiler qualifiers).
src_srcs=$( { printvar src wget_SOURCES; echo version.c; } | tr ' ' '\n' | grep '\.c$' | sort -u)
# Object names must be unique within each object directory (lib objects go to
# their own, so lib/hash.c and src/hash.c can coexist).
for list in "$lib_srcs" "$src_srcs"; do
    dups=$(echo "$list" | xargs -n1 basename | sort | uniq -d)
    [ -z "$dups" ] || die "duplicate object names: $dups"
done

mkdir -p "$stage/vms"
echo "$lib_srcs" > "$hostcfg/lib-sources.txt"
echo "$src_srcs" > "$hostcfg/src-sources.txt"
python3 "$top/tools/gen_mms.py" "$cfgdir/ccflags.txt" "$hostcfg/lib-sources.txt" \
    "$hostcfg/src-sources.txt" "$top/overlay/vms/extra-sources.txt" > "$stage/vms/sources.mms"

# The CA bundle the kit installs (WGET$ROOT:[SSL]CACERT.PEM); the smoke test
# uses it from [.VMS].
cp "$top/cache/$(basename "$CA_BUNDLE_URL")" "$stage/vms/CACERT.PEM"

# src/version.c as src/Makefile would write it.
{ echo '/* version.c */'
  echo '/* Autogenerated by tools/prepare.sh - DO NOT EDIT */'
  echo
  echo '#include "version.h"'
  echo "const char *version_string = \"$UPSTREAM_VERSION\";"
  echo "const char *compilation_string = \"CC $(tr -d '\n' < "$cfgdir/ccflags.txt" | sed 's/["\\]/\\&/g')\";"
  echo "const char *link_string = \"LINK\";"
} > "$stage/src/version.c"

# --- snapshot: the resolved configuration, committed and reviewed ----------
mkdir -p "$snapshot"
cp "$hostcfg/src/config.h" "$snapshot/config.h"
echo "$lib_srcs" > "$snapshot/lib-sources.txt"
echo "$src_srcs" > "$snapshot/src-sources.txt"
# Every cached answer, and where it came from.
cat "$cfgdir/next-headers.site" "$cfgdir/vms-manual.site" > "$hostcfg/manual.site"
python3 "$top/tools/cfgreport.py" "$hostcfg/config.cache" "$answers" \
    "$hostcfg/manual.site" > "$snapshot/cache-answers.txt"
step "inherited-from-Linux answers: $(grep -c ' host$' "$snapshot/cache-answers.txt" || true)" \
     "(see snapshot/cache-answers.txt)"

step "staged $stage"
if ! git -C "$top" diff --quiet -- snapshot 2>/dev/null; then
    step "snapshot/ changed - review with: git diff -- snapshot"
fi
