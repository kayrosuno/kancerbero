# Verificación

## Build y probe

```bash
./scripts/build.sh
./build/Build/Products/Debug/KancerberoProbe symbols
./build/Build/Products/Debug/KancerberoProbe procs --limit 10
./build/Build/Products/Debug/KancerberoProbe ifaces
./build/Build/Products/Debug/KancerberoProbe nstat --seconds 5
```

## Tráfico por proceso

```bash
nettop -P -L 3 -s 1 -x
nettop -P -d -L 3 -s 1 -x
```

- La primera muestra de `nettop -L` es la línea base; comparar acumulados tras alinear el inicio.
- Tolerancia orientativa: ±10% en tasas, ±2% en acumulados.
- `nettop` incluye loopback; usar el mismo filtro al comparar.
- **Atribución:** kancerbero usa `epid` cuando existe, igual que Activity Monitor
  (`_accumulateProtocolSnapshot:`). `nettop` muestra el proceso de la fuente. Por eso un proceso
  puede diferir entre ambas herramientas si parte de su tráfico lo gestiona un helper XPC; es una
  diferencia de atribución, no de contadores.
- Comprobado: `ollama`, `2.1.310` y `rapportd` coinciden con `nettop` (±1%).
- Prueba controlada:

```bash
mkdir -p /tmp/loadtest
dd if=/dev/zero of=/tmp/loadtest/blob bs=1m count=30
(cd /tmp/loadtest && python3 -m http.server 8899 &)
curl -s --limit-rate 400k http://127.0.0.1:8899/blob -o /dev/null &
./build/Build/Products/Debug/KancerberoProbe nstat --seconds 5
```

## Conexiones y ficheros

```bash
sudo lsof -nP -i
sudo /usr/sbin/netstat -anv -p tcp
./build/Build/Products/Debug/KancerberoProbe sockets <pid>
./build/Build/Products/Debug/KancerberoProbe files <pid>
```

Comparar el conjunto estable (listeners y conexiones establecidas) en una ventana de 1 s; las
conexiones transitorias pueden diferir. Los estados `TSI_*` deben coincidir con `netstat -anv`.

## Interfaces

```bash
/usr/sbin/netstat -ibI en0
```

En la primera fila, `Ibytes` está en `$7` y `Obytes` en `$10`. Los contadores deben ser idénticos;
el delta puede diferir <1% por desfase de lectura.

Nota: si se usa `NET_RT_IFLIST2`, macOS 27 devuelve solo los 32 bits bajos de los bytes.
kancerbero usa la ruta IFMIB (`net.link.generic.system.ifcount` +
`IFMIB_IFDATA`/`IFDATA_GENERAL`), que sí coincide con `netstat`. Verificado:

## Daemon y XPC

```bash
./scripts/install-agent.sh
launchctl print gui/$(id -u)/uno.kayros.kancerbero.agent
# la app debe mostrar "source: daemon" en la barra inferior
./scripts/uninstall-agent.sh

sudo ./scripts/install-daemon.sh
sudo launchctl print system/uno.kayros.kancerbero.daemon
sudo ./scripts/uninstall-daemon.sh
```

## Captura visual de la UI sin TCC

`screencapture` requiere el permiso de Grabación de pantalla para el proceso host. La app puede
capturar su propia ventana con AppKit sin ese permiso:

```bash
build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero \
  --screenshot /tmp/kancerbero-ui.png \
  [--section networking|disk|daemons|cpu] \
  [--tab interfaces|connections|processes] \
  [--disk-tab volumes|analyzer] \
  [--disk-path=<carpeta>] [--disk-scan] [--disk-item <diskXsY>] \
  [--cpu-search <texto>] [--cpu-selected <pid>] \
  [--networking-state established|listening|connecting|closing|other] \
  [--networking-search <texto>] \
  [--sidebar-collapsed]
```

`--section` selecciona la sección de primer nivel, `--tab` la subpestaña de Networking,
`--disk-tab` la de Disk, `--disk-path`/`--disk-scan` lanzan el analizador sobre una ruta y
`--disk-item` preselecciona un dispositivo en Volumes. `--cpu-search` aplica el filtro inicial de
la tabla de CPU, `--cpu-selected` preselecciona un PID, `--networking-state` aplica la categoría
de estado TCP y `--networking-search` el filtro de la tabla de procesos. `--sidebar-collapsed`
captura el panel lateral oculto. El PNG se escribe a escala de backing (2x en Retina) y la app
termina con código 0.

