#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROBE="$ROOT/build/Build/Products/Debug/KancerberoProbe"

"$PROBE" symbols
"$PROBE" procs --limit 5
"$PROBE" thermal --seconds 2 --interval 1
"$PROBE" ifaces
"$PROBE" nstat --seconds 2

echo
echo "==> interface counters vs netstat (en0)"
/usr/sbin/netstat -ibI en0 | tail -2
