# kancerbero

Monitor de red para macOS inspirado en Activity Monitor. Muestra tráfico por proceso,
conexiones por proceso, contadores por interfaz y una ventana de inspección por proceso con
estadísticas, memoria, ficheros abiertos y puertos, al estilo de Activity Monitor.

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

El detalle de binarios, permisos, instalación y librerías está en
`docs/daemons-and-libraries.md`.

- **Modo local** (sin daemon): procesos y sockets del mismo uid; tráfico por proceso vía
  NetworkStatistics (`net.statistics_privcheck = 0`).
- **Modo daemon**: todas las interfaces, todos los procesos y sockets de cualquier uid (si el
  daemon corre como root).
- **Fallback**: si NetworkStatistics no está disponible, la app sigue mostrando conexiones e
  interfaces y marca el modo como degradado.

## Interfaz

`NavigationSplitView` con panel lateral colapsable de ancho fijo (252 pt):

- **Networking** — a la izquierda, una tarjeta **Activity** con tres métricas —procesos con
  sockets, conexiones totales y conexiones activas (con tráfico en los últimos 10 s)— donde las
  dos de conexiones actúan como filtro (todas / solo activas), y una tarjeta **Protocols** con el
  desglose TCP4/TCP6/UDP4/UDP6/UNIX/OTHER; primero, la tarjeta **Network statistics**, fija a la
  izquierda, con las tasas actuales **Upload** arriba y **Download** debajo, en bits/s (pkt/s
  como subtítulo) y, bajo un separador, los totales acumulados **Bytes** y **Packets** In/Out
  desde el arranque. A la derecha, la tarjeta **Traffic** se adapta hasta un mínimo y lleva en la
  cabecera, en una sola línea, el título, la leyenda con **Upload** y **Download** (punto de
  color, etiqueta y tasa en las unidades del modo activo) y el selector **Bits/Packets** glass a
  la derecha; cada entrada de la leyenda alterna el foco de su dirección al pulsarla. El gráfico
  es un **ecualizador espejado** de barras sólidas (upload arriba, download abajo) coloreadas con
  la escala de calor según su magnitud. Las barras ocupan slots
  fijos desde la izquierda, de modo que un histórico corto queda empaquetado en lugar de
  repartirse por todo el ancho, sobre cuadrícula, niveles y eje temporal nominal (120 × intervalo). Una **barra de filtros** entre las pills y la
  tarjeta de la tabla reúne los grupos de checkboxes multiselección en cápsulas. En Connections:
  **IP** (IPv4/IPv6), **Transport** (TCP/UDP/Other), **TCP State** (Established, Listening,
  Connecting (SYN), Closing (Close/Fin/Time Wait)) y **Other** en su propia cápsula (solo el
  checkbox, estados TCP no clasificados); en Processes: **Socket domain** (AF_INET, AF_INET6,
  AF_UNIX, Other), **Socket protocols** (TCP/UDP/ICMP/ICMPv6/SCTP/GRE/ESP/RAW/Other) y
  **Socket type** (stream/dgram/raw/seqpacket/other). Las tres facetas de Processes se cruzan sobre **el mismo
  socket** usando las firmas `(domain, type, protocol)` de libproc; un protocolo seleccionado
  exige familia AF_INET/AF_INET6. Todos los valores están marcados por defecto, incluido
  **Other**; desmarcar excluye y un grupo sin nada marcado no muestra filas. Other afecta solo a
  estados TCP no clasificados: desmarcarlo no oculta las filas UDP, que dependen de
  **Transport › UDP**. La cabecera de la tarjeta
  conserva el título, **Filter process**
  en Connections / **Filter processes** en Processes (nombre o PID; en Processes también ruta y
  usuario), y, alineados a la derecha, el contador de filas, **Resolve names** y el botón
  **Inspect Process**, que queda en el extremo derecho.
  La tabla de Connections muestra Process, PID, Local, Remote, Proto, State, RX,
  TX, Rate (bits/s) e Iface, y permite ordenar por cualquier columna. La cabecera incluye
  **Resolve names** (apagado por defecto): al activarlo, Local y Remote cambian de
  `ip:puerto` a `hostname:puerto` a medida que termina la resolución inversa, conservan la IP
  si no hay PTR y el tooltip guarda `hostname · ip:puerto`. Los flujos
  UDP, que no tienen estado TCP, muestran **Datagram** en State.
  La tabla de Processes lista solo procesos con flujos TCP/UDP o sockets (incluye UNIX y RAW vía
  libproc) y muestra Process, PID, Guard, **Domain**, **Protocols**, **Type**, Flows, RX, TX,
  Rate y Path. Domain lista las familias (`INET`, `INET6`, `UNIX`, `SYSTEM`…; el tooltip conserva
  el nombre `AF_*` completo) y Protocols solo los protocolos IP reales (`TCP`, `UDP`, `ICMP`,
  `ICMPv6`, `SCTP`, `GRE`, `ESP`, `RAW`…), sin `+N`. Type muestra el desglose
  stream/dgram/raw/seqpacket/other. El tooltip de ambas columnas detalla cada firma
  `AF_* · SOCK_* · IPPROTO_*`. Sin escaneo se usan las etiquetas agregadas y el detalle de
  `RAW4`/`RAW6`/`OTHER` como antes.
  (p. ej. daemon antiguo o sockets restringidos). El inspector de proceso muestra la misma etiqueta
  en su columna Type. Los filtros de cada subpestaña son independientes. Ambas
  tablas se pueden ordenar por cualquier columna. Sin root solo se leen sockets del propio
  usuario; el daemon root cubre el resto. Las **velocidades** se muestran en bits con unidades
  humanas (`bps`, `Kbps`, `Mbps`, `Gbps`); los **totales acumulados** siguen en Bytes (`KB`, `MB`,
  `GB`). El selector de **Interval** ajusta la cadencia real de Networking y CPU; con el daemon
  conectado reenvía la suscripción y en local despierta el bucle de polling. Al cambiarlo, los
  historiales se reinician para que el eje temporal del gráfico coincida con la nueva cadencia.
