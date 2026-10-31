# APIs privadas y evidencia REA

Ingeniería inversa de `/System/Applications/Utilities/Activity Monitor.app` con REA 6.7.0
(Hopper) y herramientas de solo lectura (`otool`, `nm`, `codesign`). Binario analizado:
Mach-O universal arm64e, sha256 `70593b6e60f57767255a1bca5d9c5da09abb9f410a2cb0405bae5843ff89fd5d`.

## Qué hace Activity Monitor

| Función | Mecanismo | Evidencia |
|---|---|---|
| Tráfico por proceso | `NetworkStatistics.framework`: `NWStatsManager` + `NWStatsProtocolSnapshot`; `configure:` con `kNWStatsSelectInterfaceWiFi/Wired/Cellular/CompanionLinkBluetooth` + `kNWStatsParameterReportOpen`; deltas `deltaAccountingRx/Tx*Bytes`; atribución a `epid`/`processID` | `-[NetStatManager initWithQueue:queryCompleteBlock:]` 0x100045030; `sample` 0x1000457c4; `_accumulateProtocolSnapshot:` 0x1000453b8; `-[SMProcess updateWithNetStatDictionary:]` 0x100039738 |
| Totales de interfaz | `sysctl {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0}`; `RTM_IFINFO2`; `if_indextoname` | `-[SMStatisticsManager processSystemSysmonTable:]` 0x100012398; MIB en 0x10005ab18 |
| (kancerbero) contadores de interfaz | `net.link.generic.system.ifcount` + `IFMIB_IFDATA`/`IFDATA_GENERAL` (`ifmibdata.if_data64`) | En macOS 27, `NET_RT_IFLIST2` devuelve `ifi_ibytes` truncado a 32 bits; IFMIB coincide con `netstat` |
| Lista de procesos | `libsysmon` privado | imports `_sysmon_*` |
| Open Files and Ports | `/usr/sbin/lsof -Fn <pid>` local o vía helper XPC root | `-[SMProcessInspector _listOpenFiles]` 0x10002d63c; `listOpenFilesWithProcessID:taskID:result:` 0x100001428 |
| Privilegios | Entitlements privados + helper `_RoleAccount=root` + AuthorizationServices | `codesign -d --entitlements`; Info.plist del helper |

## Uso en kancerbero

### NetworkStatistics (privado)

Se carga con `dlopen` porque el `.tbd` del SDK declara solo `x86_64`, `arm64e` y `arm64e.x1`
(no `arm64`), y enlazarlo estáticamente rompería el build.

Símbolos usados:

```
NStatManagerCreate, NStatManagerSetFlags,
NStatManagerAddAllTCPWithFilter, NStatManagerAddAllUDPWithFilter,
NStatSourceSetDescriptionBlock, NStatSourceQueryDescription,
NStatSourceSetCountsBlock, NStatSourceQueryCounts,
NStatSourceSetRemovedBlock
```

Claves usadas (variables `CFStringRef` resueltas con `dlsym`):

```
kNStatSrcKeyPID, EPID, ProcessName, Provider, TCPState,
kNStatSrcKeyLocal, Remote, Interface, InterfaceName, InterfaceType, UUID,
kNStatSrcKeyRxBytes, TxBytes, RxPackets, TxPackets,
kNStatSrcKeyRxWiFiBytes, TxWiFiBytes, RxWiredBytes, TxWiredBytes,
kNStatSrcKeyRxCellularBytes, TxCellularBytes,
kNStatSrcKeyRxDupeBytes, RxOOOBytes, TxReTx, AvgRTT, StartAbsoluteTime
```

Hallazgo importante: `NStatSourceCopyProperties` y el description block devuelven identidad pero
contadores a 0; los valores reales llegan en el bloque de counts (`NStatSourceQueryCounts`).
`NStatSourceIdentifier` devolvió punteros no válidos en macOS 27 y no se usa.

### libproc

