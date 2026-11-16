# Verificación

## Build y probe

```bash
./scripts/clean.sh --debug        # build limpio (borra build/ antes de compilar)
./scripts/build.sh
./build/Build/Products/Debug/KancerberoProbe symbols
./build/Build/Products/Debug/KancerberoProbe procs --limit 10
./build/Build/Products/Debug/KancerberoProbe ifaces
./build/Build/Products/Debug/KancerberoProbe nstat --seconds 5
```

## Filesystems

```bash
./build/Build/Products/Debug/KancerberoProbe disk filesystems
/bin/df -k -Y

# Pruebas independientes de porcentaje/APFS, inodos y límites numéricos:
xcrun swiftc Sources/KancerberoCore/Models/KBFilesystem.swift \
  Tests/KancerberoTests/FilesystemModelTests.swift \
  -o "$TMPDIR/kancerbero-filesystem-tests"
"$TMPDIR/kancerbero-filesystem-tests"
```

Comparar montajes, tipo y Size/Used/Available (el probe muestra bytes; `df -k`, bloques
de 1024 bytes). Capacity y %iused deben coincidir; permitir pequeños cambios de espacio/inodos
entre lecturas. APFS usa `ATTR_VOL_SPACEUSED`, no `Size − Available`, y Capacity usa
`ceil(Used / (Used + Available) × 100)`. Los montajes remotos/autofs se marcan como cached:
no se contacta al servidor para refrescarlos. Los fallos de permisos locales conservan las
cifras del kernel y muestran la advertencia correspondiente.

