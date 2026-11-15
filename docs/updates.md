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
./scripts/release.sh 0.1.2 2026111701
```

El script:

1. Comprueba que el árbol está limpio.
2. Escribe `Config/Version.xcconfig` con `scripts/set-version.sh` y hace commit + push del bump.
3. `build-release.sh`: build Release limpio, valida versiones/firma/entitlements.
4. `notarize.sh`: notarytool + stapler + spctl.
5. `package-release.sh`: crea el ZIP **después** del stapling y lo verifica extrayéndolo.
6. `generate-appcast.sh`: descarga el feed anterior, añade la versión nueva y firma el appcast.

Para publicar:

```bash
export GITHUB_TOKEN=...
./scripts/release.sh 0.1.2 2026111701 --publish
```

Se puede ejecutar directamente (hace todo) o después de un `release.sh` sin `--publish`: si el
bump ya está commiteado, lo reutiliza. Eso crea el tag `v0.1.2`, la release, sube el ZIP,
publica el appcast en `gh-pages` y verifica feed + asset.

### Orden manual equivalente

```bash
./scripts/set-version.sh 0.1.2 2026111701
git commit -am "Release 0.1.2" && git push github main

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

La versión 0.1.0 no incluye Sparkle, así que no puede autoactualizarse. La primera build con
Sparkle (0.1.1) se instala a mano; a partir de ahí las actualizaciones son automáticas. Para
probar 0.1.1 → 0.1.2, instalar 0.1.1 primero.

## Versionado

`Config/Version.xcconfig` es la fuente única:

```xcconfig
KANCERBERO_MARKETING_VERSION = 0.1.1
KANCERBERO_BUILD_VERSION = 2026111601
```

- `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` los heredan todos los targets.
- Los `Info.plist` de app y filtro usan `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)`.
- `KBVersion.current`/`KBVersion.build` salen de `kb_version()`/`kb_build_version()`, inyectadas
  por `GCC_PREPROCESSOR_DEFINITIONS`. Son constantes compiladas: un daemon viejo sigue
  reportando su versión vieja aunque el bundle nuevo esté en disco.
- `CURRENT_PROJECT_VERSION` debe ser estrictamente creciente. Sparkle lo usa para comparar
  versiones y sysextd para reemplazar la extensión staged.
- `FilterVersion.current` es la versión de marketing del bundle del filtro; `FilterVersion.build`
  es el número de build que el filtro envía en sus ACK para detectar una extensión obsoleta. No
  cambiar `FilterVersion.schema` salvo que cambie el protocolo.

## Qué ocurre al actualizar

Sparkle cierra la app, reemplaza `/Applications/Kancerbero.app` (con el daemon y la extensión
embebidos), y la relanza.

- **Daemon**: al conectar, la app compara `hello.daemonVersion`/`hello.daemonBuild` con
  `KBVersion.current`/`KBVersion.build`. Si no coinciden, envía el `daemonAction .stop` existente
  (launchctl mata el job); `KeepAlive.SuccessfulExit=false` hace que launchd lo relance desde el
  bundle nuevo. Si el stop falla, cae a `repairDaemonService()` (unregister/register) y muestra el
  estado en **System status**. No se añade ningún mensaje XPC nuevo.
- **System extension**: el `CFBundleVersion` del filtro sube en cada release. Al arrancar,
  `FilterModel.start()` llama `ensureInstalled()` si el filtro está habilitado; sysextd recibe una
  activation request `.replace` y staged la versión nueva. Si macOS responde
  `willCompleteAfterReboot`, Ajustes → Updates muestra “The network filter update completes after a
  restart”.
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
launchctl print system/uno.kayros.kancerbero.daemon.v2 | grep -E 'pid|state'

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
- **El daemon sigue en la versión vieja**: System status → Repair / re-register. Si el daemon es
  legacy, retirarlo antes.
- **El filtro sigue viejo**: `systemextensionsctl list`; si macOS pide reinicio, reiniciar. Como
  último recurso, `sudo systemextensionsctl uninstall AK37TK8X2Y uno.kayros.kancerbero.filter` y
  reactivar desde Ajustes.
- **Clave perdida**: publicar una versión con una clave nueva en `SUPublicEDKey` e instalarla
  manualmente; no hay rotación silenciosa.

## Seguridad

- Clave privada EdDSA en el Keychain, nunca en el repo.
- `SUVerifyUpdateBeforeExtraction` y `SURequireSignedFeed` activos: firma del ZIP y del feed.
- HTTPS obligatorio (Pages y Releases). Sin excepciones ATS en Release.
- `CFBundleVersion` estrictamente creciente: impide downgrades.
- La release se publica desde una máquina de confianza; el token de GitHub no se commitea.
- Un feed comprometido no sirve sin la clave privada.
