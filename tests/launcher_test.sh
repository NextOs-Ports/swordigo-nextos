#!/usr/bin/env bash
# Host-side gates for the shipped launcher and recipe.  No device required.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swordigo-launcher-test.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT INT TERM

fail() { printf 'launcher test: %s\n' "$*" >&2; exit 1; }

sh -n "$ROOT/Swordigo.sh" || fail 'the entry script is not valid POSIX shell'
bash -n "$ROOT/run.sh" || fail 'the runtime launcher is not valid bash'

# Never force a video or audio backend: the firmware chooses (fleet rule).
if grep -qE '^[^#]*export[[:space:]]+SDL_(VIDEODRIVER|AUDIODRIVER)=' "$ROOT/run.sh"; then
  fail 'the launcher forces an SDL video or audio driver'
fi

# Audio: release 1.0.0 shipped mute because the OpenAL config was applied only
# on firmwares without a PulseAudio socket, so every box with a sound server ran
# with no backend order and no ALSA fix.  The config must be unconditional and
# it must pin the order.
grep -qE '^\s*drivers\s*=\s*pipewire,pulse,alsa\s*$' "$ROOT/alsoft.conf" ||
  fail 'alsoft.conf does not pin the backend order'
if grep -n 'ALSOFT_CONF=' "$ROOT/run.sh" | grep -q 'pulse_available'; then
  fail 'ALSOFT_CONF is applied only on some firmwares'
fi
grep -q 'ALSOFT_CONF="$GAMEDIR/alsoft.conf"' "$ROOT/run.sh" ||
  fail 'the launcher does not point OpenAL at the shipped config'

# The visible launcher must stay thin enough to read at a glance.
[ "$(wc -c < "$ROOT/Swordigo.sh")" -le 3072 ] ||
  fail 'the visible PortMaster launcher is no longer thin'

# Resolution: the .sh must find the game folder in the PortMaster layout, in
# the NextOS ports_scripts split, and in the muOS card roots.
mkdir -p "$TEST_ROOT/portmaster/roms/ports/swordigo"
printf '#!/usr/bin/env bash\nprintf RAN\n' \
  > "$TEST_ROOT/portmaster/roms/ports/swordigo/run.sh"
cp "$ROOT/Swordigo.sh" "$TEST_ROOT/portmaster/roms/ports/"
[ "$(sh "$TEST_ROOT/portmaster/roms/ports/Swordigo.sh")" = RAN ] ||
  fail 'the PortMaster layout was not resolved'

mkdir -p "$TEST_ROOT/nextos/roms/ports/swordigo" "$TEST_ROOT/nextos/roms/ports_scripts"
printf '#!/usr/bin/env bash\nprintf RAN\n' \
  > "$TEST_ROOT/nextos/roms/ports/swordigo/run.sh"
cp "$ROOT/Swordigo.sh" "$TEST_ROOT/nextos/roms/ports_scripts/"
[ "$(sh "$TEST_ROOT/nextos/roms/ports_scripts/Swordigo.sh")" = RAN ] ||
  fail 'the NextOS ports_scripts split was not resolved'

mkdir -p "$TEST_ROOT/muos/mmc/ports/swordigo" "$TEST_ROOT/muos/mmc/roms/ports"
printf '#!/usr/bin/env bash\nprintf RAN\n' \
  > "$TEST_ROOT/muos/mmc/ports/swordigo/run.sh"
cp "$ROOT/Swordigo.sh" "$TEST_ROOT/muos/mmc/roms/ports/"
[ "$(sh "$TEST_ROOT/muos/mmc/roms/ports/Swordigo.sh")" = RAN ] ||
  fail 'the muOS split between mmc/ports and mmc/roms/ports was not resolved'

# A missing game folder must fail loudly, with a written reason.
mkdir -p "$TEST_ROOT/broken/roms/ports"
cp "$ROOT/Swordigo.sh" "$TEST_ROOT/broken/roms/ports/"
if sh "$TEST_ROOT/broken/roms/ports/Swordigo.sh" >/dev/null 2>&1; then
  fail 'a missing game folder was reported as success'
fi
[ -s "$TEST_ROOT/broken/roms/ports/swordigo-launcher-error.log" ] ||
  fail 'a missing game folder failed silently'

# The recipe must stay loadable by the pinned engine.
python3 "$ROOT/nxextract.py" recipe-check --recipe "$ROOT/extractor.json" >/dev/null ||
  fail 'the extractor recipe was rejected'

# The pin file must describe the engine actually vendored here.
pinned=$(head -1 "$ROOT/nxextract-version.txt")
engine=$(grep -m1 NXEXTRACT_VERSION "$ROOT/nxextract.py" | sed 's/.*"\(.*\)".*/\1/')
[ "$pinned" = "$engine" ] ||
  fail "nxextract-version.txt says $pinned but the engine is $engine"

printf 'launcher tests passed\n'
