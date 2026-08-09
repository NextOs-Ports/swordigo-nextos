# Swordigo v1.0.7 — reliable updates from 1.0.4

Release ZIP SHA-256:
`d79de193d43c134fc331a99dce15155de8a7cfb3dee3cde89ee28cdfbdd152a5`

Canonical loader SHA-256:
`c1add34c0f815652c21e879d652632dd1e0705cc364088d2b1a59d061e64426c`

The dArkOSRE field log identified a mixed installation rather than the current
runtime: it still embedded `executable=swordigo` and the two-quirk v1.0.4
contract, while v1.0.5 and later embed `swordigo-nextos` and three quirks.
Version 1.0.7 makes this update path deterministic by packaging a regular,
byte-identical compatibility copy at the old path. Even when a firmware keeps
the old visible launcher during an overlay update, it now executes the current
loader. Current installations continue to use `swordigo-nextos` directly.

The ZIP independently audits the canonical loader, compatibility copy and
NXExtract UI. Both runtime paths are AArch64, byte-identical and require at
most `GLIBC_2.27`; the extractor UI requires `GLIBC_2.17`. Package construction
fails if either copy diverges, if any ELF exceeds `GLIBC_2.30`, or if owner game
data enters the release.

This release also contains the v1.0.6 durable-stderr correction relevant to the
muOS v1.0.5 no-log report. The native Android lifecycle, rendering, audio,
controls, extraction and user data are otherwise unchanged.

## Português

O log do dArkOSRE mostrou uma instalação mista: ainda estava usando
`executable=swordigo` e os dois quirks da v1.0.4, embora desde a v1.0.5 o
contrato use `swordigo-nextos` e três quirks. A v1.0.7 inclui no caminho antigo
uma cópia ELF regular e byte a byte idêntica ao loader atual. Assim, mesmo que o
firmware preserve o launcher antigo numa atualização por cima, ele executa o
runtime novo. Instalações atuais continuam escolhendo `swordigo-nextos`.

O ZIP também leva a correção de log da v1.0.6, importante para o relato do
muOS com a v1.0.5. Não há APK nem dados do jogo no pacote, e não é necessário
apagar `assets`, `res`, `libswordigo.so` ou saves ao atualizar.

---

# Swordigo v1.0.6 — durable runtime logging

Release ZIP SHA-256:
`92031b8bd83f8da083ccc81d38b09a91f6c0205f8ca1914f8b25d4772ac20849`

This maintenance release keeps every gameplay, graphics, audio, control and
extraction change from v1.0.5. It fixes the universal bootstrap's descriptor
probes so their local error suppression cannot redirect the launcher's stderr
away from `debug.log` during the runtime handoff. The canonical isolated
bootstrap suite covers the regression; no device-specific workaround was
added.

The package remains BYO-data, contains one visible `Swordigo.sh`, has no
`run.sh`, and keeps the public loader name `swordigo-nextos`.

---

# Swordigo v1.0.5 — dArkOSRE display handoff and transactional present

Release ZIP SHA-256:
`aa59275531ecfeb50789d37c416abeed7855519418a65ab3a7db33ba35281146`

