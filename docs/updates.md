# Actualizaciones (Sparkle 2)

Kancerbero se actualiza con **Sparkle 2.10.1**. El appcast vive en GitHub Pages y los ZIP
notarizados en GitHub Releases:

- Feed: <https://kayrosuno.github.io/kancerbero/appcast.xml>
- Binarios: `https://github.com/kayrosuno/kancerbero/releases/download/v<build>/Kancerbero-<version>.zip`
- Build: `YYMMDDHHMM` (10 dígitos, UTC); la versión es `<prefijo>.<build>`
- Firma: EdDSA sobre cada ZIP y sobre el propio appcast (`SURequireSignedFeed`).

Otty usa un updater propio con feed JSON y un `install-helper.sh`; su `sha256` está vacío. No se
copia ese diseño: Sparkle firma criptográficamente cada archivo, verifica la firma antes de
extraer, reemplaza el bundle con rollback y relanza la app.

## Checklist de GitHub (una sola vez)

1. **Repo público.** Pages y los assets deben ser accesibles sin autenticación. No hay CNAME: el
   site es `https://kayrosuno.github.io/kancerbero/`.
2. **Autenticación de publicación.** Recomendado `gh auth login` y comprobar con `gh auth status`.
   Alternativa sin `gh`: PAT fine-grained con **Contents: Read and write** sobre
   `kayrosuno/kancerbero`, guardado en el Keychain:
   ```bash
   security add-generic-password -U -a kancerbero-github -s kancerbero-github -w
   export GITHUB_TOKEN="$(security find-generic-password -a kancerbero-github -s kancerbero-github -w)"
   ```
   El tag y `gh-pages` se empujan por SSH; la credencial (gh o PAT) solo se usa para la release.
3. **Primer release en orden.** No usar `release.sh --publish` la primera vez: Pages aún no está
   activo y `verify-release.sh` fallaría. Ejecutar:
   ```bash
   ./scripts/release.sh              # build + notarización + ZIP + appcast + DMG
   ./scripts/publish-release.sh     # tag v<build> + release + assets (ZIP y DMG)
   ./scripts/publish-appcast.sh     # crea/actualiza gh-pages
   # activar Pages (paso 4)
   ./scripts/verify-release.sh
   ```
4. **Activar Pages.** Repo → **Settings → Pages → Deploy from a branch → `gh-pages` / (root) →
   Save**. La rama debe existir antes de poder seleccionarla. Si `has_pages` ya era true pero el
   feed da 404, comprobar que la fuente no sea `main` ni GitHub Actions.
5. **Verificar.** `./scripts/verify-release.sh` espera 12×15 s; el primer despliegue de Pages
   puede tardar más, así que reintentar no es un fallo. Comprobación manual:
   ```bash
   curl -fsSL -H 'Cache-Control: no-cache' \
     https://kayrosuno.github.io/kancerbero/appcast.xml -o /tmp/appcast.xml
   xmllint --noout /tmp/appcast.xml
   gh release view v<build> --repo kayrosuno/kancerbero
   ```
6. **Bootstrap.** La primera build con Sparkle se instala a mano (`gh release download` o `curl`);
   después se publica otra build y se prueba **Kancerbero → Check for Updates…**.

Antes del primer release: árbol limpio, perfil `kancerbero-notary`, copia de la clave EdDSA y
`build/updates/` sin artefactos obsoletos (`generate_appcast` reutiliza el appcast y escanea todos
los ZIP del directorio).

## Puesta en marcha (una sola vez)

### Herramientas de Sparkle

El paquete SPM se resuelve con:

```bash
xcodebuild -project Kancerbero.xcodeproj -scheme Kancerbero \
  -resolvePackageDependencies -derivedDataPath build
```

Las herramientas quedan en
`build/SourcePackages/artifacts/sparkle/Sparkle/bin/` (`generate_keys`, `generate_appcast`,
`sign_update`).

El target Kancerbero tiene una fase **Re-sign Sparkle helpers** después de embeber los productos:
re-firma `Autoupdate`, `Updater.app` y los XPC `Downloader`/`Installer` con la identidad Developer
ID y `--timestamp`, y vuelve a firmar el framework. Sin ella, notarytool rechaza esos binarios
anidados (“not signed with a valid Developer ID certificate” / “does not include a secure
timestamp”). Por eso `ENABLE_USER_SCRIPT_SANDBOXING = NO` en `Config/Kancerbero.xcconfig`.

### Clave EdDSA

La clave privada ya está en el Keychain de esta máquina con la cuenta `kancerbero-ed25519`. La
pública está en `Resources/App/Info.plist` (`SUPublicEDKey`):

```
xfQbkGYIvoax6VF89Rwz+sQ5tPmW8labaux5hoHJvlc=
```

