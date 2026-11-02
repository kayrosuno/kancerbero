# Arquitectura

## Targets

| Target | Tipo | Responsabilidad |
|---|---|---|
| `KancerberoC` | static lib C | `dlopen` de NetworkStatistics, tabla de fuentes, parsers de libproc y sysctl |
| `KancerberoCore` | static lib Swift | Modelos, wire codec, collectors, contabilidad, capacidades y diagnóstico |
| `KancerberoDaemon` | tool | `NSXPCListener` en `uno.kayros.kancerbero.daemon.v2`, recolección y push |
| `Kancerbero` | app | SwiftUI, inspector, cliente XPC y modo local |
| `KancerberoProbe` | tool | Diagnóstico y comparación con herramientas del sistema |
| `KancerberoFilterContract` | static lib Swift | Contrato Codable y protocolos XPC compartidos por app y filtro |
| `KancerberoFilter` | system extension | `NEFilterDataProvider`: flujos, estadísticas y allow/deny por proceso |

## UI

- `RootView`: `NavigationSplitView` con `columnVisibility`; sidebar colapsable con
  `SidebarCommands()` y el toggle nativo que macOS dibuja en la toolbar.
- `SidebarView`: selección propia con `matchedGeometryEffect` para Networking / Disk / Daemons /
  CPU / Memory / Energy / Applications; cabecera con marca y estado live, engranaje de Settings
  sobre el separador de estado y pie con fuente (daemon/local), privcheck y hora.