- **Disk** — cuatro subpestañas:
  - **Filesystems** — tarjeta con todos los sistemas de ficheros montados, al estilo de
    `df`: Filesystem, Type, Size, Used, Available, Capacity, iused, ifree, %iused y Mounted on.
    Tabla ordenable con filtro por dispositivo/tipo/mount, botón Refresh y actualización cada
    5 segundos mientras está visible. Usa `getfsstat`/`statfs` y
    `getattrlist(ATTR_VOL_SPACEUSED)` para el uso individual de APFS; Capacity es
    `ceil(Used / (Used + Available) × 100)`, como `df`. Respeta Decimal/Binary.
    Los montajes de red y autofs usan estadísticas del kernel, marcadas con un reloj,
    para no bloquear con servidores inaccesibles. Los errores locales conservan las cifras
    disponibles y muestran un aviso. Las capacidades APFS no se suman entre filas.
    Diagnóstico: `KancerberoProbe disk filesystems` (bytes exactos).
  - **Volumes** — jerarquía nativa de discos físicos, particiones, contenedores APFS y volúmenes
    (IOKit + DiskArbitration + `getmntinfo`/`getattrlist`), con capacidad, usado, libre, punto de
    montaje, UUID, roles APFS, modelo/protocolo y cifrado. No ejecuta procesos externos. La
    cabecera de la tarjeta muestra el disco que se está viendo con el chip de capacidad resaltado y
    los chips de Capacity/Partitions/Containers/Volumes (icono + nombre + número), más pequeños y
    siempre en una sola línea: el nombre del disco se reduce o trunca antes; las tablas por disco
    muestran la jerarquía
    completa. El flag `--volumes-focus` sigue permitiendo filtrar las tablas para capturas. El
    panel izquierdo es una pila de tablas, una por disco, con cabecera colapsable en una línea
    (chevron, `Nombre — disk0`, tipo de medio más tenue y, a la derecha, capacidad · usado ·
    libre), con textos en tinta contrastada; por defecto están todas abiertas. Cada tabla repite las columnas
    **Name / Disk / Type / Size / Used / Free / Mounted / Mount**, con filas de una línea y sin
    indentación (la jerarquía se sigue por los chevrons y la cabecera de cada disco). Los títulos
    de Used, Free y Mounted van centrados, y los valores de Mounted también. La cabecera
    separa las columnas con líneas arrastrables para redimensionarlas; los anchos se comparten
    entre tablas y se conservan durante la sesión, y Mount absorbe el espacio sobrante. Con los
    anchos por defecto las ocho columnas caben en el panel a 1/2 en una ventana de 1440, sin barra
    horizontal; si no caben, cada tabla se desplaza horizontalmente.
    Disk muestra el identificador del dispositivo de cada fila (`disk0`, `disk0s2`, `disk3s1`…);
    Type combina el tipo y el sistema de ficheros
    (`Volume APFS`, `Partition MS-DOS`, `Container APFS`; nombre completo en el tooltip) y Mounted
    Yes/No en volúmenes y snapshots, `—` en el resto. Mount usa el mismo color de tinta que el
    resto de celdas, no un gris más claro. Used incluye una mini barra (volúmenes: parte del usado
    del contenedor; resto: usado/capacidad) y Free muestra `—` en volúmenes (espacio compartido).
    El panel de tablas y el de detalle se reparten el ancho a la mitad
    (sin selección, las tablas ocupan todo); el divisor central se puede arrastrar para cambiar el
    reparto y la proporción se conserva durante la sesión. La tabla conserva su posición de scroll
    al seleccionar un elemento. El detalle muestra una tarjeta hero con Capacity/Free/Used a la
    izquierda, una barra vertical de volúmenes en medio y un treemap rectangular anidado con la
    estructura del disco (particiones →
    contenedores APFS → volúmenes, con libre, residual y espacio no asignado). La cabecera de la
    tarjeta muestra el nombre del disco y no cambia al seleccionar un volumen o contenedor. Cada
    rectángulo
    tiene un tamaño mínimo visible, así que todas las particiones y volúmenes aparecen aunque las
    áreas dejen de ser estrictamente proporcionales al uso; el texto de los tiles es mayor y la
    altura del treemap se adapta al contenido (420/460–860 pt) para que quepan las etiquetas sin
    crecer de más. Todos los contenedores y
    volúmenes muestran su uso/% (inline en
    filas compactas); los tiles suficientemente grandes
    muestran nombre, usado y porcentaje (los volúmenes vacíos, `Not mounted`). Cada etiqueta
    incluye el identificador y el tipo (`disk3s5 · Macintosh HD - Data · APFS volume`), y las
    particiones/contenedores dejan un marco visible (inset 12/9/7 pt) alrededor de sus hijos. Las
    particiones comparten un hueso claro, los contenedores un hueso medio y los volúmenes, por
    defecto, la paleta azul grisácea de tres tonos (`#c9cbd0 #b9bcc2 #a9adb4`; free `#f7f3ea`,
    residual `#d2c9ba`). Si hay un volumen seleccionado, ese pasa al azul de la app (`#4f93cc`) y
    los demás conservan los grises; cada partición muestra su usado y porcentaje alineado a la
    derecha en la cabecera. El texto de los tiles tiene un mínimo legible de 11.5 pt (12.5
    maximizado): si no cabe se trunca con elipsis, nunca se reduce por debajo. La cabecera de la
    tarjeta muestra el nombre del disco con el chip de capacidad resaltado y los chips de
    componentes con sus nombres (icono + nombre + número); el disco aparece como contenedor raíz
    dentro del treemap, con su banda de cabecera (`disk0`, capacidad, usado y libre) y las
    particiones dentro; el gráfico no lleva fondo ni recuadro exterior, se apoya directamente en
    la tarjeta de detalle. La tarjeta de detalle vuelve al material claro de la app, con un lavado
    ámbar/teal, borde y sombra suaves. El treemap usa esa paleta hueso, con bordes y texto en
    tinta oscura cálida; las barras de la tabla siguen en azul.
    La barra mide 4/5 de la altura del treemap, se acota al alto disponible de la tarjeta para
    que quepa al redimensionar la ventana y no tiene líneas de unión con el treemap. Es un carril
    oscuro de esquinas redondeadas: una sección por cada volumen APFS del disco y una por el
    espacio libre de cada contenedor (las particiones y los contenedores no se dibujan). Los
    volúmenes llevan un degradado azul y el espacio libre se distingue por una trama diagonal. El
    grupo seleccionado pasa a un degradado cian-azul y se rodea de un contorno luminoso; el resto
    queda en azul grisáceo oscuro. Cada sección recibe una altura mínima visible y el espacio
    restante se reparte proporcionalmente, así que los bloques mayores crecen cuando hay sitio. La
    selección abarca el subárbol del elemento: un volumen destaca su sección; un contenedor, todas
    sus secciones y su espacio libre; una partición o el disco, todo su subárbol. Sobre la barra se
    muestran el tipo y el porcentaje del elemento seleccionado; debajo, la leyenda "of
    container"/"of capacity". La columna Capacity/Free/Used queda a la izquierda: Capacity y Free
    arriba, y Used a la altura de la porción seleccionada, unido a la barra con una línea
    horizontal; la nota de espacio compartido queda debajo. Si se selecciona el espacio libre en el
    treemap, esa sección se destaca también en la barra (Used vuelve a su posición superior).
    Pulsar de nuevo el elemento seleccionado en el treemap, o su tramo resaltado en la barra,
    quita el resaltado del detalle sin cambiar la selección de las tablas; un clic fuera del
    treemap y de la barra también lo quita. El panel de detalles sigue mostrando todo
    (estadísticas, treemap, barra y metadata) sin ningún tile o tramo resaltado; volver a pulsar
    el elemento o la barra restaura el resaltado y la x cierra el panel.
    El mount point de cada volumen se dibuja en la misma línea que el nombre (a la izquierda) y el
    tamaño/uso (a la derecha), empezando en una columna central común del treemap y alineado a la
    izquierda; las hojas que no cruzan esa columna no muestran el mount. No hay pop/tooltip sobre
    el treemap.
    Si el elemento es un contenedor o volumen APFS se indica el espacio compartido y con qué
    volúmenes/contenedor.
    Las actions (Reveal, Copy ID, Analyze) van en una sola línea por encima de la metadata. No hay
    leyenda debajo
    del treemap: el rectángulo ocupa ese espacio. El elemento
    seleccionado queda resaltado; la barra comparte la selección y las barras de las tablas
    siguen en azul. Al
    pulsar un rectángulo se selecciona ese elemento en las tablas y el detalle se
    actualiza; pulsar el fondo del treemap selecciona el disco.
    Cada tarjeta se puede maximizar al área de Volumes y restaurar. El
    selector **Decimal/Binary** de la línea de
    pestañas cambia todas las cifras de Disk: Decimal (por defecto, como Finder) usa KB/MB/GB con
    base 1000; Binary usa KiB/MiB/GiB con base 1024. La elección se recuerda.
  - **Analyzer** — escaneo local de una carpeta o volumen con `getattrlistbulk`, mapa radial
    interactivo (un clic selecciona un sector y su fila en las tablas; doble clic en un sector
    para bajar, doble clic en el centro para subir), drill-down, mayores archivos, progreso y
    cancelación. **Hidden** viene activado por defecto: el mapa y las tablas muestran entradas
    ocultas y Largest files incluye ficheros ocultos (el ajuste se aplica al iniciar el escaneo).
    La selección se comparte entre el mapa, la tabla de contenidos y la de mayores archivos; se
    limpia al navegar o al iniciar un escaneo, y en sectores anidados el mapa resalta el sector
    exacto mientras la tabla resalta su ancestro de primer nivel. **Contents** lista carpetas y
    los ficheros directos retenidos por el escaneo (los 200 mayores de cada carpeta, con un tope
    global); la cabecera indica “top N of M files” cuando hay truncado y la tarjeta Files filtra
    solo ficheros. Al seleccionar un fichero en **Contents** o en **Largest files** el mapa
    navega al directorio que lo contiene y dibuja un sector sintético resaltado para el fichero;
    el sector seleccionado se expande hacia fuera hasta ~10 pt sobre su geometría normal, además
    del halo. El panel derecho reparte su altura entre ambas tablas con un separador horizontal
    arrastrable, con mínimos por tabla. El mapa y las tarjetas se actualizan en vivo durante el
    escaneo; las tablas de contenidos y mayores archivos aparecen al terminar. Las etiquetas del
    mapa muestran el nombre y el tamaño en formato humano. Las tarjetas filtran el panel derecho
    (todo, solo ficheros, solo carpetas o rutas denegadas); no se lee contenido de ficheros.
  - **I/O** — actividad de disco con gráfico espejado lectura/escritura (histórico de 120 muestras),
    selector **Data / Operations**, tasas y totales de Reads in, Writes out, Data read y Data
    written, y tabla de procesos por actividad de disco (Command, PID, USER, Read/s, Write/s,
    Bytes Read, Bytes Written, Writes, State). Los contadores del sistema salen de `IOBlockStorageDriver`
    (`Bytes/Operations`); los de proceso de `rusage_info_v6`.
