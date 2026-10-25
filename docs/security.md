# Seguridad

## Modelo

- La app no está sandboxeada y usa APIs privadas; no es apta para App Store.
- El daemon de desarrollo corre como root vía LaunchDaemon cuando se instala con
  `sudo scripts/install-daemon.sh`; el LaunchAgent de usuario corre sin privilegios y solo ve el
  uid actual.
- El daemon solo expone lectura de inventario (procesos, sockets, ficheros, contadores y
  CPU/memoria). No lee contenido de ficheros, no ejecuta comandos y no escribe en disco.

## Pestaña Disk

- El inventario usa IOKit (`IOMedia`, `AppleAPFSMedia`, `AppleAPFSVolume`), DiskArbitration
  (`DADiskCreateFromIOMedia`/`DADiskCopyDescription`), `getmntinfo` y
  `getattrlist(ATTR_VOL_*)`. Son APIs públicas y de solo lectura.
- La app **no** ejecuta `diskutil` ni ningún otro proceso para Disk. La información detallada se
  obtiene directamente del sistema.
- El escáner usa `open(O_RDONLY|O_DIRECTORY)` + `getattrlistbulk` por directorio. Solo lee
  metadatos (nombre, tipo, tamaños); nunca abre ni lee el contenido de los ficheros.
- No hay acciones destructivas: no se borra, mueve, monta, desmonta ni reparticiona. Las únicas
  acciones son revelar en Finder, copiar identificadores y lanzar el analizador.
- Los errores de permisos se registran como rutas denegadas y se muestran en la UI; no se eleva
  privilegios ni se recurre al daemon root.
- El daemon y su superficie XPC no cambian.

## Pestaña CPU

- Usa APIs públicas de solo lectura: `host_processor_info`, `host_statistics64`, `getloadavg`,
  `sysctlbyname("vm.swapusage")`, `sysctl(KERN_BOOTTIME)`, `PROC_PIDTASKALLINFO` y
  `PROC_PIDTBSDINFO`. No se añaden entitlements ni frameworks privados.
- Sin root, macOS solo enumera y expone procesos del uid actual (`proc_listallpids` incluido).
  Con el daemon root se ven todos; el daemon no necesita entitlements adicionales.
- Los contadores de procesos de otro uid no legibles se marcan como no disponibles (`—`), nunca
  como 0. No se implementan kill, renice ni `task_for_pid`.
- `getpwuid_r` puede bloquear con cuentas de DirectoryService; se ejecuta en un task detached y
  se cachean resultados positivos y negativos. Nunca se llama desde el hilo principal.
- No se lee contenido de ficheros ni se ejecutan comandos para obtener estas métricas.

## Autorización XPC

Estado actual (desarrollo):

- `NSXPCListener` acepta conexiones locales.
- Se registra `pid`, `effectiveUserIdentifier` y la ruta del cliente con `os.Logger`.
- La política de inspector sigue el modelo del kernel: `proc_pidfdinfo` solo funciona para el
  mismo uid salvo que el daemon sea root. `proc_listallpids`/`proc_pidinfo` tienen el mismo
  límite: sin root solo se enumeran procesos del uid actual.
- El inventario agregado de sockets (`kb_socket_summary_all`) usa la misma política: sin root
  solo se leen sockets del uid actual. Solo se envían **conteos** (protocolo, tipo, total,
  restringido/truncado), sin direcciones, puertos ni rutas UNIX. El barrido se ejecuta en
  background cada ~10 s, no en cada refresco.
- El snapshot incluye CPU/memoria agregadas y contadores por proceso; no contiene rutas de
  ficheros abiertos ni contenido. `hostMetrics` es opcional para mantener compatibilidad con
  daemons anteriores.

Pendiente para producción:

- `newConnection.setCodeSigningRequirement(...)` con identificador y Team ID.
- Verificación adicional con `SecCodeCopyGuestWithAttributes(kSecGuestAttributePid)` +
  `SecCodeCheckValidity`.
- Allowlist de desarrollo por `proc_pidpath`/cdhash (el instalador puede escribirla en el plist).
- Límites: 4 clientes, 1 inspector en vuelo por cliente, 10 peticiones/min, payload ≤ 32 MB.
- Firma Developer ID del daemon y de la app, hardened runtime, notarización.
- Despliegue con `SMAppService.daemon(plistName:)`: el helper y el plist van dentro de
  `Kancerbero.app/Contents/Library/LaunchDaemons/`; la app los registra y el usuario aprueba en
  Ajustes → Login Items → Allow in the Background. El icono y el nombre se resuelven mediante
  `AssociatedBundleIdentifiers` y el registro de la app.
- El daemon registrado exige app **notarizada**; una build ad-hoc puede mostrar el estado pero
  `register()` no es fiable. El cliente XPC usa `NSXPCConnection` con `.privileged`.
- Antes de registrar hay que eliminar los plists legacy (`install-agent.sh`/`install-daemon.sh`):
  comparten label/Mach service con el daemon SMAppService.

## Acciones sobre servicios launchd

- `DaemonDelegate` calcula `canControl` por conexión: en desarrollo acepta la ruta de
  `Kancerbero.app` o un cliente del mismo uid; las denegaciones se registran. Producción debe usar
  `setCodeSigningRequirement` + Team ID.
- El daemon solo acepta acciones del dominio `system`; `gui`/`user` se ejecutan en la app.
- `LaunchctlRunner` ejecuta únicamente operaciones concretas de `/bin/launchctl` con dominio y
  label validados (`^[A-Za-z0-9._-]+$`). No hay shell, launchPath libre ni ejecución arbitraria.
- Límite de 10 acciones/minuto por cliente y una acción en vuelo; timeout de 5–10 s.
- La UI pide confirmación para acciones de sistema y para stop/disable.

## Superficie de ataque

- Los mensajes XPC se decodifican con `PropertyListDecoder` desde `Data`; un payload inválido
  devuelve `NSError` y no tumba el servicio.
- `pid` se valida > 0 antes de usarlo en libproc; no se pasa a ninguna shell.
- No hay ninguna ruta que reciba rutas de fichero del cliente.
- Los límites de tamaño (32 MB) y de frecuencia aún no están implementados; ver la lista
  pendiente.
