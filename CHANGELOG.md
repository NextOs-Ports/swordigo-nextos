# Changelog

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
