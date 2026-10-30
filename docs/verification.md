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
  [--section networking|disk|daemons|cpu|memory|energy] \
  [--tab interfaces|connections|processes] \
  [--disk-tab volumes|analyzer|io] \
  [--disk-path=<carpeta>] [--disk-scan] [--disk-item <diskXsY>] \
  [--disk-io-search <texto>] [--disk-io-selected <pid>] \
  [--disk-io-graph data|operations] \
  [--cpu-search <texto>] [--cpu-selected <pid>] \
  [--memory-search <texto>] [--memory-selected <pid>] \
  [--energy-search <texto>] [--energy-selected <pid>] \
  [--screenshot-dock <ruta>] [--dock-style <estilo|all>] \
  [--networking-transport tcp|udp|other[,..]|all] \
  [--networking-ip ipv4|ipv6[,..]|all] \
  [--networking-state established|listening|connecting|closing|other[,..]|all] \
  [--networking-connection-search <texto>] [--networking-search <texto>] \
  [--networking-process-ip ipv4|ipv6[,..]|all] \
  [--networking-process-protocol tcp|udp|raw|unix|other[,..]|all] \
  [--networking-process-socket stream|dgram|raw|seqpacket|other[,..]|all] \
  [--sidebar-collapsed]
```

`--section` selecciona la sección de primer nivel, `--tab` la subpestaña de Networking,
`--disk-tab` la de Disk, `--disk-path`/`--disk-scan` lanzan el analizador sobre una ruta y
`--disk-item` preselecciona un dispositivo en Volumes. `--disk-tab io` abre la pestaña de
actividad; `--disk-io-search`/`--disk-io-selected` filtran y preseleccionan procesos y
`--disk-io-graph data|operations` elige el tipo de gráfico. `--cpu-search` aplica el filtro inicial de
la tabla de CPU, `--cpu-selected` preselecciona un PID, `--memory-search`/`--memory-selected`
hacen lo mismo en la tabla de Memory, `--energy-search`/`--energy-selected` en la de Energy,
`--screenshot-dock` renderiza el icono del Dock a PNG (256×256) y `--dock-style` elige el estilo
(`applicationIcon`, `cpuUsage`, `cpuHistory`, `networkUsage`, `diskActivity`, `memoryUsage`,
`memoryPressure`, `gpuUsage`, `energyUsage` o `all`),
`--networking-transport`/`--networking-ip`
marcan solo esos checkboxes (lista con comas; `all` equivale a todos), `--networking-state` marca
solo esas categorías de estado TCP, `--networking-connection-search` el filtro de proceso de
Connections y `--networking-search` el de la tabla de procesos. Los flags
`--networking-process-ip`/`--networking-process-protocol`/`--networking-process-socket` marcan los
grupos propios de Processes (misma sintaxis de lista). `--sidebar-collapsed`
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
  "--section memory" \
  "--section energy" \
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
- Los filtros de tipo, ámbito, origen y estado se combinan con AND entre grupos; dentro de un
  grupo, se muestran las filas de la unión de los valores pulsados. Todos los valores están
  pulsados al arrancar; si un grupo se queda sin pulsar, no se muestra ninguna fila. Las tarjetas
  Running / Stopped / Disabled reflejan el subconjunto filtrado y alternan ese estado en el
  conjunto; la tarjeta Services restablece todos los grupos y limpia la búsqueda.
- `--daemon-domain system|gui|user` sigue funcionando como atajo: system selecciona daemons y
  gui/user seleccionan agentes. Los flags `--daemon-type`, `--daemon-scope`, `--daemon-origin` y
  `--daemon-state` aceptan listas separadas por comas (p. ej. `--daemon-scope system,user`).
- La tabla se ordena pulsando cualquier cabecera (ascendente/descendente). Label, Program y Plist
  comparan sin distinguir mayúsculas y dejan los valores ausentes («—») al final en ascendente;
  PID usa un centinela para los servicios sin proceso; State sigue Running → Stopped → Disabled →
  Not loaded y Type/Scope usan rangos enteros. El orden se conserva al refrescar (5 s) y al
  cambiar de pestaña; sin orden elegido se mantiene el del deduplicador. Las capturas no pueden
  pulsar cabeceras, así que esta comprobación es manual.
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
$K --screenshot /tmp/kb-disk-io.png --section disk \
  --disk-tab io --screenshot-delay 6
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
- El toggle “Animate status bar values” se guarda en `statusBarTextAnimationsEnabled` y por
  defecto está **apagado**: las cifras de la barra inferior cambian de golpe y el `numericText`
  no rueda. Al encenderlo vuelven esas animaciones; con Reduce Motion activo no se animan.
- El filtro All/Agents/Daemons sigue animando su píldora con el toggle apagado, porque es un
  filtro y no una pestaña.
- Confirmar que siguen animándose sparklines, hover de tarjetas, paneles de detalle, filtros/foco
  y LiveDot; los valores de la barra de estado solo con su toggle encendido.

## Intervalo de actualización

- Con daemon conectado, ejecutar

```bash
log stream --predicate 'subsystem == "uno.kayros.kancerbero"' --info --debug
```

  y cambiar el selector 5 → 0,5 → 2 s desde el toolbar (visible en todas las pestañas). Debe
  aparecer un `resubscribed interval=…` en el cliente y un nuevo `subscribed interval=…` en el
  daemon por cada valor distinto. Volver a seleccionar el mismo valor no debe reenviar la
  suscripción.
- Comprobar la cadencia real por la hora de “Updated” y el avance de los sparklines: a 0,5 s la
  ventana de 60 muestras abarca ~30 s; a 5 s, ~5 min. Los historiales se conservan al cambiar el
  intervalo y el eje temporal usa las marcas de `sampleDates`, así que no mezcla cadencias.
- Regresión de cadencia lenta: con **5 s**, las gráficas y cifras basadas en tasas (tráfico de
  red, Disk → I/O y columnas de CPU%, energía, wakeups e I/O por proceso) deben seguir avanzando
  cada ~5 s, no quedarse a 0. Pausar más que `max(5 s, 2,5 × cadencia)` y reanudar debe producir
  una muestra a 0 y la siguiente normal.
- Sin daemon, cambiar de 5 s a 0,5 s y verificar que la siguiente actualización llega en ~0,5 s,
  no tras el sueño anterior. Pausa/Play debe seguir funcionando y el refresh manual debe
  actualizar aunque esté pausado.
- El selector está en el toolbar de todas las pestañas. Daemons mantiene su refresco de 5 s y Disk
  su caché de inventario, así que el selector no cambia la cadencia de esas dos vistas.
- El intervalo de arranque se ajusta en **Settings → Sampling** (`startupSamplingInterval`, por
  defecto 2 s). Cambiar el selector del toolbar y reiniciar la app debe volver al valor de
  Settings, no al último elegido. Para probar sin la UI:
  `defaults write uno.kayros.kancerbero startupSamplingInterval -float 5` (y
  `defaults delete uno.kayros.kancerbero startupSamplingInterval` para volver a 2 s).

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
- El recuento de procesos debe coincidir con `ps -ax | wc -l` y `top -l 1 -n 0` (±5) e incluir
  kernel_task (PID 0). Como usuario, `threads` es menor que `top` y la UI muestra
  “partial”/“N restricted”; con el daemon root actualizado coinciden procesos e hilos. Si el
  daemon es antiguo, System status muestra “Process data Incomplete — N of M processes”.
- Igual que en otras tablas con refresco en vivo, macOS 27 puede registrar
  `reentrant operation in its NSTableView delegate`; no afecta a los datos.
- Para fugas: dejar la pestaña abierta varios minutos con intervalo de 0,5 s y comprobar que el
  RSS de Kancerbero se mantiene estable (`ps -o rss`, `leaks`). El sampler libera el array de
  `host_processor_info` y el puerto Mach en cada tick.
- Altura de las cards: al maximizar o estirar la ventana, la franja superior de CPU, Memory,
  Energy y Disk → I/O se mantiene en 210 pt (`KBTheme.cardStripHeight`) y todo el espacio extra
  lo absorbe la tabla de procesos. Comparar una captura a 1440×860 con otra de ventana más alta.

Pestaña Memory:

```bash
P=./build/Build/Products/Debug/KancerberoProbe
K=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
$P cpu --interval 1 | grep -E "memoryAM|pressure"
$K --screenshot /tmp/kb-memory.png --section memory --screenshot-delay 6
$K --screenshot /tmp/kb-memory-filter.png --section memory \
  --memory-search java --screenshot-delay 6