Abrir `--section disk --disk-tab filesystems` y comprobar ordenación, filtro, Refresh,
actualización a los 5 segundos, tooltips con rutas/cifras completas y Decimal/Binary.
Tras montar/desmontar un volumen, su fila debe aparecer/desaparecer. Los tamaños APFS
compartidos no se totalizan. Capturar también a 1340×700 para revisar el scroll y truncado.

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
- **Network statistics y selector Bits/Packets:** capturar
  `--section networking --traffic-graph bits` y `--traffic-graph packets`. La card **Network
  statistics** queda siempre la primera de la franja: tasas **Upload** arriba y **Download**
  debajo, en bits/s con pkt/s como subtítulo, y bajo un separador los totales acumulados de
  Bytes/Packets In/Out desde el arranque. Traffic se adapta hasta su mínimo; su cabecera reúne en
  una línea el título, la leyenda **Upload**/**Download** (punto de color y tasa en las unidades
  del modo activo) y el selector glass a la derecha (segmentado nativo en versiones anteriores);
  cada entrada de la leyenda alterna el foco de su dirección al pulsarla. Contrastar tasas con
  Activity Monitor → Network y
  totales con `netstat -ib` sumando `en*` y excluyendo `lo0`/`utun`. A 1340×700 comprobar que las
  tres cards siguen en una fila, sin recortes de Traffic, y que la cabecera mantiene título y
  selector legibles. `--cards-collapsed` oculta toda la franja.
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
K=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
"$K" --register-service
launchctl print system/uno.kayros.kancerbero.daemon.service
# la app debe mostrar "source: daemon" en la barra inferior
"$K" --unregister-service
```

## Captura visual de la UI sin TCC

`screencapture` requiere el permiso de Grabación de pantalla para el proceso host. La app puede
capturar su propia ventana con AppKit sin ese permiso:

```bash
build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero \
  --screenshot /tmp/kancerbero-ui.png \
  [--cards-collapsed] [--cards-expanded] \
  [--cards-collapsed-sections networking,cpu,...] \
  [--screenshot-size <ancho>x<alto>] \
  [--section networking|disk|daemons|cpu|memory|energy] \
  [--tab interfaces|connections|processes] \
   [--disk-tab volumes|filesystems|analyzer|io] \
  [--disk-path=<carpeta>] [--disk-scan] [--disk-item <diskXsY>] \
  [--disk-io-search <texto>] [--disk-io-selected <pid>] \
  [--disk-io-graph data|operations] \
  [--disk-units decimal|binary] \
  [--volumes-focus disks|containers|volumes|capacity|free] \
  [--volumes-maximized tree|details] \
  [--cpu-search <texto>] [--cpu-selected <pid>] \
  [--memory-search <texto>] [--memory-selected <pid>] \
  [--energy-search <texto>] [--energy-selected <pid>] \
  [--screenshot-dock <ruta>] [--dock-style <estilo|all>] \
  [--networking-transport tcp|udp|other[,..]|all] \
  [--networking-ip ipv4|ipv6[,..]|all] \
  [--networking-state established|listening|connecting|closing|other[,..]|all] \
  [--networking-connection-search <texto>] [--networking-interface-search <texto>] \
  [--networking-search <texto>] \
  [--networking-resolve-names] \
  [--networking-process-domain inet|inet6|unix|other[,..]|all] \
  [--networking-process-ip ipv4|ipv6[,..]|all] \
  [--networking-process-protocol tcp|udp|icmp|icmpv6|sctp|gre|esp|raw|other[,..]|all] \
  [--networking-process-socket stream|dgram|raw|seqpacket|other[,..]|all] \
  [--traffic-graph bits|packets] \
  [--show-status] [--show-about] \
  [--sidebar-collapsed]
```

Los flags **sin valor** (`--cards-collapsed`, `--cards-expanded`, `--sidebar-collapsed`,
`--disk-scan`, `--show-status`, `--show-about`, `--networking-resolve-names`) deben ir al final de
la línea de argumentos; si quedan en medio,
macOS puede abrir la app sin ventana principal y la captura no se genera. `--cards-collapsed` /
`--cards-expanded` fuerzan todas las tarjetas colapsadas/expandidas, `--cards-collapsed-sections`
un estado mixto y `--screenshot-size 1340x700` fija el tamaño de la ventana.

`--section` selecciona la sección de primer nivel, `--tab` la subpestaña de Networking,
`--traffic-graph bits|packets` cambia solo las unidades del gráfico de Traffic,
`--disk-tab` la de Disk, `--disk-path`/`--disk-scan` lanzan el analizador sobre una ruta y
`--disk-item` preselecciona un dispositivo en Volumes. `--disk-tab io` abre la pestaña de
actividad; `--disk-io-search`/`--disk-io-selected` filtran y preseleccionan procesos y
`--disk-io-graph data|operations` elige el tipo de gráfico. `--disk-units decimal|binary` cambia
el sistema de unidades de tamaño/velocidad de la pestaña Disk (por defecto decimal); sin el flag
se usa el valor guardado por el selector. `--volumes-maximized tree|details` maximiza la tarjeta
indicada al área de Volumes; sin selección, el detalle maximizado cae al layout normal.
`--cpu-search` aplica el filtro inicial de
la tabla de CPU, `--cpu-selected` preselecciona un PID, `--memory-search`/`--memory-selected`
hacen lo mismo en la tabla de Memory, `--energy-search`/`--energy-selected` en la de Energy,
`--screenshot-dock` renderiza el icono del Dock a PNG (256×256) y `--dock-style` elige el estilo
(`applicationIcon`, `cpuUsage`, `cpuHistory`, `networkUsage`, `diskActivity`, `memoryUsage`,
`memoryPressure`, `gpuUsage`, `energyUsage` o `all`),
`--networking-transport`/`--networking-ip`
marcan solo esos checkboxes (lista con comas; `all` equivale a todos), `--networking-state` marca
solo esas categorías de estado TCP, `--networking-connection-search` el filtro de proceso de
Connections y `--networking-search` el de la tabla de procesos.
`--networking-resolve-names` activa el checkbox **Resolve names** (solo sesión, apagado por
defecto) para capturar las tablas con hostnames. Los flags
`--networking-process-domain`/`--networking-process-protocol`/`--networking-process-socket`
marcan los grupos propios de Processes (misma sintaxis de lista);
`--networking-process-ip ipv4|ipv6` queda como alias de domain (inet/inet6) y
`--networking-process-protocol unix` se sustituye por `--networking-process-domain unix`.
`--sidebar-collapsed`
captura el panel lateral oculto. El PNG se escribe a escala de backing (2x en Retina) y la app
termina con código 0.

### Comando reproducible

```bash
# 1. Compilar
CONFIG=Debug ./scripts/build.sh

# 2. Capturar (los flags sin valor, SIEMPRE al final)
build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero \
  --screenshot /tmp/kb-disk-io.png \
  --section disk --disk-tab io \
  --screenshot-size 1440x860 \
  --screenshot-delay 3 \
  --cards-expanded
```

- `--screenshot-delay` espera a que llegue el primer snapshot del daemon (4 s por defecto); súbelo
  a 6-8 s si la captura sale con ceros o el analizador aún está escaneando.
- También se puede lanzar vía LaunchServices, pasando los mismos flags tras `--args`:
  `open build/Build/Products/Debug/Kancerbero.app --args --screenshot /tmp/kb.png ... --cards-expanded`.
- La app termina sola con código 0 y no requiere permisos de Grabación de pantalla.

**Errores frecuentes**

| Síntoma | Causa |
|---|---|
| No se genera el PNG y queda una ventana sin contenido (o ninguna ventana) | Un flag sin valor (`--cards-expanded`, `--cards-collapsed`, `--sidebar-collapsed`, `--disk-scan`, `--show-status`, `--show-about`, `--networking-resolve-names`) quedó en medio de los argumentos; muévelo al final. |
| El PNG sale con ceros o «Last 0 samples» | `--screenshot-delay` insuficiente o daemon no disponible; súbelo. |
| La captura no corresponde a la sección/pestaña pedida | Valor no válido en `--section`, `--tab` o `--disk-tab`; usa solo los de la lista superior. |
| Ventana recortada o tarjetas apiladas | Usa `--screenshot-size 1340x700` (mínimo soportado) o superior. |

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

## Tarjetas colapsadas

El botón global del toolbar (delante del selector de intervalo) colapsa/expande las tarjetas de
todas las secciones; el botón `Hide cards`/`Show cards` de cada cabecera cambia solo esa pestaña y
`Cmd+Shift+H` alterna el global. El estado es **solo de sesión**.

```bash
K=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
$K --screenshot /tmp/kb-col-cpu.png --section cpu --screenshot-delay 4 --cards-collapsed
$K --screenshot /tmp/kb-col-memory.png --section memory --screenshot-delay 4 --cards-collapsed
$K --screenshot /tmp/kb-col-energy.png --section energy --screenshot-delay 4 --cards-collapsed
$K --screenshot /tmp/kb-col-networking.png --section networking --screenshot-delay 4 --cards-collapsed
$K --screenshot /tmp/kb-col-daemons.png --section daemons --screenshot-delay 4 --cards-collapsed
$K --screenshot /tmp/kb-col-applications.png --section applications --screenshot-delay 4 --cards-collapsed
$K --screenshot /tmp/kb-col-disk-volumes.png --section disk --disk-tab volumes --screenshot-delay 4 --cards-collapsed
$K --screenshot /tmp/kb-col-disk-io.png --section disk --disk-tab io --screenshot-delay 5 --cards-collapsed
$K --screenshot /tmp/kb-col-disk-analyzer.png --section disk --disk-tab analyzer --screenshot-delay 5 --cards-collapsed
```

- En todas: título/subtítulo y botón `Show cards` visibles; tarjetas ocultas; filtros, controles,
  banners, tablas/mapa y tabla intactos; la tabla ocupa el espacio liberado sin recortes.
- Reset de filtros ocultos: `--section disk --disk-tab volumes --volumes-focus capacity
  --screenshot-delay 4 --cards-collapsed` muestra las tablas jerárquicas por disco (no la lista
  plana de capacidad); `--section networking --tab interfaces --networking-focus connections
  --screenshot-delay 4 --cards-collapsed` muestra «N interfaces», no «N of M».
- Estado mixto: `--cards-collapsed-sections networking,disk,daemons,memory,energy,applications`
  con `--section cpu` deja las tarjetas de CPU visibles y el resto ocultas. El botón global pasa a
  «Hide all»; al pulsarlo colapsa todas («Show all»); `Show cards` en CPU expande solo CPU.
- Ventana mínima: `--screenshot-size 1340x700`; el botón de cabecera y el global caben sin truncar.
- La sidebar no se recorta al redimensionar: el mínimo de la ventana (1340 pt) cubre el layout
  completo (sidebar de 252 pt + tabla de Connections) y la columna tiene ancho fijo
  (`KBTheme.sidebarWidth`), así que no queda a medias. Con el botón nativo de la toolbar o Ver >
  Ocultar barra lateral se oculta entera y se restaura con el mismo ancho.
- Con la sidebar oculta (`--sidebar-collapsed`), el mínimo baja a 1088×700: capturar con
  `--screenshot-size 1088x700` deja la ventana en 1088 (2176 px de ancho) y el contenido cabe
  entero, incluidas la columna Iface y la barra de estado. Pedir 1000 se queda también en 1088.
  Al volver a mostrar la sidebar el mínimo sube de nuevo a 1340.
- Reduce Motion o “Animate tab changes” desactivado: el cambio es instantáneo. El estado no se
  guarda en `UserDefaults` y desaparece al reiniciar.

## Apariencia

El primer botón del toolbar alterna claro/oscuro y su menú contextual vuelve a `system`. El valor
persiste en `UserDefaults` (`appearanceMode`); para las capturas se puede forzar sin escribir la
preferencia pasando una clave del dominio de argumentos:

```bash
K=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
$K -appearanceMode light --screenshot /tmp/kb-light.png --section disk \
  --disk-tab volumes --disk-item disk3s1s1 --screenshot-delay 5
$K -appearanceMode dark --screenshot /tmp/kb-dark.png --section disk \
  --disk-tab volumes --disk-item disk3s1s1 --screenshot-delay 5
$K --screenshot /tmp/kb-system.png --section disk --screenshot-delay 5
```

- Claro y oscuro: sidebar, tarjetas, tablas, treemap, barra de estado y barra de título cambian a
  la vez; el modo oscuro usa la rampa grafito del treemap.
- `system` (o sin clave) sigue la apariencia de macOS y reacciona a sus cambios.
- Las ventanas System status, Filter rules y Settings heredan el modo por `NSApp.appearance`.
- Las capturas de `--screenshot` solo incluyen el `contentView`, así que el botón del toolbar no
  aparece en ellas; comprobar manualmente el icono `moon`/`sun.max`, la alternancia y el menú
  “Use System Appearance”.

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

Disk (filtros CLI de Volumes): las antiguas tarjetas resumen ya no existen; `--volumes-focus`
sigue filtrando las tablas por disco para capturas y, sin foco, las tablas muestran la jerarquía
completa.

```bash
$K --screenshot /tmp/kb-disk-free.png --section disk \
  --disk-tab volumes --volumes-focus free --screenshot-delay 5
$K --screenshot /tmp/kb-disk-containers.png --section disk \
  --disk-tab volumes --volumes-focus containers --screenshot-delay 5
$K --screenshot /tmp/kb-vol-2col.png --section disk --disk-tab volumes \
  --disk-item disk3s1s1 --screenshot-delay 5
$K --screenshot /tmp/kb-vol-max.png --section disk --disk-tab volumes \
  --disk-item disk3s1s1 --volumes-maximized details --screenshot-delay 5
$K --screenshot /tmp/kb-vol-cols.png --section disk --disk-tab volumes \
  --disk-item disk0 --volumes-maximized tree --screenshot-delay 5
$K --screenshot /tmp/kb-vol-cols-narrow.png --section disk --disk-tab volumes \
  --disk-item disk0 --screenshot-size 1340x700 --screenshot-delay 5
$K --screenshot /tmp/kb-vol-5050.png --section disk --disk-tab volumes \
  --disk-item disk0 --disk-units decimal --screenshot-size 1440x900 \
  --screenshot-delay 5 --cards-expanded
$K --screenshot /tmp/kb-vol-noselect.png --section disk --disk-tab volumes \
  --volumes-focus disks --disk-units decimal --screenshot-size 1440x900 \
  --screenshot-delay 5 --cards-expanded
$K --screenshot /tmp/kb-vol-noscroll.png --section disk --disk-tab volumes \
  --disk-item disk4 --disk-units decimal --screenshot-size 1440x900 \
  --screenshot-delay 5 --cards-expanded
$K --screenshot /tmp/kb-vol-compact-1440.png --section disk --disk-tab volumes \
  --disk-item disk0 --disk-units decimal --screenshot-size 1440x900 \
  --screenshot-delay 5 --cards-expanded
$K --screenshot /tmp/kb-vol-compact-1340.png --section disk --disk-tab volumes \
  --disk-item disk0 --disk-units decimal --screenshot-size 1340x700 \
  --screenshot-delay 5 --cards-expanded
$K --screenshot /tmp/kb-vol-treemap-bone.png --section disk --disk-tab volumes \
  --disk-item disk0 --disk-units decimal --volumes-maximized details \
  --screenshot-size 1440x900 --screenshot-delay 5 --cards-expanded
$K --screenshot /tmp/kb-mountline-1440.png --section disk --disk-tab volumes \
  --disk-item disk0 --disk-units decimal --screenshot-size 1440x900 \
  --screenshot-delay 5 --cards-expanded
$K --screenshot /tmp/kb-mountline-details.png --section disk --disk-tab volumes \
  --disk-item disk0 --disk-units decimal --volumes-maximized details \
  --screenshot-size 1440x900 --screenshot-delay 5 --cards-expanded
$K --screenshot /tmp/kb-mediakind-1440.png --section disk --disk-tab volumes \
  --disk-item disk0 --disk-units decimal --screenshot-size 1440x900 \
  --screenshot-delay 5 --cards-expanded
$K --screenshot /tmp/kb-mediakind-tree.png --section disk --disk-tab volumes \
  --disk-item disk0 --disk-units decimal --volumes-maximized tree \
  --screenshot-size 1440x900 --screenshot-delay 5 --cards-expanded
$K --screenshot /tmp/kb-headers-1340.png --section disk --disk-tab volumes \
  --disk-item disk0 --disk-units decimal --screenshot-size 1340x700 \
  --screenshot-delay 5 --cards-expanded
$K --screenshot /tmp/kb-follow-disk4.png --section disk --disk-tab volumes \
  --disk-item disk4 --disk-units decimal --screenshot-size 1440x900 \
  --screenshot-delay 5 --cards-expanded
$K --screenshot /tmp/kb-disk-folders.png --section disk \
  --disk-tab analyzer --disk-path="$HOME/Documents" --disk-scan \
  --analyzer-focus folders --screenshot-delay 8
$K --screenshot /tmp/kb-disk-io.png --section disk \
  --disk-tab io --screenshot-delay 6
```

- Volumes: por defecto tablas 1/2 + detalle 1/2 (sin selección, las tablas ocupan todo); no existe
  una tercera tarjeta ni las tarjetas resumen superiores. El divisor central se puede arrastrar
  para repartir el ancho entre ambos paneles (mínimos de 300 pt para las tablas y 360 pt para el
  detalle) y la proporción se conserva durante la sesión. El panel izquierdo es una pila de tablas,
  una por disco, con cabecera colapsable en una línea (chevron, `Nombre — disk0`, tipo de medio más
  tenue y capacidad · usado · libre a la derecha, con textos contrastados) y todas abiertas por
  defecto. Cada tabla repite la cabecera
  **Name / Disk / Type / Size / Used / Free / Mounted / Mount**, con filas de una línea y sin
  indentación (la jerarquía se lee por los chevrons y la cabecera de la sección). Los títulos de
  Used, Free y Mounted van centrados, y los valores de Mounted también. La cabecera
  muestra separadores verticales arrastrables: al arrastrar uno, la columna cambia de ancho, Mount
  absorbe el espacio sobrante y el ancho se mantiene al cambiar de disco, sección o tamaño de
  ventana. Los anchos son de sesión y se comparten entre todas las tablas; los defaults son
  Name 132, Disk 70, Type 72, Size/Used/Free 46 y Mounted 50. Con esos anchos (~549 pt de mínimo)
  las ocho columnas caben a 1/2 en una ventana de 1440 sin barra horizontal; en 1340 cada tabla se
  desplaza horizontalmente si no caben. La tabla conserva su
  posición de scroll al seleccionar un elemento: ya no se centra ni se alinea la sección; solo
  cambian el resaltado y el detalle. Disk muestra el
  `deviceIdentifier` de cada fila (`disk0`, `disk0s2`, `disk3s1`…) tanto en las filas de la
  jerarquía como en las filas planas de `--volumes-focus`; Type combina el tipo con el sistema de
  ficheros
  (`Volume APFS`, `Partition MS-DOS`) y Mounted Yes/No solo en volúmenes y snapshots (`—` en el
  resto). Used muestra el valor y una
  mini barra (volúmenes: parte del usado del contenedor; resto: usado/capacidad); Free muestra `—`
  en volúmenes (libre compartido); Mount trunca con tooltip. Un contenedor sin volumen montado
  muestra `—` en Used/Free. La cabecera de la tarjeta muestra el nombre del disco con los chips de
  capacidad y de particiones/contenedores/volúmenes con nombre y número, en una sola línea (el
  título se trunca antes). No hay flecha
  de subir nivel.
- Columnas: en `kb-vol-cols.png` (árbol maximizado) se ven las ocho cabeceras y los separadores
  verticales; en `kb-vol-cols-narrow.png` se comprueba que la tabla estrecha conserva la cabecera
  y hace scroll horizontal. Arrastrar un separador a izquierda/derecha cambia el ancho, Mount
  absorbe el sobrante y el valor se mantiene al cambiar de disco o de sección (interacción manual).
  Las filas de un mismo panel comparten el mismo borde izquierdo, sin indentación, y los chevrons
  siguen expandiendo/colapsando la jerarquía.
- Tabla compacta: en `kb-vol-compact-1440.png` las ocho columnas caben en el panel a 1/2 sin barra
  horizontal; USED/FREE/MOUNTED están centrados, MOUNTED no se corta, Mounted muestra Yes/No/—
  centrado y Mount queda estrecho, con el texto del mount en el mismo color de tinta que el resto
  de celdas (no gris). Disk y Mounted son más estrechos que antes. En
  `kb-vol-compact-1340.png` se comprueba el comportamiento en la ventana mínima (puede requerir
  scroll por el ancho del panel).
- Cabeceras por disco: en `kb-mediakind-1440.png` cada cabecera muestra `Nombre — disk0` en una
  sola línea, sin identificador suelto, seguido del tipo de medio más tenue (`Internal`, `USB`,
  `Disk Image`…), y a la derecha `capacidad · usado · libre`. Los textos del título, tipo, resumen
  y cabecera de columnas usan tinta contrastada. En `kb-mediakind-tree.png` se comprueban disk0
  `Internal`, disk4/disk10 `USB` y disk6/disk8 `Disk Image`.
- Divisor de paneles: en `kb-vol-5050.png` las dos tarjetas ocupan aproximadamente la mitad y el
  divisor queda centrado; en `kb-vol-noselect.png` no hay divisor y la tabla ocupa todo el ancho.
  Arrastrar el divisor cambia el reparto, respeta los mínimos (300 pt tablas / 360 pt detalle) y la
  proporción se conserva al cambiar de disco, sección o pestaña. En `kb-vol-noscroll.png` la tabla
  sigue arriba (sección disk0) mientras el detalle muestra disk4: la selección no desplaza la
  tabla; `kb-vol-2col.png` puede abrir con la fila seleccionada fuera del área visible, sin
  centrarla.
- Treemap y barra: la tarjeta muestra Capacity/Free/Used a la izquierda, una barra vertical en
  medio y el treemap a la derecha; ambos ocupan el alto disponible de la tarjeta y terminan a la
  misma línea (la barra deja 25 pt para su caption). La barra es un carril oscuro de esquinas
  redondeadas
  con una sección por volumen APFS del disco y una por el espacio libre de cada contenedor; no
  dibuja particiones ni contenedores. Los volúmenes usan un degradado azul y el libre una trama
  diagonal; cada sección recibe una altura mínima visible y el resto se reparte proporcionalmente.
  El grupo seleccionado pasa a un degradado cian-azul con un contorno luminoso (un volumen, todas
  las secciones de un contenedor con su libre, o todo el disco/partición); el resto queda en azul
  grisáceo oscuro. Used se coloca a la altura de la sección seleccionada con una línea horizontal
  hasta la barra; arriba queda la capacidad rotulada según el alcance (`Disk capacity`,
  `Partition capacity`, `Container capacity`) con su subtítulo de capacidad compartida, y Free
  debajo. Al seleccionar un bloque free en el treemap, su
  sección se destaca en la barra (y en el treemap) y Used vuelve a su posición superior. Pulsar un
  tramo de la barra selecciona el volumen/partición/contenedor que representa; los tramos libres
  mantienen su resaltado. Pulsar de nuevo el tramo del elemento ya seleccionado, o el elemento en
  el treemap, quita el resaltado del detalle sin cambiar la selección de las tablas; un clic fuera
  del treemap y de la barra también lo quita. El panel sigue mostrando todo el contenido sin
  ningún tile o tramo
  resaltado; volver a pulsar restaura el resaltado y la x lo cierra. No hay conectores
  barra-treemap. El
  gráfico es un rectángulo anidado (particiones → contenedores APFS → volúmenes, con “Other” para
  el espacio no asignado, residual y libre) que llena el alto disponible de la tarjeta (el
  adaptativo 420/460…860 pt queda como fallback), con texto de tile mayor. Si el disco no tiene tabla de
  particiones, el contenedor APFS cuelga directamente del disco y sus volúmenes se dibujan igual,
  apilados en filas (p. ej. `disk11 → disk12 → disk12s1`). Particiones y contenedores usan la
  paleta hueso (`#e8e2d7`, `#d9d1c3`); los volúmenes usan por defecto los tres azules grisáceos
  (`#c9cbd0` `#b9bcc2` `#a9adb4`) y el volumen seleccionado pasa al azul `#4f93cc`. Free
  `#f7f3ea`, residual `#d2c9ba`. Bordes y texto en tinta cálida oscura. La tarjeta es un panel
  material claro con lavado ámbar/teal, borde y sombra suaves. El disco aparece como contenedor
  raíz dentro del treemap, con su banda de cabecera (`disk0`, capacidad, usado y libre) y las
  particiones anidadas; la cabecera de la tarjeta muestra el nombre del disco con los chips de
  capacidad y de componentes con nombre y número, en una sola línea (el título se trunca
  antes). **No hay
  bloque-resumen sobre el gráfico ni leyenda debajo**; el rectángulo ocupa ese espacio. La
  cabecera no cambia al seleccionar un volumen o contenedor. Cada contenedor y volumen muestra su
  uso/% (inline si la fila es compacta). El
  texto de los tiles tiene un mínimo de 11.5 pt (12.5 maximizado): si no cabe se trunca con
  elipsis, nunca se reduce. El rectángulo seleccionado usa un trazo de tinta de 2 pt, distinto del
  hover/ancestros. No hay pop/tooltip sobre el treemap; el mount point de cada volumen se dibuja en
  la misma línea que el nombre (izquierda) y el tamaño/uso (derecha), comenzando en una columna
  central común y alineado a la izquierda; las hojas que no cruzan la columna no lo muestran. Las
  particiones y contenedores etiquetan su banda superior. Hover resalta el rectángulo. No hay
  flecha de subir nivel: la navegación es por las tablas y los rectángulos. El detalle termina en
  el treemap; no hay fila de acciones ni metadata. El clic derecho en una cabecera, fila, la
  tarjeta de detalle, un tramo de la barra o un tile del treemap abre Reveal, Copy ID, Analyze y
  “Get Info” para el elemento bajo el cursor (el fondo usa el seleccionado): Reveal/Analyze se
  deshabilitan sin mount point, Copy ID siempre está activo y “Get Info” abre una ventana
  independiente por elemento; si desaparece del inventario, la ventana muestra “Item unavailable”.
  En `kb-2d-disk.png`,
  `kb-bar-container.png` y `kb-bar-volume.png` se comprueba que el contenido de la barra no
  cambia al cambiar de selección, solo el contorno.
- Disco raíz, línea de mount y altura: en `kb-mountline-1440.png` se ve `disk0` como contenedor
  raíz con banda de cabecera y sin fondo/recuadro exterior; el mount de cada volumen aparece en su
  línea de nombre/tamaño, empezando en la columna central común. En `kb-mountline-details.png`
  se comprueba que `disk0s3` muestra `disk2` y sus volúmenes `Recovery`/`Update` con
  `Not mounted`. En un disco con pocos volúmenes (p. ej. `kb-follow-disk4.png`) el treemap baja a
  ~420/460 pt; el máximo sigue siendo 860.
- Barra: no hay id rotado, pop ni conectores barra-treemap; no lleva tipo ni porcentaje encima y
  sí la leyenda “of container”/“of capacity” debajo. La capacidad va arriba rotulada por alcance y
  con el subtítulo de espacio compartido; Free queda debajo y Used a la altura de la sección
  seleccionada con su línea horizontal. Al seleccionar un contenedor/volumen
  APFS aparece la fila “Shared with” con el contenedor y los volúmenes (nombre+id); no se muestra
  para discos, particiones ni snapshots. Las barras de las tablas siguen en azul.
- Maximizar/restaurar en tablas y detalle: la tarjeta ocupa el área de Volumes y se oculta la otra
  columna; la cabecera, las pestañas y el selector de unidades siguen visibles.
  `--volumes-maximized details` sin selección cae al layout normal.

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
  ventana de 120 muestras de Traffic y Disk abarca ~60 s; a 5 s, ~10 min. El resto de gráficos
  mantiene 60. Los historiales se conservan al cambiar el
  intervalo; Traffic usa slots fijos y un eje nominal de 120 × intervalo, de modo que las muestras
  antiguas se re-espacian uniformemente al cambiar la cadencia.
- Todos los gráficos temporales (Traffic, CPU, Disk I/O, memoria, batería, sparklines y core bars,
  además de los estilos del icono del Dock) dibujan el dato más reciente a la izquierda. En
  Traffic el eje lee `now → -60s → -2m`; en Battery el ancla antigua queda a la derecha y la
  muestra nueva en el borde izquierdo. Los gráficos de composición no cambian.
- Crecimiento progresivo: con 1-3 muestras los gráficos temporales ocupan solo los primeros slots
  a la izquierda (CPU history, GPU, Physical Memory, presión, composición, Energy, wake-ups y los
  estilos del Dock) y se extienden a la derecha al llegar muestras hasta llenar la ventana (60
  muestras; 120 en Traffic/Disk). No deben estirarse con 2-3 muestras. En Battery, con minutos de
  histórico la línea queda junto al borde izquierdo; el eje de 12 h no cambia.
- Arranque limpio: capturar Networking a 1, 2, 4 y 6 s no debe mostrar ningún pico GB/s ni un techo
  desproporcionado; la primera muestra es 0 y las siguientes se estabilizan. Repetir en Disk →
  I/O (Data/Operations) y Energy (sparklines de Energy y Wake-ups) y con `--screenshot-dock
  --dock-style all`: `.networkUsage`, `.diskActivity` y `.energyUsage` tampoco deben mostrar el
  triángulo de una muestra. CPU, cores, memoria, GPU y batería son valores absolutos y no cambian
  por este fix. Probar también Refresh manual, pausa/reanudar y el cambio local↔daemon.
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
- La card Cores es un muro ecualizador `C1..C8` con barritas rectangulares del histórico reciente
  (16 en la card, 30 en el popover), color por carga, grupos P/E y uso/temperatura al pie. Con
  intervalo de 2 s dejar ~35 s para llenar la ventana
  (`$K --screenshot /tmp/kb-cpu-cores.png --section cpu --screenshot-delay 35`); bajo carga
  (`yes > /dev/null` por core) las barras deben subir y pasar a naranja/rojo. Con la ventana
  mínima o más de 8 cores se usa el fallback de filas con etiquetas C y medidores rectangulares.
- RSS de procesos propios con `ps -o rss`; con `sudo`, para todos. La memoria “used” puede diferir
  de `top`/Activity Monitor por definición (`active + wired + compressed`); documentar la cifra.
- Sin daemon root la tabla solo enumera procesos del uid actual y muestra “your processes only”.
  Con el daemon root aparecen todos. Los procesos sin task info muestran `—`, nunca 0.
- CPU% puede superar 100% en multithread; `TIME+` es tiempo acumulado. Ordenar por cada columna,
  filtrar y cambiar de sección: búsqueda, selección y orden se conservan.
- `%GPU` y `GPU Time` por proceso: `GPU Time` es la suma de `accumulatedGPUTime` de todos los
  user clients de `IOAccelerator` del PID y debe coincidir con
  `ioreg -r -d 2 -c IOAccelerator -l -w 0` (segundos truncados); `%GPU` es el delta sobre la
  ventana, limitado a 100%. Comprobación:

  ```bash
  P=./build/Build/Products/Debug/KancerberoProbe
  $P procs --cpu --limit 20 --interval 2
  ioreg -r -d 2 -c IOAccelerator -l -w 0 | grep -E "IOUserClientCreator|accumulatedGPUTime"
  sudo powermetrics --samplers gpu_power --show-process-gpu -n 1 -i 1000
  K=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
  $K --screenshot /tmp/kb-cpu-gpu.png --section cpu --screenshot-delay 6
  ```

  Para forzar carga, compilar un pequeño bucle Metal y filtrar la tabla con
  `--cpu-search kb-gpuload`; la fila debe mostrar `%GPU` > 0 y `GPU Time` creciente. Sin fuente
  `AppUsage` (Intel antiguos, VMs), ambas columnas muestran `—`, nunca ceros. Pausar y reanudar
  no debe producir picos: el primer tick válido vuelve a 0%.

  Test aislado del cálculo de porcentaje:

  ```bash
  xcrun swiftc Sources/KancerberoCore/Support/ProcessGPURate.swift \
    Tests/KancerberoTests/ProcessGPURateTests.swift \
    -o "$TMPDIR/kancerbero-gpu-rate-tests"
  "$TMPDIR/kancerbero-gpu-rate-tests"
  ```
- El recuento de procesos debe coincidir con `ps -ax | wc -l` y `top -l 1 -n 0` (±5) e incluir
  kernel_task (PID 0). Como usuario, `threads` es menor que `top` y la UI muestra
  “partial”/“N restricted”; con el daemon root actualizado coinciden procesos e hilos. Si el
  daemon es antiguo, System status muestra “Process data Incomplete — N of M processes”.
- Igual que en otras tablas con refresco en vivo, macOS 27 puede registrar
  `reentrant operation in its NSTableView delegate`; no afecta a los datos.
- Para fugas: dejar la pestaña abierta varios minutos con intervalo de 0,5 s y comprobar que el
  RSS de Kancerbero se mantiene estable (`ps -o rss`, `leaks`). El sampler libera el array de
  `host_processor_info` y el puerto Mach en cada tick.
- Altura de las cards: al maximizar o estirar la ventana, con las tarjetas visibles la franja
  superior de CPU, Memory, Energy, Disk → I/O y Networking se mantiene en 190 pt
  (`KBTheme.cardStripHeight`, Traffic 190, Activity 100 + Protocols 80) y todo el espacio extra lo
  absorbe la tabla de procesos. Con las tarjetas colapsadas la franja desaparece y la tabla ocupa
  todo el alto. Comparar una captura a 1440×860 con otra de ventana más alta.
- Temperaturas: `$P symbols` debe informar `Thermal: available`; `$P thermal --seconds 5
  --interval 1` muestra paquete, fuente (`PMU tdie` en Apple Silicon; `eACC/pACC` o `SOC MTR` como
  respaldo) y temperatura por core, y `$P cpu --interval 1` añade `temp=` a cada `cpuN`.
  Contrastar con btop (±1–2 °C). Bajo carga (`yes > /dev/null` por core) los valores deben subir.
  Si no hay sensores (Intel/VM) la UI muestra `—` y el popover lo explica.

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
$P battery-graph
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
- `$P battery-graph` debe imprimir `charges`/`states` y `time_on_source`. En macOS 27.2 / M1 Pro la
  API devuelve una sola muestra (`charges=1 states=1`, `level=100`, `source=AC`); la card debe
  dibujar igualmente una banda verde a todo el ancho y una línea cian plana al 100 % (inset de
  2 pt), y «Time on AC» debe coincidir con Activity Monitor (±1 min). Un gráfico vacío o «—»
  indica que se sigue descartando la muestra única.
- Sin batería, o si `systemstats_get_battery_charge_graph` no está disponible o el diccionario es
  inconsistente, la card vuelve a la barra de capacidad sin errores ni avisos (ver
  `docs/private-apis.md`).

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
  --tab processes --networking-process-protocol tcp,icmp --screenshot-delay 12
$APP --screenshot /tmp/kb-net-process-domain.png --section networking \
  --tab processes --networking-process-domain unix,inet6 --screenshot-delay 12
$APP --screenshot /tmp/kb-net-process-socket.png --section networking \
  --tab processes --networking-process-socket stream,dgram --screenshot-delay 12
$APP --screenshot /tmp/kb-net-process-ip.png --section networking \
  --tab processes --networking-process-ip ipv4 --screenshot-delay 12
$APP --screenshot /tmp/kb-net-process-cross.png --section networking \
  --tab processes --networking-process-domain unix \
  --networking-process-protocol icmp --screenshot-delay 12
$APP --screenshot /tmp/kb-net-process-independent.png --section networking \
  --tab processes --networking-transport udp --screenshot-delay 12
```

- Traffic: cabecera en una línea con el título, la leyenda **Upload**/**Download** (punto de
  color y tasa en las unidades del modo activo) y el selector Bits/Packets; cada entrada alterna
  el foco de su dirección; ecualizador espejado de barras sólidas con upload arriba y download abajo,
  coloreadas por calor según su magnitud, sobre cuadrícula, etiquetas Y en
  `bps/Kbps/Mbps/Gbps` y eje temporal nominal `now/-60s/-2m` (con el intervalo de 1 s; el dato
  más reciente entra por la izquierda). Al pasar el ratón, una línea vertical marca la muestra y
  un tooltip muestra su antigüedad y las tasas Upload/Download de esa muestra. La escala vertical
  se ajusta al mayor valor visible, de modo que la barra más alta llena siempre su mitad. Las
  barras ocupan slots fijos desde el borde izquierdo,
  así que un histórico corto queda empaquetado. Sin salto de layout entre 0,3 s y 5 s.