`proc_listallpids` devuelve bytes (`proc_listallpids(NULL, 0)` → tamaño necesario), no PIDs.
`proc_pidinfo`/`proc_pidfdinfo` requieren mismo uid salvo root.

Para el resumen de sockets se usa `PROC_PIDLISTFDS` + `PROC_PIDFDSOCKETINFO` por PID:
`soi_kind` (`SOCKINFO_TCP`/`IN`/`UN`), `soi_family` (AF_INET=2, AF_INET6=30, AF_UNIX=1),
`soi_type` (stream/dgram/raw/seqpacket) y `soi_protocol` (TCP/UDP/raw). `soi_so` es el handle
opaco del socket y se usa solo para deduplicar FDs duplicados dentro del mismo PID; no se
persiste ni viaja por XPC. `pri_un` permite identificar AF_UNIX. El inventario expone únicamente
conteos agregados, no direcciones ni rutas.

### sysctl

Activity Monitor usa `NET_RT_IFLIST2` para el gráfico global, pero en macOS 27 esa ruta
devuelve `if_data64` con solo los 32 bits bajos de `ifi_ibytes/ifi_obytes` (verificado con un
programa C independiente y comparado con `netstat`). kancerbero usa la ruta IFMIB:

```
sysctlnametomib("net.link.generic.system.ifcount", mib, &len)  // [4,18,0,1,1]
mib[3] = IFMIB_IFDATA; mib[4] = index; mib[5] = IFDATA_GENERAL;
sysctl(mib, 6, &ifmibdata, &len, NULL, 0)
```

`ifmibdata.ifmd_data` es `struct if_data64` y coincide exactamente con `netstat -ibI`.

## CPU y procesos (pestaña CPU)

Análisis REA de `/opt/homebrew/Cellar/htop/3.5.3/bin/htop` (arm64, sha256
`fc141c6d72271dc3b24d3f5aeb55c461de47aab235fbe758df804c61d070ca0d`, Ghidra 12.2). Se
inspeccionaron `_CPUMeterCommonDraw`, `_CPUMeter_updateValues`, `_Platform_setCPUValues`,
`_TasksMeter_updateValues`, `_UptimeMeter_updateValues`, `_MemoryMeter_updateValues`,
`_Platform_setMemoryValues` y `_Process_updateCPUFieldWidths`.

- htop obtiene ticks por núcleo de Mach (`PROCESSOR_CPU_LOAD_INFO`), memoria de
  `HOST_VM_INFO64`, load con `getloadavg`, uptime con `kern.boottime` y CPU/RSS de procesos con
  task info de libproc/Mach. Son las mismas APIs públicas que usa kancerbero; no hay dependencia
  de frameworks privados.
- Los porcentajes por núcleo de htop son deltas normalizados por ticks; el CPU% por proceso puede
  superar 100% (no se divide por el número de núcleos). kancerbero replica ambas convenciones.
- Hallazgo de macOS 27: `proc_bsdinfo.pbi_status` devuelve 2 (SRUN) para procesos dormidos y
  activos por igual. Para el estado se usa `proc_taskinfo.pti_numrunning` (>0 → R, 0 → S) y se
  reserva `pbi_status` para idle/stopped/zombie.
- `ps` y `top` de Apple ven procesos de otros uid sin root porque están firmados con el
  entitlement privado `com.apple.system-task-ports.read`. kancerbero **no** usa ese entitlement:
  sin daemon root solo enumera el uid actual; con el daemon root obtiene task info de todos.
- `PROC_PIDTASKALLINFO`, `PROC_PIDTBSDINFO`, `host_processor_info`, `host_statistics64`,
  `sysctlbyname` y `getloadavg` son APIs públicas del SDK; no se usan símbolos privados de
  `libsysmon` ni `task_for_pid`.

## Temperaturas CPU (IOHID)

kancerbero no lee SMC: usa los servicios de temperatura HID del sistema, la misma fuente que btop
1.4.8 en Apple Silicon. Verificado contra el código fuente de btop 1.4.8
(`src/osx/sensors.cpp`) y sus literales (`strings /opt/homebrew/bin/btop`).

