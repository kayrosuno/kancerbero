# Daemons y librerías

Este documento describe los artefactos ejecutables de kancerbero —daemons, system extension y
herramienta de diagnóstico— y todas las librerías que compila. El proyecto es un
`Kancerbero.xcodeproj` con siete targets: no hay Swift Package, `.dylib`, `.framework` ni
`.xcframework`; las librerías son **static libraries** que se enlazan dentro de cada consumidor y
no se instalan por separado.

Hay tres ejecutables en background:

- **`KancerberoDaemon`**: daemon launchd con servidor XPC. Aporta la recolección privilegiada y
  el control de servicios launchd del dominio `system`.
- **`KancerberoFilter`**: system extension de Network Extension. Es el filtro de red que observa
  flujos y pide allow/deny para procesos vigilados.
- **`KancerberoProbe`**: CLI de diagnóstico. No se instala; solo sirve para comprobar las fuentes
  de datos y comparar con las herramientas del sistema.

`Kancerbero.app` no es un daemon: es el consumidor de las librerías y el embebedor del daemon y
de la system extension. Tampoco existen XPC services, helpers `SMJobBless` ni ningún otro
artefacto con plist propio.

## Resumen

### Ejecutables en background

| Componente | Tipo | Producto | Se ejecuta como | Para qué se usa |
|---|---|---|---|---|
| `KancerberoDaemon` | tool + LaunchDaemon/Mach service | `KancerberoDaemon` | root con `SMAppService` o LaunchDaemon; usuario en el LaunchAgent legacy | Procesos, sockets, CPU/memoria e interfaces de todos los uid; inventario y acciones de servicios launchd del dominio `system` |
| `KancerberoFilter` | system extension (`NEFilterDataProvider`) | `uno.kayros.kancerbero.filter.systemextension` | root, App Sandbox, sin UI ni sesión | Filtro de red: identifica el proceso de cada flujo, aplica reglas allow/deny y pausa conexiones para pedir aprobación |
| `KancerberoProbe` | tool CLI (sin instalación) | `KancerberoProbe` | el usuario que lo lanza (root opcional) | Diagnóstico manual de NetworkStatistics, libproc, interfaces, launchd y disco |

### Librerías

| Librería | Tipo | Producto | Consumidores | Para qué se usa |
|---|---|---|---|---|
| `KancerberoC` | static lib C (Clang module) | `libKancerberoC.a` | `KancerberoCore`, app, daemon y probe | Puente C a `NetworkStatistics.framework` (`dlopen`/`dlsym`), libproc, sysctl/IFMIB, `launch_msg`, IOKit/DiskArbitration y `getattrlistbulk` |
| `KancerberoCore` | static lib Swift | `libKancerberoCore.a` | app, daemon y probe | Modelos, wire codec, protocolos XPC, collectors de todas las fuentes y diagnóstico de capacidades |
| `KancerberoFilterContract` | static lib Swift | `libKancerberoFilterContract.a` | app y `KancerberoFilter` | Contrato `Codable` y protocolos XPC que comparten la app y la system extension |

### Dependencias

```
Kancerbero.app ───┬──> KancerberoCore ──> KancerberoC
KancerberoDaemon ─┤
KancerberoProbe ──┘

Kancerbero.app ──────> KancerberoFilterContract <────── KancerberoFilter
```

- `KancerberoCore` depende de `KancerberoC`; la app, el daemon y el probe enlazan ambas.
- La system extension **no** enlaza `KancerberoCore` ni `KancerberoC`: solo
  `KancerberoFilterContract`, para no arrastrar libproc, sysctl ni la API privada al sandbox.
- El daemon y la extensión no comparten código: la app enlaza `KancerberoCore` para hablar con
  el daemon y `KancerberoFilterContract` para hablar con la extensión.

### Etiquetas, servicios y rutas

| Etiqueta o servicio | Artefacto | Dónde vive | Quién lo registra |
|---|---|---|---|
| `uno.kayros.kancerbero.daemon.v2` (Mach service) | `KancerberoDaemon` | proceso del daemon | `NSXPCListener` del daemon |
| `uno.kayros.kancerbero.daemon.v2` (LaunchDaemon) | `KancerberoDaemon` + `uno.kayros.kancerbero.daemon.plist` | `Kancerbero.app/Contents/Library/LaunchDaemons/` | `SMAppService.daemon(plistName:)` |
| `uno.kayros.kancerbero.daemon` (LaunchDaemon legacy) | plist legacy | `/Library/LaunchDaemons/uno.kayros.kancerbero.daemon.plist` + `/Library/PrivilegedHelperTools/uno.kayros.kancerbero.daemon` | `scripts/install-daemon.sh` |
| `uno.kayros.kancerbero.agent` (LaunchAgent legacy) | `KancerberoDaemon` | `~/Library/LaunchAgents/uno.kayros.kancerbero.agent.plist` | `scripts/install-agent.sh` |
| `group.uno.kayros.kancerbero.filter` (Mach service) | `KancerberoFilter` | system extension | `NEMachServiceName` del Info.plist |

