# kancerbero

Monitor de red para macOS inspirado en Activity Monitor. Muestra tráfico por proceso,
conexiones por proceso, contadores por interfaz y un inspector con sockets y ficheros abiertos.

El diseño se basa en ingeniería inversa de `Activity Monitor.app` con REA (ver
`docs/private-apis.md`), no en suposiciones: Activity Monitor obtiene el tráfico por proceso de
`NetworkStatistics.framework`, los totales de interfaz de `sysctl(NET_RT_IFLIST2)` y los ficheros
abiertos de `lsof`. kancerbero usa la misma fuente para el tráfico y mejora el inspector usando
`libproc` estructurado (con `lsof` solo como fallback).

## Arquitectura

```
App SwiftUI ──XPC──> KancerberoDaemon (root opcional)
     │                       │
     └── modo local ─────────┴──> KancerberoCore
                                  ├── KancerberoC: NetworkStatistics (dlopen), libproc, sysctl
                                  └── modelos + contabilidad de deltas/tasas
```

- **Modo local** (sin daemon): procesos y sockets del mismo uid; tráfico por proceso vía
  NetworkStatistics (`net.statistics_privcheck = 0`).
- **Modo daemon**: todas las interfaces, todos los procesos y sockets de cualquier uid (si el
  daemon corre como root).
- **Fallback**: si NetworkStatistics no está disponible, la app sigue mostrando conexiones e
  interfaces y marca el modo como degradado.

## Interfaz

`NavigationSplitView` con panel lateral colapsable:

- **Networking** — tarjeta **Traffic** ancha con Download/Upload en la cabecera y un gráfico
  espejado (download arriba, upload abajo) con cuadrícula, niveles y eje temporal. Al lado, una
  tarjeta **Activity** que agrupa Connections y Processes, y una tarjeta **Protocols** con el
  desglose TCP4/TCP6/UDP4/UDP6/UNIX/OTHER. Los selectores **Transport** (TCP/UDP/Other) e **IP**
  (IPv4/IPv6) filtran las tablas de Connections/Processes y se combinan con el foco de las
  tarjetas. La tabla de Connections muestra Local, Remote, Protocol, RX, TX, State, Iface, PID y
  Process (última), y permite ordenar por cualquier columna. La tabla de Processes lista solo
  procesos con flujos TCP/UDP o sockets (incluye UNIX y RAW vía libproc), con badges de
  protocolo, tipos de socket (stream/dgram/raw), número de flujos, RX/TX acumulados y Path;
  también se puede ordenar por cualquier columna. Sin root solo se leen sockets del propio
  usuario; el daemon root cubre el resto. Las **velocidades** se muestran en bits con unidades
  humanas (`bps`, `Kbps`, `Mbps`, `Gbps`); los **totales acumulados** siguen en Bytes (`KB`, `MB`,
  `GB`).
- **Disk** — dos subpestañas:
  - **Volumes** — jerarquía nativa de discos físicos, particiones, contenedores APFS y volúmenes
    (IOKit + DiskArbitration + `getmntinfo`/`getattrlist`), con capacidad, usado, libre, punto de
    montaje, UUID, roles APFS, modelo/protocolo y cifrado. No ejecuta procesos externos. Las
    tarjetas All / Disks / Volumes / Capacity / Free filtran la lista (vista completa, medios,
    volúmenes montados, orden por tamaño o por menos espacio libre); All restaura el árbol
    completo expandido.
  - **Analyzer** — escaneo local de una carpeta o volumen con `getattrlistbulk`, mapa radial
    interactivo (clic en un sector para bajar, clic en el centro para subir), drill-down, mayores
    archivos, progreso y cancelación. El mapa y las tarjetas se actualizan en vivo durante el
    escaneo; las tablas de contenidos y mayores archivos aparecen al terminar. Las etiquetas del
    mapa muestran el nombre y el tamaño en formato humano. Las tarjetas filtran el panel derecho
    (todo, solo ficheros, solo carpetas o rutas denegadas); no se lee contenido de ficheros.
- **Daemons** — inventario de servicios launchd con filtros combinables por tipo (agentes /
  daemons), ámbito (sistema / global / usuario / runtime), origen (Apple / custom / desconocido)
  y estado (running / stopped / disabled / not loaded), además de búsqueda. Los agentes
  duplicados entre los dominios GUI y User se deduplican por label, conservando ambos dominios en
  el detalle. Inspector con Start / Stop / Restart / Enable·Disable / Load·Unload / Reveal.
  Las acciones de sistema requieren el daemon root y confirmación; GUI/User funcionan en local.
  Los login items quedan para una iteración posterior.