```

- `memoryAM` imprime los valores de Activity Monitor: `app = internal − purgeable`,
  `cachedFiles = external + purgeable`, `used = app + wired + compressed`. Compararlos con
  `vm_stat` (internal/external/purgeable × page size) y con Activity Monitor (±1%) y con
  `memory_pressure`/`sysctl kern.memorystatus_vm_pressure_level` para la presión.
- La composición App/Wired/Compressed/Cached/Free debe sumar la memoria física (±1%). La tabla
  está ordenada por memoria residente: comparar el primer `Memory` con `ps -o rss` del mismo PID.
- Filtrar (`--memory-search`), seleccionar e inspeccionar; los procesos sin task info muestran
  `—` y el aviso “your processes only” aparece sin daemon root.

Pestaña Energy:

```bash
P=./build/Build/Products/Debug/KancerberoProbe
K=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
$P cpu --interval 1 | grep -E "energy|power|preventingSleep"
pmset -g batt
pmset -g assertions | grep -E "pid [0-9]+" | head
$K --screenshot /tmp/kb-energy.png --section energy --screenshot-delay 6
$K --screenshot /tmp/kb-energy-filter.png --section energy \
  --energy-search java --screenshot-delay 6
```

- `power` debe coincidir con `pmset -g batt` (carga, cargando, conector y fuente); la lista de
  `preventingSleep` debe coincidir con las assertions `PreventUserIdleSystemSleep`/`PreventSystemSleep`
  de `pmset -g assertions`.
- `energy` imprime el proceso con más vatios y sus wake-ups; comparar el orden con la pestaña
  Energy de Activity Monitor y con `top`. La energía por proceso sale de `ri_energy_nj` y los
  wake-ups de `ri_interrupt_wkups + ri_pkg_idle_wkups` (rusage_info_v6), convertidos a tasas por
  `ProcessCPUTracker`. Solo se incluye el histórico de la sesión; la media de 12 h y la energía de
  la GPU no se muestran.
- Sin daemon root la tabla solo enumera procesos del uid actual; el fallback local rellena
  energía/batería cuando el daemon conectado es antiguo.
- La card Battery muestra el gráfico de 12 h al estilo Activity Monitor → Energy: línea cian del
  nivel, bandas verdes del periodo en AC y rejilla discontinua. Comparar la forma y la ventana con
  Activity Monitor y la fuente con `pmset -g batt`. Al enchufar/desenchufar, la banda verde cambia
  en el siguiente refresco (≤60 s) o al abrir el popover.
- Sin batería, o si `systemstats_get_battery_charge_graph` no está disponible en el sistema, la
  card vuelve a la barra de capacidad sin errores ni avisos (ver `docs/private-apis.md`).

Icono del Dock:

```bash
K=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
$K --screenshot-dock /tmp/dock.png --dock-style all --screenshot-delay 6
ioreg -r -d 1 -w 0 -c IOBlockStorageDriver | grep Statistics
```

- Se generan `/tmp/dock-<estilo>.png` (CPU usage/history, red, disco, memoria, presión, GPU,
  energía). Cada tile debe ser legible: CPU History apilado, NET/DISK con dos gráficos
  (RX/TX, lectura/escritura) e importes que coinciden con las pestañas.
- En la app, el menú **Dock Icon** (y Ajustes → Dock) cambia el icono en vivo; “Show Application
  Icon” restaura el icono; la elección persiste en `dockIconStyle` y `Clear History` vacía los
  históricos. El controlador sigue refrescando con la ventana cerrada.
- La actividad de disco sale de `IOBlockStorageDriver.Statistics` (`Bytes (Read)`/`Bytes (Write)`)
  y es host-wide sin privilegios; comparar las tasas con deltas de `ioreg`.

Tarjeta Traffic, Activity, Protocols y filtros de protocolo:

```bash
APP=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
$APP --screenshot /tmp/kb-net-cards.png --section networking --tab interfaces \
  --screenshot-delay 5