El daemon de `SMAppService` usa la identidad `uno.kayros.kancerbero.daemon.v2`; los modos legacy
conservan el label y el Mach service antiguos (`uno.kayros.kancerbero.daemon`). La app sigue
negándose a registrar el servicio moderno si detecta un registro legacy, y los dos no deben
convivir. El sufijo `.v2` existe para escapar de registros de ServiceManagement/BTM creados por
versiones anteriores: macOS guarda un *launch constraint* por label y, si ya no coincide, volver
a registrar el mismo label no lo refresca (`Launch Constraint Violation` al arrancar). La system
extension usa un Mach service distinto y es independiente del daemon.

## KancerberoDaemon

### Ficha técnica

| Campo | Valor |
|---|---|
| Target | `KancerberoDaemon` |
| Tipo | `com.apple.product-type.tool` (ejecutable suelto) |
| Producto | `KancerberoDaemon` |
| Bundle ID | ninguno (tool sin Info.plist); identificador de firma `uno.kayros.kancerbero` |
| Mach service | `uno.kayros.kancerbero.daemon.v2` |
| Fuentes | `Sources/KancerberoDaemon/main.swift`, `DaemonDelegate.swift`, `DaemonService.swift` |
| Configuración | `Config/KancerberoDaemon.xcconfig` |
| Módulos | `KancerberoCore` (y `KancerberoC` por debajo) |
| Frameworks | CoreFoundation, Security, IOKit, DiskArbitration |
| Deployment target | macOS 15.6 |
| Firma | Debug ad-hoc; Release Developer ID + hardened runtime + timestamp, sin entitlements, identificador `-i uno.kayros.kancerbero` |

`main.swift` exige el argumento `--daemon`. Sin él imprime la versión, la versión del core y el
`euid`, y sale con código 0; es la forma de comprobar qué binario se va a ejecutar.

### Dónde se instala y se ejecuta

Hay tres modos, y solo uno debe estar activo a la vez:

| Modo | Binario | Plist y dominio | Permisos | Logs |
|---|---|---|---|---|
| `SMAppService` (distribución) | `Kancerbero.app/Contents/Library/LaunchDaemons/KancerberoDaemon` | `uno.kayros.kancerbero.daemon.plist` embebido en la app; lo registra `SMAppService.daemon(plistName:)` | root | `os.Logger` (subsystem `uno.kayros.kancerbero`) |
| LaunchDaemon legacy | `/Library/PrivilegedHelperTools/uno.kayros.kancerbero.daemon` | `/Library/LaunchDaemons/uno.kayros.kancerbero.daemon.plist`, dominio `system` | root | `os.Logger` + `/Library/Logs/Kancerbero/daemon.{out,err}.log` |
| LaunchAgent legacy | `build/Build/Products/<Config>/KancerberoDaemon` | `~/Library/LaunchAgents/uno.kayros.kancerbero.agent.plist`, dominio `gui/<uid>` | usuario | `os.Logger` + `~/Library/Logs/Kancerbero/agent.{out,err}.log` |

En el modo de distribución la app embebe el binario y el plist con la fase `Embed Daemon`
(destino `Contents/Library/LaunchDaemons`), y macOS ejecuta el helper desde dentro del bundle.
La aprobación se hace en **Ajustes → General → Login Items & Extensions → Allow in the
Background**; el plist declara `AssociatedBundleIdentifiers` para que el ítem muestre el nombre y
el icono de Kancerbero.

La ventana **System status** expone el registro, la aprobación y **Repair / re-register**
(desregistrar y volver a registrar para que macOS pida la aprobación de nuevo). No ejecuta
`sudo` ni scripts: los comandos legacy se copian al portapapeles.

El plist de `SMAppService` contiene:

| Clave | Valor | Efecto |
|---|---|---|
| `Label` | `uno.kayros.kancerbero.daemon.v2` | Identidad launchd |
| `BundleProgram` | `Contents/Library/LaunchDaemons/KancerberoDaemon` | Binario dentro del bundle |
| `ProgramArguments` | `KancerberoDaemon --daemon` | Arranque del modo XPC |
| `MachServices` | `uno.kayros.kancerbero.daemon.v2` | Endpoint XPC |
| `RunAtLoad` | `true` | Arranca al registrarse |
| `KeepAlive.SuccessfulExit` | `false` | Relanza si termina con error |
| `ThrottleInterval` | `5` | Espera mínima entre relanzamientos |
| `ProcessType` | `Interactive` | Clase de scheduling |

### Permisos y firma

- LaunchDaemon y `SMAppService` arrancan el proceso como **root**. Con `euid == 0` el daemon
  publica el modo `daemonFull` y puede enumerar procesos, sockets, ficheros y contadores de
  cualquier uid. Sin root publica `daemonRestricted` y solo ve el uid actual; `main.swift` deja
  un aviso en el log.
- No hay entitlements ni App Sandbox en este target: las APIs que usa (libproc, sysctl, IOKit,
  DiskArbitration) no los necesitan. La API privada `NetworkStatistics.framework` se carga con
  `dlopen` y funciona sin entitlement mientras `net.statistics_privcheck` valga 0.
- El `.entitlements` del daemon está vacío a propósito. Un ejecutable suelto no puede reclamar
  `com.apple.application-identifier` sin un provisioning profile embebido (TN3125); si Xcode lo
  inyecta, añade `PRODUCT_BUNDLE_IDENTIFIER`/`DEVELOPMENT_TEAM` y el daemon se firma con ese
  entitlement restringido. `scripts/build-release.sh` falla si el daemon lleva cualquier
  entitlement.
