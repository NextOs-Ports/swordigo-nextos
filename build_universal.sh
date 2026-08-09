#!/usr/bin/env bash
# Build the single universal AArch64 loader for every supported firmware.
#
# The Debian Buster cross toolchain keeps the executable below GLIBC_2.30, so
# the same binary runs on ArkOS/ROCKNIX/muOS-class handhelds and on the current
# NextOS image.  SDL2, OpenAL, mpg123, GLES1 and EGL are supplied by the target
# firmware: they are linked through link-only stubs that carry nothing but the
# stable SONAME, so no host library version leaks into the result.
#
# Recipe proven by the published Prizefighters 2 universal port.
set -euo pipefail

PORT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUTPUT=${SWORDIGO_UNIVERSAL_OUTPUT:-swordigo-nextos-v108}
BUILDER_IMAGE=playfetch-builder:buster
BUILDER_IMAGE_ID=sha256:036c7910ea53bc78cc213452afa92fa83d55de1c51ae54f315af58b5a41a45cf
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
for tool in "$CC" "$NM" "$READELF" "$STRIP" file strings; do
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

SOURCES=(
  src/main.c
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
    -D_GNU_SOURCE -O2 -g -fPIE -fno-strict-aliasing -fno-omit-frame-pointer \
    -ffile-prefix-map=/repo=. -fdebug-prefix-map=/repo=. \
    -Wall -Wextra -Wno-unused-parameter -Wno-unused-function \
    -c "$source" -o "$object"
  OBJS+=("$object")
done

# Every library below is a firmware component.  Recording only the SONAME keeps
# the loader free of the host's newer glibc while still binding at runtime to
# whatever SDL2/OpenAL/mpg123/GLES the device actually ships.
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
make_stub libGLESv1_CM.so.1    '^gl[A-Z]'               GLESv1_CM
make_stub libEGL.so.1          '^egl[A-Z]'              EGL

"$CC" -fPIE -pie -rdynamic -o "$OUTPUT" "${OBJS[@]}" \
  -L"$STUBDIR" -Wl,--no-as-needed \
  -lSDL2 -lopenal -lmpg123 -lGLESv1_CM -lEGL -Wl,--as-needed \
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
  libEGL.so.1 libGLESv1_CM.so.1 libSDL2-2.0.so.0 libc.so.6 libdl.so.2 \
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

chown "${SWORDIGO_HOST_UID:-0}:${SWORDIGO_HOST_GID:-0}" "$OUTPUT" 2>/dev/null || true
printf 'universal loader: %s | ABI %s | interpreter %s\n' \
  "$OUTPUT" "$MAX_GLIBC" "$INTERPRETER"
printf 'DT_NEEDED: %s\n' "$(printf '%s\n' "$NEEDED" | tr '\n' ' ')"
printf 'TLS guard: %s; memsz=%s\n' "$PAD_LAYOUT" "$TLS_MEMSZ"
file "$OUTPUT"
sha256sum "$OUTPUT"