- `NetworkingView`: franja superior como un único `HStack` sin `ViewThatFits`: columna
  `ActivityCard` (procesos con sockets, conexiones totales y conexiones activas dentro de la
  ventana configurada —10 s por defecto—, las dos últimas como filtro todas/activas) +
  `ProtocolCard`, `NetworkTotalsCard` fijo y
  `TrafficCard` con mínimo 260. Network siempre queda en la franja. `NetworkTotalsCard` recibe
  solo contadores: dos grupos apilados y sombreados, **Bytes** encima de **Packets**, cada uno
  con filas Input/Output y su total acumulado. `TrafficCard` recibe las tasas y usa
  `TrafficModeSelector` (glass en macOS 26+, `Picker` segmentado nativo en versiones anteriores)
  a la derecha de una cabecera con dos grupos de tasas, **Bytes** y **Packets**, ambos visibles;
  el grupo del modo activo se resalta y el otro queda atenuado. Cada tasa es un botón que alterna
  el foco Download/Upload. `TrafficChart` dibuja el gráfico espejado, escala compartida con techo
  1/2/5×10^n, cuadrícula, niveles y eje temporal; ventana de 60 muestras con el dato más reciente
  a la izquierda (`now` → `-60 s`).
  Debajo, `PillTabBar` y las tablas (`NetworkingTables.swift`). `NetworkingUIState` guarda, por un
  lado, los filtros de Connections —`transports: Set<NetworkingTransport>`, `ipVersions:
  Set<NetworkingIPVersion>` y `connectionStates: Set<NetworkingConnectionState>`— y, por otro,
  los de Processes —`processDomains: Set<ProcessDomain>` (AF_INET, AF_INET6, AF_UNIX, Other),
  `processProtocols: Set<ProcessProtocolCategory>` (TCP, UDP, ICMP, ICMPv6, SCTP, GRE, ESP, RAW,
  Other) y `processSocketTypes: Set<ProcessSocketType>` (stream, dgram, raw, seqpacket, other)—.
  Todos los valores están marcados por defecto, incluido `connectionStates.other`.
  `NetworkingProtocolFilter` combina transport/IP y `filteredSources` los
  aplica solo a Connections; `filteredProcessRows` recibe sus propios facetas
  (`domains:protocols:socketTypes:`) y es independiente de los de Connections. Esas facetas se
  cruzan sobre **la misma firma** `(AF_*, SOCK_*, IPPROTO)` del inventario libproc
  (`ProcessInventoryRow.socketSignatures`); un protocolo seleccionado exige familia AF_INET o
  AF_INET6. Sin firmas (daemon antiguo o proceso restringido) se usa el fallback agregado por
  badges y contadores. Los grupos
  viven en `NetworkingFilterBar`, una barra a todo el ancho entre `PillTabBar` y la tarjeta de la
  tabla (la tarjeta conserva el título, la búsqueda y el botón Inspect junto a ella, y el
  contador de filas a la derecha), y se dibujan con
  `CheckboxFilterGroup` (nativo `.toggleStyle(.checkbox)`) dentro de una cápsula neutra: todo
  marcado equivale a sin filtro, desmarcar excluye y un grupo vacío no coincide con ninguna fila.
  El filtro de estados se divide en **TCP State** (Established, Listening, Connecting, Closing) y
  **Other** en su propia cápsula (solo el checkbox). `NetworkingConnectionState.category(for:)`
  clasifica el `tcpState` crudo de NStat; `.other` agrupa solo estados TCP no clasificados,
  mientras que las filas sin estado (UDP) pasan el filtro de estados y las controla Transport
  (desmarcar Other no las oculta). La tabla de Interfaces tiene
  búsqueda propia (`interfaceSearch`) y ordena por todas sus columnas, incluidas RX/TX bit/s
  mediante la fila derivada `InterfaceRow` (`interfaceSortOrder`). En Processes, el fallback sin
  firmas usa los `tags`/`socketTypes` agregados y `otherProtocols` para aproximar la
  combinación. La tabla de Processes añade
  `Filter processes` en su cabecera, reutilizando `KBProcessInfo.matchesSearch` (nombre, ruta,
  PID o usuario). Connections ordena por cualquier columna (`Table` + `KeyPathComparator`) y
  muestra Process, PID, Local, Remote, Proto, State, RX, TX, Rate e Iface; los flujos UDP
  muestran `Datagram` en State porque no tienen estado TCP.
  Local/Remote usan un comparador numérico de endpoints y el criterio se guarda en
  `connectionSortOrder` dentro de `NetworkingUIState`. La tabla de Processes usa
  `ProcessInventoryRow` (agregado de flujos NStat + inventario de sockets libproc) y ordena con
  `processSortOrder`. Las columnas **Domain** y **Protocols** reparten las etiquetas de la misma
  firma: Domain muestra las familias (`domainBadgeLabels`, con el `AF_*` completo en el tooltip) y
  Protocols solo los protocolos IP (`protocolLabels`: TCP/UDP/ICMP/ICMPv6/SCTP/GRE/ESP/RAW…); la
  columna **Type** (antes Sockets) mantiene el desglose stream/dgram/raw/seqpacket/other. El
  tooltip muestra una línea `AF_* · SOCK_* · IPPROTO_*` por firma. Sin firmas se usan los
  protocolos reales del inventario (`otherProtocols`, un bitset de IPPROTO que rellena
  `kb_classify_socket` y traduce `KBIPProtocol`) en `ProcessInventoryRow.rawProtocolLabels`, y el
  genérico OTHER con las familias reales (`otherFamilies`, bitset de AF traducido por
  `KBSocketFamily` con la tabla completa de `sys/socket.h`) y los providers NStat no TCP/UDP
  (`ProcessInventoryRow.otherProtocolLabels`); un flujo TCP/UDP sin familia 4/6 se etiqueta
  `TCP`/`UDP` (`ProcessInventoryBuilder.otherLabel`). Sin detalle (daemon antiguo, sockets
  restringidos) se mantienen RAW4/RAW6 y OTHER. El inspector de proceso aplica la misma
  clasificación por socket vía `KBSocketInfo.protocolLabel`. `ActivityCard` recibe flags separados por pestaña: Connections refleja sus
  filtros de protocolo/estado/búsqueda y Processes sus facetas (IP, protocolo, socket) y búsqueda;
  `ProtocolCard` sigue siendo global y recibe el conjunto `ipVersions` de Connections (solo
  etiqueta una familia cuando queda aislada). `SocketSummaryCollector`
  enumera sockets por PID (TCP4/6, UDP4/6, UNIX, RAW4/6, OTHER y tipos stream/dgram/raw),
  deduplica FDs por `soi_so` dentro de cada PID y corre en `CollectionActor` cada ~10 s en
  background, sin bloquear NStat. El resultado viaja como campo **opcional**
  `socketInventory` en `KBCollectionSnapshot` (sin subir `schema`), por lo que también lo
  produce el daemon root. Sin root solo cubre el uid actual. Los historiales y
  `KBRates` siguen en bytes/s; la presentación usa `KBFormat.bitRate` y los totales acumulados
  `KBFormat.bytes`.
