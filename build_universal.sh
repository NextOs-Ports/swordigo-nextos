#!/usr/bin/env bash
# Build the single universal AArch64 loader for every supported firmware.
#
# The Debian Buster cross toolchain keeps the executable below GLIBC_2.30, so
# the same binary runs on ArkOS/ROCKNIX/muOS-class handhelds and on the current
# NextOS image.  SDL2, OpenAL, GLES1 and EGL are supplied by the target
# firmware.  mpg123 is built from its pinned LGPL source and bundled because
# not every otherwise-compatible firmware provides its SONAME.
#
# Recipe proven by the published Prizefighters 2 universal port.
set -euo pipefail

PORT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUTPUT=${SWORDIGO_UNIVERSAL_OUTPUT:-swordigo-nextos}
BUILDER_IMAGE=playfetch-builder:buster
BUILDER_IMAGE_ID=sha256:036c7910ea53bc78cc213452afa92fa83d55de1c51ae54f315af58b5a41a45cf
MPG123_VERSION=1.31.3
MPG123_ARCHIVE="mpg123-${MPG123_VERSION}.tar.bz2"
MPG123_URL="https://downloads.sourceforge.net/sourceforge/mpg123/${MPG123_ARCHIVE}"
MPG123_SHA256=1ca77d3a69a5ff845b7a0536f783fee554e1041139a6b978f6afe14f5814ad1a
export LC_ALL=C
export TZ=UTC
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1786233600}

case "$OUTPUT" in
  ''|.*|*[!A-Za-z0-9._-]*)
    echo "SWORDIGO_UNIVERSAL_OUTPUT must be a plain safe basename" >&2
    exit 1
    ;;
esac

if [ "${SWORDIGO_BUSTER_IN_CONTAINER:-0}" != "1" ]; then
  NEXTOS_ROOT=${NEXTOS_ROOT:-/mnt/ARQUIVOS/NextOS-Elite-Edition}
  NEXTOS_TOOLCHAIN=$(
    find -H "$NEXTOS_ROOT" -maxdepth 2 -type d \
      -path '*/build.NextOS-Retro-Elite-Edition-Amlogic-old.aarch64-*/toolchain' \
      -print 2>/dev/null | sort -V | tail -1
  )
  [ -n "$NEXTOS_TOOLCHAIN" ] || {
    echo "current NextOS toolchain not found below $NEXTOS_ROOT" >&2
    exit 1
  }
  NEXTOS_SYSROOT=$NEXTOS_TOOLCHAIN/aarch64-libreelec-linux-gnu/sysroot
  [ -d "$NEXTOS_SYSROOT" ] || {
    echo "NextOS sysroot not found: $NEXTOS_SYSROOT" >&2
    exit 1
  }
  command -v docker >/dev/null 2>&1 || {
    echo "docker is required for the GLIBC <= 2.30 build" >&2
    exit 1
  }

  mkdir -p "$PORT_DIR/.build/distfiles"
  MPG123_DISTFILE="$PORT_DIR/.build/distfiles/$MPG123_ARCHIVE"
  if [ ! -f "$MPG123_DISTFILE" ]; then
    command -v curl >/dev/null 2>&1 || {
      echo "curl is required to fetch the pinned mpg123 source" >&2
      exit 1
    }
    curl --fail --location --retry 3 --output "$MPG123_DISTFILE" \
      "$MPG123_URL"
  fi
  printf '%s  %s\n' "$MPG123_SHA256" "$MPG123_DISTFILE" |
    sha256sum --check --status || {
      echo "mpg123 source hash mismatch: $MPG123_DISTFILE" >&2
      exit 1
    }

  ACTUAL_IMAGE_ID=$(docker image inspect "$BUILDER_IMAGE" \
    --format '{{.Id}}' 2>/dev/null) || {
      echo "pinned offline builder image is missing: $BUILDER_IMAGE" >&2
      exit 1
    }
  [ "$ACTUAL_IMAGE_ID" = "$BUILDER_IMAGE_ID" ] || {
    echo "builder image changed: $ACTUAL_IMAGE_ID" >&2
    exit 1
  }

  exec docker run --rm --network none \
    -e SWORDIGO_BUSTER_IN_CONTAINER=1 \
    -e SWORDIGO_UNIVERSAL_OUTPUT="$OUTPUT" \
    -e SWORDIGO_HOST_UID="$(id -u)" \
    -e SWORDIGO_HOST_GID="$(id -g)" \
    -e LC_ALL=C -e TZ=UTC -e SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
    -v "$PORT_DIR":/repo \
    -v "$NEXTOS_SYSROOT":/nxsr:ro \
    "$BUILDER_IMAGE_ID" \
    bash /repo/build_universal.sh
