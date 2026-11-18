# scripts

Scripts de compilación, verificación y publicación de Kancerbero. Todos son Bash con
`set -euo pipefail`, calculan la raíz del repositorio a partir de su propia ruta (se pueden invocar
desde cualquier directorio) y dejan los productos en `build/`, que es el `-derivedDataPath` local
(no tocan `~/Library/Developer/Xcode/DerivedData`).

Resumen:

| Script | Para qué |
| --- | --- |
| `build.sh` | Compila Debug (app, probe y daemon) sin firma de distribución. |
| `clean.sh` | Borra `build/` y, opcionalmente, recompila. |
| `install-app.sh` | Copia la app Release a `/Applications`. |
| `verify.sh` | Ejecuta el probe de diagnóstico y lo compara con `netstat`. |
| `make-icon.sh` | Genera el icono de la app a partir de un PNG. |
| `set-version.sh` | Cambia el prefijo `major.minor` de la versión. |
| `prepare-build-version.sh` | Genera build y versiones de app, daemon y filtro en cada compilación. |
| `build-release.sh` | Compila Release firmado con Developer ID y lo valida. |
| `notarize.sh` | Notariza, grapa y verifica la app Release. |
| `package-release.sh` | Crea el ZIP de Sparkle a partir de la app notarizada. |
| `generate-appcast.sh` | Genera y firma el `appcast.xml` de Sparkle. |
| `package-dmg.sh` | Crea el DMG de distribución con fondo y layout de Finder. |
| `publish-release.sh` | Crea el tag `v<build>` y publica ZIP y DMG en GitHub Releases. |
| `publish-appcast.sh` | Publica `appcast.xml` en la rama `gh-pages`. |
| `verify-release.sh` | Comprueba el feed publicado y que los assets responden 200. |
| `release.sh` | Orquesta el release completo; con `--publish`, lo publica. |
| `lib/version.sh` | Funciones compartidas de versiones (se hace `source`). |
| `lib/dmg-background.swift` | Genera el PNG de fondo del DMG con AppKit. |

## Uso diario

### `build.sh`

```bash
./scripts/build.sh                 # Debug
CONFIG=Release ./scripts/build.sh  # Release ad-hoc
```

Ejecuta `prepare-build-version.sh`, compila `Kancerbero`, `KancerberoProbe` y `KancerberoDaemon`
con firma ad-hoc (`CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS=`),
y comprueba que el daemon y el probe informan de las versiones esperadas y que la system
extension lleva la versión de filtro registrada en `Config/ComponentVersions.xcconfig`.

No sirve para distribuir: un build ad-hoc no activa el filtro y el daemon no se puede registrar
con `SMAppService`. Para eso está `build-release.sh`.

### `clean.sh`

```bash
./scripts/clean.sh            # borra build/
./scripts/clean.sh --debug    # borra build/ y compila Debug limpio
./scripts/clean.sh --release  # borra build/ y compila Release con build-release.sh
```

Muestra el tamaño de `build/` antes de borrarlo. Nunca toca el DerivedData de Xcode.

### `install-app.sh`

```bash
./scripts/install-app.sh                       # -> /Applications/Kancerbero.app
./scripts/install-app.sh /ruta/alternativa.app
```

Requiere que `build-release.sh` haya dejado la app Release. Borra el destino y lo reemplaza con
`ditto`.

### `verify.sh`

Ejecuta `KancerberoProbe` (Debug) para listar símbolos, procesos, sensores térmicos, batería,
interfaces y contadores de red (`nstat`), y termina comparando los contadores de `en0` con
`netstat -ibI en0`. Necesita un `build.sh` Debug previo del probe. Las tolerancias están en
[`../docs/verification.md`](../docs/verification.md).

### `make-icon.sh`

```bash
./scripts/make-icon.sh [origen.png]
```

