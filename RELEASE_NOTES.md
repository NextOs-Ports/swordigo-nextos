# Swordigo v1.0.1 — audio fix

Release 1.0.0 came back mute from field testing. This release fixes the audio
path and makes it verifiable from the log. Nothing else changed: same universal
AArch64 loader, same `GLIBC_2.27` ceiling, same BYO-data install.

## What was wrong

The launcher exported `alsoft.conf` **only on firmwares without a PulseAudio
socket**, so every box that runs a sound server got no backend order and none
of the ALSA fixes the file carries. That is exactly the case in the tester
logs: OpenAL Soft's PipeWire backend fails to start
(`Failed to create PipeWire event context`), and because the library picks one
playback backend at init and never reconsiders, the game drops through to raw
ALSA — the mmap path the fleet already knows stalls silently on these
handhelds. The log said `openal: ok` the whole time, because it never named the
backend that actually won.

## What changed

- `alsoft.conf` is applied on **every** firmware and pins
  `drivers = pipewire,pulse,alsa` — the order the approved Bully port proved on
  PipeWire, Amlogic Mali-450 and ALSA-only R36S hardware. A sound server is
  preferred over raw ALSA, and raw ALSA always gets `mmap = false`. It only
  orders backends OpenAL Soft already has and still never forces one.
- `PULSE_SERVER` also picks up the per-user `$XDG_RUNTIME_DIR/pulse/native`
  socket.
- The log now names the output that won:
  `openal: ok ... spec='OpenAL Soft' out='HDMI_I2S' rate=48000`, plus a
  `[launcher] openal ALSOFT_CONF=... pulse=...` line. **If a device is still
  mute, that pair of lines says why.**
- Music: an `MPG123_NEW_FORMAT` announcement on the first decode is no longer
  treated as a decode failure, and a start request is kept until the track
  really starts instead of being dropped after one empty prime.
- Host test gate: the launcher may not make the OpenAL config conditional
  again, and the config must keep the pinned order.

## Verified

Clean install of this ZIP on an Amlogic Mali-450 NextOS unit, on-device
extraction from the APK, game running: the PulseAudio stream is live and
unmuted (`application.name = "swordigo"`, `Corked: no`, `Mute: no`, 100%), and
a 3-second capture of the sink monitor while the game plays measures peak 8376
/ mean 1326 — real signal, not silence. Log line:
`openal: ok ... spec='OpenAL Soft' out='HDMI_I2S' rate=48000`.

## Installation

Same as 1.0.0 — extract the ZIP **into the `ports` folder** of the ROM card
(`mmc/roms/ports` on muOS), keep `Swordigo.sh` and the `swordigo` folder side
by side, put a legally owned **Swordigo 1.4.12 APK** in `swordigo/gamedata/`,
and launch from Ports. On NextOS/EmuELEC also copy the `.sh` to
`roms/ports_scripts/`. Data already extracted by 1.0.0 is reused as is.

## Controls

Move with the D-pad or left stick, **A** jumps, **X** attacks, **B** casts
magic, **Y** uses an item, **LB** equips magic, **Start** opens the menu,
**RB** goes back. The right stick drives an on-screen cursor and **R3** taps.
**SELECT + START** exits to the frontend.

---

# Swordigo v1.0.1 — correção de áudio

A 1.0.0 voltou muda do teste de campo. Esta versão corrige o caminho de áudio e
deixa ele conferível pelo log. Nada mais mudou: mesmo loader universal AArch64,
mesmo teto `GLIBC_2.27`, mesma instalação BYO-data.

**O que estava errado:** o launcher só exportava o `alsoft.conf` em firmware
**sem** socket do PulseAudio. Logo, todo aparelho com servidor de som ficava sem
ordem de backend e sem nenhuma das correções do arquivo. É o caso dos logs dos
testadores: o backend PipeWire do OpenAL Soft não sobe
(`Failed to create PipeWire event context`) e, como a biblioteca escolhe **um**
backend na inicialização e não reconsidera, o jogo cai no ALSA cru — o caminho
mmap que a frota já sabe que trava calado nesses aparelhos. E o log dizia
`openal: ok` o tempo todo, porque nunca dizia qual backend venceu.

**O que mudou:** o `alsoft.conf` passa a valer em **todo** firmware e fixa
`drivers = pipewire,pulse,alsa` (a ordem provada pelo Bully aprovado em
PipeWire, Mali-450 e R36S só-ALSA); servidor de som na frente do ALSA cru, e
ALSA cru sempre com `mmap = false`. O `PULSE_SERVER` também aceita o socket em
`$XDG_RUNTIME_DIR`. O log agora nomeia a saída que venceu — se algum aparelho
continuar mudo, é essa linha que diz o motivo. A música também ficou mais
robusta (`MPG123_NEW_FORMAT` e retentativa do play).

**Comprovação:** instalação limpa deste ZIP em Mali-450/NextOS, extração no
aparelho e jogo rodando: stream vivo e sem mute no PulseAudio e captura de 3s do
monitor do sink com pico 8376 / média 1326 — sinal real, não silêncio.