Capturas recomendadas:

```bash
for args in \
  "--section networking --tab interfaces" \
  "--section networking --tab connections" \
  "--section networking --tab processes" \
  "--section disk" \
  "--section daemons" \
  "--section cpu" \
  "--section networking --sidebar-collapsed"
do
  ./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero \
    --screenshot "/tmp/kb-$(echo $args | tr ' /' '__').png" $args
done
```

## Daemons

```bash
./build/Build/Products/Debug/KancerberoProbe daemons system
./build/Build/Products/Debug/KancerberoProbe daemons gui
./build/Build/Products/Debug/KancerberoProbe daemons user
```

- Comparar label, dominio, PID y estado con `launchctl print system`, `launchctl print
  gui/$(id -u)`, `launchctl print user/$(id -u)` y LaunchControl.
- `launch_msg("GetJobs")` devuelve los mismos jobs que `launchctl list` en el dominio del usuario.
- Estado disabled: comparar con `launchctl print-disabled <dominio>`.

Prueba de control con un agente temporal (limpiar al terminar):

```bash
LABEL=uno.kayros.kancerbero.test
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
# ProgramArguments: /bin/sleep 300, RunAtLoad=false
launchctl bootstrap "gui/$(id -u)" "$PLIST"
./build/Build/Products/Debug/KancerberoProbe daemon-action gui start "$LABEL"
./build/Build/Products/Debug/KancerberoProbe daemon-action gui restart "$LABEL"
./build/Build/Products/Debug/KancerberoProbe daemon-action gui stop "$LABEL"
./build/Build/Products/Debug/KancerberoProbe daemon-action gui disable "$LABEL"
./build/Build/Products/Debug/KancerberoProbe daemon-action gui enable "$LABEL"
./build/Build/Products/Debug/KancerberoProbe daemon-action gui unload "$LABEL"
launchctl bootout "gui/$(id -u)/$LABEL"; rm -f "$PLIST"
```

Resultado esperado: start/restart devuelven estado 0 con PID nuevo; stop deja el servicio
"not running"; disable/enable se reflejan en `print-disabled`; unload/load funcionan con
`bootstrap`/`bootout`. Las acciones de system requieren el daemon root y una confirmación.

Nota: con actualizaciones en vivo, SwiftUI `Table` puede registrar
`reentrant operation in its NSTableView delegate` en macOS 27. No afecta a los datos; el refresco
de Daemons se hace cada 5 s y la metadata se cachea 30 s para reducir esas ventanas.

Capturas:

```bash
K=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
$K --screenshot /tmp/kb-daemons.png --section daemons --screenshot-delay 5
$K --screenshot /tmp/kb-daemons-running.png --section daemons \
  --daemon-state running --screenshot-delay 5
$K --screenshot /tmp/kb-daemons-user-agents.png --section daemons \
  --daemon-type agent --daemon-scope user --screenshot-delay 5
$K --screenshot /tmp/kb-daemons-detail.png --section daemons \
  --daemon-selected com.apple.AMPArtworkAgent --screenshot-delay 5
```

Comprobar además:

- Cada label de agente aparece una sola vez (el dominio canónico es GUI si está cargado; si no,
  User). El panel de detalle muestra `Domains` con ambos dominios cuando existen.
- Los filtros se combinan con AND y las tarjetas Running / Stopped / Disabled reflejan el
  subconjunto filtrado; volver a pulsar la tarjeta activa limpia el filtro.
- `--daemon-domain system|gui|user` sigue funcionando como atajo: system selecciona daemons y
  gui/user seleccionan agentes.
- Sin daemon root, los servicios de sistema aparecen como `Not loaded`; no se reinterpretan como
  `Stopped`.
- Tras el refresco de 5 s, la selección y el panel de detalle se mantienen si el servicio sigue
  cumpliendo el filtro.

Disk (filtros de tarjetas):

