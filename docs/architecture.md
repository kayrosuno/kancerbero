# Arquitectura

## Targets

| Target | Tipo | Responsabilidad |
|---|---|---|
| `KancerberoC` | static lib C | `dlopen` de NetworkStatistics, tabla de fuentes, parsers de libproc y sysctl |
| `KancerberoCore` | static lib Swift | Modelos, wire codec, collectors, contabilidad, capacidades y diagnóstico |
| `KancerberoDaemon` | tool | `NSXPCListener` en `com.alejandro.kancerbero.daemon`, recolección y push |
| `Kancerbero` | app | SwiftUI, inspector, cliente XPC y modo local |
| `KancerberoProbe` | tool | Diagnóstico y comparación con herramientas del sistema |

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

## XPC

- Mach service: `com.alejandro.kancerbero.daemon`.
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
