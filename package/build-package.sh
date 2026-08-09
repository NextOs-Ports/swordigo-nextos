#!/usr/bin/env bash
# Build the Swordigo universal BYO-data package.
#
# Layout is the canonical PortMaster one: one visible generated launcher and
# the swordigo/ folder at the ZIP root.  The launcher loads nxbootstrap.sh
# directly; a second-stage run.sh is deliberately forbidden.  One release
# migration bridge is included for CFW installers that preserve the v1.0.4
# launcher's embedded executable name while replacing the payload below it.
#
# The package contains NO game data: NXExtract prepares libswordigo.so,
# assets/ and res/ on the device from an APK the player legally owns, dropped
# in swordigo/gamedata/.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
VERSION=$(tr -d '\r\n' < "$ROOT/version.txt")
case "$VERSION" in
  ''|*[!0-9A-Za-z._-]*) printf 'invalid version.txt\n' >&2; exit 1 ;;
esac

if [ "${SWORDIGO_SKIP_BUILD:-0}" != 1 ]; then
  "$ROOT/build_universal.sh"
fi
BIN=$ROOT/swordigo-nextos
[ -x "$BIN" ] || { printf 'swordigo-nextos is missing\n' >&2; exit 1; }

MAX_GLIBC=$(readelf --version-info "$BIN" |
  grep -oE 'GLIBC_[0-9]+([.][0-9]+)*' | sort -Vu | tail -1)