- Activity muestra tres métricas: **processes** con sockets (total de la tabla Processes),
  **Connections** totales (`sources.count`) y **Active** (flujos con tráfico RX+TX dentro de la
  ventana configurada, 10 s por defecto). Los tres son totales y no dependen de los filtros.
  Connections filtra a todas las
  conexiones y Active a solo las activas; el tile seleccionado queda resaltado. Con
  `--networking-focus active` el número de Active y el numerador de «N of M connections»
  coinciden si los checkboxes están por defecto.
- Protocols muestra la barra y la leyenda de los seis tipos; el filtro IP de Connections reduce
  el desglose, el Transport no.
- La cabecera de Connections agrupa en cápsulas los checkboxes **IP** (IPv4/IPv6), **Transport**
  (TCP/UDP/Other), **TCP State** (Established, Listening, Connecting (SYN), Closing
  (Close/Fin/Time Wait)) y **Other** en su propia cápsula (UDP y estados no clasificados), todos
  marcados por defecto, más `Filter process`. Desmarcar un valor excluye sus filas; desmarcar todo
  un grupo deja “0 of M connections”. La cápsula **Other** muestra solo el checkbox y controla los
  estados TCP no clasificados: desmarcarla no oculta las filas UDP, que dependen de
  **Transport › UDP** (desmarcar UDP las elimina). La familia de dirección desconocida se excluye
  cuando el grupo IP no está completo.