- **Daemons** — inventario de servicios launchd con chips multiselección por tipo (agentes /
  daemons), ámbito (sistema / global / usuario / runtime), origen (Apple / custom / desconocido)
  y estado (running / stopped / disabled / not loaded). Todos los valores están pulsados al
  arrancar; solo se muestran las filas de los valores pulsados y un grupo sin nada pulsado no
  muestra filas. La búsqueda vive en la cabecera de la tarjeta Services y las tarjetas Running /
  Stopped / Disabled alternan ese estado en el filtro. La tabla es ordenable por cualquiera de sus
  columnas. Los agentes duplicados entre los dominios
  GUI y User se deduplican por label, conservando ambos dominios en el detalle. Inspector con
  Start / Stop / Restart / Enable·Disable / Load·Unload / Reveal.
  Las acciones de sistema requieren el daemon root y confirmación; GUI/User funcionan en local.
  Los login items quedan para una iteración posterior.
- **CPU** — dashboard tipo `htop`: tarjetas de CPU, load average, tareas/hilos y memoria con
  sparklines; card de núcleos tipo muro ecualizador (`C1..CN`) con barritas rectangulares del
  histórico reciente de cada core, color por carga, grupos Performance/Efficiency, uso y
  temperatura por core, y temperatura de paquete vía IOHID (como btop); uptime; memoria y swap
  con desglose Active/Wired/Compressed/Cached/Free; y tabla de procesos ordenable con búsqueda
  (Command, PID, USER, PRI/NI, VIRT, RES, S/THR, CPU%, MEM%, TIME+, %GPU y GPU Time). CPU% no
  se normaliza (puede superar 100% en multihilo). `%GPU` y `GPU Time` salen de
  `IOAccelerator > AppUsage` (`accumulatedGPUTime`) por proceso, legible sin root: `%GPU` es el
  delta sobre la ventana (limitado a 100%) y `GPU Time` usa el formato de `TIME+`. El listado usa
  `KERN_PROC_ALL` e incluye todos los procesos
  (kernel_task incluido), sin descartar los que no exponen task info. Sin daemon root los
  contadores de otros usuarios quedan restringidos; si el daemon es antiguo la app fusiona las
  identidades locales y avisa en System status (los hilos aparecen como “partial”).