$APP --screenshot /tmp/kb-net-tcp.png --section networking --tab connections \
  --networking-transport tcp --screenshot-delay 5
$APP --screenshot /tmp/kb-net-ipv6.png --section networking --tab connections \
  --networking-ip ipv6 --screenshot-delay 5
$APP --screenshot /tmp/kb-net-tcp-udp.png --section networking --tab connections \
  --networking-transport tcp,udp --screenshot-delay 5
$APP --screenshot /tmp/kb-net-connection-search.png --section networking --tab connections \
  --networking-connection-search rapportd --networking-transport tcp --screenshot-delay 5
$APP --screenshot /tmp/kb-net-combined.png --section networking --tab connections \
  --networking-focus connections --networking-transport udp --networking-ip ipv4 \
  --screenshot-delay 5
$APP --screenshot /tmp/kb-net-download.png --section networking --tab connections \
  --networking-focus download --screenshot-delay 5
$APP --screenshot /tmp/kb-net-state-listening.png --section networking \
  --tab connections --networking-state listening --screenshot-delay 5
$APP --screenshot /tmp/kb-net-state-established.png --section networking \
  --tab connections --networking-state established --screenshot-delay 5
$APP --screenshot /tmp/kb-net-state-multi.png --section networking \
  --tab connections --networking-state established,listening --screenshot-delay 5