- **CPU** — dashboard tipo `htop`: tarjetas de CPU, load average, tareas/hilos y memoria con
  sparklines; medidores segmentados por núcleo (user/system/nice/idle); uptime; memoria y swap
  con desglose Active/Wired/Compressed/Cached/Free; y tabla de procesos ordenable con búsqueda
  (PID, USER, PRI/NI, VIRT, RES, S/THR, CPU%, MEM%, TIME+ y Command). CPU% no se normaliza
  (puede superar 100% en multihilo). Sin daemon root macOS solo enumera los procesos del uid
  actual; el daemon root muestra todos.

La barra inferior es contextual: muestra métricas de la sección activa (tráfico, capacidad de
disco, servicios o CPU/memoria) y, a la derecha, el estado global de la conexión con el daemon,
la última actualización de la fuente correspondiente y el posible error.

Las selecciones y configuraciones de cada sección (filtros, tarjeta activa, fila seleccionada,
panel de detalle y árbol expandido) se conservan al cambiar de pestaña o sección durante la
sesión; al reiniciar la app se vuelven a los valores iniciales. La preferencia de animaciones es
la excepción: **Kancerbero → Settings… (⌘,)** permite activar o desactivar las animaciones de
cambio de sección/subpestaña y del resaltado del sidebar y las píldoras. Se guarda en
`UserDefaults` y respeta Reduce Motion de macOS.

El panel se oculta con el toggle de la toolbar o `Cmd+Ctrl+S`; `Cmd+1/2/3/4` cambia de sección
(Networking, Disk, Daemons, CPU).

## Compilar

```bash
./scripts/build.sh                 # Debug: app, probe y daemon
# o
xcodebuild -project Kancerbero.xcodeproj -scheme Kancerbero \
  -configuration Debug -derivedDataPath build build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

Productos en `build/Build/Products/Debug/`.

## Icono

El icono de la app vive en `Sources/Kancerbero/Assets.xcassets/AppIcon.appiconset` y se genera con:

```bash
./scripts/make-icon.sh [origen.png]
```

Por defecto usa `/Users/alejandro/CODE/Iconos/kancerbero/kancerbero_1024x1024.png` (1254×1254; el
script lo reduce a 1024 para el slot mayor) y produce los 10 tamaños de macOS entre 16 y 1024.
El logotipo interno de la barra lateral es independiente y no se modifica. Si Finder/Dock muestra
un icono antiguo, es caché de LaunchServices: copia la app a otra ruta o reinicia Finder/Dock.

## Ejecutar

```bash
open build/Build/Products/Debug/Kancerbero.app
./build/Build/Products/Debug/KancerberoProbe all --seconds 3
./build/Build/Products/Debug/KancerberoProbe cpu --interval 1
./build/Build/Products/Debug/KancerberoProbe procs --cpu --limit 20
```

Captura de la UI sin permisos de Grabación de pantalla (la app se dibuja a sí misma y termina):

```bash
build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero \
  --screenshot /tmp/kancerbero-ui.png \
  [--section networking|disk|daemons|cpu] \
  [--tab interfaces|connections|processes] \
  [--disk-tab volumes|analyzer] \
  [--disk-path=<carpeta>] [--disk-scan] [--disk-item <diskXsY>] \
  [--cpu-search <texto>] [--cpu-selected <pid>] \
  [--networking-focus download|upload|connections|processes] \
  [--networking-transport tcp|udp|other] [--networking-ip ipv4|ipv6] \
  [--volumes-focus disks|volumes|capacity|free] \
  [--analyzer-focus scanned|files|folders|denied] \
  [--daemon-type agent|daemon] [--daemon-scope system|global|user|runtime] \
  [--daemon-origin apple|custom|unknown] \
  [--daemon-state running|stopped|disabled|unloaded] \
  [--daemon-domain system|gui|user] [--daemon-selected <label>] \
  [--sidebar-collapsed]