- El daemon se firma con el **mismo identificador que la app** (`-i uno.kayros.kancerbero`,
  `Config/KancerberoDaemon.xcconfig`). ServiceManagement deriva el launch constraint del job del
  requisito de la app; un tool firmado con su nombre de target no lo satisface y launchd lo mata
  al arrancar con `CODESIGNING 4 Launch Constraint Violation`, aunque Login Items lo muestre
  habilitado. La copia embebida se re-firma con `CodeSignOnCopy` y
  `--preserve-metadata=identifier,entitlements,flags`, por eso el producto del target debe ser
  correcto antes de copiarlo.
- Release firma con **Developer ID Application**, hardened runtime y timestamp
  (`Config/Release.xcconfig`); Debug firma ad-hoc. Un daemon `SMAppService` exige app Developer ID
  **notarizada**.
- Autorización de clientes: es la política de desarrollo. `DaemonDelegate` registra `pid`, `uid`
  y ruta del cliente, y calcula `canControl` si la ruta contiene
  `/Kancerbero.app/Contents/MacOS/` o si el uid coincide con el del daemon. `canControl` solo
  protege las acciones; la lectura de inventario se acepta. Está pendiente el
  `setCodeSigningRequirement` con identificador y Team ID (ver `docs/security.md`).

### Ciclo de vida

1. launchd arranca `KancerberoDaemon --daemon` según `RunAtLoad`.
2. El proceso crea `NSXPCListener(machServiceName: "uno.kayros.kancerbero.daemon.v2")`, instala
   `DaemonDelegate` y llama a `listener.resume()`; después entra en `RunLoop.main.run()`.
3. Cada conexión aceptada crea un `DaemonService` que comparte el `CollectionActor` del proceso.
   Al invalidarse la conexión se cancela la tarea de suscripción y se suelta el cliente.
4. `KeepAlive.SuccessfulExit = false` y `ThrottleInterval = 5` relanzan el helper si falla.
5. Desregistrar el servicio o desinstalar la app lo detiene; la app vuelve al modo local.

### Funciones y uso

`KancerberoDaemonXPC` expone cuatro mensajes y la app implementa un callback:

| Mensaje | Contenido | Efecto |
|---|---|---|
| `handshake` | `KBHelloRequest` (`appVersion`, `schemaVersion`) | Responde `KBHelloResponse` con versión del daemon, del core y capacidades |
| `subscribe` | `KBSubscription` (`interval`, `topics`) | Arranca el push periódico de snapshots; intervalo efectivo limitado a 0.5–10 s |
| `request` | `KBRequestMessage` | Petición puntual; ver tipos abajo |
| `unsubscribe` | — | Cancela la tarea de push |
| `push` (callback) | `KBWireEnvelope` | Snapshot enviado al cliente |

Tipos de `request`:

| `Kind` | Respuesta | Restricciones |
|---|---|---|
| `snapshot` | `KBSnapshotPayload` con `KBCollectionSnapshot`, capacidades y diagnóstico | Ninguna adicional |
| `processDetail` | `KBProcessDetail` (proceso, sockets, ficheros abiertos) | `pid > 0`; mismo uid salvo root |
| `daemonServices` | `KBDaemonSnapshotPayload` del dominio `system` | Ninguna adicional |
| `daemonAction` | `KBDaemonActionResultPayload` con el resultado y el snapshot posterior | Solo dominio `system`, `canControl` y límite de 10 acciones/minuto |

La colección la hace `CollectionActor.refresh()`: procesos (libproc), sockets y ficheros por PID,
interfaces (IFMIB), tráfico por proceso (NetworkStatistics), CPU/memoria (`host_processor_info`,
`host_statistics64`, `getloadavg`), inventario launchd y disco. El daemon no lee contenido de
ficheros ni ejecuta comandos arbitrarios; las acciones son operaciones concretas de
`/bin/launchctl` con dominio explícito y sin shell.

Uso desde la app:

- El pill **Local / Daemon** de la barra inferior y el footer del sidebar muestran el estado.
- **System status** registra, repara y desregistra el servicio.
- El selector de intervalo reenvía `subscribe`; en modo local despierta el bucle de la app.

Comprobación manual:

```bash
launchctl print system/uno.kayros.kancerbero.daemon.v2
launchctl kickstart -k system/uno.kayros.kancerbero.daemon.v2
log show --last 5m --predicate 'subsystem == "uno.kayros.kancerbero"' --info --debug
```

Si el ítem aparece habilitado en Login Items pero no hay proceso, comprobar que launchd no lo
está matando por firma:

```bash
codesign -dvvv /Applications/Kancerbero.app/Contents/Library/LaunchDaemons/KancerberoDaemon
codesign -d --entitlements - --xml /Applications/Kancerbero.app/Contents/Library/LaunchDaemons/KancerberoDaemon
log show --last 10m --predicate 'process == "kernel" AND (eventMessage CONTAINS "AMFI" OR eventMessage CONTAINS "Launch Constraint")'
```

Debe aparecer `Identifier=uno.kayros.kancerbero`, sin claves de entitlements, y ninguna línea
`Launch Constraint Violation` para KancerberoDaemon. Un registro antiguo que ya no coincide puede
quedar atascado en BTM; como último recurso `sudo sfltool resetbtm` + reinicio y volver a
registrar desde la app (afecta a todos los ítems de Login Items del sistema).

### Límites

