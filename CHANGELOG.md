# Changelog

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