fi

CC=aarch64-linux-gnu-gcc
NM=aarch64-linux-gnu-nm
READELF=aarch64-linux-gnu-readelf
STRIP=aarch64-linux-gnu-strip
for tool in "$CC" "$NM" "$READELF" "$STRIP" file strings make tar sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "missing pinned-builder tool: $tool" >&2
    exit 1
  }
done
[ -e /usr/lib/aarch64-linux-gnu/libz.so ] || {
  echo "pinned builder is missing the AArch64 zlib development link" >&2
  exit 1
}
cd /repo

OBJDIR=$(mktemp -d)
STUBDIR=$(mktemp -d)
trap 'rm -rf "$OBJDIR" "$STUBDIR"' EXIT

MPG123_DISTFILE="/repo/.build/distfiles/$MPG123_ARCHIVE"
printf '%s  %s\n' "$MPG123_SHA256" "$MPG123_DISTFILE" |
  sha256sum --check --status || {
    echo "pinned mpg123 source is missing or corrupt" >&2
    exit 1
  }
tar -xjf "$MPG123_DISTFILE" -C "$OBJDIR"
MPG123_SOURCE="$OBJDIR/mpg123-$MPG123_VERSION"
[ -x "$MPG123_SOURCE/configure" ] || {
  echo "unexpected mpg123 source layout" >&2
  exit 1
}
find "$MPG123_SOURCE" -exec touch -d '@1700000000' {} +
(
  cd "$MPG123_SOURCE"
  CFLAGS="-O2 -ffile-prefix-map=$MPG123_SOURCE=. -fdebug-prefix-map=$MPG123_SOURCE=." \
  LDFLAGS="-Wl,--build-id=sha1" \
  ./configure --host=aarch64-linux-gnu --prefix=/usr \
    --enable-shared --disable-static --enable-network=no \
    --enable-modules=no --with-cpu=aarch64 >/dev/null
  make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" >/dev/null
)
MPG123_LIBRARY=$(find "$MPG123_SOURCE" -type f \
  -name 'libmpg123.so.0.*' -print | sort | head -1)
[ -n "$MPG123_LIBRARY" ] || {
  echo "mpg123 shared library was not produced" >&2
  exit 1
}
"$STRIP" --strip-debug "$MPG123_LIBRARY"
cp -L "$MPG123_LIBRARY" /repo/libmpg123.so.0
chmod 0755 /repo/libmpg123.so.0
cp "$MPG123_SOURCE/COPYING" /repo/licenses/mpg123-LGPL-2.1-or-later.txt
chmod 0644 /repo/licenses/mpg123-LGPL-2.1-or-later.txt

SOURCES=(
  src/main.c
  src/contract.c
  src/crash_diag.c
  src/glfix.c
  src/gl_latebind.c
  src/gl_provider_policy.c
  src/imports.c
  src/jni_fake.c
  src/music_player.c
  src/util.c
  src/error.c
  src/so_util.c
  src/pthread_bridge.c
)
OBJS=()
for source in "${SOURCES[@]}"; do
  object="$OBJDIR/$(basename "${source%.c}").o"
  "$CC" -I src -idirafter /nxsr/usr/include \
    -O2 -g -fPIE -fno-strict-aliasing -fno-omit-frame-pointer \
    -ffile-prefix-map=/repo=. -fdebug-prefix-map=/repo=. \
    -Wall -Wextra -Wno-unused-parameter -Wno-unused-function \
    -c "$source" -o "$object"
  OBJS+=("$object")