- `DiskView`: `PillTabBar` con Volumes / Analyzer / I/O. Volumes muestra el árbol
  disco → partición → contenedor APFS → volumen, un inspector y `CapacityBar`; Analyzer muestra
  controles de escaneo, progreso, `RadialDiskMap` y las tablas de contenidos y mayores archivos;
  I/O muestra el gráfico Data/Operations y la tabla de procesos por actividad de disco.
  Las tarjetas de ambas subpestañas filtran el contenido (medios/volúmenes/orden por tamaño o
  espacio libre; todo/ficheros/carpetas/denegados).
- `DaemonsView`: inventario launchd deduplicado por label (`DaemonDeduplicator`). Los filtros de
  tipo, ámbito, origen y estado son chips multiselección (`MultiSelectChipBar`): todos los valores
  están pulsados al arrancar, se muestran las filas de los valores pulsados y un grupo sin nada
  pulsado no coincide con ninguna fila. La búsqueda vive en la cabecera de la tarjeta sobre la
  tabla (patrón de `CPUProcessTable`), y las tarjetas Running/Stopped/Disabled alternan ese estado
  dentro del conjunto; la tarjeta Services restablece todos los grupos y la búsqueda. La tabla es
  ordenable por cualquiera de sus columnas mediante claves no opcionales de `DaemonListEntry`
  (rangos enteros para los enums y centinelas para valores ausentes); el criterio vive en
  `DaemonsUIState.sortOrder` y, sin orden elegido, se conserva el del deduplicador.
- `CPUView`: dashboard tipo `htop`. Cuatro `SummaryCard` (CPU, load, tareas/hilos, memoria) con
  `Sparkline`; tarjeta de núcleos tipo muro ecualizador (`C1..CN`, `CoreLoadBars` sobre
  `AppModel.coreUsageHistory`, grupos Performance/Efficiency, uso y temperatura por core, y
  temperatura de paquete IOHID). Con ancho suficiente y ≤8 cores usa una fila de columnas con
  barritas; en ventanas estrechas o Macs con más cores cae a la rejilla de filas con medidores
  rectangulares. Uptime; tarjeta
  de memoria/swap con segmentos Active/Wired/Compressed/Cached/Free y `CapacityBar`; tabla de
  procesos `CPUProcessTable` (PID, USER, PRI/NI, VIRT, RES, S/THR, CPU%, MEM%, TIME+, Command)
  ordenable, con búsqueda, selección persistida e inspector. `CPUProcessRow` añade claves de
  orden no opcionales para que los procesos sin task info queden al final. SwiftUI limita el
  `TableColumnBuilder` a 10 columnas, así que PRI/NI y S/THR se muestran combinadas.
- `ProcessCollector`/`kb_process_list`: enumera con `sysctl(KERN_PROC_ALL)` (incluye PID 0 y
  procesos sin task info), enriquece con `PROC_PIDTASKALLINFO` y `rusage_info_v6` y nunca descarta
  un proceso por falta de permisos. `AppModel` fusiona `ProcessCollector.metadataSnapshot()`
  cuando el daemon reporta menos procesos que macOS y expone `daemonProcessesIncomplete`; System
  status muestra el aviso y la tabla marca “N restricted”. Con el daemon root actualizado los
  contadores e hilos están completos; sin root quedan restringidos.
- `MemoryView`: panel dedicado tipo Activity Monitor. En una franja superior fija
  (`KBTheme.cardStripHeight`, 190 pt) van la presión con
  `MemoryPressureChart` y su explicación, la composición App/Wired/Compressed/Cached/Free
  (`SegmentedMeter` + `MeterLegend`) y el detalle Physical Memory / Memory Used / App / Wired /
  Compressed / Cached Files, más una tarjeta de swap con `CapacityBar`. Debajo, el resto del alto,
  `MemoryProcessTable` ordena `CPUProcessRow` por memoria residente con búsqueda, selección e
  inspector. Los valores AM se derivan de `KBMemoryStats` (`appMemoryBytes`,
  `cachedFileBytes`, `activityMonitorUsedBytes`).