- El intervalo de suscripción se recorta a `0.5...10` segundos en el daemon.
- Las tasas por intervalo se validan con `RateTiming`: el hueco entre muestras debe cumplir
  `elapsed <= max(5 s, 2,5 × cadencia)`. Así 5 s (selector) y hasta 10 s (suscripción) producen
  tasas reales; solo un hueco mayor (pausa, desconexión) se descarta y reporta 0 en esa muestra.
- Las acciones están limitadas a **10 por minuto y cliente**; no hay todavía guardia de una
  acción en vuelo, límite de 4 clientes ni payload máximo de 32 MB (figuran como pendientes en
  `docs/security.md`).
- Las acciones de `gui`/`user` no pasan por el daemon: las ejecuta la app en local. Sin daemon,
  el dominio `system` es de solo lectura.
- `restart` se implementa como `kill SIGTERM` + `kickstart`, no con `launchctl kickstart -k`,
  porque `-k` se queda esperando con servicios de larga duración en macOS 27.
- `KB_LOG_LEVEL=debug` aparece en el plist legacy, pero ningún código actual lo lee; no cambia
  el nivel de `os.Logger`.

### Instalación, desinstalación y diagnóstico

```bash
# Distribución: app Developer ID + daemon embebido
./scripts/build-release.sh
./scripts/notarize.sh
./scripts/install-app.sh

# Legacy de desarrollo (root); comparten label/Mach service con SMAppService
sudo ./scripts/install-daemon.sh
sudo ./scripts/uninstall-daemon.sh

# Legacy de usuario (sin sudo)
./scripts/install-agent.sh
./scripts/uninstall-agent.sh
```

Antes de registrar el daemon de `SMAppService`, elimina cualquier instalación legacy: la ventana
System status la detecta y muestra los comandos, pero no los ejecuta. Los requisitos de firma y
notarización están en `README.md` y `docs/verification.md`.

Categorías de log: `daemon.lifecycle`, `daemon.listener` y `daemon`. En modo legacy también
escriben `daemon.out.log` y `daemon.err.log` (root en `/Library/Logs/Kancerbero/`, usuario en
`~/Library/Logs/Kancerbero/`).

Verificación completa en `docs/verification.md` (secciones «Servicio en background
(SMAppService)» y «Daemon y XPC»).

## KancerberoFilter

### Ficha técnica

| Campo | Valor |
|---|---|
| Target | `KancerberoFilter` |
| Tipo | `com.apple.product-type.system-extension` (bundle `SYSX`) |
| Producto | `uno.kayros.kancerbero.filter.systemextension` |
| Bundle ID | `uno.kayros.kancerbero.filter` |
| Extension point | `com.apple.networkextension.filter-data` |
| Clase del provider | `KancerberoFilter.FilterDataProvider` |
| Mach service | `group.uno.kayros.kancerbero.filter` (`NEMachServiceName`) |
| Fuentes | `Sources/KancerberoFilter/{main,FilterDataProvider,FilterCore,FilterProcessIdentity,FilterFlowEndpoints}.swift` |
| Configuración | `Config/KancerberoFilter.xcconfig`, `Resources/Filter/Info.plist` |
| Módulos | `KancerberoFilterContract` |
| Frameworks | NetworkExtension, Network, `libbsm` |
| Deployment target | macOS 15.6 |
| Firma | Developer ID + provisioning profile + notarización en Release |

`main.swift` llama a `NEProvider.startSystemExtensionMode()` y después `dispatchMain()`; el
sistema arranca el provider cuando el filtro está habilitado.

### Instalación y activación

La extensión va embebida en la app, en
`Kancerbero.app/Contents/Library/SystemExtensions/uno.kayros.kancerbero.filter.systemextension`
(fase `Embed Filter Extension`). macOS no la ejecuta desde ahí de forma permanente: tras
aprobarla, gestiona una copia instalada bajo `/Library/SystemExtensions`.

Flujo de activación:

1. La app pide la instalación con `OSSystemExtensionManager`
   (`Sources/Kancerbero/Filter/FilterController.swift`).
2. El usuario aprueba la extensión en **Ajustes → General → Login Items & Extensions**.
3. La app configura `NEFilterManager` (`filterSockets = true`, grade `.firewall`) y macOS pide
   el aviso de filtrado de contenido.
4. El filtro queda activo, incluso con la app cerrada, hasta que se desactive o se elimine.

La extensión no comparte `UserDefaults` ni container con la app. Declara el App Group
`group.uno.kayros.kancerbero` porque `NEMachServiceName` de una network system extension
sandboxeada debe empezar por uno de sus App Groups; no se usa para compartir estado.

### Permisos y entitlements

| Artefacto | Config | Entitlements | Archivo |
|---|---|---|---|
| App | Release | `content-filter-provider-systemextension`, `system-extension.install`, App Group | `Resources/App/Kancerbero.entitlements` |
| App | Debug | `content-filter-provider`, `system-extension.install`, App Group | `Resources/App/Kancerbero-Development.entitlements` |
| Extensión | Release | `content-filter-provider-systemextension`, `app-sandbox`, App Group | `Resources/Filter/KancerberoFilter.entitlements` |
| Extensión | Debug | `content-filter-provider`, `app-sandbox`, App Group | `Resources/Filter/KancerberoFilter-Development.entitlements` |