- `IOHIDEventSystemClientCreate` + `IOHIDEventSystemClientSetMatching` con
  `{PrimaryUsagePage: 0xff00, PrimaryUsage: 5}`; `IOHIDEventSystemClientCopyServices`.
- Por servicio se lee `"Product"` y se clasifica por prefijo:
  `eACC`/`pACC` (clústeres), `PMU tdie<N>` (die indexado) y `SOC MTR Temp Sensor`.
- Temperatura: `IOHIDServiceClientCopyEvent(service, 15, 0, 0)` y
  `IOHIDEventGetFloatValue(event, 15 << 16)`; se descarta fuera de `0...150 °C`.
- Paquete: media de ACC; si no hay, de tdie; si no, de SOC. Sensores por core: índices tdie
  ordenados o, en su defecto, nombres ACC. Cada core lógico `i` usa
  `sensor = i × sensores / coreCount`, como btop. Apple no expone el mapa real core→sensor, así
  que el valor por core es aproximado; la UI lo indica en el popover.
- Los símbolos no están en cabeceras públicas del SDK (sí en `IOKit.tbd`). Se resuelven con
  `dlopen`/`dlsym` desde `kb_thermal.c` y, si desaparecen en una versión futura, la temperatura
  muestra `—` sin impedir el arranque. No se añaden entitlements.
- Macs Intel y algunas VMs no publican estos servicios: `valid = 0` y la card muestra `—`. La
  ruta SMC (`TC0P`/`TC0c`) de btop para Intel queda fuera de alcance.

## Pestaña Network (Activity Monitor)

Análisis con REA/Hopper sobre la build actual (arm64e, sha256 `2c5fddfd…`). El gráfico de red no
usa NetworkStatistics para el gráfico global: `SMNetworkGraphController` mantiene dos gráficos
espejados y selecciona la fuente según un popup `graphType`.

| Función | Mecanismo | Evidencia |
|---|---|---|
| Selector | `graphType` (popup) 0 = paquetes, 1 = datos; persiste en `NetworkGraphType` | `-[SMNetworkGraphController graphTypeChanged:]` 0x10000fce0 |
| Series | `packetsInRateHistory`/`packetsOutRateHistory` → top/bottom graph; o `dataReceivedSpeedHistory`/`dataSentSpeedHistory` | `-[SMNetworkGraphController didReceiveSystemStatisticsUpdateNotification:]` 0x100010288 |
| Etiquetas | `packetsInRateLabel`, `packetsOutRateLabel`, `dataReceivedSpeedLabel`, `dataSentSpeedLabel` | outlets del controlador; `-[SMUtility networkSpeedFormatter]`, `-[SMNetworkSpeedFormatter stringFromBytesPerSecond:]` |
| Datos | `SMSystemStatistics`: `networkPacketsIn/OutCount`, `networkDataReceived/SentSize`, `networkPacketsIn/OutRate`, `networkDataReceived/SentSpeed` | propiedades del modelo 0x10000b408-0x10000b46c |

kancerbero replica el modelo con las interfaces IFMIB: `AppModel.systemRates` agrega tasas de bytes
y paquetes (sin loopback/túnel), `systemCounters` agrega los contadores acumulados y
`rxPacketHistory`/`txPacketHistory` guardan el histórico de paquetes. La card `Network` muestra
solo los totales acumulados; las tasas actuales viven en los grupos Bytes/Packets de la cabecera de
`TrafficCard`, y el selector Bits/Packets cambia el gráfico y resalta el grupo correspondiente, como
el popup de Activity Monitor.

## Disk Inspector y Disk Utility (pestaña Disk)

Análisis REA (Hopper) de `/Applications/Disk Inspector.app` (`com.nektony.diskinspector`, que se
anuncia como “Disk Space Analyzer”) y de `/System/Applications/Utilities/Disk Utility.app`.

### Disk Inspector 6.0.3