- **Memory** — panel dedicado tipo Activity Monitor: presión de memoria (Low/Medium/High) con
  histórico y explicación, composición App/Wired/Compressed/Cached/Free, detalle de Physical
  Memory, Memory Used, App Memory, Wired, Compressed, Cached Files y Swap, y tabla de procesos
  ordenada por memoria residente (Command, PID, USER, Memory, MEM%, Threads) con búsqueda,
  selección e inspector.
- **Energy** — panel tipo Activity Monitor: estado de batería (carga, tiempo restante, cargando,
  conector) con el gráfico de 12 h de carga, bandas verdes del tiempo en AC y «Time on AC/Battery»,
  consumo por proceso en vatios y wake-ups inactivos con histórico, procesos que impiden dormir, y
  tabla ordenada por energía (Command, PID, USER, Energy, Impact, Wake-ups, CPU%, Preventing Sleep).

**Dock icon** — el menú `Dock Icon` (y Ajustes → Dock) cambia el icono del Dock por gráficos en
vivo, igual que Activity Monitor: aplicación, uso e histórico de CPU, uso de red, actividad de
disco, uso y presión de memoria, GPU y energía. La elección se guarda en `dockIconStyle`;
`Clear History` vacía los históricos y “Show Application Icon” restaura el icono normal. Se dibuja
con `NSDockTile.contentView` y sigue actualizándose aunque la ventana esté cerrada.