- La extensión corre como **root**, con **App Sandbox** activo, sin UI y en contexto global (no
  por usuario).
- La app no está sandboxeada; solo necesita `system-extension.install` y el entitlement de
  Network Extension para hospedar y configurar el filtro.
- Los perfiles **Developer ID** añaden el sufijo `-systemextension` a los valores de Network
  Extension; los perfiles de desarrollo Apple Development solo conceden el valor sin sufijo.
  Por eso `Debug` y `Release` usan archivos distintos.
- Un build ad-hoc o Apple Development no puede activar la extensión con SIP activo; `sysextd`
  responde `no policy, cannot allow apps outside /Applications` o
  `developer/groundhog mode isn't on`. Los prerrequisitos y errores están en
  `docs/verification.md`.

### Ciclo de vida

1. `startFilter(completionHandler:)` arranca `FilterCore`, que carga `rules.plist` y publica el
   listener XPC.
2. `handleNewFlow(_:)` decide cada flujo nuevo; `handle(_ report:)` acumula bytes y cierra
   registros.
3. `stopFilter(with:completionHandler:)` para el core: resuelve los flujos pausados con `drop`,
   invalida el listener y guarda reglas y decisiones recordadas.
4. Reglas y decisiones recordadas se persisten en `rules.plist` dentro del container sandbox de
   la extensión (`Application Support/KancerberoFilter/rules.plist`), así que siguen aplicándose
   tras un reinicio sin la app. Los flujos y el historial viven solo en memoria.

### Funciones y uso

El canal app↔extensión invierte la dirección habitual: la **extensión es el servidor** y la app
el cliente. La extensión publica `NEMachServiceName` y exige al cliente un requisito de firma
(`identifier "uno.kayros.kancerbero"` + Team ID `AK37TK8X2Y`) mediante
`setConnectionCodeSigningRequirement`.

Protocolos (`KancerberoFilterContract/FilterXPC.swift`):

| Protocolo | Método | Dirección |
|---|---|---|
| `KancerberoFilterXPC` | `send(_ envelope: Data, reply:)` | App → extensión |
| `KancerberoFilterClientXPC` | `receive(_ envelope: Data)` | Extensión → app (push) |

Tipos de `FilterEnvelope` (`FilterWire.swift`): `hello`, `helloAck`, `setRules`, `setRulesAck`,
`decide`, `decideAck`, `snapshotRequest`, `snapshot` y `push`. El payload es un
`PropertyListEncoder` binario.

Comportamiento del filtro:

- **Identidad del flujo**: `sourceAppAuditToken`/`sourceProcessAuditToken` →
  `audit_token_to_pid` → `proc_pidpath`. En macOS `sourceAppIdentifier` no existe.
- **Políticas**: `ask`, `allow` y `deny` por ruta de ejecutable (`FilterRule`).
- **Decisiones**: `once`, `rememberApp`, `rememberDestination`, `alwaysAllow` y `alwaysDeny`.
  Las recordadas se indexan por ruta de ejecutable y, si aplica, por destino.
- **Pausa y reanudación**: con política `ask` y sin decisión recordada, el flujo se **pausa**, se
  envía `FilterRequest` a la app y se resuelve con `resumeFlow(_:with:)`.
- **Fail-closed**: sin cliente XPC, sin respuesta dentro del plazo o con demasiados flujos
  pausados, el flujo se **deniega**.
- **Contadores**: cada veredicto lleva `shouldReport = true` y
  `statisticsReportFrequency = .medium`; `handle(_ report:)` acumula
  `bytesInboundCount`/`bytesOutboundCount` por flujo. Son contadores agregados del kernel.

| Límite | Valor | Efecto |
|---|---|---|
| Flujos registrados | 2.000 | Al superarlo el veredicto se sigue aplicando, pero el flujo no se guarda ni se muestra |
| Historial | 200 flujos cerrados | Se descartan los más antiguos |
| Flujos pausados | 32 | Los siguientes se deniegan con `too many pending` |
| Espera TCP | 60 s | Pasado el plazo se deniega |
| Espera UDP | 8 s | El sistema descarta UDP a los ~10 s |

Uso desde la app: pestaña **Filter** (flujos, RX/TX y estado), escudo por fila en **Processes**
para vigilar un proceso, hoja de aprobación en `RootView` y filas de estado en **System status**.

### Desinstalación y diagnóstico

```bash
systemextensionsctl list | grep kancerbero
log show --last 10m --predicate 'subsystem == "uno.kayros.kancerbero.filter"' --info --debug
log stream --predicate 'subsystem == "uno.kayros.kancerbero.filter"' --level debug
log show --last 10m --predicate 'process == "sysextd"' --info --debug | grep -i kancerbero
codesign -d --entitlements :- /Applications/Kancerbero.app
sudo systemextensionsctl uninstall AK37TK8X2Y uno.kayros.kancerbero.filter
```

- **Disable** en la pestaña Filter desactiva `NEFilterManager` y elimina su configuración.
- **Remove filter extension** en System status desactiva la system extension.
- La app ofrece **Copy diagnostics** con rutas, estado y último error de activación.
- No se afirma un límite de payload de 1 MB en el código: `docs/security.md` lo describe como
  intención de diseño, pero `FilterCore` no lo comprueba explícitamente.

Verificación y pruebas funcionales en `docs/verification.md` (sección «Filtro de red (Network
Extension)»).

