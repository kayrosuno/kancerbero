#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"

usage() {
    cat <<'USAGE'
Uso: scripts/clean.sh [--release | --debug]

Sin opciones borra el DerivedData local (build/) y termina.
  --release  Borra build/ y ejecuta scripts/build-release.sh (Developer ID).
  --debug    Borra build/ y ejecuta scripts/build.sh en Debug.
USAGE
}

MODE="clean"
for argument in "$@"; do
    case "$argument" in
        --release) MODE="release" ;;
        --debug) MODE="debug" ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "opción desconocida: $argument" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# build/ es el -derivedDataPath de scripts/build.sh y build-release.sh. No se
# toca ~/Library/Developer/Xcode/DerivedData: ese directorio pertenece a Xcode.
if [[ -e "$BUILD" || -L "$BUILD" ]]; then
    size="$(du -sh "$BUILD" 2>/dev/null | awk '{print $1}')"
    echo "==> borrando $BUILD${size:+ ($size)}"
    rm -rf -- "$BUILD"
else
    echo "==> $BUILD no existe; nada que borrar"
fi

case "$MODE" in
    release)
        exec "$ROOT/scripts/build-release.sh"
        ;;
    debug)
        export CONFIG=Debug
        exec "$ROOT/scripts/build.sh"
        ;;
    clean)
        echo "listo: build/ limpio"
        ;;
esac
