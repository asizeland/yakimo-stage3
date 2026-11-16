#!/bin/sh
# Export a complete development root as a compressed archive.
set -eu

SOURCE=$(readlink -f "${1:-/tmp/pkg-e2e-ports/root}")
OUT=${2:-image/out}
case "$SOURCE" in
    ""|/) echo "refusing an empty or host root source" >&2; exit 2 ;;
esac
[ -d "$SOURCE/usr/lib/pkg/.store" ] || { echo "$SOURCE has no package store" >&2; exit 1; }
[ -d "$SOURCE/var/lib/pkg/recipes" ] || { echo "$SOURCE has no installed recipes" >&2; exit 1; }
mkdir -p "$OUT"
OUT=$(readlink -f "$OUT")
ARCHIVE=$OUT/yakimo-dev-root.tar.zst
TEMP=$OUT/.yakimo-dev-root.tar.zst.tmp
trap 'rm -f "$TEMP"' EXIT INT TERM

tar --numeric-owner --owner=0 --group=0 -C "$SOURCE" -cf - . \
    | zstd -T0 -10 --long=25 -o "$TEMP"
mv -f "$TEMP" "$ARCHIVE"
(
    cd "$OUT"
    sha256sum yakimo-dev-root.tar.zst > SHA256SUMS.root
)
printf 'root archive: %s\n' "$ARCHIVE"