**Copia de seguridad obligatoria**: si se pierde la privada, las instalaciones existentes no
podrán validar actualizaciones futuras y habrá que publicar una versión con una clave nueva e
instalarla a mano.

```bash
SPARKLE_BIN=build/SourcePackages/artifacts/sparkle/Sparkle/bin
"$SPARKLE_BIN/generate_keys" --account kancerbero-ed25519 \
  -x "$HOME/Desktop/kancerbero-ed25519.key"
# mover el fichero a un almacén cifrado y borrarlo del escritorio
```

Nunca commitear la clave privada.

### GitHub Pages

La primera publicación crea la rama `gh-pages`. Después, una sola vez:

GitHub → repo → **Settings → Pages → Deploy from a branch → `gh-pages` / (root)**.

Comprobar:

```bash
curl -fsSL https://kayrosuno.github.io/kancerbero/appcast.xml | head
```

### GitHub CLI o token

`publish-release.sh` usa `gh` si está instalado y autenticado:

```bash
gh auth login        # una vez
gh auth status
```

Si no hay `gh`, cae a la API de Releases y exige un PAT con `Contents: Read and write`:

```bash
export GITHUB_TOKEN="$(security find-generic-password -a kancerbero-github -s kancerbero-github -w)"
```

## Publicar una versión

```bash
./scripts/release.sh
```

El script:

1. Comprueba que el árbol está limpio (incluido `Config/ComponentVersions.xcconfig`) y, con
   `--publish`, que `gh`/el token y el upstream están listos antes de compilar.
2. `build-release.sh`: `clean` + `build` Release; genera la versión/build de la app y valida que
   el filtro y el daemon coinciden con sus identidades anotadas.
3. `notarize.sh`: notarytool + stapler + spctl.
4. `package-release.sh`: crea `Kancerbero-<version>.zip` **después** del stapling. La versión ya
   contiene el build, así que el nombre es único.
5. `generate-appcast.sh`: descarga el feed anterior, añade la versión nueva y firma el appcast.
6. `package-dmg.sh`: crea y notariza `Kancerbero-<version>.dmg` desde la misma app stapled. El DMG
   queda en `build/updates/dmg/`, fuera del directorio que escanea `generate_appcast`.

Para publicar:

```bash
gh auth login          # una vez
./scripts/release.sh --publish
```

Con `gh` no hace falta `GITHUB_TOKEN`; si no está instalado, exportarlo como antes.
`publish-release.sh` es idempotente: reutiliza la release existente y reemplaza el ZIP y el DMG en
un reintento. `generate-appcast.sh` rechaza publicar un build que no sea mayor que el item más
nuevo del feed. `release.sh --publish` comprueba antes de compilar que la credencial y el upstream
estén listos; si `github/main` está obsoleto, `git fetch github`.

El tag es `v<build de la app>` y la release se llama `Kancerbero <version> (<build>)`. No hay
commit de bump: la versión/build de la app se generan en el build y el tag apunta al HEAD ya
commiteado.

### Orden manual equivalente

```bash
./scripts/build-release.sh
./scripts/notarize.sh
./scripts/package-release.sh
./scripts/generate-appcast.sh
./scripts/package-dmg.sh
./scripts/publish-release.sh
./scripts/publish-appcast.sh
./scripts/verify-release.sh
```

Nunca publicar el appcast antes que los assets: Sparkle daría 404 al descargar.

### Bootstrap

La primera versión con Sparkle se instala a mano (`gh release download v<build> --repo
kayrosuno/kancerbero` o `curl`); a partir de ahí las actualizaciones son automáticas.

## DMG de distribución

El DMG no forma parte del appcast de Sparkle, pero sí del release: `release.sh` lo genera después
del ZIP y `publish-release.sh` sube ambos a los assets de la misma release de GitHub.

```bash
./scripts/release.sh              # ZIP + appcast + DMG local
./scripts/release.sh --publish   # publica ZIP y DMG en la release
```

Para generarlo de forma aislada a partir de la app Release ya notarizada y stapled:

```bash
./scripts/build-release.sh
./scripts/notarize.sh
./scripts/package-dmg.sh
```

Salida: `build/updates/dmg/Kancerbero-<version>.dmg` (APFS dentro de UDZO). El script firma el DMG
con Developer ID, lo notariza con `kancerbero-notary`, le grapa el ticket y verifica la imagen y la
app embebida. Necesita una sesión gráfica y permiso de Automatización para controlar Finder; el
fondo y las posiciones de los iconos se configuran con AppleScript.

- El fondo está versionado en `Resources/DMG/background.png` (1320×896, 144 DPI) y se regenera con
  `scripts/lib/dmg-background.swift`.
- `publish-release.sh` sube el DMG como `application/x-apple-diskimage` junto al ZIP de Sparkle y
  verifica que ambos assets devuelven 200. El appcast sigue apuntando al ZIP.
