# Seguridad

## Modelo

- La app no está sandboxeada y usa APIs privadas; no es apta para App Store.
- El daemon se registra con `SMAppService` y corre como root; no hay modos legacy de instalación
  ni helpers instalados con `sudo`. El plist legado `.v2` que se incrusta temporalmente es inerte:
  no se registra y solo permite desregistrar el servicio anterior durante la migración.
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
  `PROC_PIDTBSDINFO`. Además lee temperaturas con símbolos privados de IOHID
  (`IOHIDEventSystemClient*`, `IOHIDServiceClientCopyEvent`, `IOHIDEventGetFloatValue`),
  resueltos con `dlopen`/`dlsym`: son de solo lectura, no requieren root y degradan a `—` si no
  existen. No se añaden entitlements ni frameworks privados enlazados.
- Sin root, macOS solo enumera y expone procesos del uid actual (`proc_listallpids` incluido).
  Con el daemon root se ven todos; el daemon no necesita entitlements adicionales.
- Los contadores de procesos de otro uid no legibles se marcan como no disponibles (`—`), nunca
  como 0. `kill` se limita a lo descrito en «Terminar procesos (kill)»; no se implementan renice
  ni `task_for_pid`.
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
- Firma Developer ID del daemon y de la app, hardened runtime, notarización. El daemon se firma
  con el **mismo identificador de code signing que la app** (`-i uno.kayros.kancerbero`) y **sin
  entitlements**: ServiceManagement deriva el launch constraint del job del requisito de la app,
  y un tool con identificador propio o un entitlement restringido sin profile embebido muere al
  arrancar (`Launch Constraint Violation`). Hereda el `DEVELOPMENT_TEAM` del proyecto para que
  Xcode pueda firmarlo con Developer ID, pero no lleva App ID ni provisioning profile;
  `build-release.sh` verifica el binario firmado.
- Despliegue con `SMAppService.daemon(plistName:)`: el helper y el plist van dentro de
  `Kancerbero.app/Contents/Library/LaunchDaemons/`; la app los registra y el usuario aprueba en
  Ajustes → Login Items → Allow in the Background. El icono y el nombre se resuelven mediante
  `AssociatedBundleIdentifiers` y el registro de la app.
- El daemon registrado exige app **notarizada**; una build ad-hoc puede mostrar el estado pero
  `register()` no es fiable. El cliente XPC usa `NSXPCConnection` con `.privileged`.

## Acciones sobre servicios launchd

- `DaemonDelegate` calcula `canControl` por conexión: en desarrollo acepta la ruta de
  `Kancerbero.app` o un cliente del mismo uid; las denegaciones se registran. Producción debe usar
  `setCodeSigningRequirement` + Team ID.
- El daemon solo acepta acciones del dominio `system`; `gui`/`user` se ejecutan en la app.
- `LaunchctlRunner` ejecuta únicamente operaciones concretas de `/bin/launchctl` con dominio y
  label validados (`^[A-Za-z0-9._-]+$`). No hay shell, launchPath libre ni ejecución arbitraria.
- Límite de 10 acciones/minuto por cliente y una acción en vuelo; timeout de 5–10 s.
- La UI pide confirmación para acciones de sistema y para stop/disable.

## Terminar procesos (kill)

- **Dos rutas.** Un proceso del mismo uid se señala en la app con `kill(2)` directamente
  (`ProcessSignaler.signalLocally`); funciona sin daemon. Un proceso de otro uid o de root se envía
  al daemon root por XPC (`processSignal`) y exige autorización de administrador. Si el daemon no
  anuncia `KBCapabilities.kill`, la UI deshabilita la ruta privilegiada; el mismo uid sigue
  funcionando en local.
- **Solo `SIGTERM` y `SIGKILL`.** El wire transporta un enum (`terminate`/`forceKill`), nunca un
  número de señal. No se señalan grupos (`killpg`), PIDs negativos ni PIDs ≤ 1. La UI siempre pide
  confirmación con dos botones explícitos; `Terminate` no escala solo a `Force Kill`.
- **Identidad revalidada.** Cada petición lleva `pid`, `startTimeUS` y `expectedUID` obligatorios
  (y `expectedPath` cuando se conoce). App y daemon re-resuelven la identidad con
  `proc_pidinfo(PROC_PIDTBSDINFO)` inmediatamente antes de la señal; si el pid se reutilizó o el uid
  no coincide, se rechaza con `stale`/`notfound`. El daemon repite la comprobación justo antes de
  `kill` para reducir la ventana TOCTOU (macOS no ofrece `pidfd`; la ventana residual es de
  microsegundos).
