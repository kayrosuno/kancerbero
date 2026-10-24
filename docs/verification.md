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
launchctl print gui/$(id -u)/com.alejandro.kancerbero.agent
# la app debe mostrar "source: daemon" en la barra inferior
./scripts/uninstall-agent.sh

sudo ./scripts/install-daemon.sh
sudo launchctl print system/com.alejandro.kancerbero.daemon
sudo ./scripts/uninstall-daemon.sh
```

## Rendimiento

```bash
ps -o pid,%cpu,rss,etime -p <pid-daemon>
sample <pid-daemon> 5 -file /tmp/kancerbero.sample.txt
leaks <pid-daemon>
```

Objetivo: CPU <3% y RSS <150 MB con miles de conexiones; sin crecimiento de memoria en una hora.