La barra inferior es contextual: muestra métricas de la sección activa (tráfico, capacidad de
disco, servicios o CPU/memoria) y, a la derecha, el estado global de la conexión con el daemon,
la última actualización de la fuente correspondiente y el posible error. Pulsar **Local mode /
Daemon connected** en el footer del sidebar, el pill **Local / Daemon** de la barra inferior o el
icono de Kancerbero en la cabecera del sidebar abre la ventana **System status** con un checklist
de la app, el helper, la colección, los
privilegios, el acceso total al disco (FDA), el registro SMAppService, la aprobación en Login
Items y la conexión XPC. Incluye explicaciones, los pasos para habilitar el acceso completo y acciones
para activar, abrir Login Items, reintentar, reparar/re-registrar, refrescar o revelar la app. Si
falta Acceso Total al Disco, la fila correspondiente abre una guía paso a paso y la pestaña
Applications muestra un aviso para desbloquear los contenedores de otras apps.

La pestaña **Filter** muestra los flujos que ve la Network Extension (proceso, endpoints,
protocolo, RX/TX por flujo y estado). En **Processes**, el escudo de cada fila marca un proceso
como vigilado y, cuando lo está, muestra junto a él un badge con su política (Ask/Allow/Deny):
cada conexión nueva de un proceso vigilado pide aprobación (allow/deny, una vez o recordada por
app o app+destino). La aprobación es una hoja grande con el icono y el nombre del
proceso, el destino destacado, una cuenta atrás circular y un selector **Remember** (Once / This
app / App + destination) junto a dos botones **Allow** / **Deny**; Return permite y Escape deniega,
y la hoja no se cierra sin decidir. Las decisiones cierran la hoja al instante y las operaciones
del filtro tienen timeout, así que la ventana nunca se queda bloqueada esperando al sistema. La
barra del Filter incluye **Resolve names** (comparte estado con la tabla de Connections) y
**Filter Rules…**, que abre una ventana
con el estado del filtro y la lista de reglas (cambiar la política pulsando su badge, y borrar
seleccionando la fila y usando **Delete** en la cabecera, la papelera de la fila o el menú
contextual) y de decisiones recordadas (borrar). La pestaña incluye además un interruptor global
**Block all new connections**: mientras está activo deniega todo flujo nuevo (también los de
procesos con Allow o decisión recordada) sin crear ninguna regla, se conserva al reiniciar y la
tarjeta se vuelve roja con un pulso; la barra de estado muestra **Blocking** (o **Block armed**
si el filtro aún no está corriendo, y **Block outdated** si la extensión en ejecución es una
build anterior y hay que reinstalarla/reactivarla). Si Kancerbero está cerrado o nadie responde, la conexión se
deniega (fail-closed). Requiere una build firmada con Developer ID, los entitlements de Network
Extension y aprobar la system extension; el detalle de binario y permisos está en
`docs/daemons-and-libraries.md` y las pruebas en `docs/verification.md`.

Las selecciones y configuraciones de cada sección (filtros, tarjeta activa, fila seleccionada,
panel de detalle y tablas expandidas) se conservan al cambiar de pestaña o sección durante la
sesión; al reiniciar la app se vuelven a los valores iniciales. **Kancerbero → Settings… (⌘,)** o el
botón **Settings** (engranaje) al pie del sidebar permiten ajustar las animaciones de cambio de
sección/subpestaña y del resaltado del sidebar y las píldoras, las animaciones de los valores de
la barra de estado (desactivadas por defecto), el intervalo de muestreo con el que arranca la app
(2 s por defecto), la ventana de conexiones activas (10 s por defecto; 5/10/20/30/60/120) y el
icono del Dock. Todo se guarda en `UserDefaults` y las animaciones respetan
Reduce Motion de
macOS. El selector del toolbar cambia el intervalo solo durante la sesión y no modifica la
preferencia de arranque.