## KancerberoProbe

### Ficha técnica

| Campo | Valor |
|---|---|
| Target | `KancerberoProbe` |
| Tipo | `com.apple.product-type.tool` |
| Producto | `KancerberoProbe` |
| Bundle ID | `uno.kayros.kancerberoprobe` |
| Fuente | `Sources/KancerberoProbe/main.swift` |
| Configuración | `Config/KancerberoProbe.xcconfig` |
| Módulos | `KancerberoCore` (y `KancerberoC`) |
| Frameworks | CoreFoundation, IOKit, DiskArbitration |
| Deployment target | macOS 15.6 |
| Instalación | Ninguna: `SKIP_INSTALL = YES`; solo existe en `build/Build/Products/<Config>/` |
| Entitlements | Ninguno |

### Dónde se ejecuta y permisos

No se instala, no se embebe y no se firma para distribución: `scripts/build.sh` lo compila junto
con la app y el daemon. Hereda los permisos del usuario que lo lanza. Sin root,
`proc_listallpids`/`proc_pidinfo`/`proc_pidfdinfo` solo devuelven procesos del uid actual; con
`sudo` cubre todos los uid. `symbols` informa de `euid`, de la disponibilidad de
NetworkStatistics y de `net.statistics_privcheck`.

### Comandos

| Comando | Efecto | Valores por defecto |
|---|---|---|
| `version` | Versión del probe, del core y schema | — |
| `symbols` | Disponibilidad de NetworkStatistics, `net.statistics_privcheck`, `euid` y Thermal (IOHID) | — |
| `procs [--cpu] [--limit N] [--interval S]` | Lista de procesos, con CPU acumulada si `--cpu` | `--limit 20`, `--interval 1` |
| `cpu [--interval S]` | Ticks por núcleo y agregado, con temperatura de paquete y por core | `--interval 1` |
| `thermal [--seconds N] [--interval S] [--core-count N]` | Lectura forzada de temperaturas IOHID (paquete, fuente y sensores) | `--seconds 3`, `--interval 1`, `0` = todos los cores |
| `battery-graph` | Muestras del gráfico de batería de 12 h, estados AC/batería y tiempo en la fuente actual | — |
| `ifaces` | Contadores de interfaz (IFMIB) | — |
| `sockets <pid>` | Sockets del proceso | — |
| `sockets-summary [pid...]` | Resumen de sockets por protocolo/tipo; sin PIDs usa todos | — |
| `files <pid>` | Ficheros abiertos (libproc) | — |
| `daemons [system\|gui\|user]` | Inventario launchd del dominio | `system` |
| `disk volumes` | Inventario de discos y volúmenes | — |
| `disk info <diskXsY>` | Detalle de un dispositivo | — |
| `disk scan <path> [--top N] [--hidden]` | Escaneo de un directorio | `--top 20` |
| `daemon-action <domain> <action> <label> [plist]` | Ejecuta una acción de `LaunchctlRunner`; `action` ∈ `start`, `stop`, `restart`, `enable`, `disable`, `load`, `unload` | — |
| `sources` | Fuentes de tráfico disponibles | — |
| `nstat [--seconds S]` | Muestras de NetworkStatistics | `--seconds 5` |
| `all [--limit N] [--seconds S]` | Versión, símbolos, procesos, interfaces y nstat | 10 procesos, 3 s |

`daemon-action` ejecuta lo que pida `LaunchctlRunner` sin las restricciones de cliente del daemon;
es una herramienta de desarrollo y hay que tratarla como tal.

### Uso y diagnóstico

```bash
./build/Build/Products/Debug/KancerberoProbe all --seconds 3
./build/Build/Products/Debug/KancerberoProbe symbols
./build/Build/Products/Debug/KancerberoProbe cpu --interval 1
./build/Build/Products/Debug/KancerberoProbe thermal --seconds 2 --interval 1
./build/Build/Products/Debug/KancerberoProbe battery-graph
./build/Build/Products/Debug/KancerberoProbe procs --cpu --limit 20
./build/Build/Products/Debug/KancerberoProbe daemons system
./build/Build/Products/Debug/KancerberoProbe disk volumes
./build/Build/Products/Debug/KancerberoProbe daemon-action gui start <label>
```

Es la vía práctica para comparar con `netstat -ibI`, `lsof -nP -i`, `nettop` y Activity Monitor.
Detalle en `docs/verification.md` («Build y probe», «Daemons»).

## KancerberoC

### Ficha técnica

| Campo | Valor |
|---|---|
| Target | `KancerberoC` |
| Tipo | `com.apple.product-type.library.static` (C, Clang module) |
| Producto | `libKancerberoC.a` |
| Módulo | `KancerberoC` (`DEFINES_MODULE = YES`) |
| Headers | `Sources/KancerberoC/include/{KancerberoC,KBModels,KBLaunchd,KBDisk}.h`, `module.modulemap` |
| Configuración | `Config/KancerberoC.xcconfig` |
| Flags | `-fblocks`, `-Wno-deprecated-declarations` |
| Frameworks | CoreFoundation, IOKit, DiskArbitration |
| Deployment target | macOS 15.6 |
| Instalación | Ninguna: `SKIP_INSTALL = YES` |

### Enlazado y consumidores

