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

### Updating an existing installation

Extract v1.0.8 over the existing installation. You do **not** need to remove
the APK, `assets/`, `res/`, `libswordigo.so` or saves. The new launcher selects
`swordigo-nextos-v108` and `nxbootstrap-0.5.1.sh`. Regular, byte-identical
copies named `swordigo-nextos`, `swordigo` and `nxbootstrap.sh` safely cover
firmware installers that preserve an older `Swordigo.sh` during the overlay.

Logs: `swordigo/debug.log` and `swordigo/nxextract.log`. If the launcher
fails before `debug.log` can open, it writes a fresh
`swordigo-launcher-error.<pid>.log` next to the `.sh`, next to the resolved
launcher, and/or in the temporary directory when those locations are writable.
The static `swordigo/nxdeployment.json` confirms which generated deployment
was installed; it is not proof that the launcher actually ran.

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

### Atualizar uma instalação existente

Extraia a v1.0.8 por cima da instalação existente. Não apague o APK,
`assets/`, `res/`, `libswordigo.so` nem os saves. O launcher novo escolhe
`swordigo-nextos-v108` e `nxbootstrap-0.5.1.sh`; as cópias regulares e
byte-idênticas `swordigo-nextos`, `swordigo` e `nxbootstrap.sh` atendem
firmwares que preservem um `Swordigo.sh` anterior durante o overlay.

Logs: `swordigo/debug.log`, `swordigo/nxextract.log` e, para falha anterior ao
runtime, `swordigo-launcher-error.<pid>.log`. O `nxdeployment.json` prova que o
deployment gerado foi instalado, mas não prova sozinho que o launcher rodou.