$APP --screenshot /tmp/kb-net-state-combined.png --section networking \
  --tab connections --networking-state established \
  --networking-transport tcp --networking-ip ipv4 --screenshot-delay 5
$APP --screenshot /tmp/kb-net-process-search.png --section networking \
  --tab processes --networking-search rapportd --screenshot-delay 5
$APP --screenshot /tmp/kb-net-process-proto.png --section networking \
  --tab processes --networking-process-protocol tcp,unix --screenshot-delay 12
$APP --screenshot /tmp/kb-net-process-socket.png --section networking \
  --tab processes --networking-process-socket stream,dgram --screenshot-delay 12
$APP --screenshot /tmp/kb-net-process-ip.png --section networking \
  --tab processes --networking-process-ip ipv4 --screenshot-delay 12
$APP --screenshot /tmp/kb-net-process-independent.png --section networking \
  --tab processes --networking-transport udp --screenshot-delay 12
```

- Traffic: Download/Upload en la cabecera, gráfico espejado con cuadrícula, etiquetas Y en
  `bps/Kbps/Mbps/Gbps` y eje temporal `-60s/-30s/now` (con el intervalo de 1 s). Sin salto de
  layout entre 0,3 s y 5 s.
- Activity: agrupa Connections y Processes; los números ignoran el foco y aplican los filtros de
  la pestaña activa. En Connections, protocolo (Transport/IP), State y búsqueda de conexión; en
  Processes, sus facetas (IP, Protocolos, Socket type) y su búsqueda. Protocols muestra la barra y
  la leyenda de los seis tipos; el filtro IP de Connections reduce el desglose, el Transport no.
- La cabecera de Connections agrupa en cápsulas los checkboxes **IP** (IPv4/IPv6), **Transport**
  (TCP/UDP/Other) y **State** (Established, Listening, Connecting (SYN), Closing
  (Close/Fin/Time Wait), Other), todos marcados por defecto, más `Filter process`. Desmarcar un
  valor excluye sus filas; desmarcar todo un grupo deja “0 of M connections” (Activity 0). Con el
  grupo State completo las filas UDP siguen visibles; con un subconjunto se ocultan. La familia de
  dirección desconocida se excluye cuando el grupo IP no está completo.
- La cabecera de Processes añade en cápsulas **IP** (IPv4/IPv6), **Protocols**
  (TCP/UDP/RAW/UNIX/OTHER) y **Socket type** (stream/dgram/raw/seqpacket/other). Un IP parcial
  exige algún badge de la familia marcada y excluye las filas solo-UNIX/OTHER; un Socket type
  activo exige datos de sockets y oculta las filas con Sockets «—»; todo marcado = sin filtro y un
  grupo vacío no muestra filas.
- Los filtros son **independientes por subpestaña**: marcar/desmarcar en Connections no altera la
  tabla ni el contador de Processes (ni al revés). Se conservan al cambiar de pestaña.
- Los grupos aparecen en una **barra a todo el ancho entre las pills y la tarjeta** de la tabla;
  la tarjeta ya no los contiene y su cabecera solo muestra título, búsqueda e Inspect. Interfaces
  y Filter no muestran barra (sin hueco extra). A 1040×640 la barra cae a dos líneas sin
  recortarse.
- Processes muestra en su cabecera `Filter processes` y filtra por nombre, ruta, PID o usuario,
  igual que CPU. El contador “N of M” refleja sus facetas y la búsqueda. La columna Protocols
  muestra todos los badges (sin `+N`) y Sockets todos sus tipos.
- CLI: `--networking-transport`/`--networking-ip`/`--networking-state` marcan los grupos de
  Connections y `--networking-process-ip`/`--networking-process-protocol`/
  `--networking-process-socket` los de Processes; `all`, una lista sin valores válidos o un valor
  desconocido no filtran.

Tabla de Connections (orden y columnas):

```bash
$APP --screenshot /tmp/kb-connections-columns.png --section networking \
  --tab connections --screenshot-delay 5