Reduce la imagen con `sips` a un máster de 1024×1024 y genera los 10 PNG de macOS (16–1024 px)
en `Sources/Kancerbero/Assets.xcassets/AppIcon.appiconset`, junto con su `Contents.json`.
Avisa si la fuente no es cuadrada o es más pequeña que 1024 px. El PNG por defecto es una ruta
local del autor del proyecto; pasa siempre una ruta si trabajas en otro equipo.

## Versiones

La app usa `marketing = <prefix>.<build>` con el build como último componente. El prefijo se
fija a mano; el build se genera en cada compilación.

### `set-version.sh`

```bash
./scripts/set-version.sh 0.3
```

Valida `major.minor` y reescribe solo la línea `KANCERBERO_VERSION_PREFIX` de
`Config/Version.xcconfig` (crea el archivo si no existe). El sufijo de build se añade solo.

### `prepare-build-version.sh`

```bash
./scripts/prepare-build-version.sh
```

Normalmente no se invoca a mano: lo ejecuta la pre-action de los schemes `Kancerbero` y
`Kancerbero-AppStore`, y también `build.sh` y `build-release.sh`. Si
`KANCERBERO_VERSION_PREPARED=1` ya está definido, termina sin hacer nada para no regenerar la
versión entre el `clean` y el `build`.

Qué hace:

- Calcula el build como `YYMMDDHHMM` en UTC y garantiza que sea **estrictamente creciente**: el
  suelo es el build anterior en `build/Generated/Version.plist` y el tag `v<build>` más alto.
- Escribe `build/Generated/Version.xcconfig` (`KANCERBERO_MARKETING_VERSION`,
  `KANCERBERO_BUILD_VERSION`) y `build/Generated/Version.plist`.
- Mantiene versiones propias para daemon y filtro (`Config/ComponentVersions.xcconfig`). Cada build
  de componente solo sube cuando cambia el hash de sus fuentes (`Sources/...`,
  `Resources/...` y los xcconfigs correspondientes), no en cada compilación de la app. Si no hay
  estado previo grabado, cuenta como cambio.
- Escribe ese archivo de forma atómica y solo si cambió.

## Release

Orden completo (lo automatiza `release.sh`):

```text
build-release.sh -> notarize.sh -> package-release.sh -> generate-appcast.sh
                 -> package-dmg.sh -> publish-release.sh -> publish-appcast.sh
                 -> verify-release.sh
```

### `build-release.sh`

Compila Release firmado con **Developer ID Application** y es la única vía para obtener un
artefacto distribuible. Antes de compilar exige:

- El árbol de trabajo limpio (`git status --porcelain` vacío): el release sale siempre de un
  commit. Si hay cambios sin commitear, falla antes de borrar o compilar nada.
- `Config/Signing.local.xcconfig` (ignorado por git) con `KANCERBERO_APP_PROFILE` y
  `KANCERBERO_FILTER_PROFILE` no vacíos.
- Una identidad `Developer ID Application` en el llavero.
- Ajustes resueltos correctos en los targets: firma manual, `DEVELOPMENT_TEAM` (por defecto
  `AK37TK8X2Y`, configurable con `DEVELOPMENT_TEAM`), identidad Developer ID, y daemon **sin**
  `PRODUCT_BUNDLE_IDENTIFIER`. Xcode reescribe estos ajustes al tocar Signing & Capabilities, y
  el script falla en vez de degradar la firma a Apple Development.

Después hace `clean` y `build` por separado (el xcconfig generado debe sobrevivir al `clean`) y
valida:

- Que el daemon compilado informa de las versiones de app y daemon esperadas.
- Que el tag `v<build>` no existe y que el build supera el último tag de release.
- Que `Config/ComponentVersions.xcconfig` no cambió durante el build (si cambió, hay que
  commitearlo y repetir).
- Consistencia del daemon: `Label` y `MachServices` del plist embebido coinciden con
  `KancerberoXPCNames.machService`, y `AppModel.daemonServicePlist` nombra ese mismo plist.