- `EnergyView`: panel tipo Activity Monitor. En una franja superior fija
  (`KBTheme.cardStripHeight`, 190 pt) van la batería (`IOPowerSources`:
  carga, tiempo restante, cargando/conector), el consumo total en vatios de los procesos
  visibles y los wake-ups inactivos, cada uno con `Sparkline` de su histórico. La card Battery
  muestra además el gráfico de 12 h de `libsystemstats` (`BatteryChargeChart`: línea cian, bandas
  verdes del periodo en AC y rejilla discontinua) y «Time on AC/Battery» a partir de
  `battery_times`/`battery_states`. Con una sola muestra el gráfico se dibuja como línea plana
  (como Activity Monitor); solo si la API privada no está disponible o el diccionario está
  malformado vuelve a la barra de capacidad. Debajo, el resto
  del alto, `EnergyProcessTable` ordena por `ri_energy_nj`/s con impacto relativo, wake-ups, CPU%,
  PID, USER y `Preventing Sleep` (assertions `PreventUserIdleSystemSleep`/`PreventSystemSleep`
  vía `IOPMCopyAssertionsByProcess`). Energía y wake-ups son acumulativos en `rusage_info_v6` y
  `ProcessCPUTracker` los convierte en tasas por segundo.
- `ApplicationsView`: desinstalador tipo AppCleaner. `AppInventoryCollector` enumera apps en
  `/Applications` y `~/Applications` y widgets/plugins en las carpetas estándar de Library;
  `AppLeftoversCollector` replica sus categorías (Preferencias, ByHost/SyncedPreferences,
  Application Support, Caches, Containers, Application Scripts y Group Containers —con los
  application groups de los entitlements—, Saved State, launch items, Logs, WebKit/HTTPStorages)
  con la coincidencia de AppCleaner (bundle id case-insensitive por `contains`/prefijo,
  nombres sensibles a mayúsculas) y un recorrido profundo de `~/Library` y `/Library`; los bundles
  se clasifican en User/System según las rutas de `BundlePaths.plist` y la tabla filtra por tipo y
  origen. `ApplicationsModel` cachea leftovers y
  tamaños; `TrashCoordinator` mueve a la papelera las rutas escribibles del usuario y envía las de
  `/Library` y `/Applications` al daemon root mediante `trashItems`, validado con
  `KBPathPolicy`.
- `DockIconController`/`DockIconView`: `NSDockTile.contentView` con una vista AppKit que dibuja
  CPU usage/history, red, disco (`IOBlockStorageDriver`), memoria, presión, GPU y energía; el
  controlador vive en `KancerberoApp`, refresca cada 0,5 s y no depende de ninguna vista. La
  preferencia es `@AppStorage("dockIconStyle")` y “Show Application Icon” pone el contentView a
  `nil` para recuperar el icono de la app.
- `StatusBar`: barra inferior contextual; muestra métricas de la sección activa y el estado global
  del daemon/actualización de la fuente correspondiente.
- `SystemStatusView`: ventana “System status” (escena `Window` con id `system-status`, abierta con
  `openWindow(id:)`) desde el indicador Local/Daemon del sidebar, el pill Local/Daemon de la
  barra inferior o el icono de la cabecera del sidebar. Muestra un checklist de aplicación,
  helper embebido,
  colección, privilegios, registro SMAppService, aprobación en Login Items, conexión XPC y
  servicios legacy. `AppModel` expone el estado derivado (`appVersion`, `appBundlePath`,
  `appIsInApplications`, `daemonHelperPresent`, `daemonPlistPresent`, `hasFullDataAccess`,
  `isConnectingToDaemon`, `legacyAgentDetected`, `legacyDaemonDetected`) y las acciones
  `retryDaemonConnection`, `repairDaemonService` (unregister + register para re-lanzar la
  aprobación), `revealAppInFinder`, `openApplicationsFolder` y `copyLegacyRemovalCommands`. La
  ventana abre Settings/Finder y usa SMAppService; no ejecuta sudo ni scripts.
- Persistencia: `@AppStorage("selectedSection")`, `@AppStorage("networkingTab")`,
  `@AppStorage("diskTab")` y `@AppStorage("dockIconStyle")`. El estado de UI de cada sección (filtros, tarjeta activa, selección,
  panel de detalle y árbol expandido) vive en `UIState`, un `@Observable` inyectado desde
  `KancerberoApp`. Es **solo de sesión**: sobrevive a la destrucción de las vistas al cambiar de
  sección/subpestaña, pero no se guarda en disco. Los overrides `--networking-focus`,
  `--networking-transport`, `--networking-ip` y `--networking-state` (listas separadas por comas;
  `all` o un valor desconocido no filtran), `--networking-connection-search`,
  `--networking-interface-search`,
  `--networking-process-domain`, `--networking-process-ip` (alias ipv4/ipv6),
  `--networking-process-protocol`, `--networking-process-socket`,
  `--networking-search`, `--daemon-*`, `--volumes-focus`, `--analyzer-focus`,
  `--disk-io-search`, `--disk-io-selected`, `--disk-io-graph`, `--cpu-search`,
  `--cpu-selected`, `--memory-search`, `--memory-selected`, `--energy-search` y
  `--energy-selected` se aplican una sola vez al crear `UIState`.