- Ventana configurable: en **Settings → Network activity** el picker “Active connections
  window” ofrece 5/10/20/30/60/120 s (10 por defecto). Al cambiarlo, la caption del tile pasa a
  «last N s» y el hint se actualiza; el contador y el filtro Active usan la nueva ventana en el
  siguiente refresco. Lanzar una descarga, pararla y comprobar que el flujo sigue activo hasta que
  expira la ventana elegida.
  Para probarlo sin la UI:
  ```bash
  defaults write uno.kayros.kancerbero activeConnectionWindowSeconds -int 30
  defaults read uno.kayros.kancerbero activeConnectionWindowSeconds
  defaults delete uno.kayros.kancerbero activeConnectionWindowSeconds   # vuelve a 10
  defaults write uno.kayros.kancerbero activeConnectionWindowSeconds -int 3  # cae al default 10
  ```
- La cabecera de Processes añade en cápsulas **Socket domain** (AF_INET/AF_INET6/AF_UNIX/Other),
  **Socket protocols** (TCP/UDP/ICMP/ICMPv6/SCTP/GRE/ESP/RAW/Other) y **Socket type**
  (stream/dgram/raw/seqpacket/other). Un dominio parcial exige alguna firma de esa familia; un
  Socket type activo exige datos de sockets y oculta las filas con Type «—»; todo marcado = sin
  filtro y un grupo vacío no muestra filas.
