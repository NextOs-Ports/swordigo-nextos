# Swordigo v1.0.2 — black screen fix

Field testing on the R36S/ArkOS/DarkOS class came back with the game **running
but the screen black**: music playing, input answering, log clean. This release
fixes the known cause of that symptom and makes the next report diagnosable.
1.0.1 (audio) is included.

## What was wrong

The window was created with `SDL_GL_ALPHA_SIZE 8`. On a firmware whose scanout
honours **per-pixel alpha** — a KMSDRM plane in `ARGB8888`, the R36S class — a
frame the game leaves at alpha 0 is composited as *transparent*, which reads as
a black screen while the engine is perfectly alive. Amlogic's OSD ignores alpha,
which is why the identical build draws fine on NextOS hardware and the bug only
showed up in the field.

## What changed

- The window asks for **no alpha** in its config.
- Because that attribute is a *minimum* and drivers hand out an alpha config
  anyway (this very firmware grants `alpha=8` when asked for 0), every frame is
  additionally forced **opaque immediately before the present**, rebinding
  framebuffer 0 through `glBindFramebufferOES` first so the clear can never land
  on a bound FBO — the trap that cost Horizon Chase v1.2.0.
- The log now carries what a black-screen report needs:

  ```text
  gl: GLES1.1 1280x720 alpha=8 depth=24 driver='mali'
  gl: renderer='Mali-450 MP' version='OpenGL ES-CM 1.1'
  gl: opaque-alpha present active (fbo rebind=yes)
  ```

- From 1.0.1: `alsoft.conf` applies on every firmware and pins
  `drivers = pipewire,pulse,alsa`; `PULSE_SERVER` also reads the per-user
  runtime socket; the log names the audio output that won; music no longer
  treats the first `MPG123_NEW_FORMAT` as a decode failure.

## Verified

Measured on Mali-450 at 1280x720 with `glReadPixels` on both sides of the new
present step: alpha went from **255 on 99.0%** of the frame to **255 on 100%**,
and the **RGB bytes are identical** before and after — the clear fixes opacity
without touching a pixel of image. Regression pass with the shipped ZIP: clean
install, game running, audio streaming, frontend restored.

**Not reproduced here:** the black screen itself needs an alpha-honouring
firmware and every device on hand ignores alpha. This ships the mechanism the
fleet has already paid for twice; if a device is still black, send
`swordigo.log` — the three `gl:` lines above say which mechanism it is.

## Installation

Extract the ZIP **into the `ports` folder** of the ROM card (`mmc/roms/ports` on
muOS), keep `Swordigo.sh` and the `swordigo` folder side by side, put a legally
owned **Swordigo 1.4.12 APK** in `swordigo/gamedata/`, and launch from Ports. On
NextOS/EmuELEC also copy the `.sh` to `roms/ports_scripts/`. Data already
extracted by an earlier release is reused as is.

## Controls

Move with the D-pad or left stick, **A** jumps, **X** attacks, **B** casts
magic, **Y** uses an item, **LB** equips magic, **Start** opens the menu,
**RB** goes back. The right stick drives an on-screen cursor and **R3** taps.
**SELECT + START** exits to the frontend.

---

# Swordigo v1.0.2 — correção de tela preta

No teste de campo (R36S/ArkOS/DarkOS) o jogo **rodava com a tela preta**: música
tocando, controle respondendo, log limpo.

**Causa:** a janela era criada com `SDL_GL_ALPHA_SIZE 8`. Em firmware cujo
scanout **honra alpha por pixel** (plano KMSDRM em `ARGB8888`), o quadro que o
jogo deixa com alpha 0 é composto como *transparente* — ou seja, preto, com a
engine viva. O OSD do Amlogic ignora alpha, e por isso a mesma build desenha
normal no aparelho daqui e o defeito só apareceu na mão dos outros.

**Conserto (duas travas):** a janela passa a pedir config **sem alpha** e, como
o atributo é mínimo e o driver entrega alpha assim mesmo (aqui vem `alpha=8`
mesmo pedindo 0), todo quadro é forçado **opaco logo antes do present**,
religando o framebuffer 0 por `glBindFramebufferOES` para o clear nunca cair num
FBO amarrado (a pegadinha que custou a v1.2.0 do Horizon Chase). O log agora traz
driver de vídeo, config concedida, renderer/versão do GL e a confirmação de que o
present opaco rodou. Inclui também o fix de áudio da 1.0.1.

**Medição (Mali-450, 1280x720):** alpha de **255 em 99,0%** para **255 em 100%**,
com **RGB byte a byte idêntico** — conserta a opacidade sem tocar em imagem.

**Não reproduzido aqui:** a tela preta exige firmware que honra alpha, e todo
aparelho da bancada ignora. Se algum continuar preto, manda o `swordigo.log`: as
linhas `gl:` dizem qual mecanismo é.