- Sparkle: `SUPublicEDKey` de 44 caracteres y `SUFeedURL` HTTPS.
- Firma: `codesign --verify --deep --strict`; los tres binarios (app, extensión y daemon) con
  autoridad Developer ID.
- Daemon: hardened runtime, **cero** entitlements, sin `embedded.provisionprofile` y firmado con
  el identificador `uno.kayros.kancerbero` (si no, launchd lo mata con *Launch Constraint
  Violation*).
- App y extensión: entitlements esperados, sin `get-task-allow`, y con `embedded.provisionprofile`.

Salida: `build/Build/Products/Release/Kancerbero.app`.

### `notarize.sh`

Empaqueta la app Release en un ZIP temporal, lo envía a `notarytool submit --wait`, y si se acepta
grapa el ticket (`stapler staple`), lo valida y ejecuta `spctl`. Usa el perfil de llavero
`NOTARY_PROFILE` (por defecto `kancerbero-notary`), que se crea una vez con
`xcrun notarytool store-credentials`.

### `package-release.sh`

Crea `build/updates/Kancerbero-<version>.zip` con `ditto` **después** de grapar el ticket (el ZIP
que descargan los usuarios debe incluir la notarización). Descomprime el ZIP en un temporal y
vuelve a verificar firma, ticket y Gatekeeper sobre la copia, tal como la verá el usuario. Este ZIP
es el que consume Sparkle.

### `generate-appcast.sh`

Ejecuta el `generate_appcast` de Sparkle (en
`build/SourcePackages/artifacts/sparkle/Sparkle/bin`, resolviendo dependencias con
`xcodebuild -resolvePackageDependencies`) sobre `build/updates`:

- Descarga el feed actual y se niega a publicar un build que no sea mayor que el más reciente
  (protege ante relojes atrasados o tags obsoletos).
- Genera `build/updates/appcast.xml` con URLs de descarga de GitHub Releases (`v<build>`), notas
  embebidas, sin deltas y conservando las 3 versiones más recientes.
- Valida el XML, la versión, el build, la firma EdDSA (`sign_update --verify`) y el nombre del ZIP.

La cuenta EdDSA se elige con `SPARKLE_ACCOUNT` (por defecto `kancerbero-ed25519`).

### `package-dmg.sh`

Genera `build/updates/dmg/Kancerbero-<version>.dmg`. Requiere la app ya notarizada y grapada
(salvo en modo dev), firma Developer ID del equipo y el perfil de notarización. El proceso:

1. Comprueba el fondo `Resources/DMG/background.png` (1320×896 a 144 DPI).
2. Prepara la app, el enlace a `/Applications` y el fondo.
3. Crea una imagen APFS de lectura/escritura y configura el layout con AppleScript: ventana de
   660×420, iconos de 128 pt y fondo. Necesita sesión gráfica y permiso de Automatización para
   controlar Finder; si se deniega, abre Ajustes del Sistema.
4. Convierte a UDZO (zlib nivel 9), firma el DMG con timestamp, lo notariza, lo grapa y lo verifica.
5. Lo vuelve a montar para comprobar contenido, enlace, fondo, layout, firma, ticket y que la
   versión y el build embebidos coinciden. Imprime arquitecturas y SHA-256.

Variables:

| Variable | Efecto |
| --- | --- |
| `NOTARY_PROFILE` | Perfil de `notarytool` (por defecto `kancerbero-notary`). |
| `KANCERBERO_DMG_SIGN_IDENTITY` | Huella SHA-1 de 40 hex para firmar el DMG (hay una por defecto). |
| `KANCERBERO_DMG_DEV=1` | Firma sin notarizar ni grapar, y escribe `-dev.dmg`. No distribuir. |
| `KANCERBERO_DMG_SKIP_LAYOUT=1` | Sin Finder ni `.DS_Store` (pruebas headless; no muestra el fondo). |