Sanitized acceptance receipt:
[`v1.0.5-multi-device-acceptance.json`](https://github.com/NextOs-Ports/swordigo-nextos/blob/v1.0.5/references/v1.0.5-multi-device-acceptance.json)

This release addresses the field report where Swordigo completed extraction and
played audio but remained behind a dark screen on a dArkOSRE-class handheld.
The failure is in the display handoff: some firmware modules replace
PortMaster's normal platform helper with an empty function, so the helper can
report success while PortMaster's live dialog still owns the screen. The
bootstrap now checks the official live pipe and closes only that exact dialog
through `PortMasterDialogExit`, before NXExtract UI or SDL starts. There is no
device-name workaround and no broad process kill.

The GLES1 present is hardened independently: framebuffer zero is resolved
through SDL/EGL/process lookup, the alpha-only clear is transactional, and the
original framebuffer, colour mask, clear colour and scissor state are restored
exactly. The one-time frame probe now measures the actual backbuffer. KMSDRM
drains GLES before the page flip, selected from the backend that really opened
(`SWORDIGO_GLFINISH=0/1` is the diagnostic override).

The public Linux loader is now named `swordigo-nextos`; the Android-owned
`libswordigo.so` retains its original name. Existing extracted game data is
reused, so updating does not repeat extraction. The package remains BYO-data,
contains one visible `Swordigo.sh`, has no `run.sh`, and writes launcher/runtime
events to `debug.log` while NXExtract keeps `nxextract.log`.

The sanitized acceptance receipt is published with the source. Both available
physical regression devices produced non-black opaque frames, opened audio and
exited cleanly. Confirmation on the original dArkOSRE device is still pending.

---

# Swordigo v1.0.5 — correção do display no dArkOSRE

Este release trata o relato de Swordigo com extração concluída e áudio normal,
mas tela escura em aparelho da classe dArkOSRE. A falha fica na passagem do
display: alguns módulos do firmware substituem o helper normal do PortMaster por
uma função vazia, que retorna sucesso enquanto o diálogo vivo do PortMaster
continua dono da tela. O bootstrap agora verifica o pipe oficial e fecha somente
aquele diálogo por `PortMasterDialogExit`, antes da UI do NXExtract ou da SDL.
Não há exceção pelo nome do aparelho e nenhum `pkill` amplo.

O present GLES1 também ficou independente e transacional: seleciona o
framebuffer zero, força apenas o alpha a 1 e restaura framebuffer, máscara de
cor, clear color e scissor exatamente. No KMSDRM a fila GLES é concluída antes
do page flip. O novo executável público se chama `swordigo-nextos`; a biblioteca
Android original continua `libswordigo.so`. Dados já extraídos são reutilizados.
Os dois aparelhos físicos disponíveis produziram frames opacos e não pretos,
abriram áudio e encerraram corretamente; a confirmação no dArkOSRE do relato
original ainda está pendente.

---

# Swordigo v1.0.4 — one launcher, one durable log

The public ZIP now follows the universal PortMaster framework literally:
`Swordigo.sh` loads `swordigo/nxbootstrap.sh` and launches the loader. The
obsolete intermediate `run.sh` is gone. NXExtract is updated to 1.2.6, and the
OpenAL/Pulse setup proven by v1.0.1 lives in Swordigo's C adapter so the generic
bootstrap remains backend-neutral. Launcher and loader output now share
`swordigo/debug.log`; extraction keeps its independent `nxextract.log`.

This is a packaging/pre-main correction. The native game order, GLES1 opaque
present, fullscreen-desktop policy, audio backend order, controls and exit path
from v1.0.3 are preserved.

The exact public ZIP (`8f2934deb8d258a895db55db317d04f847db570cd7a5f78ffac88a7c939cbb89`)
was accepted on NextOS/Mali-450: NXExtract 1.2.6 fast validation, GLES1 at
1280×720, OpenAL at 48 kHz, a real non-black frame, TERM exit status 0,
PortMaster finish and no remaining process. The sanitized receipt is
[`references/v1.0.4-nextos-acceptance.json`](references/v1.0.4-nextos-acceptance.json).

---

# Swordigo v1.0.3 — black screen: the modeset, and the log that decides

Field testing came back with the game **running but the screen black**: music
playing, input answering, log clean. This release removes the most likely cause,
keeps the two fixes from 1.0.1/1.0.2, and — because the failing firmware is one
nobody here owns — ships the measurement that turns the next report into a
verdict instead of another guess.

## What changed

- **No more exclusive fullscreen.** The window is created with
  `SDL_WINDOW_FULLSCREEN_DESKTOP`. Exclusive fullscreen asks KMSDRM for a
  *modeset* to the size we requested, so a firmware reporting a desktop mode its
  panel does not actually drive returns a window that never reaches the screen —
  black picture with the engine alive. Every published port on this fleet
  already defaults to desktop fullscreen (Horizon Chase, Prizefighters 2,
  Hitman GO, Geometry Dash). `SWORDIGO_EXCLUSIVE_FULLSCREEN=1` restores the old
  behaviour, and creation falls back to exclusive on its own if desktop
  fullscreen is refused.
- **The deciding test now ships.** A few seconds in, one frame is read back and
  logged:

  ```text
  gl: frame probe 640x480 rgb_non_black=76.1% alpha255=99.0% alpha0=0.0%
  ```

  Colour with **alpha 0** → the scanout composited the frame away.
  Colour with **alpha 255** → the picture is fine and the wrong surface is being
  presented. **Empty frame** → the engine really drew nothing. One line, one
  mechanism, no device needed.
- **The launcher names who holds the display** when the game starts
  (`[launcher] display held by: ...`, `/dev/dri/*` and `/dev/fb*`). It stops
  nothing — the frontend stays PortMaster's business — it only makes the answer
  visible.
- Kept from 1.0.2: window asks for no alpha, and every frame is forced opaque
  before the present with framebuffer 0 rebound first. Kept from 1.0.1:
  `alsoft.conf` applies on every firmware with `drivers = pipewire,pulse,alsa`,
  and the log names the audio output that won.

## Ruled out, with evidence

- **The extractor is not involved.** Its progress UI starts only *after* the
  fast marker check, and every failing log says `fast validation marker
  accepted` — no UI process existed in those boots.
- **Per-pixel alpha is not confirmed as the cause.** An ArkOS R36S-class unit
  (Mali-G31, KMSDRM, `alpha=8`) draws the title screen perfectly on the very
  release that was reported black, measured by `kmsgrab` capture: 73.6% of the
  frame carries colour. The 1.0.2 alpha work stays because it is a real
  mechanism and measured harmless, but it is not the answer here.

## Verified

On the ArkOS R36S-class unit, install from this ZIP and run: game alive, log
reports `driver='KMSDRM' renderer='Mali-G31' fullscreen=desktop`, frame probe
`rgb_non_black=76.1% alpha255=99.0%`, and a `kmsgrab` capture of the real screen
shows the full title screen (73.7% non-black). On Amlogic Mali-450: same run
clean, audio streaming to PulseAudio, alpha 100% opaque, RGB untouched.

**Still not reproduced here:** no device on the bench shows the black screen.
If it persists, send `swordigo.log` — the `gl:` lines and
`[launcher] display held by:` now say which mechanism it is.

## Installation

Extract the ZIP **into the `ports` folder** of the ROM card (`mmc/roms/ports` on
muOS), keep `Swordigo.sh` and the `swordigo` folder side by side, put a legally
owned **Swordigo 1.4.12 APK** in `swordigo/gamedata/`, and launch from Ports. On
NextOS/EmuELEC also copy the `.sh` to `roms/ports_scripts/`. Data extracted by an
earlier release is reused as is.

## Controls

Move with the D-pad or left stick, **A** jumps, **X** attacks, **B** casts
magic, **Y** uses an item, **LB** equips magic, **Start** opens the menu,
**RB** goes back. The right stick drives an on-screen cursor and **R3** taps.
**SELECT + START** exits to the frontend.

---

# Swordigo v1.0.3 — tela preta: o modeset, e o log que decide

**O que mudou:** a janela deixa de usar fullscreen exclusivo e passa a
`SDL_WINDOW_FULLSCREEN_DESKTOP`. O exclusivo pede **modeset** ao KMSDRM para o
tamanho solicitado; firmware que reporta um modo que o painel não dirige devolve
uma janela que nunca chega à tela — preto com a engine viva. É o padrão de todo
port publicado da frota (Horizon Chase, Prizefighters 2, Hitman GO, Geometry
Dash). `SWORDIGO_EXCLUSIVE_FULLSCREEN=1` volta ao comportamento antigo.

**O release agora carrega o teste que decide:** um quadro é lido de volta e
logado — `gl: frame probe ... rgb_non_black=% alpha255=% alpha0=%`. Cor com
alpha 0 = o scanout apagou o quadro; cor com alpha 255 = imagem boa e surface
errada no present; quadro vazio = a engine não desenhou. O launcher também diz
**quem está segurando o display** (`/dev/dri/*`, `/dev/fb*`) — sem parar nada.

**Descartado com prova:** a extração **não** tem parte nisso (a UI do extrator só
sobe *depois* do fast-path, e os logs que falharam dizem `fast validation marker
accepted`); e o alpha por pixel **não está confirmado** como causa — um R36S/ArkOS
(Mali-G31, KMSDRM, `alpha=8`) desenha o título perfeito na mesma versão relatada
como preta, com captura `kmsgrab` provando 73,6% de pixels com cor.

**Comprovado:** ArkOS R36S — instalação do ZIP, jogo vivo, captura real da tela
com o título completo (73,7% não-preto). Mali-450 — rodada limpa, áudio no
PulseAudio, alpha 100% opaco, RGB intacto. **A tela preta segue não reproduzida
na bancada**; se persistir, o `swordigo.log` agora diz qual mecanismo é.
