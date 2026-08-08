#!/usr/bin/env bash
# Universal Swordigo runtime for PortMaster/NextOS-class ARM64 systems.
# Video, audio and gamepad identity are negotiated at runtime: the loader binds
# SDL2, OpenAL, mpg123, GLES1 and EGL by SONAME, so each firmware supplies its
# own stack.  Never force a driver here.

SWORDIGO_RUNTIME_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" \
  2>/dev/null && pwd -P) || exit 1
PORTNAME='Swordigo (NextOS)'
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d /opt/system/Tools/PortMaster ]; then
  controlfolder=/opt/system/Tools/PortMaster
elif [ -d /opt/tools/PortMaster ]; then
  controlfolder=/opt/tools/PortMaster
elif [ -d "$XDG_DATA_HOME/PortMaster" ]; then
  controlfolder=$XDG_DATA_HOME/PortMaster
elif [ -d /roms/ports/PortMaster ]; then
  controlfolder=/roms/ports/PortMaster
elif [ -d /storage/roms/ports/PortMaster ]; then
  controlfolder=/storage/roms/ports/PortMaster
else
  controlfolder=/storage/.config/PortMaster
fi

if [ -f "$controlfolder/control.txt" ] && [ ! -L "$controlfolder/control.txt" ]; then
  # shellcheck source=/dev/null
  source "$controlfolder/control.txt"
  case "${CFW_NAME:-}" in
    ''|*[!A-Za-z0-9._-]*) ;;
    *)
      if [ -f "$controlfolder/mod_${CFW_NAME}.txt" ] &&
         [ ! -L "$controlfolder/mod_${CFW_NAME}.txt" ]; then
        # shellcheck source=/dev/null
        source "$controlfolder/mod_${CFW_NAME}.txt"
      fi
      ;;
  esac
  declare -F get_controls >/dev/null 2>&1 && get_controls
fi
: "${ESUDO:=}"
: "${CUR_TTY:=/dev/tty0}"

launcher_error() {
  local message console
  message="Swordigo: $*"
  printf '%s\n' "$message" >&2
  # Failures raised before the log redirect would otherwise be invisible when
  # the port is launched from the frontend.
  printf '=== %s ===\n%s\n' \
    "$(date -Is 2>/dev/null || date 2>/dev/null || echo unknown)" "$message" \
    >> "$SWORDIGO_RUNTIME_DIR/swordigo-launcher-error.log" 2>/dev/null
  for console in "${CUR_TTY:-/dev/tty0}" /dev/tty1 /dev/console; do
    [ -w "$console" ] || continue
    printf '\n%s\nSee %s\n' "$message" \
      "$SWORDIGO_RUNTIME_DIR/swordigo-launcher-error.log" >> "$console" \
      2>/dev/null && break
  done
  exit 1
}

GAMEDIR=${SWORDIGO_GAMEDIR:-$SWORDIGO_RUNTIME_DIR}
GAMEDIR=$(CDPATH= cd -- "$GAMEDIR" 2>/dev/null && pwd -P) ||
  launcher_error 'game directory is missing'
BIN=$GAMEDIR/swordigo

finish_done=0
finish_frontend_once() {
  [ "$finish_done" -eq 0 ] || return
  finish_done=1
  ${ESUDO:-} chmod 666 "$CUR_TTY" 2>/dev/null || true
  [ -w "$CUR_TTY" ] && printf '\033c' >> "$CUR_TTY" 2>/dev/null || true
  command -v pm_finish >/dev/null 2>&1 && pm_finish
}
finish_on_exit() {
  local status=$?
  trap - EXIT
  finish_frontend_once
  exit "$status"
}
trap finish_on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$GAMEDIR" || launcher_error 'could not enter game directory'

# One instance only, and the lock lives on the binary itself so a second
# launcher cannot start the game behind the first one.
if command -v flock >/dev/null 2>&1; then
  exec 9<"$BIN" 2>/dev/null || true
  flock -n 9 2>/dev/null || launcher_error 'Swordigo is already running'
fi

# A stale instance from a crashed session still owns the display and the audio
# device, so the port stops it before taking over -- matched by executable and
# working directory, never by process name alone.
stop_existing_game() {
  local process pid executable working_directory old_pids remaining attempt

  matching_game_pids() {
    for process in /proc/[0-9]*; do
      pid=${process##*/}
      [ "$pid" = "$$" ] && continue
      executable=$(command readlink "$process/exe" 2>/dev/null || true)
      working_directory=$(command readlink "$process/cwd" 2>/dev/null || true)
      case "$executable" in
        "$BIN"|"$BIN (deleted)"|*/ports/swordigo/swordigo) printf '%s\n' "$pid" ;;
        *)
          [ "$working_directory" = "$GAMEDIR" ] &&
            [ "$(cat "$process/comm" 2>/dev/null || true)" = swordigo ] &&
            printf '%s\n' "$pid"
          ;;
      esac
    done
  }

  old_pids=$(matching_game_pids)
  [ -n "$old_pids" ] || return 0
  for pid in $old_pids; do
    printf '[launcher] stopping old Swordigo instance pid=%s\n' "$pid"
    kill "$pid" 2>/dev/null || true
  done
  attempt=0
  remaining=$(matching_game_pids)
  while [ -n "$remaining" ] && [ "$attempt" -lt 20 ]; do
    sleep 0.5
    attempt=$((attempt + 1))
    remaining=$(matching_game_pids)
  done
  for pid in $remaining; do
    kill -9 "$pid" 2>/dev/null || true
  done
  [ -z "$remaining" ] || sleep 1
}

