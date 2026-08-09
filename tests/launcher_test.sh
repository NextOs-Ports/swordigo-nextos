#!/usr/bin/env bash
# Host-only contract for the generated single launcher. No game, SDL or device.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swordigo-launcher-test.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT INT TERM
BOOTSTRAP_VERSION=0.5.1
VERSIONED_BOOTSTRAP=$ROOT/swordigo/nxbootstrap-$BOOTSTRAP_VERSION.sh

fail() { printf 'launcher test: %s\n' "$*" >&2; exit 1; }

bash -n "$ROOT/Swordigo.sh" || fail 'entry script is not valid Bash'
bash -n "$ROOT/swordigo/nxbootstrap.sh" || fail 'nxbootstrap is not valid Bash'
bash -n "$VERSIONED_BOOTSTRAP" ||
  fail 'versioned nxbootstrap is not valid Bash'
[[ $(head -n 1 "$ROOT/Swordigo.sh") == '#!/bin/bash' ]] ||
  fail 'generated launcher does not use the portable /bin/bash interpreter'
[ -f "$VERSIONED_BOOTSTRAP" ] && [ ! -L "$VERSIONED_BOOTSTRAP" ] &&
  [ ! -x "$VERSIONED_BOOTSTRAP" ] ||
  fail 'versioned nxbootstrap is missing, linked or executable'
[ -f "$ROOT/swordigo/nxbootstrap.sh" ] &&
  [ ! -L "$ROOT/swordigo/nxbootstrap.sh" ] &&
  [ ! -x "$ROOT/swordigo/nxbootstrap.sh" ] ||
  fail 'canonical nxbootstrap is missing, linked or executable'
cmp -s "$ROOT/swordigo/nxbootstrap.sh" "$VERSIONED_BOOTSTRAP" ||
  fail 'canonical and versioned nxbootstrap bytes differ'

grep -q 'source "$NXPORT_GAME_DIR/$NXPORT_BOOTSTRAP_LIBRARY"' \
  "$ROOT/Swordigo.sh" ||
  fail 'entry script does not source the pinned nxbootstrap directly'
grep -q 'nxbootstrap_main "$@"' "$ROOT/Swordigo.sh" ||
  fail 'entry script does not invoke nxbootstrap_main'
grep -Fx 'NXPORT_EXECUTABLE=swordigo-nextos-v108' \
  "$ROOT/Swordigo.sh" >/dev/null ||
  fail 'generated launcher executable diverges from nxport.json'
grep -Fx 'NXPORT_BOOTSTRAP_VERSION=0.5.1' "$ROOT/Swordigo.sh" >/dev/null ||
  fail 'generated launcher does not pin nxbootstrap 0.5.1'
grep -Fx 'NXPORT_BOOTSTRAP_LIBRARY=nxbootstrap-0.5.1.sh' \
  "$ROOT/Swordigo.sh" >/dev/null ||
  fail 'generated launcher does not select the versioned bootstrap'
grep -F "NXPORT_REQUIRED_FILES='swordigo-nextos-v108" \
  "$ROOT/Swordigo.sh" >/dev/null ||
  fail 'generated launcher required_files diverges from nxport.json'
grep -q "trap 'nxport_launcher_on_exit \$?' EXIT" "$ROOT/Swordigo.sh" ||
  fail 'generated launcher has no early EXIT diagnostic trap'
grep -F 'game.swordigo.present-finish' "$ROOT/Swordigo.sh" >/dev/null ||
  fail 'generated launcher omitted the declared present policy'
if grep -q 'run[.]sh' "$ROOT/Swordigo.sh"; then
  fail 'obsolete second-stage run.sh is still referenced'
fi
[ ! -e "$ROOT/run.sh" ] || fail 'obsolete run.sh still exists'

if grep -qE '^[^#]*export[[:space:]]+SDL_(VIDEODRIVER|AUDIODRIVER)=' \
    "$ROOT/Swordigo.sh" "$ROOT/swordigo/nxbootstrap.sh" \
    "$VERSIONED_BOOTSTRAP"; then
  fail 'launcher forces an SDL video or audio driver'
fi

grep -qE '^\s*drivers\s*=\s*pipewire,pulse,alsa\s*$' "$ROOT/alsoft.conf" ||
  fail 'alsoft.conf does not preserve the approved backend order'
grep -q 'configure_runtime_environment' "$ROOT/src/main.c" ||
  fail 'adapter-owned runtime environment is not initialized in the loader'
grep -q 'SWORDIGO_DEBUG_CONTROL' "$ROOT/src/main.c" ||
  fail 'developer control channel is not opt-in'