```bash
$K --screenshot /tmp/kb-disk-free.png --section disk \
  --disk-tab volumes --volumes-focus free --screenshot-delay 5
$K --screenshot /tmp/kb-disk-folders.png --section disk \
  --disk-tab analyzer --disk-path="$HOME/Documents" --disk-scan \
  --analyzer-focus folders --screenshot-delay 8
```

La barra inferior debe mostrar métricas de la sección activa y la marca de actualización de su
fuente (red, inventario de disco, servicios launchd o CPU/memoria).

## Settings y animaciones de pestaña

Abrir **Kancerbero → Settings…** (⌘,) y comprobar el toggle “Animate tab changes”. La preferencia
se guarda en `UserDefaults` con la clave `tabAnimationsEnabled`; si la clave no existe, el valor
por defecto es activado.

```bash
defaults read uno.kayros.kancerbero tabAnimationsEnabled
defaults write uno.kayros.kancerbero tabAnimationsEnabled -bool false
defaults write uno.kayros.kancerbero tabAnimationsEnabled -bool true
defaults delete uno.kayros.kancerbero tabAnimationsEnabled   # vuelve al valor por defecto: on
```

Tras un `defaults write`/`delete` externo puede hacer falta relanzar la app para que el cambio se
refleje; el toggle de Settings se actualiza en vivo.

- Con el toggle apagado: cambiar Networking/Disk/Daemons/CPU por sidebar y por ⌘1–⌘4, cambiar las
  píldoras de Networking y Disk y usar Volumes → Analyzer. No debe haber fundido, deslizamiento
  ni movimiento del resaltado; todo cambia de golpe.
- Con el toggle encendido: las transiciones vuelven sin reiniciar. Cada cambio debe animarse una
  sola vez (sin doble transacción).
- Tras reiniciar la app, el valor del toggle se conserva.
- Con Reduce Motion activo en Ajustes del Sistema → Accesibilidad → Pantalla, no debe animarse
  ninguna pestaña aunque el toggle esté encendido; Settings muestra el aviso y conserva el valor.
- El filtro All/Agents/Daemons sigue animando su píldora con el toggle apagado, porque es un
  filtro y no una pestaña.
- Confirmar que siguen animándose sparklines, valores de la barra de estado, hover de tarjetas,
  `numericText`, paneles de detalle, filtros/foco y LiveDot.

## Intervalo de actualización

- Con daemon conectado, ejecutar

```bash
log stream --predicate 'subsystem == "uno.kayros.kancerbero"' --info --debug
```

  y cambiar el selector 5 → 0,5 → 2 s en Networking o CPU. Debe aparecer un
  `resubscribed interval=…` en el cliente y un nuevo `subscribed interval=…` en el daemon por
  cada valor distinto. Volver a seleccionar el mismo valor no debe reenviar la suscripción.
- Comprobar la cadencia real por la hora de “Updated” y el avance de los sparklines: a 0,5 s la
  ventana de 60 muestras abarca ~30 s; a 5 s, ~5 min. Al cambiar el intervalo los historiales se
  reinician, así que el eje temporal no mezcla cadencias.
- Sin daemon, cambiar de 5 s a 0,5 s y verificar que la siguiente actualización llega en ~0,5 s,
  no tras el sueño anterior. Pausa/Play debe seguir funcionando y el refresh manual debe
  actualizar aunque esté pausado.
- Daemons mantiene su refresco de 5 s y Disk su caché de inventario; el selector no está visible
  en esas pestañas.

## CPU y memoria

```bash
P=./build/Build/Products/Debug/KancerberoProbe
$P cpu --interval 1
$P procs --cpu --limit 20
sudo $P procs --cpu --limit 20

K=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
$K --screenshot /tmp/kb-cpu.png --section cpu --screenshot-delay 6
$K --screenshot /tmp/kb-cpu-filter.png --section cpu \
  --cpu-search java --screenshot-delay 6
$K --screenshot /tmp/kb-cpu-selected.png --section cpu \
  --cpu-selected 9680 --screenshot-delay 6
```

- Comparar CPU por núcleo con `top` (±1–2%) y el agregado con la suma ponderada por ticks, no
  con la media de porcentajes. Comparar load con `uptime` (±0,01), uptime con `uptime` (±1 s) y
  swap con `sysctl -n vm.swapusage`.