No se instala: se enlaza estáticamente. La usa `KancerberoCore` desde su bridging header y la
enlazan en su fase `Frameworks` `Kancerbero.app`, `KancerberoDaemon` y `KancerberoProbe`. La
system extension no la usa.

### API y contenido

| Área | Archivo | Funciones principales |
|---|---|---|
| NetworkStatistics (privado) | `kb_nstat.c` | `kb_nstat_open/close/is_available/start/poll/snapshot/source_count`, `kb_nstat_last_error` |
| Procesos, sockets y ficheros | `kb_libproc.c` | `kb_process_list`, `kb_process_path`, `kb_socket_list`, `kb_socket_summary_all`, `kb_open_file_list` |
| sysctl, interfaces y CPU/memoria | `kb_sysctl.c` | `kb_interface_list`, `kb_sysctl_int`, `kb_host_stats_read` |
| Temperaturas CPU (IOHID privado) | `kb_thermal.c` | `kb_thermal_stats_read`, `kb_thermal_is_available`, `kb_thermal_last_error`, `kb_thermal_reset` |
| launchd | `kb_launchd.c` | `kb_launchd_jobs`, `kb_launchd_last_error` (`launch_msg("GetJobs")`) |
| Discos (IOKit/DiskArbitration) | `kb_disk_media.c` | `kb_disk_media_list` |
| Escaneo de directorios | `kb_disk_scan.c` | `kb_disk_list_directory` (`getattrlistbulk`) |
| Estructuras compartidas | `KBModels.h` | Structs C que cruzan a Swift vía el module map |

### Permisos y efectos

- Solo lectura: no escribe ficheros, no lanza procesos y no usa shell.
- `NetworkStatistics.framework` se abre con `dlopen` y las funciones con `dlsym`; es una API
  privada y no apta para App Store. `kb_thermal.c` hace lo mismo con los símbolos de temperatura
  de IOHID (`IOHIDEventSystemClient*`, `IOHIDServiceClientCopyEvent`, `IOHIDEventGetFloatValue`):
  son de solo lectura y, si faltan, la temperatura queda sin datos.
- La visibilidad de libproc es la del kernel: mismo uid salvo que el proceso sea root.
- No necesita entitlements. El daemon hereda esta capacidad al enlazarla.

### Uso y verificación

Se usa desde Swift (`KancerberoCore`, `KancerberoDaemon`, `KancerberoProbe`) y desde el
bridging header de `KancerberoCore`. `KancerberoProbe symbols`, `ifaces`, `procs`, `sockets`,
`files` y `disk` ejercen casi toda la superficie de la librería. La evidencia de ingeniería
inversa de cada API está en `docs/private-apis.md`.

## KancerberoCore

### Ficha técnica

| Campo | Valor |
|---|---|
| Target | `KancerberoCore` |
| Tipo | `com.apple.product-type.library.static` (Swift) |
| Producto | `libKancerberoCore.a` |
| Módulo | `KancerberoCore` (`DEFINES_MODULE = YES`) |
| Bridging header | `Sources/KancerberoCore/KancerberoCore-Bridging-Header.h` |
| Configuración | `Config/KancerberoCore.xcconfig` |
| Dependencia | `KancerberoC` |
| Frameworks | CoreFoundation, IOKit, DiskArbitration |
| Deployment target | macOS 15.6 |
| Instalación | Ninguna: `SKIP_INSTALL = YES` |

### Enlazado y consumidores

La enlazan `Kancerbero.app`, `KancerberoDaemon` y `KancerberoProbe`. La system extension no la
usa: su contrato vive en `KancerberoFilterContract`. No se instala; se enlaza dentro de cada
consumidor.

### Contenido

| Directorio | Archivos | Responsabilidad |
|---|---|---|
| `Models/` | `KBModels.swift`, `KBDaemonModels.swift`, `KBDiskModels.swift`, `KBHostMetrics.swift` | Procesos, sockets, interfaces, snapshots, daemons, disco, CPU/memoria y tasas |
| `Wire/` | `KBWire.swift`, `KancerberoXPC.swift` | `KBWireEnvelope`, `KBHello*`, `KBSubscription`, `KBRequestMessage`, codec binario y protocolos `KancerberoDaemonXPC`/`KancerberoClientXPC` |
| `Collectors/` | `CollectionActor.swift`, `NStatCollector`, `ProcessCollector`, `DescriptorCollector`, `InterfaceCollector`, `DaemonsCollector`, `LaunchdQuery`, `LaunchctlRunner`, `DiskInventoryCollector`, `DiskScanner`, `HostMetricsCollector`, `ThermalStatsReader`, `SocketSummaryCollector`, `UserCollector` | Recolección y contabilidad de cada fuente |
| `Diagnostics/` | `KBCapabilitiesProbe.swift` | Modo efectivo (local/daemon), disponibilidad de NetworkStatistics y privacidad |
| `Support/` | `KBInterop.swift`, `CPUTopology.swift` | Conversión entre structs C y modelos Swift; clústeres Performance/Efficiency |
| — | `KBVersion`, `KBRates`, `KBProcessKey` | Versión de schema, tasas y claves estables |

`CollectionActor` es el punto de entrada: `refresh()` devuelve un `KBCollectionSnapshot` y
`interfaceRates()` las tasas por interfaz. Los deltas y las tasas se calculan contra la muestra
anterior con reloj monótono; `socketInventory` y `hostMetrics` son campos opcionales del
snapshot para no romper la compatibilidad de schema con daemons antiguos.