El panel se oculta con el toggle de la toolbar o `Cmd+Ctrl+S`; `Cmd+1/2/3/4/5/6/7` cambia de sección
(Networking, Disk, Daemons, CPU, Memory, Energy, Applications). El título de la ventana es el de la
app, como texto nativo. Cuando la sidebar está oculta, el selector segmentado con los 7 iconos se
centra en el hueco entre el título y los controles de la derecha y se mantiene centrado al
redimensionar; al mostrar la sidebar, el selector y su reborde desaparecen. Los controles de la
derecha conservan su posición.

Las tarjetas de dashboard se pueden colapsar para dejar solo la cabecera, los filtros y la tabla.
El botón de la toolbar (delante del selector de intervalo) colapsa o expande **todas** las
secciones; el botón `Hide cards`/`Show cards` de cada cabecera cambia solo esa pestaña;
`Cmd+Shift+H` alterna el estado global. El estado es solo de la sesión. Al colapsar se resetean los
filtros que solo existen dentro de las tarjetas (foco de descarga/subida en Networking y foco de
volumen/analizador en Disk) para no dejar tablas filtradas sin control visible.

## Compilar

```bash
./scripts/build.sh                 # Debug: app, probe y daemon
./scripts/clean.sh                 # borra build/ (DerivedData local)
./scripts/clean.sh --debug         # borra build/ y compila Debug limpio
./scripts/clean.sh --release       # borra build/ y compila Release con build-release.sh
# o
xcodebuild -project Kancerbero.xcodeproj -scheme Kancerbero \
  -configuration Debug -derivedDataPath build build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

Productos en `build/Build/Products/Debug/`.

La build Debug desde Xcode se firma con la identidad automática **Apple Development**, y la
system extension se firma con la misma identidad para que `ValidateEmbeddedBinary` pase. En Debug
se usan `Resources/App/Kancerbero-Development.entitlements` y
`Resources/Filter/KancerberoFilter-Development.entitlements`, con el valor
`content-filter-provider` sin sufijo, que es el único que conceden los perfiles Mac Team.

**Un build Debug no puede activar el filtro** en un Mac con SIP activado: `sysextd` lo rechaza con
`no policy, cannot allow apps outside /Applications` o `developer/groundhog mode isn't on`, y
`systemextensionsctl developer on` exige SIP deshabilitado.

Para el filtro de red en Release hacen falta un certificado **Developer ID Application** y dos
provisioning profiles Developer ID (app y extensión) con la capability Network Extensions; en
Release la extensión usa `Resources/Filter/KancerberoFilter.entitlements` con el valor
`content-filter-provider-systemextension`. Copiar `Config/Signing.local.xcconfig.example` a
`Config/Signing.local.xcconfig` (ignorado por git), rellenar los nombres o UUID de los perfiles y
usar `./scripts/build-release.sh` (falla a propósito si falta esa configuración). Los builds
ad-hoc (`./scripts/build.sh`, que pasa `CODE_SIGN_IDENTITY=-` y `CODE_SIGN_ENTITLEMENTS=`) siguen
compilando y ejecutando el resto de la app, pero muestran el filtro como no disponible.

## Icono

El icono de la app vive en `Sources/Kancerbero/Assets.xcassets/AppIcon.appiconset` y se genera con:

```bash
./scripts/make-icon.sh [origen.png]
```

Por defecto usa `/Users/alejandro/CODE/Iconos/kancerbero/kancerbero_1024x1024.png` (1254×1254; el
script lo reduce a 1024 para el slot mayor) y produce los 10 tamaños de macOS entre 16 y 1024.
El logotipo interno de la barra lateral es independiente y no se modifica. Si Finder/Dock muestra
un icono antiguo, es caché de LaunchServices: copia la app a otra ruta o reinicia Finder/Dock.

## Ejecutar

```bash
open build/Build/Products/Debug/Kancerbero.app
./build/Build/Products/Debug/KancerberoProbe all --seconds 3
./build/Build/Products/Debug/KancerberoProbe cpu --interval 1
./build/Build/Products/Debug/KancerberoProbe battery-graph
./build/Build/Products/Debug/KancerberoProbe procs --cpu --limit 20
```

Comandos y permisos de `KancerberoProbe` en `docs/daemons-and-libraries.md`.

Captura de la UI sin permisos de Grabación de pantalla (la app se dibuja a sí misma y termina):