```

- Orden de columnas: Process, PID, Local, Remote, Proto, RX, TX, State e Iface.
- Pulsar cada cabecera: debe mostrarse el indicador de orden y alternar ascendente/descendente.
  Local/Remote ordenan numéricamente (no `10.x` antes que `2.x`); RX/TX/PID numéricamente; el
  resto por texto. Process ordena por nombre (con Unknown para PID sin nombre).
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
- Comprobar todos los badges de protocolo (TCP4/TCP6/UDP4/UDP6/UNIX/RAW4/RAW6/OTHER) sin `+N`,
  los tipos de socket (stream/dgram/raw/seqpacket/other), Flows, RX/TX (Bytes) y “—” en procesos
  solo-locales. Con 8 badges la columna Protocols llega a su ancho ideal y la tabla puede requerir
  scroll horizontal en ventanas estrechas.
- En modo local, los procesos de otros uid pueden mostrar Protocols/Flows/RX/TX pero Sockets
  “—” (restringido); con el daemon root deben mostrar también sus sockets. Con un Socket type
  activo esas filas «—» desaparecen; con el grupo completo siguen visibles.
- Probar los tres grupos de la cabecera en cápsula: IP, Protocols y Socket type. Desmarcar todo un
  grupo deja “0 of M networked processes”; desmarcar `UNIX`/`RAW` oculta los procesos que solo
  tienen esos badges; con IP parcial desaparecen los solo-UNIX/OTHER.
- En Protocols, un proceso con sockets de familia especial debe mostrar el valor real en gris
  (`AF_SYSTEM`, `AF_NDRV`, `AF_VSOCK`…) en vez de `OTHER`; un provider NStat no TCP/UDP debe
  mostrarse tal cual. Ninguna familia definida en `sys/socket.h` (3–25, 27–38, 40) debe salir como
  `AF_<n>`; solo 26 y 39, que no existen en Darwin. Un flujo TCP/UDP cuya versión IP no se conoce
  se etiqueta `TCP`/`UDP`, no `AF_UNSPEC`. OTHER queda solo como reserva sin detalle.
- Los badges `RAW4`/`RAW6` deben ceder su sitio al protocolo real: un `ping` en marcha muestra
  `ICMP`, y SCTP/GRE/ESP/… muestran su nombre; `RAW` queda para `SOCK_RAW`. La columna Proto del
  inspector (doble clic en la fila) debe coincidir. Se puede comprobar sin GUI:

  ```bash
  build/Build/Products/Debug/KancerberoProbe sockets $(pgrep -n -x ping)        # ICMP
  build/Build/Products/Debug/KancerberoProbe sockets <pid de un proceso TCP>     # TCP4/TCP6
  build/Build/Products/Debug/KancerberoProbe sockets-summary $(pgrep -n -x ping) # inet-protos=[ICMP]
  ```

  En modo local funciona directamente; en modo daemon hace falta que el daemon en marcha lleve el
  código nuevo (tras instalar, usar **Repair** en System status o reiniciar el servicio), porque un
  daemon antiguo no envía `otherFamilies` ni `otherProtocols`.
- Cambiar el filtro Transport/IP en Connections y volver a Processes: la tabla y el contador de
  Processes no cambian (filtros independientes).
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
./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero \
  --screenshot /tmp/kb-disk-io.png --section disk --disk-tab io \
  --screenshot-delay 6
```

