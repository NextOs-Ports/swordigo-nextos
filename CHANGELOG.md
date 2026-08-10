# Changelog

## 1.0.9 — 2026-08-10 (test candidate)

- **Black screen with live audio on dArkOS-family firmwares fixed in the
  loader (glfix).** Field diagnosis (credit: charles): those firmwares ship
  crossed SONAMEs — `libGLESv1_CM.so.1`/`libEGL.so.1` resolve to driverless
  Mesa builds while the real Mali blob sits behind the unversioned names. The
  loader now detects the only safe signal (a real context whose
  `glGetString(GL_RENDERER)` comes back empty), picks a validated Mali blob
  (prefers `-gbm`, requires the GLES1 entry points via `dlsym`, refuses
  `dummy`/`stub`/`x11`/`wayland` variants) and re-executes itself once with
  `LD_PRELOAD` pointing at it. Healthy stacks — including Mesa/Panfrost,
  which report a renderer — are never touched. Controls:
  `SWORDIGO_GLFIX=0` disables, `SWORDIGO_GLFIX_BLOB=/path` forces a blob.
- **R3 is now the finger, not a click pulse.** Press R3 = touch down at the
  cursor, keep holding and move the right stick = drag (enchanting the sword
  with a talisman now works), release = touch up. A quick press still taps.
- **Single self-contained launcher (nxbootstrap 0.6.0).** The 0.5.1 bash
  library, its receipt and the fail-closed deployment pins are retired.
  The new launcher is fail-open on PortMaster, holds a single-instance
  `flock` on the loader, forwards INT/TERM/HUP to the game and re-waits for
  its true exit status, resets the console before `pm_finish`, and
  canonicalizes `GAMEDIR` (symlinked ROM roots broke recipe containment).
- Single runtime `swordigo-nextos-v109` (GLIBC_2.27); the three same-byte
  copies of 1.0.8 are gone. Clean install recommended.
- Validated end to end on NextOS Elite (Amlogic/Mali-450 fbdev): extraction
  from the APK, gameplay frames on screen, clean TERM exit. The crossed-
  SONAME repair itself still needs a physical pass on a dArkOS device.

## 1.0.8 — 2026-08-09 (release candidate)

- Applied the generated nxbootstrap 0.5.1 deployment contract. The visible
  launcher now pins `nxbootstrap-0.5.1.sh` by version, SHA-256 and a static
  `nxdeployment.json` receipt; the non-versioned `nxbootstrap.sh` remains a
  regular, byte-identical compatibility copy and is never a fallback for the
  new launcher. Early failures before `debug.log` now create per-attempt
  `swordigo-launcher-error.<pid>.log` diagnostics, and runtime logs identify
  the deployment, selected bootstrap and lifecycle phase.
- Kept `host.portmaster` fail-closed: missing or failed PortMaster integration
  stops before the game, and an active `PM_PIPE` is accepted only as a live,
  non-symlink FIFO that the official close API actually removes.
- Moved the selected public runtime to `swordigo-nextos-v108` so an overlay
  cannot silently retain the 1.0.7 payload. Regular `swordigo-nextos` and
  `swordigo` aliases remain byte-identical for launchers preserved from
  v1.0.5-v1.0.7 and v1.0.4 respectively. No symlink is used.
- Hardened the package gates around the complete deployment: both bootstrap
  names and all three loader names must be byte-identical, no `run.sh` may
  exist, and every packaged Linux ELF is independently audited against the
  `GLIBC_2.30` ceiling with no `RPATH`/`RUNPATH` accepted.
- Moved release construction to the content-pinned NXRelease 0.2.5 schema-2
  manifest. The deterministic ZIP now carries its own inventory, source
  manifest, dependency closure, ELF audit and CycloneDX SBOM, while the
  allowlist excludes owner game data and local/private paths.
- Preserved Swordigo's native Android lifecycle order and every existing
  game-specific present, fullscreen, audio and input policy. This candidate has
  host/build/package validation only; physical extraction and gameplay
  validation of v1.0.8 remains pending.

## 1.0.7 — 2026-08-09

- Made overlay updates from 1.0.4 deterministic. Field evidence showed a mixed
  install whose visible launcher still embedded `executable=swordigo`, while
  1.0.5 and later use `swordigo-nextos`. The ZIP now carries a regular,
  byte-identical AArch64 compatibility copy at the legacy path, so even a CFW
  that preserves the old launcher executes the current runtime. The canonical
  launcher and public executable name remain `swordigo-nextos`.