if [ -s "$GAMEDIR/swordigo.log" ]; then
  mv -f -- "$GAMEDIR/swordigo.log" "$GAMEDIR/swordigo.prev.log"
fi
exec > "$GAMEDIR/swordigo.log" 2>&1
release_version=$(command tr -d '\r\n' < "$GAMEDIR/version.txt" 2>/dev/null || true)
printf '=== %s | release %s | %s ===\n' \
  "$PORTNAME" "${release_version:-unknown}" "$(date -Is 2>/dev/null || date)"

${ESUDO:-} chmod +x "$BIN" "$GAMEDIR/run.sh" 2>/dev/null || true

[ -x "$BIN" ] || launcher_error 'runtime loader is missing or not executable'
stop_existing_game
[ -f "$GAMEDIR/extractor.json" ] &&
[ -f "$GAMEDIR/run-extractor.sh" ] &&
[ -f "$GAMEDIR/nxextract-runtime-env.sh" ] &&
[ -f "$GAMEDIR/nxextract.py" ] ||
  launcher_error 'runtime or NXExtract files are missing'

firmware_libraries=
for directory in "$controlfolder/libs" "$controlfolder/libs.aarch64"; do
  [ -d "$directory" ] &&
    firmware_libraries=${firmware_libraries:+$firmware_libraries:}$directory
done

# Host libraries stay first so SDL, EGL, Mali and audio always match the
# running kernel/firmware.
host_libraries='/usr/local/lib/aarch64-linux-gnu:/usr/local/lib:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:/usr/lib:/lib'
[ -n "$firmware_libraries" ] && host_libraries=$host_libraries:$firmware_libraries
export LD_LIBRARY_PATH="$host_libraries:$GAMEDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export HOME=$GAMEDIR
export SDL_GAMECONTROLLER_USE_BUTTON_LABELS=0
export SDL_VIDEO_FULLSCREEN_DESKTOP=1

[ -n "${sdl_controllerconfig:-}" ] &&
  export SDL_GAMECONTROLLERCONFIG=$sdl_controllerconfig
if [ -z "${SDL_GAMECONTROLLERCONFIG_FILE:-}" ]; then
  for database in \
    "$controlfolder/gamecontrollerdb.txt" \
    "$controlfolder/gamecontrollerdb-SDL2.txt" \
    /storage/.config/SDL-GameControllerDB/gamecontrollerdb.txt \
    /storage/.config/SDL-GameControllerDB/gamecontrollerdb-SDL2.txt; do
    if [ -r "$database" ] && [ ! -L "$database" ]; then
      export SDL_GAMECONTROLLERCONFIG_FILE=$database
      break
    fi
  done
fi

pulse_available=0
for pulse_socket in /var/run/pulse/native /run/pulse/native; do
  if [ -S "$pulse_socket" ]; then
    pulse_available=1
    [ -z "${PULSE_SERVER:-}" ] && export PULSE_SERVER=unix:$pulse_socket
    break
  fi
done
# ALSA-only firmwares: OpenAL Soft's mmap path stalls with a broken pipe in
# long sessions on RK3326-class handhelds.  Never forces a driver -- it only
# tunes the backend the firmware already chose.
if [ "$pulse_available" -eq 0 ] && [ -z "${ALSOFT_CONF:-}" ] &&
   [ -r "$GAMEDIR/alsoft.conf" ]; then
  export ALSOFT_CONF="$GAMEDIR/alsoft.conf"
fi

memory_kib=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || true)
case "$memory_kib" in ''|*[!0-9]*) memory_kib=0 ;; esac
if [ "$memory_kib" -gt 0 ] && [ "$memory_kib" -lt 1250000 ]; then
  export MALLOC_ARENA_MAX=${MALLOC_ARENA_MAX:-2}
  export MALLOC_TRIM_THRESHOLD_=${MALLOC_TRIM_THRESHOLD_:-131072}
  export MALLOC_MMAP_THRESHOLD_=${MALLOC_MMAP_THRESHOLD_:-65536}
fi

${ESUDO:-} chmod +x \
  "$GAMEDIR/run-extractor.sh" \
  "$GAMEDIR/nxextract-runtime-env.sh" \
  "$GAMEDIR/nxextract.py" \
  "$GAMEDIR/nxextract-ui" \
  2>/dev/null || true

# NXExtract prepares the owner data from the APK in gamedata/ on the first
# launch and validates it with a fast marker check afterwards.
NXEXTRACT_GAME_DIR=$GAMEDIR \
NXEXTRACT_FIRMWARE_LIBRARY_PATH=$firmware_libraries \
  "$GAMEDIR/run-extractor.sh" || {
  status=$?
  launcher_error "game-data preparation failed ($status)"
}
if [ "${SWORDIGO_EXTRACTOR_ONLY:-0}" = 1 ]; then
  printf '[launcher] extractor-only validation completed\n'
  exit 0
fi

printf '[launcher] binary=%s video=%s audio=%s controller=%s\n' \
  "$(basename "$BIN")" \
  "${SDL_VIDEODRIVER:-firmware-auto}" \
  "${SDL_AUDIODRIVER:-firmware-auto}" \
  "${SDL_GAMECONTROLLERCONFIG:+PortMaster mapping}"

if command -v pm_platform_helper >/dev/null 2>&1; then
  pm_platform_helper "$BIN" >/dev/null ||
    launcher_error 'PortMaster could not prepare frontend lifecycle'
fi

"$BIN" "$GAMEDIR"
exit $?