```

## Daemon

### Servicio en background (SMAppService)

La app embebe el helper y su plist en
`Kancerbero.app/Contents/Library/LaunchDaemons/` y los registra con
`SMAppService.daemon(plistName:)` desde el footer del sidebar o el menú **Daemon**. macOS lo
muestra en **Ajustes → General → Login Items & Extensions → Allow in the Background** con el
icono de Kancerbero (vía `AssociatedBundleIdentifiers`); el usuario debe aprobarlo. La app usa
`NSXPCConnection` privilegiado para el daemon de sistema.

Requisitos de distribución:

```bash
./scripts/build-release.sh      # Developer ID + hardened runtime, embebe el daemon
# Crear el perfil de notarización una sola vez:
xcrun notarytool store-credentials kancerbero-notary \
  --apple-id "<Apple ID>" --team-id AK37TK8X2Y --password "<app-specific password>"
./scripts/notarize.sh           # notarytool + stapler + spctl
./scripts/install-app.sh        # copia a /Applications/Kancerbero.app
```

Un daemon registrado con `SMAppService` exige app firmada con Developer ID y **notarizada**.
La build Debug ad-hoc puede mostrar la UI y el estado, pero no se espera que `register()` funcione.

Antes de registrar, elimina cualquier registro legacy: comparte label y Mach service.

```bash
./scripts/uninstall-agent.sh
sudo ./scripts/uninstall-daemon.sh
```

### Modo legacy de desarrollo

```bash
./scripts/install-agent.sh     # LaunchAgent de usuario, sin sudo
./scripts/uninstall-agent.sh
```

Sirve para probar el camino XPC completo en desarrollo. Solo ve procesos de tu usuario y no
puede convivir con el daemon SMAppService.

```bash
sudo ./scripts/install-daemon.sh
sudo ./scripts/uninstall-daemon.sh
```

Instala el binario en `/Library/PrivilegedHelperTools/` y el plist en
`/Library/LaunchDaemons/`. Es el modo legacy de desarrollo, no el camino de distribución.

## Daemons

- Estado e inventario con `launch_msg("GetJobs")` (`<launch.h>` del SDK) + plists; el daemon root
  consulta el dominio `system` y la app los dominios `gui`/`user`.
- Acciones con `/bin/launchctl` y dominio explícito, sin shell. Restart = stop + start.
- Estado disabled desde `launchctl print-disabled`.
- Diagnóstico:

```bash
./build/Build/Products/Debug/KancerberoProbe daemons system
./build/Build/Products/Debug/KancerberoProbe daemons gui
./build/Build/Products/Debug/KancerberoProbe daemon-action gui start <label>
```

## Disk

- Inventario nativo, sin `diskutil`: IOKit (`IOMedia`, `AppleAPFSMedia`, `AppleAPFSVolume`) para la
  jerarquía y los metadatos APFS; DiskArbitration para nombres, puntos de montaje, UUIDs, modelo y
  cifrado; `getmntinfo` + `getattrlist(ATTR_VOL_*)` para capacidad y usado por volumen.
- Análisis con `getattrlistbulk` por directorio (`ATTR_CMN_RETURNED_ATTRS`, `NAME`, `OBJTYPE`,
  `ATTR_FILE_TOTALSIZE/ALLOCSIZE`, `ATTR_DIR_ALLOCSIZE/MOUNTSTATUS`), sin seguir symlinks y sin
  cruzar puntos de montaje por defecto.
- Diagnóstico:

```bash
./build/Build/Products/Debug/KancerberoProbe disk volumes
./build/Build/Products/Debug/KancerberoProbe disk info disk3s5
./build/Build/Products/Debug/KancerberoProbe disk scan "$HOME/Documents" --top 20
```

## Verificación

```bash
./scripts/verify.sh
```

Compara con `netstat -ibI`, `lsof -nP -i`, `nettop` y Activity Monitor. Detalle y tolerancias en
`docs/verification.md`.

## Limitaciones conocidas

- APIs privadas (`NetworkStatistics.framework`): no apto para App Store.
- Sin firma Developer ID, el daemon se instala en modo desarrollo (ad-hoc + launchd manual).
- `NStatSourceIdentifier` no es fiable en macOS 27; se usa el puntero de fuente y las claves
  `PID`/`UUID`.
- La atribución por proceso usa `epid` cuando existe (como Activity Monitor); los flujos sin
  proceso se agrupan como desconocidos.
- El inspector usa `libproc`; para procesos de otros uid requiere el daemon root.
