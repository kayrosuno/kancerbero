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
