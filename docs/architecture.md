# Arquitectura

## Targets

| Target | Tipo | Responsabilidad |
|---|---|---|
| `KancerberoC` | static lib C | `dlopen` de NetworkStatistics, tabla de fuentes, parsers de libproc y sysctl |
| `KancerberoCore` | static lib Swift | Modelos, wire codec, collectors, contabilidad, capacidades y diagnóstico |
| `KancerberoDaemon` | tool | `NSXPCListener` en `uno.kayros.kancerbero.daemon`, recolección y push |
| `Kancerbero` | app | SwiftUI, inspector, cliente XPC y modo local |
| `KancerberoProbe` | tool | Diagnóstico y comparación con herramientas del sistema |

## UI

- `RootView`: `NavigationSplitView` con `columnVisibility`; sidebar colapsable con
  `SidebarCommands()` y botón propio en la toolbar.
- `SidebarView`: selección propia con `matchedGeometryEffect` para Networking / Disk / Daemons;
  cabecera con marca y estado live, pie con fuente (daemon/local), privcheck y hora.
- `NetworkingView`: cuatro tarjetas de resumen compactas (`SummaryCard` + `Sparkline`) que actúan
  como filtros conmutadores, `PillTabBar` y las tablas (`NetworkingTables.swift`) dentro de una
  tarjeta con material.
- `DiskView`: `PillTabBar` con Volumes / Analyzer. Volumes muestra el árbol
  disco → partición → contenedor APFS → volumen, un inspector y `CapacityBar`; Analyzer muestra
  controles de escaneo, progreso, `RadialDiskMap` y las tablas de contenidos y mayores archivos.
  Las tarjetas de ambas subpestañas filtran el contenido (medios/volúmenes/orden por tamaño o
  espacio libre; todo/ficheros/carpetas/denegados).
- `DaemonsView`: inventario launchd deduplicado por label (`DaemonDeduplicator`), filtros
  combinables de tipo, ámbito, origen y estado, tarjetas accionables e inspector de acciones.
- `StatusBar`: barra inferior contextual; muestra métricas de la sección activa y el estado global
  del daemon/actualización de la fuente correspondiente.
- Persistencia: `@AppStorage("selectedSection")`, `@AppStorage("networkingTab")` y
  `@AppStorage("diskTab")`.
- Captura interna para verificación: `--screenshot`, `--section`, `--tab`, `--disk-tab`,
  `--networking-focus`, `--volumes-focus`, `--analyzer-focus`, filtros `--daemon-*` y
  `--sidebar-collapsed` (ver `docs/verification.md`).

## Flujo de datos

1. **NStat (tráfico y conexiones)**
   - `dlopen` del framework privado y `dlsym` de `NStatManagerCreate`,
     `NStatManagerSetFlags`, `NStatManagerAddAllTCP/UDPWithFilter`,
     `NStatSourceSetDescriptionBlock`, `NStatSourceSetCountsBlock`,
     `NStatSourceQueryDescription`, `NStatSourceQueryCounts`.
   - La identidad (PID, nombre, extremos, estado, interfaz) llega por description y counts.
   - **Los contadores solo son válidos en el diccionario del counts block**; description y
     `NStatSourceCopyProperties` devuelven `rxBytes/txBytes = 0`. Comprobado con tráfico real.
   - Los contadores son acumulados; `CollectionActor` calcula deltas y tasas contra la muestra
     anterior con reloj monótono.

2. **Interfaces**
   - `sysctlnametomib("net.link.generic.system.ifcount")` + `IFMIB_IFDATA/IFDATA_GENERAL`.
   - `struct ifmibdata` con `if_data64`: `ifi_ibytes/obytes` de 64 bits, paquetes, errores,
     drops, MTU, baudrate y `ifmd_flags`.
   - **Importante:** en macOS 27 la ruta `NET_RT_IFLIST2` devuelve los bytes truncados a 32 bits;
     `netstat` usa IFMIB y por eso kancerbero también. Comprobado contra `netstat -ibI`.

3. **Procesos**
   - `proc_listallpids` devuelve **bytes**, no número de PIDs (verificado en macOS 27).
   - `proc_pidinfo(PROC_PIDTBSDINFO)` para pid/ppid/uid/start time/nombre y `proc_pidpath`.

4. **Sockets y ficheros (inspector)**
   - `proc_pidinfo(PROC_PIDLISTFDS)` + `proc_pidfdinfo`.
   - `PROC_PIDFDSOCKETINFO`: `socket_fdinfo.psi.soi_proto.pri_tcp.tcpsi_ini` (puertos, direcciones,
     `tcpsi_state`) o `pri_in` para UDP.
   - `PROC_PIDFDVNODEPATHINFO` para rutas y tamaño de ficheros.
   - `proc_pidfdinfo` exige mismo uid salvo root: el daemon root es necesario para otros usuarios.

## Daemons

- `DaemonsCollector(domain:)` enumera plists de `LaunchDaemons`/`LaunchAgents` y obtiene el
  estado con `LaunchdQuery.jobs()` (`launch_msg("GetJobs")`): el app consulta `gui`/`user` y el
  daemon root consulta `system`. Si `launch_msg` no aplica (p. ej. `system` sin root) se parsea
  `launchctl print <domain>`.
- `launchctl print-disabled <domain>` da el estado disabled; los plists dan programa, argumentos,
  RunAtLoad, KeepAlive, StartInterval, WorkingDirectory y EnvironmentVariables.