- Tarjetas colapsables: `UIState.collapsedCardSections` guarda las secciones cuyo dashboard está
  oculto (solo sesión). El botón global del toolbar, delante del selector de intervalo, aplica
  “todo o nada” a las 7 secciones y `CollapsibleSectionHeader` añade un control `Hide/Show cards`
  a cada cabecera para cambiar solo esa pestaña; `Cmd+Shift+H` alterna el global. Cada vista
  envuelve su bloque de tarjetas en `if !ui.cardsCollapsed(for:)` con `.transition(.opacity)`; la
  tabla permanece fuera del condicional y absorbe el espacio. Al colapsar se resetean los filtros
  que solo viven en las tarjetas: `networking.focus`, `disk.volumesFocus` y
  `disk.analyzerFocus` a `.scanned`. Los overrides `--cards-collapsed`, `--cards-expanded` y
  `--cards-collapsed-sections` permiten capturar los estados sin tocar `UserDefaults`.
- Settings: `KancerberoApp` añade una escena nativa `Settings` con `SettingsView`. El toggle
  “Animate tab changes” persiste en `@AppStorage("tabAnimationsEnabled")` (por defecto `true`) y
  condiciona únicamente las transiciones de cambio de pestaña: `RootView` (secciones),
  `PillTabBar` + `NetworkingView`/`DiskView` (subpestañas) y el resaltado del sidebar. Con
  Reduce Motion activo no se anima aunque el toggle esté encendido.
  El toggle “Animate status bar values” persiste en
  `@AppStorage("statusBarTextAnimationsEnabled")` (por defecto `false`) y controla el
  `numericText` y la animación de las cifras de la barra inferior.
  El picker “Startup interval” persiste en `@AppStorage("startupSamplingInterval")` (por defecto
  `2` s) y solo fija el valor inicial de `AppModel.interval`: el selector del toolbar cambia la
  cadencia de la sesión actual sin modificar esa preferencia.
  El picker “Active connections window” persiste en
  `@AppStorage("activeConnectionWindowSeconds")` (por defecto `10` s; opciones 5/10/20/30/60/120;
  cualquier otro valor cae al default) y fija la ventana que `AppModel` usa para
  `activeSourceIDs`, el tile Active y su filtro. `AppModel` lee `UserDefaults` en cada tick: subir
  la ventana reincorpora flujos aún presentes en `lastActivityNanoseconds` y bajarla los descarta
  en el siguiente refresco; la caption/hint del tile se actualizan en vivo vía `@AppStorage`.
  Sparklines, hover, paneles de detalle, filtros/foco y LiveDot no se tocan.
- Disk → Volumes mantiene `expanded` y `volumesFocus` en `UIState`. La expansión inicial se hace
  una sola vez (`didExpandVolumesOnce`); los refrescos de inventario solo podan ids obsoletos, así
  que el colapso manual se conserva. La tarjeta All limpia el filtro y re-expande el árbol
  completo.
- Captura interna para verificación: `--screenshot`, `--section`, `--tab`, `--disk-tab`,
  `--networking-focus`, `--networking-transport`, `--networking-ip`, `--networking-state`,
  `--networking-connection-search`, `--networking-process-domain`,
  `--networking-process-ip` (alias ipv4/ipv6), `--networking-process-protocol`,
  `--networking-process-socket`, `--networking-search`,
  `--volumes-focus`, `--analyzer-focus`, `--disk-io-search`, `--disk-io-selected`,
  `--disk-io-graph`, `--cpu-search`, `--cpu-selected`, `--memory-search`,
  `--memory-selected`, `--energy-search`, `--energy-selected`, `--screenshot-dock`,
  `--dock-style`, filtros `--daemon-*` y `--sidebar-collapsed` (ver `docs/verification.md`).

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
   - `PROC_PIDTASKALLINFO` aporta identidad BSD (pid/ppid/uid/estado/nice/start time) y task info
     (CPU acumulada, RSS/VSZ, hilos, prioridad) en una sola llamada. Si falla, se cae a
     `PROC_PIDTBSDINFO` y se marca `has_task_info = 0`. `proc_pidpath` da la ruta.
   - **Límite real:** sin root, `proc_listallpids` y `proc_pidinfo` solo devuelven procesos del
     uid actual; macOS no expone los demás a un proceso sin el entitlement privado de Apple. El
     daemon root enumera todos. La UI lo indica en la tabla de CPU.

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
    líneas. El centro muestra el nodo actual y el porcentaje del volumen; pulsarlo sube un
    nivel. Respeta Reduce Motion.
