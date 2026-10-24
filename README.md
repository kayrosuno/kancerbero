# kancerbero

Monitor de red para macOS inspirado en Activity Monitor. Muestra tráfico por proceso,
conexiones por proceso, contadores por interfaz y un inspector con sockets y ficheros abiertos.

El diseño se basa en ingeniería inversa de `Activity Monitor.app` con REA (ver
`docs/private-apis.md`), no en suposiciones: Activity Monitor obtiene el tráfico por proceso de
`NetworkStatistics.framework`, los totales de interfaz de `sysctl(NET_RT_IFLIST2)` y los ficheros
abiertos de `lsof`. kancerbero usa la misma fuente para el tráfico y mejora el inspector usando
`libproc` estructurado (con `lsof` solo como fallback).

## Arquitectura

```
App SwiftUI ──XPC──> KancerberoDaemon (root opcional)
     │                       │
     └── modo local ─────────┴──> KancerberoCore
                                  ├── KancerberoC: NetworkStatistics (dlopen), libproc, sysctl
                                  └── modelos + contabilidad de deltas/tasas
```

- **Modo local** (sin daemon): procesos y sockets del mismo uid; tráfico por proceso vía
  NetworkStatistics (`net.statistics_privcheck = 0`).
- **Modo daemon**: todas las interfaces, todos los procesos y sockets de cualquier uid (si el
  daemon corre como root).
- **Fallback**: si NetworkStatistics no está disponible, la app sigue mostrando conexiones e
  interfaces y marca el modo como degradado.

## Interfaz

`NavigationSplitView` con panel lateral colapsable:

- **Networking** — tarjetas de resumen con sparklines y subnavegación Interfaces / Connections /
  Processes, con tablas e inspector de proceso.
- **Disk** — placeholder con las capacidades previstas (I/O por proceso, volúmenes, histórico,
  SMART).
- **Daemons** — inventario de servicios launchd (System/GUI/User) con estado, PID, última salida,
  programa y plist. Inspector con Start / Stop / Restart / Enable·Disable / Load·Unload / Reveal.
  Las acciones de sistema requieren el daemon root y confirmación; GUI/User funcionan en local.
  Los login items quedan para una iteración posterior.

El panel se oculta con el botón de la toolbar o `Cmd+Ctrl+S`; `Cmd+1/2/3` cambia de sección. Las
animaciones respetan Reduce Motion.

## Compilar

```bash
./scripts/build.sh                 # Debug: app, probe y daemon
# o
xcodebuild -project Kancerbero.xcodeproj -scheme Kancerbero \
  -configuration Debug -derivedDataPath build build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

Productos en `build/Build/Products/Debug/`.

## Ejecutar

```bash
open build/Build/Products/Debug/Kancerbero.app
./build/Build/Products/Debug/KancerberoProbe all --seconds 3
```

Captura de la UI sin permisos de Grabación de pantalla (la app se dibuja a sí misma y termina):

```bash
build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero \
  --screenshot /tmp/kancerbero-ui.png \
  [--section networking|disk|daemons] \
  [--tab interfaces|connections|processes] \
  [--sidebar-collapsed]
```

## Daemon

### Desarrollo sin sudo (LaunchAgent de usuario)

```bash
./scripts/install-agent.sh     # registra el Mach service en tu sesión
./scripts/uninstall-agent.sh
```

Sirve para probar el camino XPC completo. Solo ve procesos de tu usuario.

### Acceso completo (LaunchDaemon root)

```bash
sudo ./scripts/install-daemon.sh
sudo ./scripts/uninstall-daemon.sh
```

Instala el binario en `/Library/PrivilegedHelperTools/` y el plist en
`/Library/LaunchDaemons/`. Logs en `/Library/Logs/Kancerbero/`.

Producción: firma Developer ID + `SMAppService.daemon(plistName:)` con el plist
`uno.kayros.kancerbero.daemon.smappservice.plist`. Ver `docs/security.md`.

## Daemons

- Estado e inventario con `launch_msg("GetJobs")` (`<launch.h>` del SDK) + plists; el daemon root
  consulta el dominio `system` y la app los dominios `gui`/`user`.
- Acciones con `/bin/launchctl` y dominio explícito, sin shell. Restart = stop + start.
- Estado disabled desde `launchctl print-disabled`.
- Diagnóstico:

```bash
./build/Build/Products/Debug/KancerberoProbe daemons system
./build/Build/Products/Debug/KancerberoProbe daemons gui
./build/Build/Products/Debug/KancerberoProbe daemon-action gui start <label>
```

## Verificación

```bash
./scripts/verify.sh
```

Compara con `netstat -ibI`, `lsof -nP -i`, `nettop` y Activity Monitor. Detalle y tolerancias en
`docs/verification.md`.

## Limitaciones conocidas

- APIs privadas (`NetworkStatistics.framework`): no apto para App Store.
- Sin firma Developer ID, el daemon se instala en modo desarrollo (ad-hoc + launchd manual).
- `NStatSourceIdentifier` no es fiable en macOS 27; se usa el puntero de fuente y las claves
  `PID`/`UUID`.
- La atribución por proceso usa `epid` cuando existe (como Activity Monitor); los flujos sin
  proceso se agrupan como desconocidos.
- El inspector usa `libproc`; para procesos de otros uid requiere el daemon root.