- Los filtros son **independientes por subpestaña**: marcar/desmarcar en Connections no altera la
  tabla ni el contador de Processes (ni al revés). Se conservan al cambiar de pestaña.
- Los grupos aparecen en una **barra a todo el ancho entre las pills y la tarjeta** de la tabla;
  la tarjeta ya no los contiene y su cabecera muestra el título, la búsqueda, el botón Inspect
  junto al filtro y el contador de filas a la derecha. Interfaces muestra ese mismo contador en
  su cabecera; ni ella ni Filter tienen barra (sin hueco extra). A 1340×700 la barra cae a dos
  líneas sin recortarse.
- Processes muestra en su cabecera `Filter processes` y filtra por nombre, ruta, PID o usuario,
  igual que CPU. El contador “N of M” refleja sus facetas y la búsqueda. La columna **Domain**
  muestra las familias, **Protocols** solo los protocolos IP (sin `+N`) y **Type** todos los tipos
  de socket.
- Filtros de Processes: **Socket domain** (AF_INET/AF_INET6/AF_UNIX/Other),
  **Socket protocols** (TCP/UDP/ICMP/ICMPv6/SCTP/GRE/ESP/RAW/Other) y **Socket type**
  (stream/dgram/raw/seqpacket/other).
  Las tres facetas se cruzan sobre la misma firma `(AF_*, SOCK_*, IPPROTO)` del inventario libproc;
  un protocolo seleccionado exige familia AF_INET/AF_INET6. Los badges y el tooltip de Protocols
  muestran las firmas reales (p. ej. `AF_INET · SOCK_DGRAM · ICMP` para ping).
  Comprobaciones:
  - `ping 127.0.0.1` en marcha + `--networking-process-protocol icmp` → solo el proceso `ping`,
    con badge `ICMP` y Sockets `1 dgram`.
  - `--networking-process-domain unix --networking-process-protocol icmp` → “0 of M” (ninguna
    firma puede ser AF_UNIX y protocolo ICMP a la vez).
  - `--networking-process-domain inet --networking-process-protocol icmp --networking-process-socket dgram`
    → el `ping`; un proceso con TCP y UNIX pero sin ICMP no aparece.
  - `--networking-process-ip ipv4` y `--networking-process-domain inet` dan las mismas filas.
  - Con un daemon antiguo (sin firmas) se usa el fallback agregado; el tooltip de Sockets lo avisa.
- CLI: `--networking-transport`/`--networking-ip`/`--networking-state` marcan los grupos de
  Connections y `--networking-process-domain`/`--networking-process-protocol`/
  `--networking-process-socket` los de Processes; `all`, una lista sin valores válidos o un valor
  desconocido no filtran.

Tabla de Connections (orden y columnas):

```bash
$APP --screenshot /tmp/kb-connections-columns.png --section networking \
  --tab connections --screenshot-delay 5
```

- Orden de columnas: Process, PID, Local, Remote, Proto, State, RX, TX, Rate e Iface.
  Los flujos UDP muestran `Datagram` en State (no tienen estado TCP).
- **Resolve names** está apagado por defecto: Local/Remote muestran `ip:puerto` y el tooltip solo
  la IP. Al activarlo, las celdas cambian a `hostname:puerto` a medida que terminan las consultas
  inversas (las IPs sin PTR se mantienen), el tooltip pasa a `hostname · ip:puerto` y el orden no
  cambia. El checkbox de la pestaña Filter comparte estado; apagado, la tabla de flujos vuelve a
  mostrar direcciones. Comprobar con `--networking-resolve-names` al final de la línea.
- La columna Rate muestra la suma RX+TX del intervalo en bits/s (`KBFormat.bitRate`); en reposo
  `0 bps`, y con una descarga activa el flujo debe subir a Mbps y coincidir en orden de magnitud
  con la tarjeta Traffic y `nettop`. Ordenar por Rate deja arriba la conexión con más caudal.
- Un flujo recién creado debe pasar de `SynSent` a `Established` en el siguiente refresco (la
  descripción de NStat se re-consulta en cada tick); comparar con `lsof -nP -iTCP -a -p <pid>`.
- Pulsar cada cabecera: debe mostrarse el indicador de orden y alternar ascendente/descendente.
  Local/Remote ordenan numéricamente (no `10.x` antes que `2.x`); RX/TX/Rate/PID numéricamente; el
  resto por texto. Process ordena por nombre (con Unknown para PID sin nombre).
- Seleccionar una fila, ordenar y cambiar de subpestaña/sección: la selección y el criterio de
  orden se conservan (estado de sesión en `UIState`). Si el filtro hace desaparecer la fila, la
  selección se limpia.
- Comprobar direcciones IPv6 largas (truncadas con tooltip) y el scroll horizontal a 1340×700.

Tabla de Interfaces (orden y filtro):

```bash
$APP --screenshot /tmp/kb-interfaces.png --section networking --tab interfaces \
  --networking-interface-search en --screenshot-delay 5
```

- El campo «Filter interfaces» filtra por nombre, tipo (`Ethernet`, `Wi-Fi`, …) o estado
  (`Up`/`Dormant`/`Down`) y el contador de la cabecera pasa a «N of M interfaces».
- Orden de columnas: Interface, Type, State, Received, Sent, RX bit/s, TX bit/s y MTU. Pulsar cada
  cabecera debe mostrar el indicador de orden; State ordena Up → Dormant → Down, y las tasas se
  ordenan numéricamente (`KBFormat.bitRate`).
- Con `--networking-focus active` la tabla muestra solo las interfaces usadas por conexiones
  activas.

Tabla de Processes (flujos + sockets):

```bash
$APP --screenshot /tmp/kb-processes.png --section networking --tab processes \
  --screenshot-delay 12
./build/Build/Products/Debug/KancerberoProbe sockets-summary
./build/Build/Products/Debug/KancerberoProbe sockets <pid>
```

- La tabla solo lista procesos con flujos TCP/UDP o sockets (UNIX/RAW incluidos). Comparar los
  tipos y conteos con `lsof -nP -i`/`netstat` y con el inspector del proceso.
- Comprobar las etiquetas separadas: **Domain** (INET/INET6/UNIX/SYSTEM…, tooltip con `AF_*`),
  **Protocols** (TCP/UDP/ICMP/ICMPv6/SCTP/GRE/ESP/RAW…) y **Type**
  (stream/dgram/raw/seqpacket/other), más Flows, RX/TX (Bytes), Rate (bits/s, suma de sus flujos)
  y “—” en procesos solo-locales. Con varias familias la tabla puede requerir scroll horizontal
  en ventanas estrechas.
- **Guard**: un proceso vigilado muestra el escudo medio lleno y, al lado, el badge de su
  política (Ask naranja, Allow verde, Deny rojo); los no vigilados solo muestran el escudo
  vacío. Cambiar la política desde el menú contextual o desde la ventana de reglas debe
  actualizar el badge al instante, y la elección persiste tras reiniciar la app.
- Con el ancho por defecto de la ventana deben verse también **Rate** y **Path** a la derecha
  (Guard/Protocols/Type/Flows quedan compactas). Los paths largos se recortan y el tooltip
  conserva la ruta completa.
- En modo local, los procesos de otros uid pueden mostrar Domain/Protocols/Flows/RX/TX pero Type
  “—” (restringido); con el daemon root deben mostrar también sus sockets. Con un Socket type
  activo esas filas «—» desaparecen; con el grupo completo siguen visibles.
- Probar los tres grupos de la cabecera en cápsula: Socket domain, Socket protocols y Socket
  type. Desmarcar todo un grupo deja “0 of M networked processes”; desmarcar AF_UNIX oculta los
  procesos que solo tienen sockets UNIX; con un dominio parcial desaparecen las demás familias.
- En **Domain**, un proceso con sockets de familia especial debe mostrar el valor real
  (`SYSTEM`, `NDRV`, `VSOCK`…; el tooltip conserva `AF_*`) en vez de Other. Ninguna familia
  definida en `sys/socket.h` (3–25, 27–38, 40) debe salir como `AF_<n>`; solo 26 y 39, que no
  existen en Darwin.
- En **Protocols** deben verse los protocolos reales: un `ping` en marcha muestra `ICMP`, y
  SCTP/GRE/ESP/… su nombre; `RAW` queda para `IPPROTO_RAW`. La columna Proto del
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
3. Disk → Volumes: expandir y colapsar varios nodos, seleccionar un volumen, ir a Analyzer y
   volver → selección, foco y expansión intactos. Refresh de volúmenes → no se re-expande. Pulsar
   All → tablas completas expandidas y tarjeta All marcada.
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

Estructura del detalle (Volumes):

```bash
./build/Build/Products/Debug/KancerberoProbe disk apfs
./build/Build/Products/Debug/KancerberoProbe disk apfs disk3
./build/Build/Products/Debug/KancerberoProbe disk usage
./build/Build/Products/Debug/KancerberoProbe disk usage disk0
diskutil apfs list

K=build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
$K --screenshot /tmp/kb-hero-disk.png --section disk --disk-tab volumes \
  --disk-item disk0 --screenshot-size 1440x900 --screenshot-delay 5 --cards-collapsed
$K --screenshot /tmp/kb-hero-container.png --section disk --disk-tab volumes \
  --disk-item disk3 --screenshot-size 1440x900 --screenshot-delay 5 --cards-collapsed
$K --screenshot /tmp/kb-hero-volume.png --section disk --disk-tab volumes \
  --disk-item disk3s5 --screenshot-size 1340x800 --screenshot-delay 5 --cards-collapsed
$K --screenshot /tmp/kb-hero-max.png --section disk --disk-tab volumes \
  --disk-item disk0 --volumes-maximized details \
  --screenshot-size 1440x900 --screenshot-delay 5 --cards-collapsed
$K --screenshot /tmp/kb-hero-min.png --section disk --disk-tab volumes \
  --disk-item disk0 --screenshot-size 1340x700 --screenshot-delay 5 --cards-collapsed
```