- **Lista protegida siempre.** Se rechazan incluso con autorización de administrador:
  `kernel_task`, `launchd`, `WindowServer`, `loginwindow`, `securityd`, `syspolicyd`, `tccd`,
  `trustd`, `amfid`, `authd`, `SecurityAgent`, `coreauthd`, `configd`, `notifyd`, `distnoted`,
  `opendirectoryd`, `launchservicesd`, `runningboardd`, `watchdogd`, `powerd`,
  `thermalmonitord`, `coreduetd`, `Kancerbero`, `KancerberoDaemon` y `KancerberoFilter`; cualquier
  ruta dentro de `Kancerbero.app`; y los procesos de usuarios del sistema ajenos (uid < 500, salvo
  root). Los servicios launchd se gestionan con la parada existente, no por PID.
- **Endurecimiento por ruta solo al elevar.** Los prefijos `/System/`, `/usr/libexec/`,
  `/usr/sbin/`, `/sbin/`, `/Library/Apple/` y la exigencia de un path conocido se aplican cuando la
  petición está elevada: otro uid, un objetivo root, la app corriendo como root o un peer XPC root.
  Para el propio uid sin elevación no se consulta el path: el kernel ya permite `kill(2)` y muchos
  procesos legítimos del usuario (Finder, Safari, agentes en `/usr/libexec`) viven en esas rutas.
  La denylist de nombres sigue siendo la protección efectiva de los daemons de sesión
  (`loginwindow`, `tccd`, `distnoted`, `securityd`). El path que usa la política es siempre el
  recién resuelto con `proc_pidpath` antes de decidir y de matar, no el de una fila antigua o
  fusionada sin path: `expectedPath` es una comprobación best-effort, no una entrada de
  autorización.
- **Autorización de administrador.** La app pide el right `system.privilege.admin`
  (`kAuthorizationRightExecute`) con `.interactionAllowed | .extendRights | .preAuthorize` y un
  prompt que nombra el proceso y el PID. El `AuthorizationRef` vive solo durante la petición; el
  daemon recibe el **external form de 32 bytes**, lo internaliza con
  `AuthorizationCreateFromExternalForm` y valida el right con `AuthorizationCopyRights` y flags
  **vacíos**. Es crítico no usar `ExtendRights` en el daemon: el authdb de macOS tiene
  `allow-root = true` para ese right y root se autoautorizaría sin el prompt del usuario.
  `AuthorizationSemanticsTests` verifica ambas premisas. El form es un bearer temporal: nunca se
  persiste, nunca se loguea y se borra de memoria tras usarlo.
- **Cliente autorizado.** `processSignal` solo se acepta si la conexión pasó `canSignal` (en
  Release, el mismo requisito de firma que `trashItems`; en Debug, la ruta de `Kancerbero.app`).
  El uid que decide la política es el del peer XPC, nunca el euid del daemon.
- **Límites y auditoría.** Una petición en vuelo y 10/minuto por cliente. Se registra con
  `os.Logger` pid, uid, `startTimeUS`, señal, si hubo autorización administrativa, el peer y el
  resultado; jamás el external form ni credenciales.

## Superficie de ataque

- Los mensajes XPC se decodifican con `PropertyListDecoder` desde `Data`; un payload inválido
  devuelve `NSError` y no tumba el servicio.
- `pid` se valida > 0 antes de usarlo en libproc; no se pasa a ninguna shell.
- Las únicas rutas de fichero que llegan del cliente son las de `trashItems` (revalidadas con
  `realpath` y `KBPathPolicy`) y el `expectedPath` opcional de `processSignal`, que solo se compara
  con la ruta resuelta por el daemon. No se abre ni se ejecuta nada de lo que envía el cliente.
- Límites por operación: 32 MB de payload, 4 clientes, una operación en vuelo y 10/minuto para
  señales y acciones launchd, 6/minuto para borrados. Ver «Terminar procesos (kill)».

## Filtro de red (system extension)

- La system extension corre como **root y sandboxeada**, sin sesión de usuario ni UI. No comparte
  App Group ni `UserDefaults(suiteName:)` con la app: intentar usarlos daría dos
  almacenamientos distintos (el del usuario y el de root).
- El único canal es su Mach service (`NEMachServiceName`), que está en el namespace global. La
  extensión valida al cliente con `setConnectionCodeSigningRequirement` (identificador de la app
  + Team ID) antes de aceptar `setRules`/`decide`; cualquier otro proceso queda rechazado.
- La entrada de reglas y decisiones es pequeño y acotado: payload ≤ 1 MB, reglas y decisiones
  recordadas por ruta de ejecutable, `pending` máximo 32 flujos pausados, snapshot de flujos
  acotado (2.000 activos + 200 en historial). Cada mensaje se decodifica con
  `PropertyListDecoder` desde `Data`; un payload inválido se descarta.