version_number=${MAX_GLIBC#GLIBC_}
major=${version_number%%.*}
minor=${version_number#*.}; minor=${minor%%.*}
if [ "$major" -gt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -gt 30 ]; }; then
  printf 'loader requires %s; universal ceiling is GLIBC_2.30\n' "$MAX_GLIBC" >&2
  exit 1
fi
LC_ALL=C readelf -h "$BIN" | grep -q 'Machine:.*AArch64' ||
  { printf 'loader is not AArch64\n' >&2; exit 1; }

PYTHONDONTWRITEBYTECODE=1 bash "$ROOT/tests/launcher_test.sh"

while read -r pinned_file pinned_hash; do
  [ -n "$pinned_file" ] || continue
  actual_hash=$(sha256sum "$ROOT/$pinned_file" | awk '{print $1}')
  [ "$actual_hash" = "$pinned_hash" ] || {
    printf 'stale NXExtract pin: %s\n' "$pinned_file" >&2
    exit 1
  }
done < <(sed -n \
  's/^\([^ ]*\) sha256=\([0-9a-f]\{64\}\)$/\1 \2/p' \
  "$ROOT/nxextract-version.txt")

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/swordigo-package.XXXXXX")
trap 'rm -rf -- "$STAGE"' EXIT
GAME=$STAGE/package/swordigo
mkdir -p "$GAME/gamedata" "$GAME/licenses"

install -m 0755 "$BIN" "$GAME/swordigo-nextos"
# v1.0.4 embedded NXPORT_EXECUTABLE=swordigo in the visible launcher.  Some
# overlay installers preserve that old .sh while updating the game directory,
# creating a mixed install that can never select swordigo-nextos.  Ship an
# ordinary, byte-identical ELF at the old path for the transition: symlinks are
# deliberately unsuitable because nxbootstrap rejects linked runtimes and
# common FAT extractors do not preserve them.  Current launchers never select
# this compatibility name.
install -m 0755 "$BIN" "$GAME/swordigo"
install -m 0644 "$ROOT/swordigo/nxbootstrap.sh" "$GAME/nxbootstrap.sh"
install -m 0644 "$ROOT/swordigo/nxport.json" "$GAME/nxport.json"
install -m 0644 "$ROOT/alsoft.conf" "$GAME/alsoft.conf"
install -m 0644 "$ROOT/extractor.json" "$GAME/extractor.json"
install -m 0644 "$ROOT/version.txt" "$GAME/version.txt"
install -m 0644 "$ROOT/NOTICE.md" "$GAME/NOTICE.md"
install -m 0644 "$ROOT/README.md" "$GAME/README.md"
install -m 0644 "$ROOT/INSTALLATION.md" "$GAME/INSTALLATION.md"
install -m 0644 "$ROOT/package/GAMEDATA.txt" "$GAME/gamedata/PUT-THE-APK-HERE.txt"
install -m 0644 "$ROOT/LICENSE" "$GAME/LICENSE"
install -m 0644 "$ROOT/licenses/NXExtract-MIT.txt" "$GAME/licenses/NXExtract-MIT.txt"
install -m 0644 "$ROOT/nxextract-version.txt" "$GAME/nxextract-version.txt"
install -d -m 0755 "$GAME/nxextract"
install -m 0755 "$ROOT/nxextract.py" "$GAME/nxextract/nxextract.py"
install -m 0755 "$ROOT/run-extractor.sh" "$GAME/nxextract/run-extractor.sh"
install -m 0755 "$ROOT/nxextract-runtime-env.sh" \
  "$GAME/nxextract/nxextract-runtime-env.sh"
install -m 0755 "$ROOT/nxextract-ui" "$GAME/nxextract/nxextract-ui"
install -m 0755 "$ROOT/Swordigo.sh" "$STAGE/package/Swordigo.sh"

bash -n "$STAGE/package/Swordigo.sh"
bash -n "$GAME/nxbootstrap.sh"
grep -q 'source "$NXPORT_GAME_DIR/nxbootstrap.sh"' \
  "$STAGE/package/Swordigo.sh" || {
  printf 'visible launcher does not load nxbootstrap directly\n' >&2
  exit 1
}
grep -q 'nxbootstrap_main "$@"' "$STAGE/package/Swordigo.sh" || {
  printf 'visible launcher does not invoke nxbootstrap_main\n' >&2
  exit 1
}
grep -Fx 'NXPORT_EXECUTABLE=swordigo-nextos' \
  "$STAGE/package/Swordigo.sh" >/dev/null || {
  printf 'visible launcher and manifest disagree on executable\n' >&2
  exit 1
}
grep -F "NXPORT_REQUIRED_FILES='swordigo-nextos" \
  "$STAGE/package/Swordigo.sh" >/dev/null || {
  printf 'visible launcher and manifest disagree on required_files\n' >&2
  exit 1
}
[ ! -e "$GAME/run.sh" ] || {
  printf 'obsolete second-stage run.sh entered the package\n' >&2
  exit 1
}
[ -f "$GAME/swordigo" ] && [ ! -L "$GAME/swordigo" ] &&
  [ -x "$GAME/swordigo" ] || {
  printf 'v1.0.4 update bridge is missing or unsafe\n' >&2
  exit 1
}
cmp -s "$GAME/swordigo-nextos" "$GAME/swordigo" || {
  printf 'v1.0.4 update bridge diverges from swordigo-nextos\n' >&2
  exit 1
}

# Reject game content and personal data: this is a BYO-data package.
for forbidden in libswordigo.so assets res; do
  [ ! -e "$GAME/$forbidden" ] ||
    { printf 'game data entered the package: %s\n' "$forbidden" >&2; exit 1; }
done
if find "$STAGE/package" -type f \( -iname '*.apk' -o -iname '*.xapk' -o \
  -iname '*.obb' -o -iname '*.log' -o -iname '*.mp3' -o -iname '*.pvr' -o \
  -iname '*.pyc' \) \
  -print -quit | grep -q .; then
  printf 'forbidden package, log or game asset entered the release\n' >&2
  exit 1
fi
if find "$STAGE/package" -type d -name '__pycache__' -print -quit | grep -q .; then
  printf 'Python cache entered the release\n' >&2
  exit 1
fi
if grep -IRnE '192[.]168[.]|169[.]254[.]|10[.][0-9]+[.]|/home/|/media/|root@|password[[:space:]]*=|(api|access)[_-]?token[[:space:]]*=' \
    "$STAGE/package" --include='*.sh' --include='*.md' --include='*.txt' \
    --include='*.json' --include='*.py'; then
  printf 'private host data entered the release\n' >&2
  exit 1
fi

# Only the runtime, its byte-identical v1.0.4 update bridge and extractor UI
# may be ELFs.  Every copy is independently checked against the public ABI
# ceiling below.
while IFS= read -r -d '' candidate; do
  case "$(file -b "$candidate")" in
    *ELF*)
      relative=${candidate#"$STAGE/package/"}
      case "$relative" in
        swordigo/swordigo-nextos|swordigo/swordigo|swordigo/nxextract/nxextract-ui) ;;
        *) printf 'unexpected ELF entered package: %s\n' "$relative" >&2; exit 1 ;;
      esac
      newest=$(readelf --version-info "$candidate" 2>/dev/null |
        grep -oE 'GLIBC_[0-9]+([.][0-9]+)*' | sort -Vu | tail -1)
      [ -n "$newest" ] || {
        printf 'could not determine glibc requirement: %s\n' "$relative" >&2
        exit 1
      }
      elf_version=${newest#GLIBC_}
      elf_major=${elf_version%%.*}
      elf_minor=${elf_version#*.}; elf_minor=${elf_minor%%.*}
      if [ "$elf_major" -gt 2 ] ||
         { [ "$elf_major" -eq 2 ] && [ "$elf_minor" -gt 30 ]; }; then
        printf '%s requires %s; ceiling is GLIBC_2.30\n' \
          "$relative" "$newest" >&2
        exit 1
      fi
      ;;
    *PE32*|*Mach-O*)
      printf 'foreign executable entered package: %s\n' "$candidate" >&2; exit 1 ;;
  esac
done < <(find "$STAGE/package" -type f -print0)

mkdir -p "$ROOT/.build"
OUTPUT=$ROOT/.build/Swordigo.NextOS-v$VERSION.zip
TEMP_ZIP=$STAGE/out.zip
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1785628800}
export TZ=UTC
find "$STAGE/package" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
(
  cd "$STAGE/package"
  find 'Swordigo.sh' swordigo -print | LC_ALL=C sort | zip -X -9 -q "$TEMP_ZIP" -@
)
mv -f -- "$TEMP_ZIP" "$OUTPUT"
HASH=$(sha256sum "$OUTPUT" | awk '{print $1}')
printf '%s  %s\n' "$HASH" "$(basename "$OUTPUT")" > "$OUTPUT.sha256"
unzip -tq "$OUTPUT" >/dev/null
unzip -p "$OUTPUT" swordigo/swordigo-nextos > "$STAGE/zip-primary"
unzip -p "$OUTPUT" swordigo/swordigo > "$STAGE/zip-bridge"
cmp -s "$STAGE/zip-primary" "$STAGE/zip-bridge" || {
  printf 'ZIP changed the v1.0.4 update bridge\n' >&2
  exit 1
}

printf 'PACKAGE OK: %s\n' "$OUTPUT"
printf 'SHA-256: %s\n' "$HASH"
printf 'loader ABI: %s\n' "$MAX_GLIBC"