- **Actividad de E/S (`DiskIOView`)**
  - Host: `kb_disk_io_read` recorre `IOBlockStorageDriver` y suma su `Statistics` (`Bytes
    (Read/Write)`, `Operations (Read/Write)`); `DiskIOReader` y `AppModel` derivan tasas por
    muestra, totales acumulados y los históricos de 60 muestras (bytes y operaciones).
  - Procesos: `rusage_info_v6` (`ri_diskio_bytesread`, `ri_diskio_byteswritten`,
    `ri_logical_writes`), convertidos a tasas por `ProcessCPUTracker`; con daemons antiguos la app
    rellena los procesos del usuario mediante `ProcessIOReader`/`kb_process_io_read`. El gráfico
    (`DiskIOChart`) alterna Data/Operations y la tabla (`DiskIOProcessTable`) ordena por actividad
    con estado, PID y usuario.
- **Límites:** SMART no está expuesto por APIs públicas; los volúmenes desmontados no tienen
  libre/usado; los hard links se cuentan por entrada; clones/snapshots APFS hacen que la suma de
  tamaños no coincida exactamente con el “Used” del contenedor.

## CPU y memoria

- **Fuentes públicas** (`kb_host_stats_read` en `kb_sysctl.c`):
  - `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` → ticks por núcleo
    (`CPU_STATE_USER/SYSTEM/IDLE/NICE`), liberados con `vm_deallocate`.
  - `host_statistics64(HOST_VM_INFO64)` + `host_page_size` → páginas de memoria; `hw.memsize`
    para el total.
  - `sysctlbyname("vm.swapusage")` (`xsw_usage`, ya en bytes) y
    `sysctl({CTL_KERN, KERN_BOOTTIME})`.
  - `getloadavg` para load 1/5/15.
- **CPU por núcleo** (`HostMetricsSampler`): deltas de ticks de 32 bits con resta wrapping
  (`current &- previous`); `used = user + system + nice`, `total = used + idle`; el agregado se
  calcula sumando ticks de todos los núcleos, no promediando porcentajes. La primera muestra no
  tiene baseline y reporta 0.
- **Temperaturas** (`kb_thermal_stats_read` → `ThermalStatsReader`): servicios IOHID de
  temperatura (page `0xff00`, usage `5`) clasificados por `Product` (`eACC`/`pACC`, `PMU tdie<N>`,
  `SOC MTR Temp Sensor`). El paquete usa ACC → tdie → SOC; los sensores por core son los índices
  tdie (o los nombres ACC) y se asignan a cada core lógico con `i × sensores / coreCount`, como
  btop. Apple no publica el mapa real core→sensor, así que el valor es aproximado. `CPUTopology`
  lee `hw.perflevel0/1.logicalcpu` para agrupar Performance/Efficiency. El reader no abre IOHID
  cuando corre como root (el LaunchDaemon de sistema no tiene sesión HID); en modo daemon la app
  rellena la temperatura localmente.
- **Wire (temperaturas):** `KBCoreCPU.temperatureCelsius`, `KBCPUStats.packageTemperatureCelsius`
  y `temperatureSource` son opcionales; un payload sin esas claves decodifica a `nil` y el app
  rellena la temperatura localmente si el daemon es antiguo. No se cambia `KBVersion.schema`.
- **CPU por proceso** (`ProcessCPUTracker`): `PROC_PIDTASKINFO.pti_total_user/system` está en
  unidades mach absolute; se convierte con `mach_timebase_info` cacheado (125/3 en Apple
  silicon, 1/1 en Intel). `cpu% = delta_segundos / elapsed * 100`, primera muestra 0, se recorta
  a `0...100×núcleos`; puede superar 100% en multihilo. Clave `KBProcessKey(pid,startTimeUS)`
  para PID reuse; el diccionario baseline se reemplaza completo en cada tick.
- **Memoria:** `used = active + wired + compressed`; `cached = inactive`;
  `free = total - used - cached` (clamp ≥ 0) para que la barra no supere el total. `top`/Activity
  Monitor usan definiciones distintas de “used”; `free_count` de `vm_statistics64` ya incluye
  speculative y no se suma dos veces.
