# Seguridad

## Modelo

- La app no está sandboxeada y usa APIs privadas; no es apta para App Store.
- El daemon de desarrollo corre como root vía LaunchDaemon cuando se instala con
  `sudo scripts/install-daemon.sh`; el LaunchAgent de usuario corre sin privilegios y solo ve el
  uid actual.
- El daemon solo expone lectura de inventario (procesos, sockets, ficheros, contadores). No lee
  contenido de ficheros, no ejecuta comandos y no escribe en disco.

## Autorización XPC

Estado actual (desarrollo):

- `NSXPCListener` acepta conexiones locales.
- Se registra `pid`, `effectiveUserIdentifier` y la ruta del cliente con `os.Logger`.
- La política de inspector sigue el modelo del kernel: `proc_pidfdinfo` solo funciona para el
  mismo uid salvo que el daemon sea root.

Pendiente para producción:

- `newConnection.setCodeSigningRequirement(...)` con identificador y Team ID.
- Verificación adicional con `SecCodeCopyGuestWithAttributes(kSecGuestAttributePid)` +
  `SecCodeCheckValidity`.
- Allowlist de desarrollo por `proc_pidpath`/cdhash (el instalador puede escribirla en el plist).
- Límites: 4 clientes, 1 inspector en vuelo por cliente, 10 peticiones/min, payload ≤ 32 MB.
- Firma Developer ID del daemon y de la app, hardened runtime, notarización.
- Migración a `SMAppService.daemon(plistName:)` para el despliegue.

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
