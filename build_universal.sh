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
OUTPUT=${SWORDIGO_UNIVERSAL_OUTPUT:-swordigo-universal}

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

  if [ -n "${SWORDIGO_BUSTER_IMAGE:-}" ]; then
    BUSTER_IMAGE=$SWORDIGO_BUSTER_IMAGE
  elif docker image inspect playfetch-builder:buster >/dev/null 2>&1; then
    BUSTER_IMAGE=playfetch-builder:buster
  else
    BUSTER_IMAGE=debian:buster
  fi

  exec docker run --rm \
    -e SWORDIGO_BUSTER_IN_CONTAINER=1 \
    -e SWORDIGO_UNIVERSAL_OUTPUT="$OUTPUT" \
    -e SWORDIGO_HOST_UID="$(id -u)" \
    -e SWORDIGO_HOST_GID="$(id -g)" \
    -v "$PORT_DIR":/repo \
    -v "$NEXTOS_SYSROOT":/nxsr:ro \
    "$BUSTER_IMAGE" \
    bash /repo/build_universal.sh
fi

export DEBIAN_FRONTEND=noninteractive
if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 || \
   [ ! -e /usr/lib/aarch64-linux-gnu/libz.so ]; then
  dpkg --add-architecture arm64
  printf '%s\n' \
    'deb [arch=amd64,arm64] http://archive.debian.org/debian buster main' \
    'deb [arch=amd64,arm64] http://archive.debian.org/debian-security buster/updates main' \
    > /etc/apt/sources.list
  apt-get -o Acquire::Check-Valid-Until=false update -qq >/dev/null
  apt-get install -y -qq --no-install-recommends \
    gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    zlib1g-dev:arm64 file >/dev/null
fi

CC=aarch64-linux-gnu-gcc
NM=aarch64-linux-gnu-nm
READELF=aarch64-linux-gnu-readelf
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
    -D_GNU_SOURCE -O2 -g -fPIC -fno-strict-aliasing -fno-omit-frame-pointer \
    -Wall -Wextra -Wno-unused-parameter \
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
  -L"$STUBDIR" -lSDL2 -lopenal -lmpg123 -lGLESv1_CM -lEGL \
  -ldl -lm -lpthread -lz -lgcc_s \
  -Wl,-rpath,'$ORIGIN'

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

chown "${SWORDIGO_HOST_UID:-0}:${SWORDIGO_HOST_GID:-0}" "$OUTPUT" 2>/dev/null || true
printf 'universal loader: %s | ABI %s\n' "$OUTPUT" "$MAX_GLIBC"
"$READELF" -d "$OUTPUT" | grep NEEDED