- La cabecera de la tarjeta muestra el nombre del disco con los chips de capacidad y de
  particiones/contenedores/volúmenes con nombre y número, en una sola línea (el título se trunca
  antes);
  el título no cambia al seleccionar un volumen o contenedor. El disco aparece como contenedor
  raíz dentro del treemap, con su banda de cabecera (`disk0`, capacidad, usado y libre) y las
  particiones dentro; no queda ningún bloque de
  resumen de conteos ni cabecera de selección encima del gráfico. El detalle termina en el
  treemap; Reveal, Copy ID, Analyze y “Get Info” viven en el menú contextual de cabeceras, filas,
  detalle, barra y treemap. Cada nivel usa su tramo de la paleta hueso y los bordes/texto se eligen
  por luminancia (tinta cálida sobre claros).
- Barra y selección: el contenido (todos los volúmenes y libres del disco) no cambia al navegar;
  un volumen seleccionado dibuja el contorno azul de su sección; un contenedor, el de todas sus
  secciones y su espacio libre; un disco o partición, el de todo su subárbol. “Get Info” abre una
  ventana por elemento con su metadata y resuelve el ítem desde el inventario vivo.
- El treemap anida filas de particiones, columnas de contenedores y filas de volúmenes; cada
  rectángulo tiene un mínimo visible por rol/eje y el resto se reparte proporcional a la fracción,
  de modo que todas las particiones y volúmenes aparecen (incluidos los desmontados, con
  `Not mounted` y un tile compacto de 20/22 pt). Cuando los volúmenes de un contenedor tienen
  tamaños muy dispares (≥ 6×), el suelo baja a 10 pt y el volumen mayor crece para que la
  proporción se lea; algún tile pequeño puede quedarse sin etiqueta. Las áreas son aproximadas.
  Partición/contenedor
  con hijos reservan una banda
  superior para su etiqueta y dejan un inset visible (12/9/7 pt normal, 14/11/8 maximizado)
  alrededor de los hijos; los volúmenes se etiquetan dentro, muestran su mount point en la línea
  del nombre/tamaño, comenzando en la columna central común y alineado a la izquierda, y si el
  tile es grande añaden `usado · %`. El texto de los tiles nunca baja de 11.5 pt
  (12.5 maximizado) y se trunca antes que reducirse. Todas las etiquetas incluyen el identificador
  y el tipo
  (`disk3s5 · Macintosh HD - Data · APFS volume`, `disk0s2 · Container · Partition`,
  `disk3 · Free space`). Cada partición, contenedor y volumen muestra su usado y porcentaje
  inline a la derecha de la cabecera/fila (o `Usage unknown`/`Not mounted`). Los colores son fijos
  por nivel sobre la tarjeta material:
  particiones hueso claro `#e8e2d7`, contenedores hueso medio `#d9d1c3`, volúmenes por defecto
  las tres azules grisáceas `#c9cbd0` `#b9bcc2` `#a9adb4` (el seleccionado `#4f93cc`); free
  `#f7f3ea`, residual `#d2c9ba`, unallocated `#ddd5c7`, unknown `#ede8de`; cada tile lleva un
  brillo blanco sutil.
  No hay callouts exteriores ni leyenda debajo del treemap. Hover resalta el rectángulo; pulsar
  el fondo del treemap selecciona el disco del alcance. Los bordes son líneas finas (0.6–1.0 pt;
  maximizado algo más); el rectángulo seleccionado usa un trazo de 2 pt en tinta, que se reduce en
  tiles pequeños.
- El treemap y la barra ocupan el alto disponible de la tarjeta; la barra comparte la altura del
  treemap y deja 25 pt para su caption. El cálculo adaptativo (420/460…860 pt) es solo el fallback.
  Cuando los volúmenes de un contenedor tienen tamaños muy dispares (ratio ≥ 6×), el tile mayor
  crece y los pequeños se compactan a un suelo de 10 pt para que la proporción se lea; en el resto
  de casos cada tile conserva su mínimo visible. Cada partición
  reserva una altura recursiva según sus volúmenes
  (tope 520/600 pt) para que su contenido se vea. A 1340×700 la tarjeta puede hacer scroll vertical
  si el contenido lo necesita.

- El número de contenedores del disco debe coincidir con `diskutil list` (incluye los
  contenedores ISC y Recovery que `diskutil apfs list` no muestra); `diskutil apfs list` sirve
  para los volúmenes y la capacidad en uso del contenedor principal. Con el selector en Decimal
  (por defecto) el gráfico muestra 494,4 GB; en Binario muestra 460,4 GiB.
  Con varios contenedores, las filas de particiones y contenedores muestran un rectángulo por
  unidad (tamaño aproximado = capacidad, con mínimos visibles), con “Other” para el espacio no
  asignado.
- Los volúmenes del contenedor muestran el desglose por usado (usado + residual +
  snapshots/metadatos + libre). Al seleccionar un contenedor o volumen, el elemento y sus
  ancestros quedan resaltados en sus rectángulos.
- Pulsar un rectángulo selecciona ese ítem en las tablas y actualiza el detalle. No hay flecha de
  subir nivel; la navegación es por las tablas y los rectángulos. Las tablas por disco tienen
  cabecera colapsable y abren todas por defecto; el chevron colapsa solo la tabla de ese disco.
- Un contenedor sin volumen montado muestra un rectángulo desconocido y `—` (nunca `0 B`).
- `usado de volúmenes + residual + libre = capacidad`; permitir la diferencia documentada de
  `ATTR_VOL_SPACEUSED` frente a `diskutil`. Si la suma de usado excede lo usable, las porciones se
  escalan y aparece la nota correspondiente.
- Las tablas muestran usado/free por fila (volúmenes con Free `—`) y la barra de Used con el criterio
  correcto. `disk usage` debe dar las mismas cifras agregadas y `partial=yes` cuando falte algún
  volumen montado; un disco/partición no APFS usa el treemap usado/libre y, sin datos, muestra
  “Structure unavailable”.
- Selector **Decimal/Binary** de la línea de pestañas:
  `--disk-units decimal` muestra `500,3 GB` para disk0 (base 1000, KB/MB/GB);
  `--disk-units binary` muestra `465,9 GiB` (base 1024, KiB/MiB/GiB). Cambian las tablas, tarjetas,
  detalle, treemap, analyzer, tablas de I/O, velocidades Read/s/Write/s y la barra de estado.
  Las operaciones/s y los contadores no cambian. CPU/Memory/Network conservan su formato. La
  elección del selector se guarda en `UserDefaults`; el flag solo afecta a la sesión/captura.

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

- En la captura de I/O, copiar un archivo grande mientras la pestaña está abierta: el gráfico
  (barras espejadas, lecturas arriba y escrituras abajo) y las tasas Read/Write deben moverse;
  la escala vertical se ajusta al mayor valor visible; al pasar el ratón, una línea vertical y un
  tooltip muestran la muestra bajo el cursor;
  Data/Operations cambia las unidades; los totales
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
- `launchctl print system/uno.kayros.kancerbero.daemon.service` y
  `log show --predicate 'subsystem == "uno.kayros.kancerbero"' --last 5m --info`.
- Comprobar la firma del daemon embebido antes y después de instalar:
  `codesign -dvvv .../KancerberoDaemon` debe mostrar `Identifier=uno.kayros.kancerbero` (el mismo
  que la app) y `codesign -d --entitlements - --xml` un diccionario vacío. Si launchd lo mata,
  el log del kernel muestra `AMFI: Launch Constraint Violation ... c[5]p[1]m[1]e[0]` y Login
  Items sigue diciendo “enabled”. Un registro BTM antiguo que no coincide no se arregla
  re-registrando el mismo label: `sudo sfltool resetbtm` + reinicio es el último recurso. La
  identidad actual `...daemon.service` es nueva y no arrastra constraints del label histórico.
- La app registra el servicio sola al arrancar si está en `/Applications` y el usuario no lo ha
  desactivado; un cambio de ejecutable/plist la re-registra una vez por ejecución. System status
  muestra el proceso real (`Daemon process`), su PID y el último error de conexión.
- La app debe pasar a “Daemon connected” y usar XPC privilegiado. Desregistrar debe detenerlo y
  volver a modo local.
- Sin notarización, Gatekeeper marca la app como “Unnotarized Developer ID” y el registro del
  daemon no es fiable; completar `notarytool store-credentials` + `scripts/notarize.sh`.

### Migración `.v2` → `.service`

1. Con la build anterior instalada y el servicio `.v2` aprobado:
   `launchctl print system/uno.kayros.kancerbero.daemon.v2` debe mostrar el job.
2. Instalar la build nueva notarizada, abrirla y aprobar el nuevo item en Login Items.
3. Comprobar:
   - `.v2` ya no existe; `launchctl print system/uno.kayros.kancerbero.daemon.service` está running;
   - hay un solo proceso `KancerberoDaemon`;
   - `defaults read uno.kayros.kancerbero daemon.legacyV2CleanupDone` vale `1`;
   - la app muestra “Daemon connected” y XPC privilegiado funciona.
