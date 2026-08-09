#!/usr/bin/env bash
# Build the Swordigo universal BYO-data package.
#
# Layout is the canonical PortMaster one: one visible generated launcher and
# the swordigo/ folder at the ZIP root.  The launcher pins the versioned
# nxbootstrap library and deployment receipt directly; a second-stage run.sh
# is deliberately forbidden.  Regular, byte-identical compatibility copies
# cover CFW installers that preserve a pre-1.0.8 launcher during an overlay.
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

for tool in file find grep python3 readelf sha256sum sort unzip zip; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'required packaging tool is missing: %s\n' "$tool" >&2
    exit 1
  }
done

if [ "${SWORDIGO_SKIP_BUILD:-0}" != 1 ]; then
  "$ROOT/build_universal.sh"
fi
BIN=$ROOT/swordigo-nextos-v108
[ -x "$BIN" ] || { printf 'swordigo-nextos-v108 is missing\n' >&2; exit 1; }
BOOTSTRAP_VERSION=0.5.1
VERSIONED_BOOTSTRAP=$ROOT/swordigo/nxbootstrap-$BOOTSTRAP_VERSION.sh
[ -f "$VERSIONED_BOOTSTRAP" ] && [ ! -L "$VERSIONED_BOOTSTRAP" ] || {
  printf 'versioned nxbootstrap %s is missing or unsafe\n' \
    "$BOOTSTRAP_VERSION" >&2
  exit 1
}
[ -f "$ROOT/swordigo/nxdeployment.json" ] &&
  [ ! -L "$ROOT/swordigo/nxdeployment.json" ] || {
  printf 'nxdeployment receipt is missing or unsafe\n' >&2
  exit 1
}

MAX_GLIBC=$(readelf --version-info "$BIN" 2>/dev/null |
  grep -oE 'GLIBC_[0-9]+([.][0-9]+)*' | sort -Vu | tail -1 || true)
[ -n "$MAX_GLIBC" ] || {
  printf 'could not determine loader glibc requirement\n' >&2
  exit 1
}
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

install -m 0755 "$BIN" "$GAME/swordigo-nextos-v108"
# Launchers from v1.0.5-v1.0.7 embedded swordigo-nextos; v1.0.4 embedded
# swordigo.  Ship ordinary, byte-identical ELFs at both old paths so a CFW that
# preserves either visible launcher cannot combine old launcher bytes with an
# old runtime. Symlinks are unsuitable because nxbootstrap rejects linked
# runtimes and common FAT extractors do not preserve them. The v1.0.8 launcher
# selects only swordigo-nextos-v108.
install -m 0755 "$BIN" "$GAME/swordigo-nextos"
install -m 0755 "$BIN" "$GAME/swordigo"
install -m 0644 "$ROOT/swordigo/nxbootstrap.sh" "$GAME/nxbootstrap.sh"
install -m 0644 "$VERSIONED_BOOTSTRAP" \
  "$GAME/nxbootstrap-$BOOTSTRAP_VERSION.sh"
install -m 0644 "$ROOT/swordigo/nxport.json" "$GAME/nxport.json"
install -m 0644 "$ROOT/swordigo/nxdeployment.json" \
  "$GAME/nxdeployment.json"
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
bash -n "$GAME/nxbootstrap-$BOOTSTRAP_VERSION.sh"
grep -q 'source "$NXPORT_GAME_DIR/$NXPORT_BOOTSTRAP_LIBRARY"' \
  "$STAGE/package/Swordigo.sh" || {
  printf 'visible launcher does not load the pinned nxbootstrap directly\n' >&2
  exit 1
}
grep -q 'nxbootstrap_main "$@"' "$STAGE/package/Swordigo.sh" || {
  printf 'visible launcher does not invoke nxbootstrap_main\n' >&2
  exit 1
}
grep -Fx 'NXPORT_EXECUTABLE=swordigo-nextos-v108' \
  "$STAGE/package/Swordigo.sh" >/dev/null || {
  printf 'visible launcher and manifest disagree on executable\n' >&2
  exit 1
}
grep -Fx 'NXPORT_BOOTSTRAP_LIBRARY=nxbootstrap-0.5.1.sh' \
  "$STAGE/package/Swordigo.sh" >/dev/null || {
  printf 'visible launcher does not pin nxbootstrap 0.5.1\n' >&2
  exit 1
}
grep -F "NXPORT_REQUIRED_FILES='swordigo-nextos-v108" \
  "$STAGE/package/Swordigo.sh" >/dev/null || {
  printf 'visible launcher and manifest disagree on required_files\n' >&2
  exit 1
}
[ ! -e "$GAME/run.sh" ] || {
  printf 'obsolete second-stage run.sh entered the package\n' >&2
  exit 1
}
launcher_count=$(find "$STAGE/package" -maxdepth 1 -type f -name '*.sh' |
  wc -l)