| Función | Mecanismo observado | Evidencia |
|---|---|---|
| Enumerar directorios | `getattrlistbulk(fd, &attrlist, buf, 25600, FSOPT_NOFOLLOW)` en bucle | `-[SizeCalculationTask scanDirPointer:]` 0x100048bec |
| Attrlist | `ATTR_BIT_MAP_COUNT`; common `RETURNED_ATTRS\|NAME\|OBJTYPE` (0x80000009); dir `MOUNTSTATUS`; file `ALLOCSIZE` | `-[SizeCalculationTask initWithFolderPath:]` 0x1000488d0 |
| Abrir | `open(path, O_RDONLY)` | `-[SizeCalculationTask scanPath:]` 0x100048b68 |
| Parsear | `length` + `attribute_set_t` + `attrreference_t` para el nombre; `VDIR==2`; tamaños `u64` | `-[TWalker scanDirEntry:pointer:]` 0x100055ac8 |
| Recorrer | VDIR → pila de paths; resto → suma al nodo actual | `-[SizeCalculationTask processDirEntry:]` 0x100048d00 |
| Árbol | `FolderSystemItem` con alloc size; hidden/package/access denied; `dispatch_group_async`; 4 walkers | `-[TWalker iterateFolderStack:withParent:]` 0x1000554f0 |
| Paquetes | `.webplugin .wdgt .kext .fs .bundle .downloads .plugin .photoslibrary .dictionary`; `.app` vía LaunchServices | strings en 0x1003fb1b6 |
| Mayores archivos | Ignora hidden; los paquetes se tratan como hoja | `-[FolderSystemItem fillBiggestFilesArray:]` 0x10002adf4 |
| Escala radial | Máximos por nivel (hasta 14) para los anillos | `-[FolderSystemItem calcTotalSizeWithMaxSizes:withCurLevel:]` 0x10002ac40 |

### Disk Utility

- `-[SUDiskInfo _buildPropertiesForDisk:]` (0x100001d34) construye el panel de información con:
  Disk Name, Simple Description, Partition Scheme, Mount Point, Type, Capacity, Free, Available,
  Used, Owners, Device Identifier, Connection, Location, Disk Type, Child Count, Volume Count,
  Physical Stores, Snapshot Name/UUID, Partition Map Type y SMART Status.
- Usa los frameworks privados `StorageKit` (`SKDisk`, `SKAPFSDisk`, `SKAPFSContainerDisk`,
  `SKAPFSStoreDisk`, `SKFilesystem`) y DiskArbitration (`DASessionCreate`,
  `DADiskCreateFromBSDName`, `DADiskGetBSDName`). StorageKit/DiskManagement viven en la caché
  dinámica y no son enlazables.
- **Decisión:** no enlazar frameworks privados ni ejecutar `diskutil` desde la app. Se replica el
  modelo con APIs públicas:
  - IOKit: jerarquía `IOMedia` y propiedades APFS (`Role`, `VolGroupUUID`, `FullName`).
  - DiskArbitration: nombre/tipo de volumen, mount point, UUIDs, modelo, protocolo, bus, flags.
  - `getmntinfo` + `getattrlist(ATTR_VOL_*)`: capacidad, libre, disponible y usado por volumen.
- Verificado en macOS 27: `ATTR_VOL_SPACEUSED` de `/` devuelve 13.655.425.024, idéntico al
  `CapacityInUse` de `diskutil info`; el volumen Data devuelve 432.794.021.888 (diferencia de
  milisegundos). IOKit expone `AppleAPFSMedia`/`AppleAPFSVolume` y `Whole`/`Content`/`Role`
  exactamente como los muestra `ioreg`.
- SMART no está expuesto por APIs públicas; se omite o se muestra “Unavailable”.

## Política de versión

- macOS 14+, probado en macOS 27.0.1 arm64.
- Si cambia el framework, `kb_nstat_open()` falla con un mensaje concreto y la app entra en modo
  degradado; `KancerberoProbe symbols` sirve para re-verificar tras cada actualización de macOS.