- En la captura de I/O, copiar un archivo grande mientras la pestaña está abierta: el gráfico y
  las tasas Read/Write deben moverse; Data/Operations cambia las unidades; los totales
  “Reads in/Writes out/Data read/Data written” deben coincidir con
  `ioreg -r -d 1 -w 0 -c IOBlockStorageDriver | grep Statistics`. La tabla se ordena por
  actividad y los procesos sin contadores (`usage` nulo o daemon antiguo) muestran “—”; el
  fallback local rellena los del usuario y el daemon actualizado todos.

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

- Pulsar **Local mode / Daemon connected** en el footer del sidebar, el pill **Local / Daemon** de
  la barra inferior o el icono de Kancerbero en la cabecera del sidebar; se abre la ventana
  **System status**.
- La ventana muestra el checklist y las acciones. “Enable background service” / “Open Login Items”
  deben llevar a `requiresApproval` o `enabled`; “Repair / re-register…” pide confirmación y
  desregistra/registra el helper para que macOS pueda volver a pedir aprobación.
- Aprobar en **Ajustes → General → Login Items & Extensions → Allow in the Background**. El
  ítem debe mostrar **Kancerbero con el icono de la app**.
- `launchctl print system/uno.kayros.kancerbero.daemon.v2` y
  `log show --predicate 'subsystem == "uno.kayros.kancerbero"' --last 5m --info`.
- Comprobar la firma del daemon embebido antes y después de instalar:
  `codesign -dvvv .../KancerberoDaemon` debe mostrar `Identifier=uno.kayros.kancerbero` (el mismo
  que la app) y `codesign -d --entitlements - --xml` un diccionario vacío. Si launchd lo mata,
  el log del kernel muestra `AMFI: Launch Constraint Violation ... c[5]p[1]m[1]e[0]` y Login
  Items sigue diciendo “enabled”. Un registro BTM antiguo que no coincide no se arregla
  re-registrando el mismo label: `sudo sfltool resetbtm` + reinicio, o usar la identidad `.v2`.
- La app registra el servicio sola al arrancar si está en `/Applications` y el usuario no lo ha
  desactivado; un cambio de ejecutable/plist la re-registra una vez por ejecución. System status
  muestra el proceso real (`Daemon process`), su PID y el último error de conexión.
- La app debe pasar a “Daemon connected” y usar XPC privilegiado. Desregistrar debe detenerlo y
  volver a modo local.
- Sin notarización, Gatekeeper marca la app como “Unnotarized Developer ID” y el registro del
  daemon no es fiable; completar `notarytool store-credentials` + `scripts/notarize.sh`.
- Antes de registrar, eliminar los plists legacy (`scripts/uninstall-agent.sh`,
  `sudo scripts/uninstall-daemon.sh`). La ventana detecta el agente/daemon legacy, muestra los
  comandos y los copia; no los ejecuta.

### Verificación visual de la ventana

`ScreenshotMode` captura solo la ventana principal; para la ventana **System status** se usa
`screencapture` desde Otty, que tiene permiso de Grabación de pantalla. El hook `--show-status`
auto-abre la ventana System status; `--sidebar-collapsed` solo cambia el layout de la ventana
principal y ya no elige qué indicador la abre.

```bash
APP=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero

"$APP" --show-status &
PID=$!
sleep 3
osascript -e 'tell application "Kancerbero" to activate'
sleep 2
# Capturar solo la ventana System status: con -w se elige con el ratón;
# también se puede usar -l <windowid> obtenido de CGWindowListCopyWindowInfo.
screencapture -x -w /tmp/kb-status.png
kill "$PID" 2>/dev/null || true
```

Revisar que se ven el banner general, las filas del checklist, el botón Repair y las acciones. El contenido
restante (pasos y troubleshooting) está en el ScrollView. Probar los estados
`unregister`/`register` y la confirmación de Repair; no se puede automatizar la aprobación de
macOS. Evitar capturas de pantalla completa: pueden incluir ventanas ajenas.

## Filtro de red (Network Extension)

### Prerrequisitos

- Certificado **Developer ID Application** instalado en el llavero
  (`security find-identity -v -p codesigning | grep "Developer ID Application"`). Una identidad
  Apple Distribution no sirve para system extensions.
- App ID `uno.kayros.kancerbero` con **System Extension** y Network Extensions; App ID
  `uno.kayros.kancerbero.filter` con Network Extensions. El entitlement es de autoservicio: no
  hay que pedir aprobación a Apple.
