#!/bin/sh
# Standard PortMaster entry point.  The full universal runtime stays beside the
# game files so ports/ and ports_scripts/ share one implementation.
#
# Resolve o proprio caminho REAL antes de procurar: em alguns frontends o
# arquivo visivel e' um symlink ou copia, e `dirname $0` apontaria para o lugar
# errado. Uma lista fixa de raizes de ROM nao cobre todo CFW (muOS usa /mnt/mmc
# e /mnt/sdcard), entao a busca relativa ao script vem primeiro e sempre vale.

SELF=$0
[ -L "$SELF" ] && SELF=$(readlink -f -- "$SELF" 2>/dev/null || printf '%s' "$0")
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$SELF")" 2>/dev/null && pwd -P) ||
  SCRIPT_DIR=.

for launcher in \
  "$SCRIPT_DIR/swordigo/run.sh" \
  "$SCRIPT_DIR/../ports/swordigo/run.sh" \
  "$SCRIPT_DIR/../../ports/swordigo/run.sh" \
  /roms/ports/swordigo/run.sh \
  /roms2/ports/swordigo/run.sh \
  /storage/roms/ports/swordigo/run.sh \
  /mnt/mmc/ports/swordigo/run.sh \
  /mnt/mmc/roms/ports/swordigo/run.sh \
  /mnt/mmc/ROMS/ports/swordigo/run.sh \
  /mnt/sdcard/ports/swordigo/run.sh \
  /mnt/sdcard/roms/ports/swordigo/run.sh \
  /mnt/sdcard/ROMS/ports/swordigo/run.sh \
  /mnt/union/roms/ports/swordigo/run.sh \
  /mnt/SDCARD/roms/ports/swordigo/run.sh \
  /userdata/roms/ports/swordigo/run.sh
do
  if [ -f "$launcher" ] && [ ! -L "$launcher" ]; then
    exec bash "$launcher" "$@"
  fi
done

# Falhar em silencio aqui foi o modo de falha reportado no muOS/RG40XXH: o
# frontend descarta stderr, o port voltava ao menu e NENHUM arquivo era gerado,
# entao nao havia o que reportar. Agora o erro fica gravado em disco.
message="Swordigo: ports/swordigo/run.sh not found. Put the folder \
\"swordigo\" in the same ports folder as this script (roms/ports/swordigo on \
muOS/ArkOS/ROCKNIX). script=$SELF dir=$SCRIPT_DIR"
printf '%s\n' "$message" >&2
for spot in "$SCRIPT_DIR/swordigo-launcher-error.log" \
            "${TMPDIR:-/tmp}/swordigo-launcher-error.log"
do
  if printf '%s\n' "$message" > "$spot" 2>/dev/null; then
    printf 'Swordigo: detalhes em %s\n' "$spot" >&2
    break
  fi
done
for console in "${CUR_TTY:-/dev/tty0}" /dev/tty1 /dev/console; do
  [ -w "$console" ] || continue
  printf '\n%s\n' "$message" >> "$console" 2>/dev/null && break
done
exit 1