- No mover el DMG al nivel superior de `build/updates`: `generate_appcast` escanea ese directorio y
  trata `.dmg` como archivo de actualización. El subdirectorio `dmg/` se ignora.
- Modos de prueba: `KANCERBERO_DMG_DEV=1` (firma sin notarizar, salida `-dev.dmg`) y
  `KANCERBERO_DMG_SKIP_LAYOUT=1` (sin Finder; el fondo no se muestra).
- Verificación:

```bash
DMG=build/updates/dmg/Kancerbero-<version>.dmg
codesign --verify --verbose=2 "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -vvv "$DMG"
hdiutil verify "$DMG"
```

## Versionado

### App (cada compilación)

`scripts/prepare-build-version.sh` (invocado por la pre-action del scheme y por los scripts)
genera `build/Generated/Version.xcconfig`:

```xcconfig
KANCERBERO_MARKETING_VERSION = 0.2.2611160955   # <prefijo>.<build>
KANCERBERO_BUILD_VERSION = 2611160955           # YYMMDDHHMM UTC, creciente
```

`Config/Version.xcconfig` guarda el prefijo (`0.2`, cambiable con `scripts/set-version.sh`) y los
fallbacks, e incluye el fichero generado. `KBVersion.current`/`KBVersion.build` salen de
`kb_version()`/`kb_build_version()`; el `Info.plist` de la app usa los mismos build settings. La
build de la app es la clave de Sparkle y del appcast; **el último componente de la versión es
exactamente el build**. El generador normaliza builds legados de 14 dígitos
(`YYYYMMDDHHMMSS`) al esquema de 10 dígitos, tanto el estado generado como los tags `v<build>`,
para que el floor monotónico no retroceda.

### Daemon y filtro (solo al cambiar)

`Config/ComponentVersions.xcconfig` (versionado) anota la identidad de cada componente:

```xcconfig
KANCERBERO_DAEMON_VERSION_PREFIX = 0.2
KANCERBERO_DAEMON_BUILD_VERSION = 2611162249
KANCERBERO_DAEMON_SOURCE_HASH = ...
KANCERBERO_FILTER_VERSION_PREFIX = 0.2
KANCERBERO_FILTER_BUILD_VERSION = 2611160954
KANCERBERO_FILTER_SOURCE_HASH = ...
KANCERBERO_DAEMON_MARKETING_VERSION = 0.2.2611162249
KANCERBERO_FILTER_MARKETING_VERSION = 0.2.2611160954
```

- El generador hashea **solo fuentes/config** de cada componente (sin marketing/build, para no
  crear un bucle). Si el hash cambia, fija el build al timestamp y reescribe la versión literal
  `prefijo.build`; si no, conserva build y versión.
- El marketing se escribe literal para que los scripts de release lo lean con `awk`.
- El fichero está versionado: un cambio de componente lo deja modificado; hay que commitearlo
  (el release lo exige).
- El daemon recibe sus macros `KANCERBERO_DAEMON_*` y reporta `daemonVersion`/`daemonBuild` en el
  handshake; el filtro usa `KANCERBERO_FILTER_MARKETING_VERSION`/`BUILD` en su `Info.plist`.
- `KBVersion.daemonVersion`/`daemonBuild` y `FilterVersion.expectedBuild` (build del filtro
  embebido en la app) son los valores esperados.
- Cambiar el prefijo de marketing a mano no incrementa el build por sí solo; cambiar fuentes o
  configuración del componente sí.
- `FilterVersion.schema` solo cambia si cambia el protocolo del filtro.

### Comparaciones

- Daemon: `hello.daemonBuild == KBVersion.daemonBuild`.
- Filtro: el ACK del filtro (`FilterVersion.build`) contra `FilterVersion.expectedBuild`.
- Las versiones de marketing no participan en estas comparaciones; solo los builds. La versión
  de la app cambia en cada compilación.

### System Status

- **Application**, **Background Services** y **Network Filter** muestran la versión en ejecución
  como una insignia compacta en la banda superior de la tarjeta (con fondo tintado por estado):
  una sola línea, sin build.
- El **panel lateral** muestra **Versions in App Bundle** con las versiones del ejecutable/app
  bundle: Kancerbero, daemon y filtro, sin build.
- Las acciones de servicio (Enable background service, Open Login Items, Repair, Retry y Refresh)
  están en **Troubleshooting**, dentro del panel lateral.
- El build no se repite en la UI porque es el último componente de la versión
  (`prefijo.<build>`). Tras el bump de migración, las versiones en ejecución y las embebidas
  coinciden.

## Qué ocurre al actualizar

Sparkle cierra la app, reemplaza `/Applications/Kancerbero.app` (con el daemon y la extensión
embebidos), y la relanza.