- Added package gates that require both runtime paths to be byte-identical,
  independently audit every packaged ELF against `GLIBC_2.30`, and verify the
  equality again from the completed ZIP. No game data is included or changed.
- Retained the 1.0.6 bootstrap stderr fix, covering the muOS 1.0.5 report that
  returned without a durable runtime log. Graphics, audio, controls, native
  lifecycle and owner-data extraction are otherwise unchanged.

## 1.0.6 — 2026-08-09

- Fixed the universal bootstrap's file-descriptor probes so their local error
  suppression cannot leave the launcher's standard error redirected to
  `/dev/null`. Swordigo's loader and framework diagnostics now remain in
  `debug.log` after the handoff.
- Runtime, graphics, audio, controls, extraction and data are unchanged from
  1.0.5; this is a logging-only framework correction covered by the canonical
  isolated bootstrap regression suite.

## 1.0.5 — 2026-08-09

- Addressed the dArkOSRE-class “audio but no picture” launch path without a
  firmware-name exception. Some PortMaster platform modules replace the
  default helper and return while their live dialog still owns the display.
  The bootstrap now detects PortMaster's own live pipe and closes that exact
  dialog through `PortMasterDialogExit` before any setup UI or game window.
  It does not scan, signal or kill an unrelated process.
- Hardened the GLES1 present transaction. The default backbuffer is selected
  through SDL, EGL or the process symbol table; framebuffer, colour mask, clear
  colour and scissor state are restored exactly after forcing alpha to one.
  The diagnostic frame probe now reads framebuffer zero instead of whichever
  off-screen FBO the game happened to leave bound.
- KMSDRM now uses the same backend-derived finish-before-swap policy proven by
  the framework (`SWORDIGO_GLFINISH=0/1` remains an explicit override). Logs
  record the actual swap interval, policy, window flags and GL resolver.
- Renamed the project-built public loader to the stable authorship identity
  `swordigo-nextos`. The original Android library keeps its upstream
  `libswordigo.so` name.
- Recorded the complete v1.0.5 package and two-device regression acceptance in
  `references/v1.0.5-multi-device-acceptance.json`; confirmation on the
  reporting dArkOSRE device remains pending.

## 1.0.4 — 2026-08-09

- Migrated the public package to the universal generated launcher contract:
  `Swordigo.sh` loads `swordigo/nxbootstrap.sh` directly and the obsolete
  second-stage `run.sh` no longer exists in source or ZIP.
- Upgraded the owner-data phase from NXExtract 1.2.4 to the canonical 1.2.6
  runtime, kept isolated from the game-private library path.
- Moved Swordigo's proven OpenAL policy and Pulse socket discovery into the
  game adapter. The generic bootstrap still never selects an SDL or audio
  backend.
- Consolidated launcher and loader output in the durable `debug.log`; the
  loader no longer unlinks or races a second log file.
- The development control socket is now disabled unless
  `SWORDIGO_DEBUG_CONTROL=1` is explicitly set.

## 1.0.3 — 2026-08-08

- The window is created with `SDL_WINDOW_FULLSCREEN_DESKTOP` instead of
  exclusive fullscreen. Exclusive fullscreen asks KMSDRM for a modeset to the
  size we requested, so a firmware that reports a desktop mode its panel does
  not actually drive hands back a window that never reaches the screen — black
  picture, engine alive. Every published port on this fleet already defaults to
  desktop fullscreen (Horizon Chase, Prizefighters 2, Hitman GO, Geometry Dash);
  `SWORDIGO_EXCLUSIVE_FULLSCREEN=1` keeps the old behaviour, and window creation
  falls back to exclusive on its own if desktop fullscreen is refused.
- The release now ships the test that decides a black-screen report, so the next
  one can be diagnosed without owning the device: one frame is read back a few
  seconds in and logged as
  `gl: frame probe 640x480 rgb_non_black=76.1% alpha255=99.0% alpha0=0.0%`.
  Colour with alpha 0 means the scanout composited the frame away, colour with
  alpha 255 means the picture is fine and the wrong surface is presented, and an
  empty frame means the engine drew nothing.
- The launcher logs which processes still hold `/dev/dri/*` or `/dev/fb*` when
  the game starts (`[launcher] display held by: ...`). It stops nothing — the
  frontend stays PortMaster's business — it only makes the answer visible.
