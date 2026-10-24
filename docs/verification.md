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
  [--section networking|disk|daemons] \
  [--tab interfaces|connections|processes] \
  [--sidebar-collapsed]
```

`--section` selecciona la sección de primer nivel, `--tab` la subpestaña de Networking y
`--sidebar-collapsed` captura el panel lateral oculto. El PNG se escribe a escala de backing
(2x en Retina) y la app termina con código 0.

Capturas recomendadas:

```bash
for args in \
  "--section networking --tab interfaces" \
  "--section networking --tab connections" \
  "--section networking --tab processes" \
  "--section disk" \
  "--section daemons" \
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
./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero \
  --screenshot /tmp/kb-daemons.png --section daemons --screenshot-delay 5
./build/Build/Products/Debug/Kancerbero.app/Contents/MacOS/Kancerbero \
  --screenshot /tmp/kb-daemons-detail.png --section daemons \
  --daemon-selected com.apple.Finder --screenshot-delay 5
```

## Rendimiento

```bash
ps -o pid,%cpu,rss,etime -p <pid-daemon>
sample <pid-daemon> 5 -file /tmp/kancerbero.sample.txt
leaks <pid-daemon>
```

Objetivo: CPU <3% y RSS <150 MB con miles de conexiones; sin crecimiento de memoria en una hora.