- `net.statistics_privcheck` debe ser 0 para usar el framework sin entitlement. Si vale 1, el
  daemon (sin el entitlement privado de Apple) no puede usarlo y la app muestra el modo degradado.

## LaunchControl 2.12 (pestaña Daemons)

Análisis REA 6.7.0 (Hopper) del binario principal y del helper privilegiado de
`/Applications/LaunchControl.app`, sin ejecutarlos.

| Función | Mecanismo observado | Evidencia |
|---|---|---|
| Enumerar | Plists en directorios estándar + bitmask por directorio; dominio 2 (usuario/gui) o 4 (sistema) | 0x10003cb1c, 0x10003c0cc |
| Detalle | `ServiceDescription readPlist` (`Label`, `Program`, `ProgramArguments`, `RunAtLoad`, `KeepAlive`, `Disabled`, `EnvironmentVariables`, `WorkingDirectory`, `StartInterval`, `StartCalendarInterval`, `LastExitStatus`…) | 0x1001736a8 |
| Estado usuario | SPI `launch_msg("GetJobs")` + `launch_data_dict_iterate` | 0x100097350, 0x100097520 |
| Estado sistema | XPC `listWithReply:` al helper; helper con `launchctl_list` (`launch_msg`) | helper 0x100017fe0 |
| Start/Stop usuario | `/bin/launchctl start|stop <label>` (NSTask) | 0x10003d850 |
| Start/Stop sistema | XPC al helper; `launchctl start|stop` como root | helper 0x100017c94, 0x100017c0c |
| Load/Unload | `/bin/sh -c "/bin/launchctl %@ -F %@ '%@'"`; helper para sistema | 0x10003d5a0 |
| Enable/Disable | `launchctl enable|disable system/<label>` / `gui/<uid>/<label>` | 0x10004dafc |
| Disabled | `launchctl print-disabled` + parser de `"disabled services"` | 0x10004d064 |
| Helper | `SMAppService`/`SMJobBless`; XPC con list/status/start/stop/load/unload/savePlist/override/señales y **ejecución arbitraria** root (`performPrivilegedTaskWithLaunchPath:arguments:`); listener sin comprobación explícita | 0x100016c38, 0x100015c58 |

Conclusiones y decisión para kancerbero:

- LaunchControl **no** usa XPC directo a launchd ni libvproc: usa `launch_msg`, `/bin/launchctl` y
  un helper XPC para el dominio `system`. Los endpoints XPC privados de launchd
  (`com.apple.xpc.launchd`, `xpc_pipe_interface_routine`) no están documentados y no se usan.
- kancerbero replica el enfoque con `launch_msg("GetJobs")` para el estado (`kb_launchd.c`,
  `<launch.h>` del SDK) y `/bin/launchctl` para las acciones, con dominio explícito y sin shell.
  Como fallback cuando `launch_msg` no aplica (p. ej. `system` sin root) se parsea
  `launchctl print <domain>`.
- **No** se implementa el endpoint genérico de ejecución root del helper de LaunchControl. El
  daemon propio solo ejecuta operaciones concretas de `launchctl` y valida el cliente.
- `launchctl kickstart -k` se queda esperando en macOS 27 con servicios de larga duración;
  `restart` se implementa como `kill SIGTERM` + `kickstart`.

## Gráfico de batería (pestaña Energy)

Análisis con REA/Ghidra 12.2 sobre la build actual de Activity Monitor (arm64e, sha256
`2c5fddfd8a1c32e43592688a69ec91a9ffa64c78e1d0d491ceec92ef2d565200`). El gráfico de batería de la
pestaña Energy no es una serie que calcule la app: viene de `libsystemstats`.