grep -q 'SWORDIGO_GLFINISH' "$ROOT/src/main.c" ||
  fail 'KMSDRM present synchronization has no explicit policy override'
if grep -q 'fopen(LOG_NAME' "$ROOT/src/util.c"; then
  fail 'loader still competes with nxbootstrap for the durable log'
fi

python3 -B - "$ROOT/Swordigo.sh" "$ROOT/swordigo/nxport.json" \
  "$ROOT/swordigo/nxdeployment.json" "$VERSIONED_BOOTSTRAP" <<'PY' ||
import hashlib
import json
import pathlib
import shlex
import sys

launcher_path, manifest_path, receipt_path, bootstrap_path = map(
    pathlib.Path, sys.argv[1:])
launcher = launcher_path.read_text(encoding="utf-8")
manifest_bytes = manifest_path.read_bytes()
manifest = json.loads(manifest_bytes)
receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
bootstrap_sha256 = hashlib.sha256(bootstrap_path.read_bytes()).hexdigest()
nxport_sha256 = hashlib.sha256(manifest_bytes).hexdigest()
material = {
    "bootstrap_filename": "nxbootstrap-0.5.1.sh",
    "bootstrap_sha256": bootstrap_sha256,
    "bootstrap_version": "0.5.1",
    "launcher_name": "Swordigo.sh",
    "nxport_sha256": nxport_sha256,
    "port_id": "swordigo",
    "schema_version": 1,
}
deployment_id = hashlib.sha256(json.dumps(
    material, sort_keys=True, separators=(",", ":"),
    ensure_ascii=False).encode("utf-8")).hexdigest()

assert manifest["executable"] == "swordigo-nextos-v108"
assert "swordigo-nextos-v108" in manifest["required_files"]
assert "swordigo-nextos" not in manifest["required_files"]
assert "swordigo" not in manifest["required_files"]
assert "game.swordigo.present-finish" in manifest["enabled_quirks"]
assert receipt == {
    "schema_version": 1,
    "port_id": "swordigo",
    "launcher_name": "Swordigo.sh",
    "deployment_id": deployment_id,
    "bootstrap": {
        "filename": "nxbootstrap-0.5.1.sh",
        "version": "0.5.1",
        "sha256": bootstrap_sha256,
    },
    "nxport_sha256": nxport_sha256,
}
for assignment in (
        "NXPORT_BOOTSTRAP_SHA256=" + bootstrap_sha256,
        "NXPORT_MANIFEST_SHA256=" + nxport_sha256,
        "NXPORT_DEPLOYMENT_ID=" + deployment_id):
    assert assignment in launcher.splitlines(), assignment
