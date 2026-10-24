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
- `NetworkingView`: cuatro tarjetas de resumen (`SummaryCard` + `Sparkline`), `PillTabBar` y las
  tablas (`NetworkingTables.swift`) dentro de una tarjeta con material.
- `DiskView` y `DaemonsView`: `PlannedSectionView` con icono animado y lista de capacidades
  previstas.
- Persistencia: `@AppStorage("selectedSection")` y `@AppStorage("networkingTab")`.
- Captura interna para verificación: `--screenshot`, `--section`, `--tab`,
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