4. Reabrir la app: el cleanup no se repite y `.v2` no reaparece.

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
   abre la hoja (y notificación si la app está en segundo plano). Comprobar el rediseño: icono y
   nombre del proceso grandes, destino a 30 pt con transporte y origen, anillo de cuenta atrás
   con segundos y barra de progreso, selector **Remember** (Once / This app / App + destination)
   y botones grandes **Deny** / **Allow**. Return permite y Escape deniega; la hoja no se puede
   cerrar sin decidir. Al abrirse no debe mostrar ningún spinner ni controles desactivados:
   Allow/Deny cierran la hoja al instante (la decisión se envía en segundo plano) y «Disable
   filter» muestra progreso solo en ese botón, con un límite de 5 s para las operaciones de
   `NEFilterManager`; si el daemon no responde, la hoja se cierra y Filter/System status muestran
   el estado `.failed` en vez de quedarse bloqueada.
   - Remember *Once* + Allow/Deny → afecta solo a esa conexión; `curl` funciona o falla.
   - Remember *This app* / *App + destination* + Allow/Deny → no vuelve a preguntar según la
     opción (la de destino queda deshabilitada si no hay remoto).
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
6. **Ventana de reglas** (Filter → **Filter Rules…**):
   - La ventana muestra el estado del filtro (Enabled/Disabled/Unsupported, conexión XPC y
     contadores) con su botón global Enable/Disable.
   - Las reglas creadas con el escudo de Processes aparecen con proceso, política, ruta y fecha;
     todas las reglas listadas están siempre activas (la ventana no permite desactivarlas).
   - Pulsar el badge de la columna **Policy** abre un selector con Ask/Allow/Deny, un checkmark
     en la política actual y una descripción de cada opción. Elegir otra la aplica al instante:
     el badge cambia de color, el de la columna Guard de Processes también y la extensión la
     aplica (Ask vuelve a preguntar, Allow pasa, Deny bloquea) sin reiniciar. El cambio persiste
     tras reiniciar app y extensión. El orden por la cabecera Policy y el resto de acciones de
     la ventana siguen funcionando.
   - Una regla se borra de tres formas: seleccionar la fila y pulsar **Delete** en la cabecera
     de la sección, la papelera de la propia fila o «Delete rule…» del menú contextual. Las tres
     piden confirmación (alert con Delete/Cancel); al confirmar la regla desaparece, se borran sus
     decisiones recordadas de esa app y el escudo de Processes deja de marcarla. Cancelar no borra
     nada y, sin selección, el **Delete** de cabecera está deshabilitado. Tras borrar, la tabla
     actualiza y la selección queda limpia.
   - Las decisiones `Always allow/deny` (app y app+destino) aparecen en su tabla; borrarlas hace
     que el siguiente flujo vuelva a preguntar.
   - Tras reiniciar app y extensión, reglas y decisiones se conservan (la app empuja el snapshot
     al conectar). El handshake sigue aceptando `schemaVersion == 1`; las cachés antiguas que
     incluyeran `enabled` se decodifican igual porque la clave desconocida se ignora.
7. **Bloqueo global de conexiones nuevas** (interruptor de la pestaña Filter):
   - Al activarlo, la tarjeta pasa a rojo con «Blocking new connections», pulso (salvo Reduce
     Motion) y el aviso naranja si el filtro está apagado; la barra de estado muestra
     **Blocking** (o **Block armed** si la extensión no corre) en cualquier sección.
   - Un proceso con regla Allow, uno con decisión recordada de allow y uno sin regla deben ser
     denegados al abrir conexiones nuevas; en Filter aparecen como `DENIED (block all)` y el
     contador/lista de reglas no cambia (no se crea ninguna regla).
   - Una conexión ya establecida antes de activar sigue funcionando.
   - Con una petición Ask pendiente, activar cierra la hoja, la fila desaparece y
     `pausedFlows` llega a 0. Toggles rápidos on/off/on dejan UI y comportamiento coherentes.
   - Cerrar la app con el bloqueo activo: la extensión sigue denegando; al reabrir, el
     interruptor sigue activo y se re-arma. Reiniciar la extensión mantiene el bloqueo.
   - Desactivarlo restaura reglas y decisiones recordadas y retira el aviso. Instalar sobre un
     perfil con un `rules.plist` anterior conserva las reglas y arranca con el bloqueo apagado.
   - **Extensión antigua**: con una app nueva conectada a una extensión anterior, el chip debe
     decir **Block outdated** y la tarjeta advertir que no está aplicando el bloqueo (el ack de
     `setRules` no trae la versión esperada). Tras reinstalar/reactivar la extensión pasa a
     **Blocking** y `log stream --predicate 'subsystem == "uno.kayros.kancerbero.filter"'`
     muestra `setRules: … global block on`.
   - **Actualizar la extensión**: los cambios en `Sources/KancerberoFilter` (o en
     `KancerberoFilterContract`/`Resources/Filter`) hacen que `prepare-build-version.sh` suba el
     build del filtro en `Config/ComponentVersions.xcconfig`; el `CFBundleVersion` de
     `Resources/Filter/Info.plist` se genera desde ahí, no se edita a mano. `build-release.sh`
     hace `clean` + `build`. Si sysextd no reemplaza la copia antigua de
     `/Library/SystemExtensions`, `sudo systemextensionsctl uninstall AK37TK8X2Y
     uno.kayros.kancerbero.filter` y volver a instalar/aprobar. Tras el reemplazo,
     `systemextensionsctl list` puede mostrar la copia anterior como «terminated waiting to
     uninstall on reboot»: reiniciar para que la nueva arranque y el proveedor pueda conectar
     por XPC.

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

- Al abrir la pestaña por primera vez no debe haber ninguna app seleccionada ni panel lateral;
  la tabla ocupa todo el ancho. `--applications-scope user` y `--applications-search` permiten
  comprobar los filtros.
- Para Antigravity el panel debe mostrar **5 entradas** (app + 4: Application Support, el PNG de
  Logi, Preferences y Logs) y para Claude **13** (app + 12, incluidas las tres de Services y
  `ClaudeAgentConfig`), igual que AppCleaner. El resumen del pie debe ser la cápsula coloreada
  «1 app + N files selected · tamaño».
- `apps` debe coincidir con `find /Applications -maxdepth 2 -name '*.app'` (más `~/Applications`,
  widgets y plugins) y `KB_APPS_LEFTOVERS` debe listar preferencias, Application Support, caches,
  contenedores, saved state, launch items y logs reales de esa app.
- La tabla muestra icono, nombre, bundle id, tipo, origen (System/User) y tamaño del
  seleccionado; el buscador está dentro de la tarjeta de la tabla y los chips filtran por tipo y
  por origen. El panel derecho es una lista plana con la app siempre marcada (check fijo) y cada
  relacionada en dos líneas (nombre y ruta) con su icono, tamaño y marca `admin` cuando toca.
- Las apps Apple de `/Applications` (Xcode, Developer, Feedback Assistant…) aparecen sin
  candado y con aviso en la hoja de confirmación; `Safari.app` no se lista y todo lo que resuelve
  a `/System` sigue rechazado. «Move to Trash» es rojo en el pie del panel y en la hoja.
- Daemon antiguo: `hello.capabilities.trash` debe ser `true` con el binario actual. Si el proceso
  en ejecución es anterior a `trashItems`, la hoja avisa «The background helper is outdated…» y
  el borrado pide el autodespido (`daemonAction` stop), espera la reconexión y continúa; el PID
  del daemon debe cambiar y `log show` debe mostrar el nuevo handshake.
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
- Fallback de permisos: con un ítem escribible cuyo padre no lo es (`chmod -w ~/Applications`),
  `FileManager.trashItem` falla con `EACCES`; el daemon debe reintentarlo y moverlo a `~/.Trash`.
  La alerta cuenta el ítem como movido, no como fallo, y no deben aparecer resultados duplicados.
- Contenedores TCC: con `~/Library/Containers/<bundle-id>` de otra app, `trashItem` y el daemon
  reciben `kTCCServiceSystemPolicyAppDataDetailed` denegado sin Acceso Total al Disco. La alerta
  debe mostrar la ruta, el aviso de Acceso Total al Disco y el botón que abre
  `Privacy_AllFiles`; no debe mostrar un error genérico de «permission» sin explicación.
  Tras conceder Acceso Total al Disco a `uno.kayros.kancerbero` y reabrir la app, el borrado debe
  completarse y el contenedor aparecer en `~/.Trash` con propietario del usuario.
- Comprobar `tccd` (`log show --predicate 'process == "tccd"'`) para ver la petición de la app
  (`euid 501`) y la del daemon (`euid 0`) cuando el fallback se ejecuta.

## Acceso Total al Disco (FDA)

```bash
P=./build/Build/Products/Debug/KancerberoProbe
K=./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero
$P fda
for p in "$HOME/Library/Safari/History.db" "$HOME/Library/Messages/chat.db"; do
  head -c 1 "$p" >/dev/null 2>&1 && echo "$p: readable" || echo "$p: denied"
done
```

- Sin FDA, `fda` debe imprimir `denied` y las rutas protegidas deben dar `Operation not permitted`.
  `$P fda` refleja el proceso del probe, no la app: seguirá en `denied` aunque se conceda FDA solo
  a Kancerbero.app. Para ver `granted`, usar la app instalada firmada (o una build firmada con el
  mismo Team ID) y su fila de System status.
- `Kancerbero --screenshot /tmp/kb-fda-status.png --show-status --screenshot-delay 6`: la card
  **Data access** debe mostrar `Full Disk Access   Not granted` (o `Granted`) con el detalle y la
  acción `How to activate…` / `Open Settings`.
- `Kancerbero --screenshot /tmp/kb-fda-apps.png --section applications --screenshot-delay 6`: con
  FDA denegado debe verse el banner compacto «Full Disk Access is off» y el botón
  `Open Full Disk Access`; sin FDA concedido el banner desaparece. El banner debe ser de una línea
  y altura fija para no alterar el layout de la tabla.
- Abrir la guía desde la fila: título «How to activate Full Disk Access», tarjeta con la ruta del
  ajuste, cinco pasos (incluido salir y reabrir), estado actual, y botones `Open System Settings`,
  `Check again` y `Done`. `Open System Settings` debe abrir Privacidad y seguridad → Acceso Total
  al Disco.
- Volver de Ajustes sin conceder debe mantener `Not granted`; conceder y pulsar `Refresh status`
  debe pasar a `Granted` y quitar el banner. Si el estado no cambia, cerrar y reabrir Kancerbero.
- El estado `unknown` (perfil sin Mail/Safari/Messages/Notes) no muestra banner y ofrece abrir el
  ajuste sin afirmar que falte el permiso.
- La fila FDA no debe confundirse con `Privileged data / Full access`, que describe el acceso root
  del daemon. Sin FDA, el banner global puede seguir diciendo «Full access» y el contenedor de otra
  app debe seguir fallando con el aviso de permisos.

### Disk Mount / Unmount / Eject