```bash
build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero \
  --screenshot /tmp/kancerbero-ui.png \
  [--section networking|disk|daemons|cpu|memory|energy|applications] \
  [--cards-collapsed | --cards-expanded] \
  [--cards-collapsed-sections networking,cpu,...] \
  [--screenshot-size <ancho>x<alto>] \
  [--tab interfaces|connections|processes] \
  [--disk-tab volumes|analyzer|io] \
  [--disk-path=<carpeta>] [--disk-scan] [--disk-item <diskXsY>] \
  [--disk-io-search <texto>] [--disk-io-selected <pid>] \
  [--disk-io-graph data|operations] \
  [--disk-units decimal|binary] \
  [--cpu-search <texto>] [--cpu-selected <pid>] \
  [--memory-search <texto>] [--memory-selected <pid>] \
  [--energy-search <texto>] [--energy-selected <pid>] \
  [--applications-search <texto>] [--applications-selected <bundle-id>] \
  [--applications-scope user|system] \
  [--show-status] \
  [--screenshot-dock <ruta>] [--dock-style <estilo|all>] \
  [--networking-focus download|upload|connections|active|processes] \
  [--traffic-graph bits|packets] \
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
  [--volumes-focus disks|containers|volumes|capacity|free] \
  [--volumes-maximized tree|details] \
  [--analyzer-focus scanned|files|folders|denied] \
  [--daemon-type all|agent|daemon[,..]] \
  [--daemon-scope system|global|user|runtime[,..]] \
  [--daemon-origin apple|custom|unknown[,..]] \
  [--daemon-state running|stopped|disabled|unloaded[,..]] \
  [--daemon-domain system|gui|user] [--daemon-selected <label>] \
  [--sidebar-collapsed]
```

`--cards-collapsed`/`--cards-expanded` fuerzan todas las tarjetas colapsadas/expandidas y
`--cards-collapsed-sections` un estado mixto (lista de secciones); `--screenshot-size 1340x700`
fija el tamaño de la ventana (mínimo 1340×700 con la sidebar; al ocultarla baja a 1088×700,
porque el contenido aprovecha sus 252 pt). Los flags **sin valor** (`--cards-collapsed`, `--cards-expanded`,
`--sidebar-collapsed`, `--disk-scan`, `--show-status`, `--networking-resolve-names`) deben ir al
final de la línea de
argumentos; si quedan en medio, macOS puede abrir la app sin ventana principal y la captura no se
genera.