### Uso y permisos

Se importa con `import KancerberoCore`. El daemon la usa dentro de su `DaemonService`; la app la
usa en modo local y para decodificar los snapshots; el probe la usa para todos sus comandos. No
tiene entitlements ni sandbox propios: hereda los del proceso anfitrión. En el daemon root ve
todos los uid; en la app y el probe sin root, solo el uid actual. Nunca lee contenido de
ficheros ni ejecuta comandos para obtener métricas.

Verificación práctica con `KancerberoProbe` y detalle en `docs/architecture.md` (secciones
«Flujo de datos» y «XPC»).

## KancerberoFilterContract

### Ficha técnica

| Campo | Valor |
|---|---|
| Target | `KancerberoFilterContract` |
| Tipo | `com.apple.product-type.library.static` (Swift) |
| Producto | `libKancerberoFilterContract.a` |
| Módulo | `KancerberoFilterContract` (`DEFINES_MODULE = YES`) |
| Configuración | `Config/KancerberoFilterContract.xcconfig` |
| Deployment target | macOS 15.6 |
| Dependencias | Solo Foundation |
| Instalación | Ninguna: `SKIP_INSTALL = YES` |

### Enlazado y consumidores

La enlazan exactamente dos targets: `Kancerbero.app` y `KancerberoFilter`. No la usan el daemon,
el probe ni `KancerberoCore`. Es la única librería que cruza el límite del sandbox de la system
extension, y por eso no depende de nada del sistema más allá de Foundation.

### Contenido

| Archivo | Contenido |
|---|---|
| `FilterModels.swift` | `FilterVersion`, `FilterPolicy`, `FilterRule`, `FilterRemember`, `RememberedDecision`, `FilterEndpoint`, `FilterFlowState`, `FilterRequest`, `FlowRecord`, `FilterStatus`, `FilterRuleSnapshot`, `FilterSnapshot`, `FilterDecisionKind`, `FilterDecisionMessage` |
| `FilterWire.swift` | `FilterEnvelope` (`hello`, `helloAck`, `setRules`, `setRulesAck`, `decide`, `decideAck`, `snapshotRequest`, `snapshot`, `push`), `FilterHello`, `FilterAck`, `FilterPush` y `FilterCodec` (`PropertyListEncoder` binario) |
| `FilterXPC.swift` | `KancerberoFilterXPC`, `KancerberoFilterClientXPC`, `FilterXPCNames` y el requisito de firma del cliente |

### Constantes

| Constante | Valor |
|---|---|
| `FilterXPCNames.appGroup` | `group.uno.kayros.kancerbero` |
| `FilterXPCNames.machService` | `group.uno.kayros.kancerbero.filter` |
| `FilterXPCNames.extensionBundleIdentifier` | `uno.kayros.kancerbero.filter` |
| `FilterXPCNames.teamIdentifier` | `AK37TK8X2Y` |
| `FilterXPCNames.clientRequirement` | `identifier "uno.kayros.kancerbero" and anchor apple generic and certificate leaf[subject.OU] = "AK37TK8X2Y"` |

`machService` debe coincidir en tres sitios: `FilterXPCNames` (código), `NEMachServiceName` del
`Resources/Filter/Info.plist` y `KBFilterMachService` del `Resources/App/Info.plist`. Si se
cambia uno, hay que cambiar los tres.

### Uso y compatibilidad

Ambos lados deben compilar el mismo contrato. El envelope lleva `schemaVersion`
(`FilterVersion.schema`, hoy `1`), pero un cambio en los modelos `Codable` o en los tipos de
`FilterEnvelope` obliga a reconstruir app y extensión juntas. No tiene permisos ni acceso al
sistema: es un contrato de datos y protocolos.

Verificación: `codesign -d --entitlements :-` sobre app y extensión, y
`systemextensionsctl list | grep kancerbero`. Detalle en `docs/architecture.md` (sección «Filtro
de red (Network Extension)»).

## Dependencias y convivencia

| Librería | App | Daemon | Probe | Filter |
|---|---|---|---|---|
| `KancerberoC` | Sí | Sí | Sí | No |
| `KancerberoCore` | Sí | Sí | Sí | No |
| `KancerberoFilterContract` | Sí | No | No | Sí |

| Pareja | Convivencia |
|---|---|
| Daemon `SMAppService` + daemon legacy | **Incompatible**: comparten label y Mach service; hay que desinstalar el legacy antes de registrar |
| Daemon `SMAppService` + LaunchAgent legacy | **Incompatible**: el agente publica el mismo Mach service con otro label |
| Daemon + system extension | Compatible e independiente: Mach services distintos; el filtro funciona sin daemon |
| `KancerberoProbe` + cualquier otro | Compatible: no se instala ni registra nada |
| Varios filtros de red del mismo grade | Pueden convivir; otras herramientas (Little Snitch, LuLu) pueden alterar el orden |

## Referencias cruzadas

- Visión general y compilación: `README.md`.
- Arquitectura, targets y XPC: `docs/architecture.md`.
- Modelo de seguridad, autorización XPC y entitlements: `docs/security.md`.
- Evidencia de ingeniería inversa (NetworkStatistics, libproc, sysctl, launchd): `docs/private-apis.md`.
- Activación, pruebas funcionales y desinstalación: `docs/verification.md`.