- RSS de procesos propios con `ps -o rss`; con `sudo`, para todos. La memoria “used” puede diferir
  de `top`/Activity Monitor por definición (`active + wired + compressed`); documentar la cifra.
- Sin daemon root la tabla solo enumera procesos del uid actual y muestra “your processes only”.
  Con el daemon root aparecen todos. Los procesos sin task info muestran `—`, nunca 0.
- CPU% puede superar 100% en multithread; `TIME+` es tiempo acumulado. Ordenar por cada columna,
  filtrar y cambiar de sección: búsqueda, selección y orden se conservan.
- Igual que en otras tablas con refresco en vivo, macOS 27 puede registrar
  `reentrant operation in its NSTableView delegate`; no afecta a los datos.
- Para fugas: dejar la pestaña abierta varios minutos con intervalo de 0,5 s y comprobar que el
  RSS de Kancerbero se mantiene estable (`ps -o rss`, `leaks`). El sampler libera el array de
  `host_processor_info` y el puerto Mach en cada tick.

Tarjeta Traffic, Activity, Protocols y filtros de protocolo:

```bash
APP=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
$APP --screenshot /tmp/kb-net-cards.png --section networking --tab interfaces \
  --screenshot-delay 5
$APP --screenshot /tmp/kb-net-tcp.png --section networking --tab connections \
  --networking-transport tcp --screenshot-delay 5
$APP --screenshot /tmp/kb-net-ipv6.png --section networking --tab connections \
  --networking-ip ipv6 --screenshot-delay 5
$APP --screenshot /tmp/kb-net-combined.png --section networking --tab processes \
  --networking-focus connections --networking-transport udp --networking-ip ipv4 \
  --screenshot-delay 5
$APP --screenshot /tmp/kb-net-download.png --section networking --tab connections \
  --networking-focus download --screenshot-delay 5
$APP --screenshot /tmp/kb-net-state-listening.png --section networking \
  --tab connections --networking-state listening --screenshot-delay 5
$APP --screenshot /tmp/kb-net-state-established.png --section networking \
  --tab connections --networking-state established --screenshot-delay 5
$APP --screenshot /tmp/kb-net-state-combined.png --section networking \
  --tab connections --networking-state established \
  --networking-transport tcp --networking-ip ipv4 --screenshot-delay 5
$APP --screenshot /tmp/kb-net-process-search.png --section networking \
  --tab processes --networking-search rapportd --screenshot-delay 5
```

- Traffic: Download/Upload en la cabecera, gráfico espejado con cuadrícula, etiquetas Y en
  `bps/Kbps/Mbps/Gbps` y eje temporal `-60s/-30s/now` (con el intervalo de 1 s). Sin salto de
  layout entre 0,3 s y 5 s.
- Activity: agrupa Connections y Processes; los números aplican el filtro de protocolo e ignoran
  el foco. Mientras Connections está activo, Connections cuenta también el filtro State;
  mientras Processes está activo, Processes cuenta también la búsqueda. Protocols muestra la
  barra y la leyenda de los seis tipos; el filtro IP reduce el desglose, el filtro Transport no.
- Los selectores Transport/IP aparecen solo en Connections/Processes; el contador muestra
  “N of M” y la tabla respeta ambos filtros combinados con el foco.
- Connections muestra en su cabecera el selector State (All, Established, Listening, Connecting
  (SYN), Closing (Close/Fin/Time Wait), Other); la columna State sigue mostrando el valor exacto.
  La normalización cubre `Listen`, `Established`, `SynSent`, `TimeWait`, `TSI_*`, etc. UDP no
  tiene estado, así que cualquier categoría seleccionada oculta sus filas.
- Processes muestra en su cabecera `Filter processes` y filtra por nombre, ruta, PID o usuario,
  igual que CPU. El contador “N of M” refleja la búsqueda.
- State solo se aplica en Connections y la búsqueda solo en Processes; al cambiar de subpestaña
  se conservan, pero no afectan a la otra tabla.
- `--networking-transport all` y `--networking-ip all` equivalen a “All”;
  `--networking-state all` y un valor desconocido equivalen a sin filtro de estado.

Tabla de Connections (orden y columnas):