- Dos provisioning profiles **Developer ID** (app y extensión), instalados en el Mac. Los perfiles
  Developer ID añaden automáticamente el sufijo `-systemextension` a los valores de Network
  Extension; los de desarrollo no.
- `Config/Signing.local.xcconfig` (ver el `.example`) con `KANCERBERO_APP_PROFILE` y
  `KANCERBERO_FILTER_PROFILE`. `scripts/build-release.sh` falla si el archivo o las variables
  faltan, o si no hay identidad Developer ID.
- Debug firma automático con **Apple Development**: usa
  `Resources/App/Kancerbero-Development.entitlements` y
  `Resources/Filter/KancerberoFilter-Development.entitlements` (valor `content-filter-provider`,
  sin sufijo). Release usa `Resources/App/Kancerbero.entitlements` y
  `Resources/Filter/KancerberoFilter.entitlements` (valor `-systemextension`).
- `systemextensionsctl developer on` (para activar builds fuera de `/Applications`) solo está
  disponible con **SIP desactivado**; con SIP activo un build Debug no puede activar la extensión.

### Build y firma

```bash
./scripts/build-release.sh
APP=build/Build/Products/Release/Kancerbero.app
EXT="$APP/Contents/Library/SystemExtensions/uno.kayros.kancerbero.filter.systemextension"
codesign -dv --entitlements :- "$APP"
codesign -dv --entitlements :- "$EXT"
security cms -D -i "$APP/Contents/embedded.provisionprofile" | plutil -p - | grep -A6 Entitlements
codesign --verify --deep --strict --verbose=2 "$APP"
./scripts/notarize.sh
./scripts/install-app.sh
open /Applications/Kancerbero.app
```

Comprobar que app, extensión y daemon tienen `Authority=Developer ID Application`, hardened
runtime y timestamp; que la app no lleva `get-task-allow`; que ambas firmas llevan
`com.apple.developer.networking.networkextension` con el valor `-systemextension` (la app además
`com.apple.developer.system-extension.install`); y que app y extensión tienen
`Contents/embedded.provisionprofile`. `spctl -a -vvv -t exec` debe aceptar la app como
`Notarized Developer ID`.

### Problemas conocidos: sysextd rechaza la activación

- `no policy, cannot allow apps outside /Applications`: el build no está firmado con Developer ID
  (aunque el bundle esté en `/Applications`); los builds Apple Development/ad-hoc no tienen
  policy de activación.
- `Failing to realize … developer/groundhog mode isn't on`: developer mode desactivado.
  `csrutil status` debe informar de SIP desactivado para poder activarlo.
- Ambos casos son rechazos de firma/política, no un bundle mal formado. La app traduce ese error
  a `.extensionNotFound`; la pestaña Filter muestra el detalle técnico y **Copy diagnostics**.
- Leer el registro crudo:
  `log show --last 10m --predicate 'process == "sysextd"' --info --debug | grep -i kancerbero`.
- Si hubiera una versión antigua registrada:
  `sudo systemextensionsctl uninstall AK37TK8X2Y uno.kayros.kancerbero.filter`.

### Activación y canal XPC

1. Abrir **Filter** (`--section networking --tab filter`) y pulsar **Install filter extension**.
2. Aprobar la system extension en **Ajustes → General → Login Items & Extensions**.
3. Aprobar el aviso “quiere filtrar el contenido de red” al habilitar el filtro.
4. `systemextensionsctl list | grep kancerbero` debe mostrar `[activated enabled]`.
5. La cabecera de Filter muestra estado y `1 app client`; `log stream --predicate
   'subsystem == "uno.kayros.kancerbero.filter"'` sin errores de XPC.

### Fase 0 (validar antes de confiar en la contabilidad)

- Identidad: vigilar `/usr/bin/curl`, lanzar `curl https://example.com` y comprobar que la
  petición muestra pid/path correctos (audit token → `proc_pidpath` funciona en el sandbox).
- Estadísticas: comprobar que llegan eventos `.statistics` y si los bytes son acumulados o
  delta; el modelo ya calcula deltas y toma `.flowClosed` como total final. Si `.statistics` no
  llega en esta versión de macOS, la tabla mostrará 0 hasta el cierre del flujo.

### Pruebas funcionales