[ "$launcher_count" -eq 1 ] || {
  printf 'package must contain exactly one visible launcher, found %s\n' \
    "$launcher_count" >&2
  exit 1
}
if find "$STAGE/package" -type f -name 'run.sh' -print -quit | grep -q .; then
  printf 'forbidden run.sh entered the package\n' >&2
  exit 1
fi
for runtime in swordigo-nextos-v108 swordigo-nextos swordigo; do
  [ -f "$GAME/$runtime" ] && [ ! -L "$GAME/$runtime" ] &&
    [ -x "$GAME/$runtime" ] || {
    printf 'runtime path is missing or unsafe: %s\n' "$runtime" >&2
    exit 1
  }
  cmp -s "$GAME/swordigo-nextos-v108" "$GAME/$runtime" || {
    printf 'runtime alias diverges from swordigo-nextos-v108: %s\n' \
      "$runtime" >&2
    exit 1
  }
done
for bootstrap in nxbootstrap.sh nxbootstrap-0.5.1.sh; do
  [ -f "$GAME/$bootstrap" ] && [ ! -L "$GAME/$bootstrap" ] &&
    [ ! -x "$GAME/$bootstrap" ] || {
    printf 'bootstrap path is missing, linked or executable: %s\n' \
      "$bootstrap" >&2
    exit 1
  }
done
cmp -s "$GAME/nxbootstrap.sh" "$GAME/nxbootstrap-0.5.1.sh" || {
  printf 'canonical and versioned nxbootstrap bytes diverge\n' >&2
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

# Only the versioned runtime, its two byte-identical update aliases and the
# extractor UI may be ELFs. Every copy is independently checked against the
# public ABI ceiling below.
while IFS= read -r -d '' candidate; do
  case "$(file -b "$candidate")" in
    *ELF*)
      relative=${candidate#"$STAGE/package/"}
      case "$relative" in
        swordigo/swordigo-nextos-v108|swordigo/swordigo-nextos|\
        swordigo/swordigo|swordigo/nxextract/nxextract-ui) ;;
        *) printf 'unexpected ELF entered package: %s\n' "$relative" >&2; exit 1 ;;
      esac
      newest=$(readelf --version-info "$candidate" 2>/dev/null |
        grep -oE 'GLIBC_[0-9]+([.][0-9]+)*' | sort -Vu | tail -1 || true)
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
      printf 'ELF OK: %s | ABI %s\n' "$relative" "$newest"
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
zip_launcher_count=$(unzip -Z1 "$OUTPUT" |
  grep -Ec '^[^/]+[.]sh$' || true)
[ "$zip_launcher_count" -eq 1 ] || {
  printf 'ZIP must contain exactly one visible launcher, found %s\n' \
    "$zip_launcher_count" >&2
  exit 1
}
if unzip -Z1 "$OUTPUT" | grep -E '(^|/)run[.]sh$' >/dev/null; then
  printf 'ZIP contains forbidden run.sh\n' >&2
  exit 1
fi
unzip -p "$OUTPUT" swordigo/swordigo-nextos-v108 > "$STAGE/zip-primary"
for runtime in swordigo-nextos swordigo; do
  unzip -p "$OUTPUT" "swordigo/$runtime" > "$STAGE/zip-$runtime"
  cmp -s "$STAGE/zip-primary" "$STAGE/zip-$runtime" || {
    printf 'ZIP changed runtime alias: %s\n' "$runtime" >&2
    exit 1
  }
done
unzip -p "$OUTPUT" swordigo/nxbootstrap.sh > "$STAGE/zip-bootstrap"
unzip -p "$OUTPUT" swordigo/nxbootstrap-0.5.1.sh \
  > "$STAGE/zip-bootstrap-versioned"
cmp -s "$STAGE/zip-bootstrap" "$STAGE/zip-bootstrap-versioned" || {
  printf 'ZIP changed canonical/versioned nxbootstrap equality\n' >&2
  exit 1
}

printf 'PACKAGE OK: %s\n' "$OUTPUT"
printf 'SHA-256: %s\n' "$HASH"
printf 'loader ABI: %s\n' "$MAX_GLIBC"
