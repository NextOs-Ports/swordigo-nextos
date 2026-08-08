# Swordigo v1.0.0 — universal ARM64 release

One AArch64 loader for NextOS, ArkOS, ROCKNIX, muOS and Knulli class
handhelds, audited at a maximum `GLIBC_2.27` requirement. It is a native,
BYO-data port: the ZIP contains no game, APK, save or purchase state.

## Highlights

- SDL2, OpenAL, mpg123, GLES1 and EGL are bound by SONAME and supplied by the
  firmware, so no video or audio backend is ever forced by the launcher.
- Fixed the `stack smashing detected` abort on Mali-G31/glibc devices: the game
  reads its stack canary from the Bionic TLS slot, which the runtime now
  anchors with a never-written thread-local pad.
- Follows the real drawable size, so touch hitboxes and the viewport stay put
  on firmwares that draw into a different size than the window they hand out.
- ALSA-only devices get `alsoft.conf` with the mmap path disabled — the fix for
  OpenAL Soft's broken-pipe stall in long sessions — applied only when no
  PulseAudio socket exists.
- One instance only, with the lock on the binary; a stale instance from a
  crashed session is stopped first, matched by executable and working
  directory rather than by name.
- BYO data through NXExtract 1.2.4: transactional staging, structural
  validation that accepts any legitimate 1.4.12 build, and a fast marker check
  on later launches.
- Never fails silently: a missing game folder or a refused second launch is
  written to `swordigo-launcher-error.log` and printed on the console.

## Controls

Move with the D-pad or left stick, **A** jumps, **X** attacks, **B** casts
magic, **Y** uses an item, **LB** equips magic, **Start** opens the menu,
**RB** goes back. The right stick drives an on-screen cursor and **R3** taps.
**SELECT + START** exits to the frontend.

## Installation

1. Extract the ZIP **into the `ports` folder** of the ROM card — `roms/ports/`
   on ArkOS/ROCKNIX/Knulli, `mmc/roms/ports` on muOS. `Swordigo.sh` and the
   `swordigo` folder must sit side by side. On NextOS/EmuELEC also copy the
   `.sh` to `roms/ports_scripts/`.
2. Put a legally owned **Swordigo 1.4.12 APK** (`com.touchfoo.swordigo`,
   containing `lib/arm64-v8a/libswordigo.so`) in `swordigo/gamedata/`.
3. Launch **Swordigo** from Ports and let NXExtract finish once.

## Verified

Proven end to end on an ArkOS R36S-class unit (RK3326, Mali-G31, glibc 2.30,
640x480): clean install from this ZIP, on-device extraction with the progress
screen, title, gameplay, audio and music, exit chord, frontend restored.

SHA-256:

```text
903fd2a9d58629ec0ce190f999086a7ce1d45162f721402e50f463309094b100  Swordigo.NextOS-v1.0.0.zip
```

---

# Swordigo v1.0.0 — release universal ARM64

Um único loader AArch64 para aparelhos NextOS, ArkOS, ROCKNIX, muOS e Knulli,
auditado com teto `GLIBC_2.27`. Port nativo **BYO-data**: o ZIP não traz o
jogo, APK, save nem estado de compra.

- SDL2, OpenAL, mpg123, GLES1 e EGL amarrados por SONAME — quem entrega é o
  firmware; o launcher nunca força driver de vídeo ou áudio.
- Corrigido o `stack smashing detected` em aparelho Mali-G31/glibc: o jogo lê o
  canário do slot TLS do bionic, agora ancorado por um pad thread-local.
- Segue o drawable real; `alsoft.conf` sem mmap em aparelho só-ALSA; instância
  única com trava no binário e limpeza de instância órfã.
- Dados BYO por NXExtract 1.2.4, com validação estrutural que aceita qualquer
  build legítima da 1.4.12.
- Nunca falha calado: o motivo vai para `swordigo-launcher-error.log` e para a
  tela.

Instalação: extraia o ZIP **dentro de `roms/ports/`** (`mmc/roms/ports` no
muOS), coloque o APK legal 1.4.12 em `swordigo/gamedata/` e abra em Ports.
No NextOS/EmuELEC, copie também o `.sh` para `roms/ports_scripts/`.