Si `Config/Signing.local.xcconfig` define `CODE_SIGN_IDENTITY`, debe coincidir con la identidad del
DMG.

### `publish-release.sh`

Exige árbol de trabajo limpio, el ZIP y el DMG ya generados, y `gh` autenticado o `GITHUB_TOKEN`
con escritura. Crea el tag anotado `v<build>` si no existe (falla si ya apunta a otro commit), lo
sube, crea la release de GitHub con ambos assets y comprueba que las URLs devuelven 200. Es
idempotente: si la release ya existe, reemplaza los assets; sin `gh`, reutiliza release y assets
vía API. Repositorio y remoto se configuran con `GITHUB_REPO` (por defecto `kayrosuno/kancerbero`)
y `GITHUB_REMOTE` (por defecto `github`).

### `publish-appcast.sh`

Publica `build/updates/appcast.xml` en la rama `gh-pages` usando un worktree temporal (crea la
rama huérfana si no existe), añade `.nojekyll`, hace commit `appcast: <version> (<build>)`, lo sube
y elimina el worktree. GitHub Pages sirve así el feed que consulta Sparkle.

### `verify-release.sh`

Espera hasta 12×15 s a que GitHub Pages publique el feed, y luego valida que `appcast.xml` contiene
la versión y el build, firma EdDSA, un enclosure `Kancerbero-<version>.zip`, y que tanto el ZIP
como el DMG (`releases/download/v<build>/...`) responden 200. Se puede apuntar a otro feed con
`SPARKLE_FEED_URL` y a otro repo con `GITHUB_REPO`.

### `release.sh`

```bash
./scripts/release.sh              # construye y empaqueta todo en local
./scripts/release.sh --publish    # además publica y verifica
```

Requiere el árbol de trabajo limpio. Con `--publish`, antes de compilar comprueba que exista `gh`
autenticado o `GITHUB_TOKEN` y que `HEAD` ya esté subido a su upstream (o a
`GITHUB_REMOTE/main`), para no construir y notarizar algo que luego no se pueda publicar.

Ejecuta en orden `build-release.sh`, `notarize.sh`, `package-release.sh`, `generate-appcast.sh` y
`package-dmg.sh`; imprime las rutas del ZIP y del DMG. Con `--publish` continúa con
`publish-release.sh`, `publish-appcast.sh` y `verify-release.sh`. Ya no acepta versión ni build
como argumento: se generan automáticamente.

## `lib/`

### `lib/version.sh`

Funciones compartidas; los scripts hacen `source` de él y no se ejecuta directamente.

- `kancerbero_normalize_build` — convierte builds antiguos de 14 dígitos al formato actual de 10.
- `kancerbero_last_tag_build` — build más alto entre los tags `v<build>`.
- `kancerbero_release_app` / `kancerbero_require_release_app` — ruta de la app Release y
  comprobación de que existe.
- `kancerbero_read_app_version` — lee `CFBundleShortVersionString` y `CFBundleVersion` del
  artefacto y exporta `VERSION` y `BUILD`; el binario construido es la fuente de verdad, no el
  xcconfig generado.
- `kancerbero_require_filter_version` — comprueba la versión de la system extension embebida.
- `kancerbero_component_value` — lee una clave de `Config/ComponentVersions.xcconfig`.

### `lib/dmg-background.swift`

Script de AppKit que dibuja el fondo del DMG (degradado, auras, cinta y flecha hacia
`Applications`) a 1320×896 px y 144 DPI. No lo invoca ningún script; se ejecuta a mano cuando se
quiere regenerar el fondo versionado:

```bash
swift scripts/lib/dmg-background.swift Resources/DMG/background.png
```

## Más detalle

El ciclo de release, la gestión de la clave de Sparkle y el diagnóstico están en
[`../docs/updates.md`](../docs/updates.md); los procedimientos de verificación y las tolerancias,
en [`../docs/verification.md`](../docs/verification.md).