Standalone policy and simulated executor regression suite:

```sh
swiftc -module-cache-path /tmp/kancerbero-swift-cache \
  Sources/KancerberoCore/Models/KBDiskModels.swift \
  Sources/KancerberoCore/Models/KBDiskSpaceUsage.swift \
  Sources/KancerberoCore/Models/KBFilesystem.swift \
  Sources/KancerberoCore/Collectors/DiskOperationPolicy.swift \
  Tests/KancerberoTests/DiskOperationTests.swift \
  -o /tmp/kancerbero-disk-operation-tests
/tmp/kancerbero-disk-operation-tests
```

Covers mounted/unmounted volumes, partial APFS containers, excluded auxiliary
roles, root and boot group protection (including a sealed root absent from the
inventory), home filesystem protection, snapshots, partitions without a
filesystem, ambiguous/unresolved eject targets, SMB/NFS, unsupported virtual
filesystems, changed/disappeared targets, and stopping before eject when
unmount fails. The app also compares device UUIDs, type, parent and size against
fresh inventories before executing each step.

Disposable image integration suite (never use a production device):

```sh
swiftc -module-cache-path /tmp/kancerbero-swift-cache \
  Sources/KancerberoCore/Models/KBDiskModels.swift \
  Sources/KancerberoCore/Models/KBDiskSpaceUsage.swift \
  Sources/KancerberoCore/Models/KBFilesystem.swift \
  Sources/KancerberoCore/Collectors/DiskOperationPolicy.swift \
  Sources/KancerberoCore/Collectors/DiskOperationService.swift \
  Tests/KancerberoTests/DiskOperationIntegrationTests.swift \
  -o /tmp/kancerbero-disk-operation-integration
hdiutil create -size 32m -fs HFS+ -volname KancerberoOperationTest /tmp/kancerbero-operation-test.dmg
hdiutil attach -nomount /tmp/kancerbero-operation-test.dmg
# Use the volume and whole-disk BSD IDs printed by attach, e.g.:
/tmp/kancerbero-disk-operation-integration disk8s1 disk8
```

On 2026-11-09, the application built successfully and a disposable HFS+ image
passed real Disk Arbitration mount, volume unmount, whole-disk unmount and eject.
A disposable APFS image also passed, including resolution from the synthetic
APFS volume to its physical image device. The simulated suite passed. Real external hardware, locked encryption,
SMB/NFS servers, busy resources, permission denial and physical disconnects
remain manual checks; they were not exercised against user devices.

UI checks: open menus on a different row from the selection; verify Filesystems
multi-row menus disable every operation; verify only one operation runs at a
time, progress/error text identifies the action and target, both inventories
refresh, vanished selections clear, and filtering/sorting survive refresh.

Automated UI inspection could not complete: the native app controller timed out
opening the Debug application. The menu interaction checks above remain manual.

## Actualizaciones (Sparkle 2)

Requiere una app Developer ID notarizada en `/Applications` y la build Sparkle. La 0.1.0
original (sin Sparkle) no puede autoactualizarse; instalar a mano la primera build con Sparkle
y publicar una versión posterior para probar el salto.

### Feed y firma

```bash
SPARKLE_BIN=build/SourcePackages/artifacts/sparkle/Sparkle/bin
curl -fsSL https://kayrosuno.github.io/kancerbero/appcast.xml -o /tmp/appcast.xml
xmllint --noout /tmp/appcast.xml
grep -E "sparkle:(version|shortVersionString|minimumSystemVersion)|enclosure" /tmp/appcast.xml
"$SPARKLE_BIN/sign_update" --account kancerbero-ed25519 --verify /tmp/appcast.xml
curl -fsSIL "$(grep -o 'https://github.com/[^"]*\.zip' /tmp/appcast.xml | head -1)" | grep -q 200

# Release y bootstrap
gh release view v<build> --repo kayrosuno/kancerbero
gh release download v<build> --repo kayrosuno/kancerbero
```

### Casos

| Caso | Procedimiento | Resultado esperado |
|---|---|---|
| Sin actualización | Feed con el mismo build | “You're up to date.” |
| Actualización feliz | Feed con build mayor | Sparkle descarga, verifica EdDSA, instala y relanza |
| Firma inválida | Modificar el ZIP o regenerar sin firmar | Rechazo; sigue la versión anterior |
| Appcast manipulado | Editar el XML sin re-firmar | `SURequireSignedFeed` lo rechaza |
| Downgrade | Feed con build menor | No se ofrece |
| Offline | Desconectar red y pulsar Check | Error controlado |
| App fuera de /Applications | Copiar a ~/Applications | Aviso; no se permite instalar |
| Daemon viejo | Instalar versión anterior y actualizar | El PID del daemon cambia; hello reporta la versión/build nuevos |
| Cambio de identidad del daemon | Actualizar desde una build con `.v2` aprobado | `.v2` desaparece; `.service` pide aprobación; tras aprobar, un solo daemon y XPC OK |
| Stop del daemon falla | Daemon sin `daemonAction` | Fallback a `repairDaemonService`; aviso, sin bucle |
| Schema incompatible | Cambiar `KBVersion.schema` en una build de prueba | El handshake falla y se reinicia el daemon |
| Filtro reemplazado | Actualizar con el filtro activo | `systemextensionsctl list` muestra el build nuevo; el filtro sigue |
| Filtro requiere reinicio | Forzar `.willCompleteAfterReboot` | Ajustes → Updates: “completes after a restart” |
| FDA | Conceder FDA antes de actualizar | Sigue concedida y una lectura protegida funciona |

### Comandos de comprobación

```bash
defaults read /Applications/Kancerbero.app/Contents/Info CFBundleShortVersionString
defaults read /Applications/Kancerbero.app/Contents/Info CFBundleVersion
launchctl print system/uno.kayros.kancerbero.daemon.service | grep -E 'pid|state'
systemextensionsctl list | grep uno.kayros.kancerbero.filter
codesign --verify --deep --strict --verbose=2 /Applications/Kancerbero.app
xcrun stapler validate /Applications/Kancerbero.app
spctl -a -vvv -t exec /Applications/Kancerbero.app
```

### Feed local (solo Debug)

La build Debug no arranca el updater salvo que se pase `KANCERBERO_UPDATE_FEED`. Verificado con
el appcast firmado servido por `python3 -m http.server 8000 --bind 127.0.0.1 --directory
build/updates`: la app hace `GET /appcast.xml` y lo acepta (ATS permite loopback). Para la prueba
real de instalación es preferible un prerelease HTTPS.

## Versión y build automáticos

La app genera su marketing/build en cada compilación; el daemon y el filtro tienen identidades
propias y solo cambian cuando cambia su hash de fuentes/config.

```bash
# Generador
./scripts/prepare-build-version.sh
/usr/libexec/PlistBuddy -c 'Print :marketing' build/Generated/Version.plist
/usr/libexec/PlistBuddy -c 'Print :build' build/Generated/Version.plist
cat Config/ComponentVersions.xcconfig

# Build desde cero (la pre-action debe recrear build/Generated sin wrapper)
rm -rf build/Generated
xcodebuild -project Kancerbero.xcodeproj -scheme Kancerbero \
  -configuration Debug -derivedDataPath build build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS=

APP=build/Build/Products/Debug/Kancerbero.app
EXT="$APP/Contents/Library/SystemExtensions/uno.kayros.kancerbero.filter.systemextension"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXT/Contents/Info.plist"
build/Build/Products/Debug/KancerberoDaemon | head -1
```

- **Versión = build**: en app, filtro y daemon, el último componente de
  `CFBundleShortVersionString` debe ser exactamente `CFBundleVersion` (p. ej.
  `0.2.2611160955` / `2611160955`).
- **Sin cambios**: dos `./scripts/build.sh` seguidos. El `CFBundleVersion` de la app sube; los de
  daemon y filtro no cambian; `Config/ComponentVersions.xcconfig` no se modifica. La app no debe
  reiniciar el daemon ni re-staged el filtro.
- **Solo app**: cambiar una vista de `Sources/Kancerbero`; el build de la app sube y los
  componentes siguen iguales.
- **Daemon**: cambiar `Sources/KancerberoDaemon` (o `KancerberoCore`/`KancerberoC`); el build del
  daemon sube en `Config/ComponentVersions.xcconfig`, el filtro no cambia y la app reinicia el
  daemon al conectar.
- **Filtro**: cambiar `Sources/KancerberoFilter` (o `KancerberoFilterContract`/`Resources/Filter`);
  el build del filtro sube, el daemon no cambia y la app envía una activation request `.replace`.
- **Anotación**: un build que cambia un componente deja `Config/ComponentVersions.xcconfig`
  modificado; hay que commitearlo. `build-release.sh` se niega a continuar si cambió durante el
  build y `release.sh` exige el árbol limpio antes de empezar.
- **System Status**: abrir la ventana (`--show-status`) y comprobar:
  - las tarjetas **Application**, **Background Services** y **Network Filter** muestran su
    versión en la banda del título, en una sola línea y sin build;
  - el **panel lateral** muestra **Versions in App Bundle** con Kancerbero, daemon y filtro,
    también sin build;
  - las acciones de servicio (Enable background service, Open Login Items, Repair, Retry y
    Refresh) están en **Troubleshooting**, dentro del panel lateral;
  - las versiones en ejecución y las embebidas coinciden; el build se comprueba con
    `PlistBuddy`/scripts, no en la UI.
- **About Kancerbero** (`--show-about`): muestra `Version 0.2.<build>` sin el build entre
  paréntesis y el enlace https://kayros.uno en los créditos.
- **Primer build del esquema 0.2**: daemon y filtro suben de build una vez (bump de migración)
  para publicar `0.2.<build>`; el primer arranque reinicia el daemon y re-stagea el filtro. A
  partir de ahí solo cambian si cambia su hash.
- **Release**: `./scripts/release.sh` valida app/filtro/daemon, notariza y genera un appcast con
  el build de la app; `sign_update --account kancerbero-ed25519 --verify`; tag `v<build de la app>`.
  `build-release.sh` comprueba además que el `Label` y `MachServices` del plist coinciden con
  `KancerberoXPCNames.machService`. `publish-release.sh` usa `gh` autenticado o, si no está
  instalado, `GITHUB_TOKEN`.
