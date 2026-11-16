#!/bin/sh
# Build a fresh stage 3 in the disposable Debian package-build container.
set -eu

WS=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(readlink -f "${1:-$WS/image/out}")
CACHE_ROOT=$(readlink -f "${2:-/tmp/pkg-e2e-ports/root}")
[ -x "$WS/release/v0.1.0/pkg" ] || { echo "missing released static pkg binary" >&2; exit 1; }
[ -d "$CACHE_ROOT/var/lib/pkg/cache" ] || { echo "missing artifact cache" >&2; exit 1; }
[ -d "$CACHE_ROOT/var/cache/pkg/sources" ] || { echo "missing source cache" >&2; exit 1; }
mkdir -p "$OUT"

exec docker run --rm --privileged \
    -e "YAKIMO_JOBS=${YAKIMO_JOBS:-$(nproc)}" \
    -v "$WS:/src:ro" \
    -v "$OUT:/out" \
    -v "$CACHE_ROOT/var/lib/pkg/cache:/cache/artifacts" \
    -v "$CACHE_ROOT/var/cache/pkg/sources:/cache/sources" \
    yakimo-test /src/image/stage3-inner.sh
