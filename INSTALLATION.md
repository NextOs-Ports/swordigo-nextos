# Swordigo — installation / instalação

## English

1. Extract the release ZIP **into the `ports` folder** of the ROM card — the
   canonical PortMaster layout. The launcher and the game folder must end up
   side by side:

   ```text
   roms/ports/Swordigo.sh
   roms/ports/swordigo/
   ```

   Firmware notes:

   - **muOS** (RG40XXH and friends): the card path is `mmc/roms/ports` (or
     `sdcard/roms/ports`). A `.sh` in `mmc/ports` never appears in the list.
   - **ArkOS / ROCKNIX / Knulli / JELOS**: `roms/ports/`.
   - **NextOS / EmuELEC**: EmulationStation lists launchers from
     `roms/ports_scripts/`, so copy `Swordigo.sh` there as well and leave the
     game folder at `roms/ports/swordigo/`.

2. Copy a legally obtained **Swordigo 1.4.12 APK** (`com.touchfoo.swordigo`,
   containing `lib/arm64-v8a/libswordigo.so`) into:

   ```text
   roms/ports/swordigo/gamedata/
   ```

3. Launch **Swordigo** from the frontend. NXExtract prepares and validates the
   owner data once; later launches use a fast marker check.

4. A successful install creates `libswordigo.so`, `assets/` and `res/`.

### Updating from 1.0.4

Extract v1.0.7 over the existing installation. You do **not** need to remove
the APK, `assets/`, `res/`, `libswordigo.so` or saves. A compatibility copy in
this release handles firmware installers that keep the old `Swordigo.sh`
instead of replacing it; the current launcher still uses `swordigo-nextos`.

Logs: `swordigo/debug.log` and `swordigo/nxextract.log`. If the launcher
cannot find the game folder it writes `swordigo-launcher-error.log` next to the
`.sh` and prints the reason on screen instead of returning silently.

## Português

1. Extraia o ZIP **dentro da pasta `ports`** do cartão. O launcher e a pasta do
   jogo ficam lado a lado:

   ```text
   roms/ports/Swordigo.sh
   roms/ports/swordigo/
   ```

   - **muOS**: `mmc/roms/ports` (ou `sdcard/roms/ports`).
   - **ArkOS / ROCKNIX / Knulli / JELOS**: `roms/ports/`.
   - **NextOS / EmuELEC**: copie o `.sh` também para `roms/ports_scripts/`.

2. Coloque o APK legal do **Swordigo 1.4.12** em
   `roms/ports/swordigo/gamedata/`.

3. Abra **Swordigo** pelo frontend e deixe o NXExtract terminar uma vez.

4. O sucesso cria `libswordigo.so`, `assets/` e `res/`.

### Atualização da 1.0.4

Extraia a v1.0.7 por cima da instalação existente. Não apague o APK,
`assets/`, `res/`, `libswordigo.so` nem os saves. Esta release contém uma cópia
de compatibilidade para firmwares que preservam o `Swordigo.sh` antigo; o
launcher atual continua usando `swordigo-nextos`.

Logs: `swordigo/debug.log` e `swordigo/nxextract.log`.