| Función | Mecanismo | Evidencia |
|---|---|---|
| Datos | `systemstats_get_battery_charge_graph` importado de `/usr/lib/libsystemstats.dylib` (dyld cache); devuelve un `CFDictionary` con `charge_times`, `charge_levels`, `battery_times` y `battery_states` | `otool -L`, `dyld_info -imports`; `_refreshBatteryGraph:` 0x10000dbf0 → 0x10000dcfc |
| Ventana | 12 h = 43 200 s; `x = ancho · (1 − t/43200)`; descarta `t >> 6 ≥ 675` | `_processChargeTimes:` 0x10000d8bc; `_processBatteryStates:` 0x10000d40c |
| Estados | `battery_states`: **0 = en AC**, 1 = batería; las bandas AC salen de las transiciones | `_processBatteryStates:` (`TIME_ON_AC` cuando el último estado es 0) |
| Dibujo | rejilla discontinua `[6,3]` al 25/50/75 % en ambos ejes; bandas verdes (`systemGreen` α 0,3) a altura completa; polígono cerrado cian (`systemCyan`, 1 pt) con el nivel de carga | `BatteryGraphView::drawRect:` 0x100044a9c |

Comprobación directa con `dlopen` + `dlsym` como usuario sin privilegios: el diccionario contiene
las cuatro claves; en la prueba, `charge_times`/`charge_levels` con 141 puntos (segundos hacia
atrás) y `battery_times`/`battery_states` con las transiciones. La función usa convención «get»
(+0): el diccionario no se libera. Activity Monitor serializa la llamada en una cola privada.

En macOS 27.2 sobre un M1 Pro la misma llamada devolvió **una sola muestra**:
`charge_times=[37626]`, `charge_levels=[100]`, `battery_times=[37626]`, `battery_states=[0]`.
REA/Ghidra 12.2 confirma que Activity Monitor la sigue dibujando: `_processChargeTimes:`
(`0x10000d8bc`) arranca en la primera muestra dentro de 12 h (o en la más reciente si no hay
ninguna), toma opcionalmente la muestra inmediatamente anterior como ancla, fija el primer punto a
`x = 0` y **siempre añade un punto final en `x = ancho`** con el último nivel, así que una muestra
produce una línea plana. `_processBatteryStates:` (`0x10000d40c`) extiende el estado actual hasta el
borde derecho y calcula «Time on AC/Time on Battery» con `battery_times` del inicio del tramo de
estado actual. kancerbero replica ambas cosas y acepta `>= 1` muestra.

kancerbero replica el gráfico en la card Battery: `kb_battery_graph.c` carga la librería con
`dlopen`, serializa la llamada con un mutex y expone `kb_battery_charge_graph_read`;
`AppModel` refresca el dato como mucho una vez por minuto. La `CapacityBar` queda solo como
fallback cuando la API no está disponible o el diccionario está malformado; con una muestra
dibuja una línea plana y muestra el tiempo en la fuente actual.

## AppCleaner 3.7.0 (pestaña Applications)

Análisis con REA/Hopper (mismo motor que el resto del documento) y contraste con Ghidra 12.2 sobre
la slice arm64 de `/Applications/AppCleaner.app` (sha256
`1b30c99cc8f132885e2b85a94a3a79e4b87680863d32969181cca89ec35fdbf8`). AppCleaner no usa APIs
privadas del sistema; su lógica es NSFileManager + launchctl + un helper propio.

