#!/usr/bin/env bash
# Host-only contract for the generated single launcher. No game, SDL or device.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swordigo-launcher-test.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT INT TERM

fail() { printf 'launcher test: %s\n' "$*" >&2; exit 1; }

bash -n "$ROOT/Swordigo.sh" || fail 'entry script is not valid Bash'
bash -n "$ROOT/swordigo/nxbootstrap.sh" || fail 'nxbootstrap is not valid Bash'

grep -q 'source "$NXPORT_GAME_DIR/nxbootstrap.sh"' "$ROOT/Swordigo.sh" ||
  fail 'entry script does not source nxbootstrap directly'
grep -q 'nxbootstrap_main "$@"' "$ROOT/Swordigo.sh" ||
  fail 'entry script does not invoke nxbootstrap_main'
if grep -q 'run[.]sh' "$ROOT/Swordigo.sh"; then
  fail 'obsolete second-stage run.sh is still referenced'
fi
[ ! -e "$ROOT/run.sh" ] || fail 'obsolete run.sh still exists'

if grep -qE '^[^#]*export[[:space:]]+SDL_(VIDEODRIVER|AUDIODRIVER)=' \
    "$ROOT/Swordigo.sh" "$ROOT/swordigo/nxbootstrap.sh"; then
  fail 'launcher forces an SDL video or audio driver'
fi

grep -qE '^\s*drivers\s*=\s*pipewire,pulse,alsa\s*$' "$ROOT/alsoft.conf" ||
  fail 'alsoft.conf does not preserve the approved backend order'
grep -q 'configure_runtime_environment' "$ROOT/src/main.c" ||
  fail 'adapter-owned runtime environment is not initialized in the loader'
grep -q 'SWORDIGO_DEBUG_CONTROL' "$ROOT/src/main.c" ||
  fail 'developer control channel is not opt-in'
if grep -q 'fopen(LOG_NAME' "$ROOT/src/util.c"; then
  fail 'loader still competes with nxbootstrap for the durable log'
fi

stub_bootstrap() {
  cat > "$1" <<'STUB'
#!/usr/bin/env bash
nxbootstrap_main() {
  printf 'NXBOOTSTRAP_OK %s\n' "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  return 0
}
STUB
}

check_layout() {
  local label=$1 launcher_dir=$2 game_dir=$3 root="$TEST_ROOT/$1" output
  mkdir -p "$root/$launcher_dir" "$root/$game_dir/swordigo"
  cp "$ROOT/Swordigo.sh" "$root/$launcher_dir/Swordigo.sh"
  cp "$ROOT/swordigo/nxport.json" "$root/$game_dir/swordigo/nxport.json"
  stub_bootstrap "$root/$game_dir/swordigo/nxbootstrap.sh"
  if output=$(cd "$root/$launcher_dir" && bash ./Swordigo.sh 2>&1) &&
     [[ $output == *"NXBOOTSTRAP_OK $root/$game_dir/swordigo"* ]]; then
    printf 'OK %-24s launcher -> nxbootstrap\n' "$label"
  else
    fail "$label layout was not resolved: $output"
  fi
}

check_layout portmaster 'roms/ports' 'roms/ports'
check_layout nextos 'storage/roms/ports_scripts' 'storage/roms/ports'
check_layout muos 'mnt/mmc/roms/ports' 'mnt/mmc/roms/ports'
check_layout userdata 'userdata/roms/ports' 'userdata/roms/ports'

mkdir -p "$TEST_ROOT/broken/roms/ports"
cp "$ROOT/Swordigo.sh" "$TEST_ROOT/broken/roms/ports/"
if (cd "$TEST_ROOT/broken/roms/ports" && bash ./Swordigo.sh >/dev/null 2>&1); then
  fail 'missing game directory was reported as success'
fi
compgen -G "$TEST_ROOT/broken/roms/ports/swordigo-launcher-error.*.log" \
  >/dev/null || fail 'missing game directory failed without a durable log'

mkdir -p "$TEST_ROOT/symlink/roms/ports/swordigo"
cp "$ROOT/Swordigo.sh" "$TEST_ROOT/symlink/roms/ports/"
cp "$ROOT/swordigo/nxport.json" "$TEST_ROOT/symlink/roms/ports/swordigo/"
ln -s /dev/null "$TEST_ROOT/symlink/roms/ports/swordigo/nxbootstrap.sh"
if (cd "$TEST_ROOT/symlink/roms/ports" && bash ./Swordigo.sh >/dev/null 2>&1); then
  fail 'launcher accepted a symlinked bootstrap'
fi

python3 -B "$ROOT/nxextract.py" recipe-check --recipe "$ROOT/extractor.json" \
  >/dev/null || fail 'NXExtract rejected the Swordigo recipe'
grep -q '^1[.]2[.]6$' "$ROOT/nxextract-version.txt" ||
  fail 'NXExtract version is not 1.2.6'

printf 'swordigo single-launcher tests passed\n'