1. **Aprobación**: vigilar `/usr/bin/curl` con el escudo de **Processes**. Cada conexión nueva
   abre la hoja (y notificación si la app está en segundo plano):
   - *Allow once* → la conexión funciona.
   - *Deny once* → `curl` falla de inmediato.
   - *Always allow this app* / *app + destination* → no vuelve a preguntar según la opción.
2. **Fail-closed**: cerrar Kancerbero y repetir `curl` desde el proceso vigilado sin decisión
   recordada → conexión bloqueada; al reabrir la app aparece en **Recent blocks** como
   `no app`. Con una decisión recordada de allow → permitida.
3. **UDP**: pausa de más de 10 s → el sistema descarta el flujo; la app debe haber denegado a
   los ~8 s.
4. **Contabilidad**: `curl -o /dev/null https://…/10MB` desde un proceso vigilado y permitido;
   comparar RX/TX de la pestaña Filter con la variación de `netstat -ib` y con nstat (margen por
   intervalo y tráfico excluido).
5. **Regresión**: con el filtro desactivado, Interfaces/Connections/Processes siguen funcionando
   con nstat; `scripts/verify.sh` sin cambios.

### Desinstalación

- **Disable** desactiva `NEFilterManager` y elimina su configuración.
- **Remove filter extension** (System status) desactiva la system extension.
- Tras borrar la app, comprobar que no quede el filtro habilitado en Ajustes del Sistema.

### Problemas conocidos

- macOS 26 ha reportado filtros que dejan de recibir flujos tras sleep/wake; si ocurre,
  desactivar y reactivar el filtro o reiniciar.
- Hasta 4 filtros del mismo grade pueden convivir; otras herramientas (Little Snitch, LuLu)
  pueden alterar el orden.
- El tráfico de procesos Apple excluidos no se observa ni se cuenta.

## Rendimiento

```bash
ps -o pid,%cpu,rss,etime -p <pid-daemon>
sample <pid-daemon> 5 -file /tmp/kancerbero.sample.txt
leaks <pid-daemon>
```

Objetivo: CPU <3% y RSS <150 MB con miles de conexiones; sin crecimiento de memoria en una hora.

## Applications

```bash
K=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
P=./build/Build/Products/Debug/KancerberoProbe
$P apps
KB_APPS_LEFTOVERS=com.anthropic.claudefordesktop $P apps
$K --screenshot /tmp/kb-apps.png --section applications --screenshot-delay 10
$K --screenshot /tmp/kb-apps-claude.png --section applications \
  --applications-selected Claude --screenshot-delay 10
```

- Para Antigravity el panel debe mostrar **5 entradas** (app + 4: Application Support, el PNG
  de Logi, Preferences y Logs), igual que AppCleaner; `--applications-scope user` y
  `--applications-search` permiten comprobar los filtros.
- `apps` debe coincidir con `find /Applications -maxdepth 2 -name '*.app'` (más `~/Applications`,
  widgets y plugins) y `KB_APPS_LEFTOVERS` debe listar preferencias, Application Support, caches,
  contenedores, saved state, launch items y logs reales de esa app.
- La tabla muestra icono, nombre, bundle id, tipo, origen (System/User) y tamaño del
  seleccionado; el buscador está dentro de la tarjeta de la tabla y los chips filtran por tipo y
  por origen. El panel derecho es una lista plana con la app siempre marcada (check fijo) y cada
  relacionada en dos líneas (nombre y ruta) con su icono, tamaño y marca `admin` cuando toca.
- Mover a la papelera una app de prueba en `~/Applications` con un plist y una carpeta en
  `~/Library`: todo debe acabar en `~/.Trash` y la lista refrescarse.
- Rutas privilegiadas (`/Library/Application Support/...`, apps de `/Applications` propiedad de
  root): requieren el daemon instalado y actualizado; comprobar que acaban en el `~/.Trash` del
  usuario con `stat -f "%Su %Sg %Sp"` y revisar
  `log show --predicate 'subsystem == "uno.kayros.kancerbero"' --last 5m`.
- LaunchAgents/Daemons: el plist se descarga (`launchctl print ...` falla) antes de moverse.
- Negativos: cliente no autorizado, ruta fuera de la lista blanca, symlink a `/System`, >256 rutas
  y >1 MiB deben rechazarse; sin daemon, los ítems privilegiados fallan con un mensaje claro y
  los del usuario siguen funcionando.