| Función | Mecanismo | Evidencia |
|---|---|---|
| Inventario | UTType application bundle en `/Applications` (nivel 3); plugins `UTType bundle` y widgets `com.apple.dashboard.widget` a nivel 1 | `-[ACBundle applicationBundlesInDirectory:]` 0x10001cbc4, `widgetBundlesInDirectory:` 0x10001cd64, `pluginBundlesInDirectory:` 0x10001cf28 |
| Leftovers | `fetchRelatedFiles` agrega preferencesFiles, miscFiles, containersFiles, savedStateFiles, agentsAndDaemonsFiles y logsFiles | `-[ACBundle fetchRelatedFiles]` 0x10001e550 |
| Misc | `libraryPaths`/`appSupportPaths`, PreferencePanes, Services, Safari/Extensions, `/Users/Shared`; con bundle id ≥ 8: Cookies, HTTPStorages, WebKit y ApplicationRecentDocuments | `-[ACBundle miscFiles]` 0x10001e990 |
| Contenedores | Containers + Application Scripts; `com.apple.security.application-groups` de los entitlements (scripts de grupo seleccionados, Group Containers no) | `-[ACBundle containersFiles]` 0x10001efc0 |
| Coincidencia | último componente normalizado; bundle id por `contains`/prefijo sin distinguir mayúsculas; nombres por **prefijo** (regex sensible a mayúsculas) de las variantes de `bundleName`/`bundleDisplayName`; al coincidir una carpeta no desciende | `relatedFilesInDirectories:maxDepth:matching:` 0x100020920 |
| Tamaños | `getAllocatedSize:ofItemAtURL:options:error:` | `-[ACFile fetchSize]` 0x100014810 |
| Borrado | descarga LaunchAgents, limpia `UF_IMMUTABLE`, `trashItemAtURL:` y, si falla por permisos, `ACHelperClient` privilegiado | `-[ACBundle recycle]` 0x100020f88 |

kancerbero replica las categorías, la coincidencia y el fallback de borrado: las rutas del
usuario se intentan con `FileManager.trashItem` y las de `/Library`/`/Applications` se envían al
daemon root (`trashItems`). Si `trashItem` falla por permisos (`NSFileWriteNoPermissionError` o
`EPERM`/`EACCES`, incluido el subyacente), el mismo ítem se reintenta en el lote del daemon y,
si este lo mueve, su resultado reemplaza al fallo local. Es el equivalente al
`ACPrivilegedTask`/`AuthorizationExecuteWithPrivileges` de AppCleaner
(`-[ACHelperClient moveFilesToTrash:reply:]`), sin diálogo de contraseña; el daemon de kancerbero
ya corre como root y se autodetuvo/relanzó vía launchd cuando el binario en ejecución era anterior
a `trashItems`. El handshake anuncia `trash` en `KBCapabilities` para que el cliente no envíe
peticiones a un daemon antiguo.

Los contenedores de otras apps (`~/Library/Containers`, group containers y application scripts)
están protegidos por TCC aunque el usuario sea el propietario. La app los intenta primero y, si
macOS la deniega, el daemon root reintenta; TCC también se aplica a root, así que sin Acceso Total
al Disco el reintento devuelve `code == "permission"` y la app ofrece abrir ese ajuste. Conceder
Acceso Total al Disco a `uno.kayros.kancerbero` cubre app y daemon (mismo identificador y
`AssociatedBundleIdentifiers`).

Rutas y matcher concretos: `Resources/BundlePaths.plist` define `System/User Applications`
(`/Applications`, `~/Applications`), `System/User Plugins` (Contextual Menu Items, InputManagers,
Internet Plug-Ins, Mail/Bundles, PreferencePanes, QuickLook, QuickTime, Screen Savers, Spotlight) y
`System/User Widgets` (`/Library/Widgets`, `~/Library/Widgets`). `relatedFilesInDirectories:` invoca
la variante con `maxDepth:0` (profundidad ilimitada) sobre todo `~/Library` y `/Library`; el matcher
acepta el bundle id por `contains` (≥8 caracteres) o prefijo (≥4, sin distinguir mayúsculas) y los
nombres por **prefijo** de las variantes de `bundleName`/`bundleDisplayName` sin extensión (regex
sensible a mayúsculas), y al coincidir un directorio no desciende. Por eso Claude suma, además de
sus preferencias/caches/logs, los tres workflows `Claude - …` de `~/Library/Services` y
`Developer/Xcode/CodingAssistant/ClaudeAgentConfig`: 12 relacionadas + el bundle = 13 entradas,
como en AppCleaner. En este Mac, Antigravity produce 4 relacionadas
(`Application Support/Antigravity`, `Application Support/Logi/.../com.google.antigravity.png`,
`Preferences/com.google.antigravity.plist`, `Logs/Antigravity`) y, con el bundle de la app, las 5
entradas que muestra la app.