- La extensión no lee contenido de paquetes: `NEFilterDataProvider` entrega metadatos de flujo y
  contadores agregados. No hay captura de payloads y el tráfico excluido por Apple no se
  contabiliza.
- Datos persistidos por la extensión en su propio container: reglas y decisiones recordadas
  (ruta de ejecutable, destino opcional, allow/deny). Los flujos y el historial viven solo en
  memoria y se envían a la app por XPC.
- Datos persistidos por la app: reglas y decisiones recordadas en `UserDefaults`; son la copia
  editable y se sincronizan al conectar.
- Fail-closed: un flujo vigilado sin decisión (app cerrada, cliente XPC desconectado, timeout de
  60 s TCP / 8 s UDP, o tope de flujos pausados) se **deniega** y se registra el motivo. Los
  flujos pausados se resuelven con `drop` al pararse el filtro o invalidarse el cliente.
- Los logs (`subsystem uno.kayros.kancerbero.filter`) no incluyen endpoints completos ni
  contenido; solo identificadores y motivos.
- Entitlements restringidos: `content-filter-provider-systemextension` en app y extensión,
  `system-extension.install` en la app. Requieren Developer ID + provisioning profiles
  embebidos; una build ad-hoc no puede activar el filtro y la UI lo indica.

## Desinstalador (pestaña Applications)

- El daemon acepta la petición `trashItems` solo para clientes autorizados. En Release el listener
  exige `setCodeSigningRequirement` con el identificador `uno.kayros.kancerbero` y el Team ID, y
  revalida cada petición con `SecCodeCopyGuestWithAttributes` + `SecCodeCheckValidity`. En Debug
  (build sin firma) se usa la ruta del ejecutable dentro de `Kancerbero.app`; es una comodidad de
  desarrollo, no una frontera de seguridad.
- Cada ruta se revalida en el daemon: absoluta, padre resuelto con `realpath`, componente final
  verbatim (un symlink se mueve, nunca se sigue su destino), dentro de `KBPathPolicy` y fuera de
  sus raíces protegidas. El `bundleIdentifier` del payload no se usa para autorizar.
- La protección de bundles sigue a SIP, no a la firma: las apps Apple instaladas en
  `/Applications` (Xcode, Developer…) se pueden mover con permisos de administrador; `/System` y
  los bundles cuyo destino resuelto cae en `/System` (por ejemplo `Safari.app`, symlink a
  `/System/Cryptexes`) siguen rechazados. También se rechazan el propio `Kancerbero.app`/daemon y
  cualquier bundle que sea un symlink.
- `KBCapabilities.trash` distingue un daemon actualizado de uno anterior. Si el cliente necesita
  privilegios y el daemon conectado no anuncia la capacidad, `AppModel.restartDaemonService()`
  pide al propio daemon que se detenga (`daemonAction` → `launchctl kill SIGTERM system/…`) y
  reconecta durante un máximo de 15 s. `KeepAlive.SuccessfulExit=false` hace que launchd lo
  relance con el binario instalado, así que el reinicio no pide contraseña. Cada conexión lleva
  una generación; los callbacks de una conexión vieja se descartan para no pisar a la nueva.
- El primer intento de borrado es local cuando `KBPathPolicy.requiresPrivilege` lo permite. Si
  `FileManager.trashItem` falla por permisos, el ítem se reenvía al daemon root en el mismo lote
  y el resultado privilegiado reemplaza al local. Esto cubre datos de otras apps protegidos por
  TCC (`kTCCServiceSystemPolicyAppDataDetailed`), como `~/Library/Containers`; la lista blanca y
  la revalidación del daemon no cambian.
- TCC se aplica también a procesos root: si el daemon tampoco tiene Acceso Total al Disco, el
  reintento falla con `code == "permission"`. La app no intenta `removeItem` ni ninguna vía que
  evite TCC; muestra la ruta afectada y ofrece abrir Ajustes del Sistema → Privacidad y seguridad
  → Acceso Total al Disco. Una concesión para `uno.kayros.kancerbero` cubre app y daemon porque
  comparten identificador y `AssociatedBundleIdentifiers`.
- El movimiento va a `~usuario/.Trash` con el uid tomado de la conexión XPC (nunca del payload),
  nombre único, `chown` recursivo al usuario, limpieza de `UF_IMMUTABLE` y `launchctl bootout` de
  LaunchAgents/Daemons antes de mover.
- Límites: 32 ítems por lote, 256 por petición, 6 peticiones/minuto con una en vuelo y resultado
  por ruta. Las rutas escribibles del usuario no pasan por el daemon: la app usa
  `FileManager.trashItem`.

## Acceso Total al Disco (FDA)