done

# Recording only stable SONAMEs keeps the loader free of the host's newer
# glibc.  mpg123 resolves to the package copy at runtime; the other stubs bind
# to the provider selected by the firmware/PortMaster environment.
UNDEFINED=$($NM --undefined-only "${OBJS[@]}" 2>/dev/null | awk '{print $NF}' | sort -u)
make_stub() {
  local soname=$1 pattern=$2 name=$3 symbol
  for symbol in $(printf '%s\n' "$UNDEFINED" | grep -E "$pattern" || true); do
    printf 'void %s(void) {}\n' "$symbol"
  done > "$STUBDIR/$name.c"
  "$CC" -shared -fPIC -nostdlib -Wl,-soname,"$soname" \
    "$STUBDIR/$name.c" -o "$STUBDIR/lib$name.so"
}
make_stub libSDL2-2.0.so.0     '^SDL_'                  SDL2
make_stub libopenal.so.1       '^(al|alc)[A-Z]'         openal
make_stub libmpg123.so.0       '^mpg123_'               mpg123

"$CC" -fPIE -pie -rdynamic -o "$OUTPUT" "${OBJS[@]}" \
  -L"$STUBDIR" -Wl,--no-as-needed \
  -lSDL2 -lopenal -lmpg123 -Wl,--as-needed \
  -ldl -lm -lpthread -lz -lgcc_s \
  -Wl,--build-id=sha1 -Wl,-z,relro,-z,now,-z,noexecstack
"$STRIP" --strip-debug "$OUTPUT"
chmod 0755 "$OUTPUT"