- Las acciones usan `LaunchctlRunner` (`/bin/launchctl`, dominio explícito, sin shell):
  `kickstart`, `kill SIGTERM`, `enable`/`disable`, `bootstrap`/`bootout`; restart = stop + start.
- La app enruta `system` al daemon (`daemonServices`/`daemonAction` por XPC) y ejecuta `gui`/`user`
  en local. Sin daemon, `system` es solo lectura.
- La metadata de plists se cachea 30 s; el refresco de la vista es cada 5 s.

## Disk

- **Inventario (`DiskInventoryCollector`)**
  - IOKit: `IOServiceMatching("IOMedia")` y el padre `IOMedia` de cada servicio reconstruyen la
    jerarquía real del IORegistry: disco físico → partición → `AppleAPFSMedia` (contenedor) →
    `AppleAPFSVolume`. Se leen `BSD Name`, `Size`, `Content`, `Whole`, `Leaf`, `UUID` y, en APFS,
    `Role`, `RoleValue`, `VolGroupUUID` y `FullName`.
  - DiskArbitration (`DADiskCreateFromIOMedia` + `DADiskCopyDescription`) aporta nombre de volumen,
    tipo de sistema de ficheros, punto de montaje, UUID de volumen, modelo, protocolo, bus,
    interno/remóvil/expulsable/escribible/cifrado.
  - `getmntinfo` mapea los sistemas montados por `f_mntfromname` (`/dev/diskXsY`). Para cada volumen
    montado, `getattrlist` con `ATTR_VOL_INFO | ATTR_VOL_SIZE | ATTR_VOL_SPACEFREE |
    ATTR_VOL_SPACEAVAIL | ATTR_VOL_SPACEUSED` da el tamaño, libre, disponible y **usado real por
    volumen APFS** (coincide con `CapacityInUse` de `diskutil`).
  - El contenedor APFS hereda el libre de sus volúmenes montados (el espacio es compartido).
  - No se ejecuta ningún proceso externo.
- **Escaneo (`DiskScanner`)**
  - Una llamada C a `kb_disk_list_directory` por directorio; la capa C usa `open(O_RDONLY |
    O_DIRECTORY)` y `getattrlistbulk` con `ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_ERROR | ATTR_CMN_NAME |
    ATTR_CMN_OBJTYPE`, `ATTR_DIR_MOUNTSTATUS | ATTR_DIR_ALLOCSIZE` y
    `ATTR_FILE_TOTALSIZE | ATTR_FILE_ALLOCSIZE`, con `FSOPT_NOFOLLOW`.
  - DFS iterativo con pila de frames; al cerrar un directorio se construye un `KBDiskNode`
    inmutable. Se retienen los `maxChildrenRetained` hijos mayores y el resto se agrupa en un nodo
    “Other”. Límites `maxDepth`/`maxNodes` marcan `truncated`.
  - Se cuentan hidden y packages, pero no se desciende por symlinks ni por puntos de montaje
    (salvo opción). Los errores `EACCES`/`EPERM` se registran como rutas denegadas.
  - Top-N de mayores archivos por inserción ordenada; progreso cada 100 ms; cancelación cooperativa.
  - Snapshots parciales opcionales cada 400 ms (`partial:` en `DiskScanner.scan`): recorren la
    cadena abierta de la pila y reutilizan `closeFrame` para plegar/ordenar, sin mutar la pila
    real. Los frames en `pending` aún no visitados se omiten. Llevan `isPartial: true`.
- **Estado y UI (`DiskModel`)**
  - `@MainActor @Observable`, inyectado en `KancerberoApp`. Conserva el inventario, la selección, el
    estado del escaneo, el snapshot final, el `liveSnapshot` parcial, el nodo actual y las rutas
    denegadas. `activeSnapshot` prefiere el final y cae al vivo mientras se escanea.
  - `DiskAnalyzerView` actualiza tarjetas y mapa con `activeSnapshot`; las tablas del panel derecho
    solo se montan con el snapshot final. Mientras tanto se muestra un panel de espera del mismo
    ancho para evitar saltos de layout.
  - `RadialDiskMap` dibuja un sunburst con `Canvas`: anillos = profundidad, ángulo = tamaño
    asignado; hit-test por radio/ángulo. Las etiquetas muestran nombre y tamaño humano en dos
    líneas. El centro muestra el nodo actual y el porcentaje del volumen. Respeta Reduce Motion.
- **Límites:** SMART no está expuesto por APIs públicas; los volúmenes desmontados no tienen
  libre/usado; los hard links se cuentan por entrada; clones/snapshots APFS hacen que la suma de
  tamaños no coincida exactamente con el “Used” del contenedor.

## XPC

- Mach service: `uno.kayros.kancerbero.daemon`.
- Protocolo: `handshake`, `subscribe`, `request`, `unsubscribe`; callback `push`.
- Envelopes `KBWireEnvelope` con `schemaVersion`, `kind`, `sequence` y payload
  `PropertyListEncoder` binario.
- El daemon comparte un único `CollectionActor`; el intervalo efectivo es el de la suscripción
  (0.5–10 s).
- Si no hay daemon, la app usa `CollectionActor` en proceso y vuelve a intentar el daemon al
  arrancar.

## Modos

| Modo | Significado |
|---|---|
| `localFullNStat` | NetworkStatistics disponible en proceso |
| `localDegraded` | NetworkStatistics no disponible; solo libproc/sysctl |
| `daemonFull` | Daemon root: todos los usuarios |
| `daemonRestricted` | Daemon sin root: mismo uid |
| `interfacesOnly` | Sin procesos ni conexiones |