- macOS no ofrece una API pública para consultar si la app tiene FDA. `KBFullDiskAccessProbe`
  hace una comprobación heurística: abre en solo lectura (`open(O_RDONLY)`, sin leer contenido ni
  enumerar directorios) rutas que TCC protege con `SystemPolicyAllFiles`: `~/Library/Safari/History.db`,
  `Bookmarks.plist`, `~/Library/Messages/chat.db`, `~/Library/Mail`, el group container de Notes y
  el `TCC.db` de usuario en macOS antiguos. Un `open` correcto demuestra el permiso; `EPERM`/`EACCES`
  (clasificado con `KBTrashError.isPermissionDenied`) lo deniega; si ninguna ruta existe, el estado
  es `unknown` y la UI no afirma que falte.
- La sonda no usa APIs privadas, no genera prompts, no ejecuta comandos y no lee datos. Se ejecuta
  fuera del main actor y `AppModel` la limita (una comprobación por segundo como máximo, con guarda
  de petición en vuelo).
- El estado aparece en **System status** (Data access → Full Disk Access) y en un banner de
  **Applications**. La guía abre Privacidad y seguridad → Acceso Total al Disco con URLs públicas
  (formato macOS 26 y fallback al anterior); nunca se usa `sudo`.
- No se consulta el daemon: FDA está ligada a la identidad de firma `uno.kayros.kancerbero`, que
  comparten app y helper, y TCC también se aplica a root. `hasFullDataAccess` (acceso root del
  daemon) y FDA son conceptos distintos; la UI los presenta por separado.

## Actualizaciones (Sparkle 2)

- **Firma EdDSA.** La clave privada vive en el Keychain (cuenta `kancerbero-ed25519`); la pública
  está en `SUPublicEDKey` (`Resources/App/Info.plist`). `generate_appcast` firma cada ZIP y
  `sign_update` firma el appcast. La app tiene `SUVerifyUpdateBeforeExtraction` y
  `SURequireSignedFeed`: rechaza un archivo o un feed sin firma válida antes de extraer nada.
- **HTTPS.** El feed está en GitHub Pages (`https://kayrosuno.github.io/kancerbero/appcast.xml`) y
  los binarios en GitHub Releases. No hay excepciones ATS en Release y la app no está
  sandboxeada, así que no necesita entitlements de red.
- **Integridad y downgrade.** Sparkle compara el `CFBundleVersion` de la **app**, un timestamp
  `YYMMDDHHMM` (10 dígitos) estrictamente creciente generado en cada build; el último componente
  de `CFBundleShortVersionString` es exactamente ese build. Los builds de daemon y filtro son
  identidades separadas, anotadas en `Config/ComponentVersions.xcconfig` y estables mientras no
  cambie su componente; sus versiones también terminan en su build y no participan en la
  comparación de Sparkle. Un appcast comprometido no puede instalar un build menor ni un archivo
  sin la firma de la clave privada.
- **Clave privada.** Nunca se commitea. Debe tener copia de seguridad cifrada: si se pierde, las
  instalaciones existentes no podrán validar actualizaciones futuras y la recuperación exige una
  versión con clave nueva instalada manualmente. No hay rotación silenciosa.
- **Credenciales de publicación.** `publish-release.sh` usa `gh` autenticado (`gh auth login`) o,
  como alternativa, un PAT con `Contents: Read and write` guardado en el Keychain. Ni el PAT ni el
  token se commitean ni se pasan por argumentos.
- **Publicación verificable.** `build-release.sh` comprueba que el `Label` y `MachServices` del
  plist coinciden con la constante XPC; `generate-appcast.sh` rechaza un item que no sea más nuevo
  que el feed; `publish-release.sh` es idempotente y el appcast se publica después del asset.
- **Post-actualización.** El daemon viejo se detecta comparando `daemonBuild` con
  `KBVersion.daemonBuild` (no con el marketing de la app) y se reinicia con el
  `daemonAction .stop` ya autorizado por `DaemonClientPolicy` (Developer ID, team
  `AK37TK8X2Y`); si falla, se re-registra el servicio. La system extension se reemplaza con su
  `CFBundleVersion` nuevo y una activation request `.replace`; la app compara el ACK con
  `FilterVersion.expectedBuild`. Un build de la app que no cambia esos componentes no los
  reinicia ni los reemplaza.
- **TCC.** El reemplazo es in-place, con el mismo bundle id, ruta y team; FDA debe conservarse. No
  cambiar bundle id ni team en un release. La identidad del servicio es
  `uno.kayros.kancerbero.daemon.service`; cambiarla otra vez exige desregistrar el label anterior
  y pedir de nuevo la aprobación en Login Items.
- **No se usa un `sha256` del feed como seguridad** (el error del updater de Otty): la garantía es
  la firma EdDSA verificada por Sparkle, más la notarización y la firma de código del bundle.
