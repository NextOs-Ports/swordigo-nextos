#!/usr/bin/env bash
# Host-only contract for the 0.6.0 single self-contained launcher.
# No game, no SDL, no device.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

fail() { printf 'launcher test: %s\n' "$*" >&2; exit 1; }

LAUNCHER=$ROOT/Swordigo.sh
bash -n "$LAUNCHER" || fail 'entry script is not valid Bash'
[[ $(head -n 1 "$LAUNCHER") == '#!/bin/bash' ]] ||
  fail 'launcher does not use the portable /bin/bash interpreter'
grep -Fq '# PORTMASTER: swordigo, Swordigo.sh' "$LAUNCHER" ||
  fail 'launcher lacks its PORTMASTER identity'
grep -Fq 'nxbootstrap 0.6.0' "$LAUNCHER" ||
  fail 'launcher does not record its generator version'

# Golden-port guarantees of the 0.6.0 shape.
for needle in \
  'source "$controlfolder/control.txt"' \
  'get_controls' \
  'GAMEDIR="/$directory/ports/swordigo"' \
  'flock -n 9' \
  'trap - INT TERM HUP' \
  'wait "$game_pid"' \
  "printf '\\033c'" \
  'pm_platform_helper' \
  'pm_finish' \
  'swordigo-nextos-v109'
do
  grep -Fq "$needle" "$LAUNCHER" || fail "launcher lacks canonical line: $needle"
done
grep -Eq '@[A-Z0-9_]+@' "$LAUNCHER" && fail 'launcher has unresolved tokens' || true

# Retired layers must stay retired.
if grep -q 'run[.]sh' "$LAUNCHER"; then
  fail 'obsolete second-stage run.sh is still referenced'
fi
[ ! -e "$ROOT/run.sh" ] || fail 'obsolete run.sh still exists'
for retired in swordigo/nxbootstrap.sh swordigo/nxbootstrap-0.5.1.sh \
               swordigo/nxdeployment.json; do
  [ ! -e "$ROOT/$retired" ] || fail "retired artifact still present: $retired"
done
if grep -qE '^[^#]*export[[:space:]]+SDL_(VIDEODRIVER|AUDIODRIVER)=' \
    "$LAUNCHER"; then
  fail 'launcher forces an SDL video or audio driver'
fi

LOADER=$ROOT/swordigo-nextos-v109
[ -f "$LOADER" ] && [ ! -L "$LOADER" ] && [ -x "$LOADER" ] ||
  fail 'public loader is missing, linked or not executable'
LC_ALL=C readelf -hW "$LOADER" | grep -q 'Machine:.*AArch64' ||
  fail 'public loader is not AArch64'
if LC_ALL=C readelf -dW "$LOADER" | grep -Eq '(RPATH|RUNPATH)'; then
  fail 'public loader embeds RPATH/RUNPATH'
fi
loader_glibc=$(LC_ALL=C readelf --version-info "$LOADER" |
  grep -oE 'GLIBC_[0-9]+([.][0-9]+)*' | sort -Vu | tail -1)
[ -n "$loader_glibc" ] || fail 'public loader has no readable glibc ABI'
loader_version=${loader_glibc#GLIBC_}
loader_major=${loader_version%%.*}
loader_minor=${loader_version#*.}; loader_minor=${loader_minor%%.*}
if [ "$loader_major" -gt 2 ] ||
   { [ "$loader_major" -eq 2 ] && [ "$loader_minor" -gt 30 ]; }; then
  fail "public loader requires $loader_glibc; ceiling is GLIBC_2.30"
fi

# The GL-provider repair (crossed-SONAME black screen) must ship in the loader.
# grep without -q: -q quits early and SIGPIPEs strings under pipefail.
LC_ALL=C strings "$LOADER" | grep 'SWORDIGO_GLFIX' >/dev/null ||
  fail 'loader lost the glfix provider repair'
grep -q 'glfix_maybe_reexec' "$ROOT/src/main.c" ||
  fail 'loader source no longer calls the glfix repair'

grep -qE '^\s*drivers\s*=\s*pipewire,pulse,alsa\s*$' "$ROOT/alsoft.conf" ||
  fail 'alsoft.conf does not preserve the approved backend order'
grep -q 'configure_runtime_environment' "$ROOT/src/main.c" ||
  fail 'adapter-owned runtime environment is not initialized in the loader'
grep -q 'SWORDIGO_DEBUG_CONTROL' "$ROOT/src/main.c" ||
  fail 'developer control channel is not opt-in'
grep -q 'SWORDIGO_GLFINISH' "$ROOT/src/main.c" ||
  fail 'KMSDRM present synchronization has no explicit policy override'
if grep -q 'fopen(LOG_NAME' "$ROOT/src/util.c"; then
  fail 'loader still competes with the launcher for the durable log'
fi

python3 -B "$ROOT/nxextract.py" recipe-check --recipe "$ROOT/extractor.json" \
  >/dev/null || fail 'NXExtract rejected the Swordigo recipe'
grep -q '^1[.]2[.]6$' "$ROOT/nxextract-version.txt" ||
  fail 'NXExtract version is not 1.2.6'

printf 'swordigo single-launcher tests passed\n'