```bash
$APP --screenshot /tmp/kb-connections-columns.png --section networking \
  --tab connections --screenshot-delay 5
```

- Orden de columnas: Local, Remote, Protocol, RX, TX, State, Iface, PID y Process (última).
- Pulsar cada cabecera: debe mostrarse el indicador de orden y alternar ascendente/descendente.
  Local/Remote ordenan numéricamente (no `10.x` antes que `2.x`); RX/TX/PID numéricamente; el
  resto por texto.
- Seleccionar una fila, ordenar y cambiar de subpestaña/sección: la selección y el criterio de
  orden se conservan (estado de sesión en `UIState`). Si el filtro hace desaparecer la fila, la
  selección se limpia.
- Comprobar direcciones IPv6 largas (truncadas con tooltip) y el scroll horizontal a 1040×640.

Tabla de Processes (flujos + sockets):

```bash
$APP --screenshot /tmp/kb-processes.png --section networking --tab processes \
  --screenshot-delay 12
./build/Build/Products/Debug/KancerberoProbe sockets-summary
./build/Build/Products/Debug/KancerberoProbe sockets <pid>
```

- La tabla solo lista procesos con flujos TCP/UDP o sockets (UNIX/RAW incluidos). Comparar los
  tipos y conteos con `lsof -nP -i`/`netstat` y con el inspector del proceso.
- Comprobar badges de protocolo (TCP4/TCP6/UDP4/UDP6/UNIX/RAW4/RAW6/OTHER), tipos de socket
  (stream/dgram/raw/seqpacket/other), Flows, RX/TX (Bytes) y “—” en procesos solo-locales.
- En modo local, los procesos de otros uid pueden mostrar Protocols/Flows/RX/TX pero Sockets
  “—” (restringido); con el daemon root deben mostrar también sus sockets.
- Ordenar por cada cabecera y comprobar que el criterio se conserva al cambiar de pestaña/sección.
- Verificar que el primer inventario de sockets puede añadir filas tras ~1–10 s sin cambiar las
  columnas ni la altura de la tabla. Comprobar CPU/RSS con el barrido periódico.

Continuidad de estado al cambiar de pestaña (manual):

1. Networking: seleccionar una conexión y un proceso, activar el botón Download de la tarjeta
   Traffic; ir a Disk y Daemons, volver → filtro y selecciones restauradas (si el flujo
   desapareció, se limpia).
2. Daemons: fijar búsqueda, tipo, ámbito, origen, estado y una selección; cambiar de sección y
   volver → todo restaurado; esperar 5 s y comprobar que la selección sigue si el servicio existe.
3. Disk → Volumes: expandir y colapsar varios nodos, activar la tarjeta Volumes, ir a Analyzer y
   volver → foco y expansión intactos. Refresh de volúmenes → no se re-expande. Pulsar All →
   árbol completo expandido y tarjeta All marcada.
4. Disk → Analyzer: activar Files y teclear una ruta sin escanear; cambiar de pestaña y volver →
   foco y borrador conservados.
5. Reiniciar la app: el estado de UI vuelve a los valores iniciales; sección y subpestañas se
   recuerdan por `@AppStorage`.

## Disk

Inventario y detalle:

```bash
./build/Build/Products/Debug/KancerberoProbe disk volumes
diskutil list
ioreg -r -c IOMedia -w 0 | grep -E 'BSD Name|Whole|Content|Size'

./build/Build/Products/Debug/KancerberoProbe disk info disk3s5
diskutil info disk3s5
```

- La jerarquía debe coincidir con `diskutil list` y con el árbol `IOMedia` de `ioreg`: disco →
  partición → contenedor APFS (`AppleAPFSMedia`) → volumen (`AppleAPFSVolume`).
- El usado por volumen (`Used`/`CapacityInUse`) debe coincidir con `diskutil info`; procede de
  `getattrlist(ATTR_VOL_SPACEUSED)` y no de una API privada.
- `diskutil`, `ioreg` y `mount` se usan **solo como referencia externa**; la app no los ejecuta.
  Comprobación:

```bash
grep -R "diskutil" Sources/ || echo "sin diskutil en el código"
```

Escaneo:

