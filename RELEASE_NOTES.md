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
