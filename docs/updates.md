# Actualizaciones (Sparkle 2)

Kancerbero se actualiza con **Sparkle 2.10.1**. El appcast vive en GitHub Pages y los ZIP
notarizados en GitHub Releases:

- Feed: <https://kayrosuno.github.io/kancerbero/appcast.xml>
- Binarios: `https://github.com/kayrosuno/kancerbero/releases/download/v<version>/Kancerbero-<version>.zip`
- Firma: EdDSA sobre cada ZIP y sobre el propio appcast (`SURequireSignedFeed`).

Otty usa un updater propio con feed JSON y un `install-helper.sh`; su `sha256` está vacío. No se
copia ese diseño: Sparkle firma criptográficamente cada archivo, verifica la firma antes de
extraer, reemplaza el bundle con rollback y relanza la app.

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

### Token de GitHub

`publish-release.sh` usa la API de Releases (no hay `gh` instalado). Exportar un PAT con
`Contents: Read and write`:

```bash
export GITHUB_TOKEN="$(security find-generic-password -s kancerbero-github -w)"
```

## Publicar una versión

```bash
./scripts/release.sh
```

El script:

1. Comprueba que el árbol está limpio (incluido `Config/ComponentVersions.xcconfig`).
2. `build-release.sh`: `clean` + `build` Release; genera la versión/build de la app y valida que
   el filtro y el daemon coinciden con sus identidades anotadas.
3. `notarize.sh`: notarytool + stapler + spctl.
4. `package-release.sh`: crea `Kancerbero-<version>-<build>.zip` **después** del stapling.
5. `generate-appcast.sh`: descarga el feed anterior, añade la versión nueva y firma el appcast.

Para publicar:

```bash
export GITHUB_TOKEN=...
./scripts/release.sh --publish
```

El tag es `v<build de la app>` y la release se llama `Kancerbero <version> (<build>)`. No hay
commit de bump: la versión/build de la app se generan en el build y el tag apunta al HEAD ya
commiteado.

### Orden manual equivalente

```bash
./scripts/build-release.sh
./scripts/notarize.sh
./scripts/package-release.sh
./scripts/generate-appcast.sh
./scripts/publish-release.sh
./scripts/publish-appcast.sh
./scripts/verify-release.sh
```

Nunca publicar el appcast antes que el asset: Sparkle daría 404 al descargar.

### Bootstrap

La primera versión con Sparkle se instala a mano; a partir de ahí las actualizaciones son
automáticas.

## Versionado

### App (cada compilación)

`scripts/prepare-build-version.sh` (invocado por la pre-action del scheme y por los scripts)
genera `build/Generated/Version.xcconfig`:

```xcconfig
KANCERBERO_MARKETING_VERSION = 0.2.20261116095540   # <prefijo>.<build>
KANCERBERO_BUILD_VERSION = 20261116095540           # YYYYMMDDHHMMSS UTC, creciente
```

`Config/Version.xcconfig` guarda el prefijo (`0.2`, cambiable con `scripts/set-version.sh`) y los
fallbacks, e incluye el fichero generado. `KBVersion.current`/`KBVersion.build` salen de
`kb_version()`/`kb_build_version()`; el `Info.plist` de la app usa los mismos build settings. La
build de la app es la clave de Sparkle y del appcast; **el último componente de la versión es
exactamente el build**.

### Daemon y filtro (solo al cambiar)

`Config/ComponentVersions.xcconfig` (versionado) anota la identidad de cada componente:

```xcconfig
KANCERBERO_DAEMON_VERSION_PREFIX = 0.2
KANCERBERO_DAEMON_BUILD_VERSION = 20261116095438
KANCERBERO_DAEMON_SOURCE_HASH = ...
KANCERBERO_FILTER_VERSION_PREFIX = 0.2
KANCERBERO_FILTER_BUILD_VERSION = 20261116095438
KANCERBERO_FILTER_SOURCE_HASH = ...
KANCERBERO_DAEMON_MARKETING_VERSION = 0.2.20261116095438
KANCERBERO_FILTER_MARKETING_VERSION = 0.2.20261116095438
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
build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update --verify /tmp/appcast.xml

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
- `CFBundleVersion` de la app estrictamente creciente (timestamp): impide downgrades. Los builds
  de daemon y filtro son independientes y estables mientras su hash no cambie; se anotan en
  `Config/ComponentVersions.xcconfig`.
- La release se publica desde una máquina de confianza; el token de GitHub no se commitea.
- Un feed comprometido no sirve sin la clave privada.