```bash
./build/Build/Products/Debug/KancerberoProbe disk scan "$HOME/Documents" --top 20
du -skx "$HOME/Documents"     # KB; multiplicar por 1024 para bytes
```

- Tolerancia orientativa ±2–5 %. Diferencias esperadas: hard links (se cuentan por entrada),
  clones/compresión/snapshots APFS y rutas denegadas (se reportan aparte).
- Sin permisos, el escaneo debe continuar, marcar `accessDenied` y listar las rutas denegadas.
- Conectar/expulsar un volumen externo y comprobar que Volumes se refresca; un volumen desmontado
  aparece sin mount point ni libre/usado.
- SMART no está disponible por APIs públicas y se muestra como “Unavailable”.

Capturas:

```bash
./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero \
  --screenshot /tmp/kb-disk-volumes.png --section disk --disk-tab volumes \
  --screenshot-delay 5
./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero \
  --screenshot /tmp/kb-disk-analyzer.png --section disk --disk-tab analyzer \
  --disk-path="$HOME/Documents" --disk-scan --screenshot-delay 8
```

Mapa en vivo durante el escaneo:

```bash
K=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
$K --screenshot /tmp/kb-disk-live-a.png --section disk --disk-tab analyzer \
  --disk-path="$HOME/Library" --disk-scan --screenshot-delay 2
$K --screenshot /tmp/kb-disk-live-b.png --section disk --disk-tab analyzer \
  --disk-path="$HOME/Library" --disk-scan --screenshot-delay 5
```

- En ambas capturas deben verse la tarjeta de progreso, las tarjetas Scanned/Files/Folders/Denied
  con valores crecientes (Scanned con caption “scanning…”), el mapa radial creciendo y las
  etiquetas con nombre + tamaño humano. El panel derecho muestra el aviso de espera, sin tablas.
- Comparar `live-a` y `live-b`: los bytes, ficheros y sectores deben ser distintos (más grandes a
  los 5 s).
- Al terminar, las tablas de contenidos y mayores archivos aparecen y la tarjeta Scanned muestra la
  duración.
- Cancelar a mitad debe mostrar “Scan cancelled. Showing partial results.”, mantener el mapa y las
  tarjetas con el parcial y montar las tablas una sola vez; no debe haber más actualizaciones.
- Consola sin avisos de reentrancy de `NSTableView` durante el escaneo (las tablas no están
  montadas).

Nota: usa `--disk-path=<ruta>` (un solo argumento). Un valor posicional que sea una ruta existente
puede ser interpretado por macOS como “abrir documento” y bloquear la ventana antes de la captura.

## Servicio en background (SMAppService)

```bash
./scripts/build-release.sh
codesign --verify --deep --strict --verbose=2 \
  build/Build/Products/Release/Kancerbero.app
./scripts/notarize.sh
./scripts/install-app.sh
open /Applications/Kancerbero.app
```

- En el footer del sidebar o en el menú **Daemon**, pulsar “Enable background daemon”.
  El estado debe pasar a `requiresApproval` o `enabled`; “Allow in Settings…” abre Login Items.
- Aprobar en **Ajustes → General → Login Items & Extensions → Allow in the Background**. El
  ítem debe mostrar **Kancerbero con el icono de la app**.
- `launchctl print system/uno.kayros.kancerbero.daemon` y
  `log show --predicate 'subsystem == "uno.kayros.kancerbero"' --last 5m --info`.
- La app debe pasar a “Daemon connected” y usar XPC privilegiado. Desregistrar debe detenerlo y
  volver a modo local.
- Sin notarización, Gatekeeper marca la app como “Unnotarized Developer ID” y el registro del
  daemon no es fiable; completar `notarytool store-credentials` + `scripts/notarize.sh`.
- Antes de registrar, eliminar los plists legacy (`scripts/uninstall-agent.sh`,
  `sudo scripts/uninstall-daemon.sh`).

## Rendimiento

```bash
ps -o pid,%cpu,rss,etime -p <pid-daemon>
sample <pid-daemon> 5 -file /tmp/kancerbero.sample.txt
leaks <pid-daemon>
```

Objetivo: CPU <3% y RSS <150 MB con miles de conexiones; sin crecimiento de memoria en una hora.