MAX_GLIBC=$(
  "$READELF" --version-info "$OUTPUT" |
    grep -oE 'GLIBC_[0-9]+([.][0-9]+)*' | sort -Vu | tail -1
)
[ -n "$MAX_GLIBC" ] || { echo 'cannot read the produced glibc ABI' >&2; exit 1; }
version=${MAX_GLIBC#GLIBC_}
major=${version%%.*}
minor=${version#*.}
minor=${minor%%.*}
if [ "$major" -gt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -gt 30 ]; }; then
  echo "loader requires $MAX_GLIBC; universal ceiling is GLIBC_2.30" >&2
  exit 1
fi

MACHINE=$("$READELF" -h "$OUTPUT" |
  sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')
[ "$MACHINE" = AArch64 ] || {
  echo "unexpected ELF machine: $MACHINE" >&2
  exit 1
}
INTERPRETER=$("$READELF" -lW "$OUTPUT" |
  sed -n 's/.*Requesting program interpreter: \([^]]*\).*/\1/p')
[ "$INTERPRETER" = /lib/ld-linux-aarch64.so.1 ] || {
  echo "unexpected PT_INTERP: $INTERPRETER" >&2
  exit 1
}
if "$READELF" -dW "$OUTPUT" | grep -Eq '(RPATH|RUNPATH)'; then
  echo "public loader contains RPATH/RUNPATH" >&2
  exit 1
fi
if "$READELF" -lW "$OUTPUT" |
    awk '$1 == "LOAD" && $0 ~ /RWE/ { bad=1 } END { exit !bad }'; then
  echo "public loader contains an RWX PT_LOAD" >&2
  exit 1
fi

NEEDED=$("$READELF" -dW "$OUTPUT" |
  awk -F'[][]' '/NEEDED/ {print $2}' | sort)
EXPECTED=$(printf '%s\n' \
  libSDL2-2.0.so.0 libc.so.6 libdl.so.2 \
  libgcc_s.so.1 libm.so.6 libmpg123.so.0 libopenal.so.1 libpthread.so.0 \
  libz.so.1 | sort)
[ "$NEEDED" = "$EXPECTED" ] || {
  echo "unexpected DT_NEEDED set:" >&2
  printf '%s\n' "$NEEDED" >&2
  exit 1
}

TLS_MEMSZ=$("$READELF" -lW "$OUTPUT" |
  awk '$1 == "TLS" { value=$6 } END { print value }')
PAD_LAYOUT=$("$READELF" -sW "$OUTPUT" |
  awk '$4 == "TLS" && $8 == "g_bionic_guard_pad" { value=$2 ":" $3 } END { print value }')
[ "$PAD_LAYOUT" = 0000000000000000:256 ] || {
  echo "Bionic guard-pad layout changed: $PAD_LAYOUT" >&2
  exit 1
}
[ $((TLS_MEMSZ)) -ge 256 ] || {
  echo "TLS block is smaller than the Bionic guard pad" >&2
  exit 1
}

if strings "$OUTPUT" |
    grep -Eq '/home/|/mnt/ARQUIVOS/|/repo/|192[.]168[.]'; then
  echo "public loader contains a private build path or test address" >&2
  exit 1
fi

MPG_MACHINE=$("$READELF" -h /repo/libmpg123.so.0 |
  sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')
[ "$MPG_MACHINE" = AArch64 ] || {
  echo "unexpected mpg123 ELF machine: $MPG_MACHINE" >&2
  exit 1
}
MPG_SONAME=$("$READELF" -dW /repo/libmpg123.so.0 |
  awk -F'[][]' '/SONAME/ {print $2}')
[ "$MPG_SONAME" = libmpg123.so.0 ] || {
  echo "unexpected mpg123 SONAME: $MPG_SONAME" >&2
  exit 1
}
MPG_MAX_GLIBC=$("$READELF" --version-info /repo/libmpg123.so.0 |
  grep -oE 'GLIBC_[0-9]+([.][0-9]+)*' | sort -Vu | tail -1)
[ "$MPG_MAX_GLIBC" = GLIBC_2.17 ] || {
  echo "unexpected mpg123 glibc floor: $MPG_MAX_GLIBC" >&2
  exit 1
}
if "$READELF" -dW /repo/libmpg123.so.0 | grep -Eq '(RPATH|RUNPATH)'; then
  echo "bundled mpg123 contains RPATH/RUNPATH" >&2
  exit 1
fi
MPG_NEEDED=$("$READELF" -dW /repo/libmpg123.so.0 |
  awk -F'[][]' '/NEEDED/ {print $2}' | sort)
[ "$MPG_NEEDED" = "$(printf '%s\n' libc.so.6 libm.so.6 | sort)" ] || {
  echo "unexpected mpg123 DT_NEEDED set:" >&2
  printf '%s\n' "$MPG_NEEDED" >&2
  exit 1
}

chown "${SWORDIGO_HOST_UID:-0}:${SWORDIGO_HOST_GID:-0}" \
  "$OUTPUT" /repo/libmpg123.so.0 \
  /repo/licenses/mpg123-LGPL-2.1-or-later.txt 2>/dev/null || true
printf 'universal loader: %s | ABI %s | interpreter %s\n' \
  "$OUTPUT" "$MAX_GLIBC" "$INTERPRETER"
printf 'DT_NEEDED: %s\n' "$(printf '%s\n' "$NEEDED" | tr '\n' ' ')"
printf 'TLS guard: %s; memsz=%s\n' "$PAD_LAYOUT" "$TLS_MEMSZ"
file "$OUTPUT"
sha256sum "$OUTPUT"
printf 'bundled mpg123: %s | ABI %s | SONAME %s\n' \
  /repo/libmpg123.so.0 "$MPG_MAX_GLIBC" "$MPG_SONAME"
sha256sum /repo/libmpg123.so.0