- **Daemon**: al conectar, la app compara `hello.daemonBuild` con `KBVersion.daemonBuild`. Si no
  coincide (o el daemon viejo no reporta build), envía el `daemonAction .stop` existente
  (launchctl mata el job); `KeepAlive.SuccessfulExit=false` hace que launchd lo relance desde el
  bundle nuevo. Si el stop falla, cae a `repairDaemonService()` y muestra el estado en **System
  status**. Una build de la app que no cambia el daemon no lo reinicia.
- **Identidad del servicio**: desde esta versión el daemon usa
  `uno.kayros.kancerbero.daemon.service` (antes `.v2`). En la primera ejecución tras actualizar, la
  app desregistra una vez el servicio antiguo con el plist legado incrustado; como la identidad
  cambia, macOS pide aprobar de nuevo el background item en Login Items. El plist legado y su
  código de limpieza se retiran tras un ciclo de release.
- **System extension**: el `CFBundleVersion` del filtro solo cambia cuando cambia el componente.
  Al arrancar, `FilterModel.start()` llama `ensureInstalled()` si el filtro está habilitado;
  sysextd recibe una activation request `.replace` y staged la versión nueva. Si macOS responde
  `willCompleteAfterReboot`, Ajustes → Updates muestra “The network filter update completes after a
  restart”. Una build de la app que no cambia el filtro no lo reemplaza.
- **FDA/TCC**: el reemplazo es in-place, con el mismo bundle id, ruta y team Developer ID
  (`AK37TK8X2Y`). La concesión de Full Disk Access se conserva; verificar tras la actualización.

## Diagnóstico

```bash
# Feed y asset
curl -fsSL https://kayrosuno.github.io/kancerbero/appcast.xml -o /tmp/appcast.xml
xmllint --noout /tmp/appcast.xml
grep -E "sparkle:(version|shortVersionString)|enclosure" /tmp/appcast.xml

# Firma del feed
build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update \
  --account kancerbero-ed25519 --verify /tmp/appcast.xml

# Release y asset
gh release view v<build> --repo kayrosuno/kancerbero
gh release download v<build> --repo kayrosuno/kancerbero

# Versión instalada y daemon
defaults read /Applications/Kancerbero.app/Contents/Info CFBundleShortVersionString
defaults read /Applications/Kancerbero.app/Contents/Info CFBundleVersion
launchctl print system/uno.kayros.kancerbero.daemon.service | grep -E 'pid|state'

# Filtro staged
systemextensionsctl list | grep uno.kayros.kancerbero.filter

# Firma/notarización
codesign --verify --deep --strict --verbose=2 /Applications/Kancerbero.app
xcrun stapler validate /Applications/Kancerbero.app
spctl -a -vvv -t exec /Applications/Kancerbero.app
```

- **Feed 404**: Pages no está activado o el despliegue aún no terminó (puede tardar minutos).
- **Feed con un build no creciente**: `generate-appcast.sh` aborta antes de publicar; comprobar el
  reloj, los tags locales o el feed descargado.
- **`gh` sin autenticar**: `gh auth status`; ejecutar `gh auth login` o exportar `GITHUB_TOKEN`.
- **“Unable to check for updates”**: comprobar red, `SUFeedURL`, `SUPublicEDKey` y la firma del
  feed. Un appcast sin firma se rechaza con `SURequireSignedFeed`.
- **El daemon sigue en la versión vieja**: System status → Repair / re-register.
- **El filtro sigue viejo**: `systemextensionsctl list`; si macOS pide reinicio, reiniciar. Como
  último recurso, `sudo systemextensionsctl uninstall AK37TK8X2Y uno.kayros.kancerbero.filter` y
  reactivar desde Ajustes.
- **Clave perdida**: publicar una versión con una clave nueva en `SUPublicEDKey` e instalarla
  manualmente; no hay rotación silenciosa.

## Seguridad

- Clave privada EdDSA en el Keychain, nunca en el repo.
- `SUVerifyUpdateBeforeExtraction` y `SURequireSignedFeed` activos: firma del ZIP y del feed.
- HTTPS obligatorio (Pages y Releases). Sin excepciones ATS en Release.
- `CFBundleVersion` de la app estrictamente creciente (`YYMMDDHHMM`, 10 dígitos): impide
  downgrades. Los builds de daemon y filtro son independientes y estables mientras su hash no
  cambie; se anotan en `Config/ComponentVersions.xcconfig`.
- La release se publica desde una máquina de confianza con `gh` autenticado o un PAT que no se
  commitea. `build-release.sh` verifica que el `Label` y `MachServices` del plist coinciden con la
  constante XPC, y `generate-appcast.sh` rechaza un feed con un build mayor o igual.
- Un feed comprometido no sirve sin la clave privada.