- **Estado y nice:** en macOS 27 `pbi_status` vale 2 (SRUN) tanto para procesos dormidos como
  activos; se usa `pti_numrunning` (>0 → R, 0 → S) y se conserva el mapeo de `pbi_status` para
  idle/stopped/zombie. `pbi_nice` viene del BSD info. `PRI` es `pti_priority` (escala de task de
  macOS, no paridad con `ps`). Sin task info el estado queda `nil` y la tabla muestra `—`.
- **Wire:** `KBCollectionSnapshot.hostMetrics` es **opcional** (igual que `socketInventory`), así
  que un daemon antiguo decodifica con `nil` y no se sube `KBVersion.schema`. La pestaña muestra
  un aviso si el daemon conectado no reporta estas métricas.
- **Permisos:** CPU global, memoria, swap, load, uptime y procesos propios no requieren root.
  Task info de otros uid y la enumeración de sus PIDs requieren el daemon root; sin él la tabla
  solo lista el uid actual y lo indica. No se usan entitlements privados ni `task_for_pid`.
- **Ventana de tasas:** un delta de contadores solo se convierte en tasa si
  `elapsed >= max(0,2 s, 0,25 × cadencia)` y `elapsed <= max(5 s, 2,5 × cadencia)`
  (`RateTiming`). El mínimo descarta pushes duplicados, cruces local↔daemon y refrescos
  inmediatos; el máximo descarta bases obsoletas (pausa, desconexión, suspensión) sin anular los
  5 s del selector ni los 10 s que acepta el daemon. Se aplica en `AppModel.apply`,
  `CollectionActor.refresh` y `ProcessCPUTracker.annotate`; cuando la cadencia es desconocida
  (petición puntual al daemon, `KancerberoProbe`) el rango es 0,2–30 s.
- **Baselines:** cada snapshot lleva su procedencia (local o daemon); al cambiar de fuente se
  vacían los baselines de red y de proceso. `KBCounters.positiveDelta(from:)` devuelve 0 cuando un
  contador retrocede, nunca el acumulado completo. Así el primer sample de una fuente solo siembra
  baseline y no puede producir el pico de GB/s del arranque. El reloj de las tasas se toma tras leer
  las interfaces; el de CPU de procesos conserva su propio inicio de recolección.

## XPC

- Mach service: `uno.kayros.kancerbero.daemon.v2` (label del job y plist: el mismo nombre).
- Protocolo: `handshake`, `subscribe`, `request`, `unsubscribe`; callback `push`.
- Envelopes `KBWireEnvelope` con `schemaVersion`, `kind`, `sequence` y payload
  `PropertyListEncoder` binario.
- `KBCollectionSnapshot` transporta `socketInventory` y `hostMetrics` como campos opcionales;
  ambos se añadieron sin subir el schema, así que un daemon/app anterior sigue conectando.
- El daemon comparte un único `CollectionActor`; el intervalo efectivo es el de la suscripción
  (0.5–10 s). Cambiar el selector de intervalo reenvía `subscribe` desde `DaemonMetricsSource`;
  el daemon cancela la tarea anterior y la reemplaza. En modo local, `AppModel` cancela el sueño
  del bucle de polling para aplicar el nuevo intervalo de inmediato.
- Si no hay daemon, la app usa `CollectionActor` en proceso y vuelve a intentar el daemon al
  arrancar.
- Distribución: el helper y su plist van embebidos en
  `Kancerbero.app/Contents/Library/LaunchDaemons/`; la app los registra con
  `SMAppService.daemon(plistName:)` y el usuario aprueba en Login Items. El cliente usa
  `NSXPCConnection` con `.privileged` para el daemon de sistema. El plist incluye
  `AssociatedBundleIdentifiers`, que asocia el servicio con el icono/nombre de la app. Requiere
  Developer ID + notarización. Los scripts `install-agent.sh`/`install-daemon.sh` son el modo
  legacy de desarrollo y no pueden convivir con el daemon SMAppService.

## Filtro de red (Network Extension)

- `KancerberoFilter` es una **system extension** (`Contents/Library/SystemExtensions`) con un
  `NEFilterDataProvider` (extension point `com.apple.networkextension.filter-data`). Corre como
  root, en sandbox y en contexto global: no comparte App Group con la app y no tiene UI.
- La app la instala/actualiza con `OSSystemExtensionManager` y configura el filtro con
  `NEFilterManager` (`filterSockets = true`, grade `.firewall`). Requiere aprobar la extensión y
  el aviso de filtrado de contenido; el filtro sigue activo con la app cerrada.