deployment_text = json.dumps(
    receipt, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
assert "NXPORT_DEPLOYMENT_RECEIPT=" + shlex.quote(deployment_text) in launcher
PY
  fail 'manifest, deployment receipt and launcher pins are inconsistent'

stub_bootstrap() {
  cat > "$1" <<'STUB'
#!/usr/bin/env bash
NXBOOTSTRAP_VERSION=0.5.1
nxbootstrap_main() {
  printf 'NXBOOTSTRAP_OK %s %s\n' \
    "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" \
    "${NXPORT_BOOTSTRAP_PATH:-missing}"
  return 0
}
STUB
}

pin_test_deployment() {
  local launcher=$1 manifest=$2 receipt=$3 bootstrap=$4
  python3 -B - "$launcher" "$manifest" "$receipt" "$bootstrap" <<'PY'
import hashlib
import json
import pathlib
import re
import shlex
import sys

launcher_path, manifest_path, receipt_path, bootstrap_path = map(
    pathlib.Path, sys.argv[1:])
bootstrap_sha256 = hashlib.sha256(bootstrap_path.read_bytes()).hexdigest()
nxport_sha256 = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
material = {
    "bootstrap_filename": receipt["bootstrap"]["filename"],
    "bootstrap_sha256": bootstrap_sha256,
    "bootstrap_version": receipt["bootstrap"]["version"],
    "launcher_name": receipt["launcher_name"],
    "nxport_sha256": nxport_sha256,
    "port_id": receipt["port_id"],
    "schema_version": receipt["schema_version"],
}
deployment_id = hashlib.sha256(json.dumps(
    material, sort_keys=True, separators=(",", ":"),
    ensure_ascii=False).encode("utf-8")).hexdigest()
receipt["bootstrap"]["sha256"] = bootstrap_sha256
receipt["nxport_sha256"] = nxport_sha256
receipt["deployment_id"] = deployment_id
receipt_text = json.dumps(
    receipt, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
receipt_path.write_text(receipt_text, encoding="utf-8")
launcher = launcher_path.read_text(encoding="utf-8")
launcher = re.sub(
    r"^NXPORT_BOOTSTRAP_SHA256=.*$",
    "NXPORT_BOOTSTRAP_SHA256=" + bootstrap_sha256,
    launcher, flags=re.MULTILINE)
launcher = re.sub(
    r"^NXPORT_DEPLOYMENT_ID=.*$",
    "NXPORT_DEPLOYMENT_ID=" + deployment_id,
    launcher, flags=re.MULTILINE)
launcher = re.sub(
    r"^NXPORT_DEPLOYMENT_RECEIPT=.*?(?=^NXPORT_REQUIRED_FILES=)",
    "NXPORT_DEPLOYMENT_RECEIPT=" + shlex.quote(receipt_text) + "\n",
    launcher, flags=re.MULTILINE | re.DOTALL)
launcher_path.write_text(launcher, encoding="utf-8")
PY
}

check_layout() {
  local label=$1 launcher_dir=$2 game_dir=$3 root="$TEST_ROOT/$1" output
  mkdir -p "$root/$launcher_dir" "$root/$game_dir/swordigo"
  cp "$ROOT/Swordigo.sh" "$root/$launcher_dir/Swordigo.sh"
  cp "$ROOT/swordigo/nxport.json" "$root/$game_dir/swordigo/nxport.json"
  cp "$ROOT/swordigo/nxdeployment.json" \
    "$root/$game_dir/swordigo/nxdeployment.json"
  stub_bootstrap \
    "$root/$game_dir/swordigo/nxbootstrap-$BOOTSTRAP_VERSION.sh"
  cp "$root/$game_dir/swordigo/nxbootstrap-$BOOTSTRAP_VERSION.sh" \
    "$root/$game_dir/swordigo/nxbootstrap.sh"
  pin_test_deployment "$root/$launcher_dir/Swordigo.sh" \
    "$root/$game_dir/swordigo/nxport.json" \
    "$root/$game_dir/swordigo/nxdeployment.json" \
    "$root/$game_dir/swordigo/nxbootstrap-$BOOTSTRAP_VERSION.sh"
  printf '%s\n' '# stale compatibility bootstrap must never be selected' \
    'exit 99' > "$root/$game_dir/swordigo/nxbootstrap.sh"
  if output=$(cd "$root/$launcher_dir" && bash ./Swordigo.sh 2>&1) &&
     [[ $output == *"NXBOOTSTRAP_OK $root/$game_dir/swordigo $root/$game_dir/swordigo/nxbootstrap-$BOOTSTRAP_VERSION.sh"* ]]; then
    printf 'OK %-24s launcher -> versioned nxbootstrap\n' "$label"
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
cp "$ROOT/swordigo/nxdeployment.json" \
  "$TEST_ROOT/symlink/roms/ports/swordigo/"
ln -s /dev/null \
  "$TEST_ROOT/symlink/roms/ports/swordigo/nxbootstrap-$BOOTSTRAP_VERSION.sh"
if (cd "$TEST_ROOT/symlink/roms/ports" && bash ./Swordigo.sh >/dev/null 2>&1); then
  fail 'launcher accepted a symlinked bootstrap'
fi

mkdir -p "$TEST_ROOT/no-receipt/roms/ports/swordigo"
cp "$ROOT/Swordigo.sh" "$TEST_ROOT/no-receipt/roms/ports/"
cp "$ROOT/swordigo/nxport.json" "$TEST_ROOT/no-receipt/roms/ports/swordigo/"
cp "$VERSIONED_BOOTSTRAP" "$TEST_ROOT/no-receipt/roms/ports/swordigo/"
if (cd "$TEST_ROOT/no-receipt/roms/ports" &&
    bash ./Swordigo.sh >/dev/null 2>&1); then
  fail 'launcher accepted a deployment without its receipt'
fi
receipt_log=$(find "$TEST_ROOT/no-receipt/roms/ports" -maxdepth 1 -type f \
  -name 'swordigo-launcher-error.*.log' -print -quit)
[ -n "$receipt_log" ] || fail 'missing receipt failed without an early log'
grep -F 'deployment receipt is missing or unsafe' "$receipt_log" >/dev/null ||
  fail 'early log does not identify the missing deployment receipt'

python3 -B "$ROOT/nxextract.py" recipe-check --recipe "$ROOT/extractor.json" \
  >/dev/null || fail 'NXExtract rejected the Swordigo recipe'
grep -q '^1[.]2[.]6$' "$ROOT/nxextract-version.txt" ||
  fail 'NXExtract version is not 1.2.6'

printf 'swordigo single-launcher tests passed\n'