Guía paso a paso, comandos reproducibles y errores frecuentes:
[`docs/verification.md` → Captura visual de la UI sin TCC](docs/verification.md#captura-visual-de-la-ui-sin-tcc).

## Daemon

Detalle de binarios, permisos, instalación y desinstalación en `docs/daemons-and-libraries.md`.

### Servicio en background (SMAppService)

La app embebe el helper y su plist en
`Kancerbero.app/Contents/Library/LaunchDaemons/` y los registra con
`SMAppService.daemon(plistName:)` al arrancar (una sola vez, salvo que el usuario lo haya
desactivado) o desde la ventana **System status** / el menú **Daemon**. macOS lo muestra en
**Ajustes → General → Login Items & Extensions → Allow in the Background** con el icono de
Kancerbero (vía `AssociatedBundleIdentifiers`); el usuario debe aprobarlo. La app usa
`NSXPCConnection` privilegiado para el daemon de sistema.

El servicio usa la identidad `uno.kayros.kancerbero.daemon.service` (label y Mach service) y el
plist `uno.kayros.kancerbero.daemon.service.plist`. Es un identificador nuevo que evita los
registros de ServiceManagement/BTM de versiones anteriores: macOS guarda un *launch constraint*
por label y, si ya no coincide, volver a registrar el mismo label no lo refresca (`Launch
Constraint Violation`). La actualización desregistra una vez el servicio anterior `.v2`; al cambiar
la identidad, macOS pide aprobar de nuevo el background item en Login Items.

El daemon se firma con el **mismo identificador de code signing que la app**
(`-i uno.kayros.kancerbero`) y sin ningún entitlement. ServiceManagement construye el launch
constraint del job a partir del requisito de la app; un tool firmado con su propio nombre no lo
satisface y muere al arrancar aunque Login Items lo muestre habilitado.

La ventana **System status** muestra el estado real (proceso vivo, PID, último error de conexión)
y permite **Repair / re-register**: desregistra y vuelve a registrar el helper para que macOS
pueda pedir la aprobación de nuevo. La aprobación en Login Items no se puede automatizar; la
ventana abre el ajuste correcto y muestra los pasos.

Requisitos de distribución:

```bash
# Crear el perfil de notarización una sola vez:
xcrun notarytool store-credentials kancerbero-notary \
  --apple-id "<Apple ID>" --team-id AK37TK8X2Y --password "<app-specific password>"

# Release completo, sin publicar (build + notarización + ZIP + appcast + DMG).
# La versión/build de la app se generan en cada compilación; el daemon y el
# filtro solo cambian cuando cambia su código (Config/ComponentVersions.xcconfig).
./scripts/release.sh

# Publicar en GitHub Releases + Pages con gh autenticado (gh auth login).
# Publica el ZIP de Sparkle y el DMG en los assets de la misma release.
# Alternativa sin gh: exportar GITHUB_TOKEN con Contents: Read and write.
./scripts/release.sh --publish

./scripts/install-app.sh        # instalación manual para probar
```

DMG de distribución:

```bash
# release.sh ya genera y publica el DMG junto al ZIP. Para generarlo solo,
# tras notarizar la app:
./scripts/package-dmg.sh
# -> build/updates/dmg/Kancerbero-<version>.dmg
```

El DMG se firma con Developer ID, se notariza, se le grapa el ticket y se verifica la imagen y la
app embebida. `release.sh` lo crea después del ZIP y `publish-release.sh` sube ambos assets a la
misma release; el appcast de Sparkle sigue apuntando al ZIP. Para probar el layout sin
notarización: `KANCERBERO_DMG_DEV=1`; en entornos sin Finder:
`KANCERBERO_DMG_SKIP_LAYOUT=1` (sin fondo).

La app se actualiza con **Sparkle 2** (feed EdDSA en GitHub Pages, ZIP en GitHub Releases). La
primera versión con Sparkle se instala a mano; a partir de ahí las actualizaciones son
automáticas. La versión de la app es `0.2.<build>`, con el build en formato `YYMMDDHHMM` (10
dígitos); el ZIP de release es `Kancerbero-<version>.zip`. Daemon y filtro tienen su propio
`0.2.<build>` y solo cambian cuando cambia su componente. La ventana **System Status** muestra las
versiones en ejecución y las que trae el ejecutable. Detalle, gestión de la clave y diagnóstico en
[`docs/updates.md`](docs/updates.md).

Un daemon registrado con `SMAppService` exige app firmada con Developer ID y **notarizada**.
La build Debug ad-hoc puede mostrar la UI y el estado, pero no se espera que `register()` funcione.

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

## Disk

- Inventario nativo, sin `diskutil`: IOKit (`IOMedia`, `AppleAPFSMedia`, `AppleAPFSVolume`) para la
  jerarquía y los metadatos APFS; DiskArbitration para nombres, puntos de montaje, UUIDs, modelo y
  cifrado; `getmntinfo` + `getattrlist(ATTR_VOL_*)` para capacidad y usado por volumen.
- Análisis con `getattrlistbulk` por directorio (`ATTR_CMN_RETURNED_ATTRS`, `NAME`, `OBJTYPE`,
  `ATTR_FILE_TOTALSIZE/ALLOCSIZE`, `ATTR_DIR_ALLOCSIZE/MOUNTSTATUS`), sin seguir symlinks y sin
  cruzar puntos de montaje por defecto.
- Diagnóstico:

```bash
./build/Build/Products/Debug/KancerberoProbe disk volumes
./build/Build/Products/Debug/KancerberoProbe disk usage disk3
./build/Build/Products/Debug/KancerberoProbe disk info disk3s5
./build/Build/Products/Debug/KancerberoProbe disk scan "$HOME/Documents" --top 20
```

## Verificación

```bash
./scripts/verify.sh
```

Compara con `netstat -ibI`, `lsof -nP -i`, `nettop` y Activity Monitor. Detalle y tolerancias en
`docs/verification.md`.

## Limitaciones conocidas

- APIs privadas (`NetworkStatistics.framework`): no apto para App Store.
- Actualizaciones: Sparkle 2 requiere app Developer ID notarizada en `/Applications`; el feed y
  los binarios son públicos. Las instalaciones anteriores a la primera versión con Sparkle no se
  autoactualizan (bootstrap manual).
- Sin firma Developer ID, el daemon se instala en modo desarrollo (ad-hoc + launchd manual).
- El filtro de red es una system extension: macOS solo la activa desde una app Developer ID
  **notarizada** (o con developer mode, que exige SIP desactivado). Con un build Apple
  Development `sysextd` responde `no policy, cannot allow apps outside /Applications` o
  `developer/groundhog mode isn't on`. El tráfico de procesos excluidos por Apple no se observa y
  los contadores son agregados del kernel, no byte-exactos.
- `NStatSourceIdentifier` no es fiable en macOS 27; se usa el puntero de fuente y las claves
  `PID`/`UUID`.
- La atribución por proceso usa `epid` cuando existe (como Activity Monitor); los flujos sin
  proceso se agrupan como desconocidos.
- El inspector usa `libproc`; para procesos de otros uid requiere el daemon root. Es una ventana
  independiente por proceso con Statistics organizada en tres grupos visuales: Process (CPU, hilos,
  grupo, padre, usuario y ruta), Memory (footprint, real, virtual, private, shared y puertos) y
  System (llamadas Mach y Unix, mensajes Mach in/out, cambios de contexto, fallos y page ins),
  además de Open Files and Ports (descriptores y sockets fusionados por fd).
