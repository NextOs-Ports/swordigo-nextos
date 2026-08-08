# Swordigo — universal NextOS/PortMaster so-loader (aarch64, GLES1.1)

**🌐 Language / Idioma:** [🇬🇧 English](#-english) · [🇧🇷 Português](#-português)

APK: `com.touchfoo.swordigo` **1.4.12** · Engine: **Caver** (TouchFoo) · GLES1.1 + OpenAL Soft + mpg123 (BGM)

Status: **PLAYABLE, UNIVERSAL** — one `GLIBC_2.27` loader proven on NextOS (Mali-450)
and on ArkOS/R36S-class hardware (Mali-G31, 640x480): title, New Game, free roam,
audio, music, pad and right-stick cursor. Data is BYO through NXExtract 1.2.4.

---

## 🇬🇧 English

### Architecture
Loads the original arm64 `libswordigo.so` with so-loader. Shims: AAsset→`assets/`, fake JNI (MusicPlayer + lifecycle), OpenAL on host OpenAL Soft / Pulse, GLES1.1 via SDL2. C++ exceptions need a custom `dl_iterate_phdr` so the in-binary unwinder sees `PT_GNU_EH_FRAME` of the mmap’d module.

### Controls (SDL Xbox layout)
| Input | Action |
|---|---|
| D-pad / Left stick | Move |
| A | Jump |
| X | Attack |
| B | Magic |
| Y | Item |
| LB | Magic equip |
| Start | Pause / menu |
| RB | Back |
| Right stick | On-screen cursor |
| R3 | Cursor click (touch) |
| SELECT+START | Quit |

### Data (full-data package / BYO)
```
ports/swordigo/
  swordigo            # NextOS loader
  libswordigo.so      # from APK lib/arm64-v8a/
  assets/resources/…
  res/*.mp3
```

### Build
```bash
./tools/build-port.sh ports/swordigo
```
Toolchain: current NextOS AArch64 sysroot (glibc of that sysroot).

### Credits / licenses
See `NOTICE.md`. Architecture reference: NaGaa95 `swordigo_nx` (same 1.4.12). Game © TouchFoo — obtain legally.

---

## 🇧🇷 Português

### Arquitetura
Carrega o `libswordigo.so` arm64 original via so-loader. Shims: AAsset→`assets/`, JNI falso (MusicPlayer + lifecycle), OpenAL no host, GLES1.1 via SDL2. Exceções C++ exigem `dl_iterate_phdr` custom para o unwinder embutido achar o `.eh_frame` do módulo mmapado.

### Controles
Mesma tabela acima (layout Xbox). Stick direito = cursor; R3 = clique. SELECT+START sai.

### Dados
Pacote Elite traz loader + `.so` + `assets/` + `res/`. No repo público só há código (BYO-data).

### Build
`./tools/build-port.sh ports/swordigo` contra o sysroot NextOS atual.

### Créditos
`NOTICE.md`. Jogo © TouchFoo — obtenha legalmente.