- Ruled out by evidence, recorded so nobody re-runs it: the extractor is not
  involved in the black screen. Its progress UI starts only after the fast
  marker check, and the failing logs say `fast validation marker accepted`, so
  no UI process ever existed in those boots.

## 1.0.2 — 2026-08-08

- Black screen with the game clearly alive (music playing, input answering) on
  firmwares whose scanout honours per-pixel alpha — the R36S/ArkOS/DarkOS class.
  The window was created with `SDL_GL_ALPHA_SIZE 8`, so a frame the game leaves
  at alpha 0 is composited as transparent and reads as black, while Amlogic's
  OSD ignores alpha and draws the very same build fine.
- Two belts, because the attribute is a minimum and drivers still hand out an
  alpha config: the window now asks for no alpha, and every frame is forced
  opaque immediately before the present, rebinding framebuffer 0 through
  `glBindFramebufferOES` first so the clear cannot land on a bound FBO — the
  trap that cost Horizon Chase v1.2.0.
- Measured on Mali-450 at 1280x720: alpha went from 255 on 99.0% of the frame
  to 255 on 100%, with the RGB bytes identical before and after, so the clear
  fixes opacity without touching a pixel of image. The firmware there grants
  `alpha=8` even when asked for 0, which is exactly why both belts ship.
- The log now carries what a black-screen report needs: video driver, the
  config actually granted (`alpha=`, `depth=`), the GL renderer and version,
  and a one-time line confirming the opaque present ran.

## 1.0.1 — 2026-08-08

- Sound is back. Release 1.0.0 exported `alsoft.conf` only on firmwares with no
  PulseAudio socket, so every box that has a sound server ran with no backend
  order and none of the ALSA fixes the file carries. That is exactly the mute
  case in the tester logs: OpenAL Soft's PipeWire backend fails to start
  (`Failed to create PipeWire event context`), and since the library picks one
  playback backend at init and never reconsiders, the game drops through to raw
  ALSA — the mmap path the fleet knows to stall silently on these handhelds.
- The config is now applied on every firmware and pins
  `drivers = pipewire,pulse,alsa`, the order the approved Bully port proved on
  PipeWire, Amlogic Mali-450 and ALSA-only R36S hardware: a sound server is
  preferred over raw ALSA, and raw ALSA always gets `mmap = false`. It still
  only orders backends OpenAL Soft already has and never forces one.
- `PULSE_SERVER` also picks up the per-user `$XDG_RUNTIME_DIR/pulse/native`
  socket, so the pulse backend finds the server on session-scoped firmwares.
- The log now names the backend that actually won
  (`openal: ok ... backend='...' rate=...`): a silently mute backend used to be
  indistinguishable from working audio in a bug report.
- Music: an `MPG123_NEW_FORMAT` announcement on the first decode is no longer
  treated as a decode failure, and a start request is kept until the track
  really starts instead of being dropped after one empty prime.

## 1.0.0 — 2026-08-08

- First universal ARM64 release: one loader for NextOS, ArkOS, ROCKNIX, muOS
  and Knulli class handhelds, audited at a maximum `GLIBC_2.27` requirement.
- SDL2, OpenAL, mpg123, GLES1 and EGL are bound by SONAME and supplied by the
  firmware, so no driver is ever forced by the launcher.
- Fixed the `stack smashing detected` abort on Mali-G31/glibc devices: the
  game reads its stack canary from the Bionic TLS slot, so the runtime now
  anchors it with a never-written thread-local pad.
- BYO data through canonical NXExtract 1.2.4 (the released engine every other
  port ships): the player drops a legally owned
  Swordigo 1.4.12 APK in `gamedata/` and the
  port prepares `libswordigo.so`, `assets/` and `res/` transactionally on the
  first launch. Both APK builds we hold validate against the recipe.
- ALSA-only firmwares (ArkOS/ROCKNIX without PulseAudio) get an `alsoft.conf`
  with the mmap path disabled, the fix the approved Bully port ships against
  OpenAL Soft's "mmap commit error: Broken pipe" stall in long sessions. It is
  applied only when no PulseAudio socket exists and never forces a driver.
- A stale instance from a crashed session is stopped before the game starts,
  matched by executable and working directory rather than by name, and a
  second launcher refuses loudly instead of running the game twice.
- Canonical PortMaster package: `Swordigo.sh` and `swordigo/` at the ZIP root,
  a launcher that resolves the game folder from every known card root, and no
  silent failure — errors land in a log next to the script and on the console.