- Canal app↔extensión: la extensión publica **un** endpoint XPC (`NEMachServiceName =
  group.uno.kayros.kancerbero.filter`) y la app conecta con
  `NSXPCConnection(machServiceName:options:.privileged)`. Los protocolos
  `KancerberoFilterXPC`/`KancerberoFilterClientXPC` transportan `FilterEnvelope` con payloads
  `PropertyListEncoder` binario (`FilterWire`). El listener exige un requisito de firma del
  Team ID para aceptar clientes.
- La extensión es la fuente de verdad en ejecución: reglas (`executablePath`) y decisiones
  recordadas se cachean en su propio container para seguir aplicándose tras un reinicio sin la
  app. La app guarda su copia editable en `UserDefaults` y sincroniza al conectar y al cambiar.
- Flujos: `handleNewFlow` resuelve el proceso con `sourceAppAuditToken`/`sourceProcessAuditToken`
  → `audit_token_to_pid` → `proc_pidpath` (en macOS `sourceAppIdentifier` no existe). Un proceso
  vigilado con política `ask` se **pausa**, se envía `FilterRequest` a la app y se reanuda con
  `resumeFlow(_:with:)` al recibir la decisión; TCP puede esperar 60 s, UDP se deniega a los 8 s
  (el sistema descarta UDP a los 10 s). Sin cliente XPC o sin decisión: **deny** (fail-closed).
- Volumen: los veredictos llevan `shouldReport = true` y `statisticsReportFrequency = .medium`;
  `handle(_ report:)` acumula `bytesInboundCount/bytesOutboundCount` por flujo. Son contadores
  agregados del kernel y el tráfico excluido por Apple no se ve.
- `FilterRule.enabled` permite dejar una regla listada sin aplicarla: la extensión solo casa
  reglas activas (`executablePath` + `enabled`). El campo es opcional al decodificar
  (`enabled ?? true`), así que las cachés antiguas siguen siendo válidas y el schema no cambia.
  La app puede activar/desactivar y borrar reglas y decisiones recordadas; cada mutación
  persiste su copia y empuja el snapshot completo (`setRules`), que la extensión reemplaza y
  guarda en su `rules.plist`.
- UI: pestaña **Filter** (flujos con RX/TX y estado), escudo por fila en **Processes**, hoja de
  aprobación en `RootView` (`FilterApprovalSheet`: icono y nombre grandes, destino a 30 pt,
  anillo de cuenta atrás, selector Remember Once/This app/App + destination y botones
  Allow/Deny; `.interactiveDismissDisabled` y Return/Escape). La decisión es optimista: la hoja se
  cierra al instante y el modelo quita el pending antes de enviar el mensaje XPC; «Disable
  filter» corre en segundo plano sin bloquear el resto. Las operaciones de `NEFilterManager`
  (`loadFromPreferences`/`saveToPreferences`/`removeFromPreferences`) tienen un timeout de 5 s
  con una continuación one-shot, para que un daemon de NetworkExtension que no responde deje el
  estado en `.failed` en vez de colgar la UI. Ventana **Filter rules**
  (`FilterRulesView`, abierta con **Rules…** desde el Filter) con estado, reglas y decisiones
  recordadas. Las reglas se pueden eliminar de varias formas: seleccionar una fila y usar
  **Delete** en la cabecera de la sección, la papelera de la fila o el menú contextual; todas
  piden confirmación con un `.alert` y borran la regla junto con las decisiones recordadas de esa
  app. Sin selección, el botón de cabecera queda deshabilitado. Filas de estado en
  **System status**.
- Entitlements: en Release, `content-filter-provider-systemextension` en app y extensión,
  `system-extension.install` en la app y `app-sandbox` en la extensión; ambos se firman con
  Developer ID + provisioning profile. En Debug se usan los archivos `-Development.entitlements`
  con el valor sin sufijo (`content-filter-provider`), que es lo que conceden los perfiles Mac
  Team (ver `docs/verification.md`).

## Modos

| Modo | Significado |
|---|---|
| `localFullNStat` | NetworkStatistics disponible en proceso |
| `localDegraded` | NetworkStatistics no disponible; solo libproc/sysctl |
| `daemonFull` | Daemon root: todos los usuarios |
| `daemonRestricted` | Daemon sin root: mismo uid |
| `interfacesOnly` | Sin procesos ni conexiones |
