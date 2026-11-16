#!/bin/sh
set -eu

ROOT=/out/stage3-extracted
[ -x "$ROOT/usr/bin/pkg" ] || { echo "extracted root has no static pkg" >&2; exit 1; }
[ ! -L "$ROOT/var/lib/pkg/cache" ] || { echo "artifact cache link survived" >&2; exit 1; }
[ ! -L "$ROOT/var/cache/pkg/sources" ] || { echo "source cache link survived" >&2; exit 1; }

bwrap --die-with-parent --unshare-all --bind "$ROOT" / \
    --proc /proc --dev /dev --tmpfs /run --tmpfs /tmp \
    --setenv PATH /usr/bin:/bin:/usr/sbin:/sbin --setenv HOME /root \
    -- /usr/bin/bash -ec '
        uname -a
        git --version
        ls --version | head -1
        /usr/bin/pkg --help >/dev/null
        /usr/bin/pkg db check
    '

export YAKIMO_IMAGE_ROOT=$ROOT
mkdir -p /tmp/yakimo-bwrap
ln -sf /src/image/debian-bwrap.py /tmp/yakimo-bwrap/bwrap
export PATH=/tmp/yakimo-bwrap:$PATH
rm -rf "$ROOT/var/lib/pkg/cache" "$ROOT/var/cache/pkg/sources"
ln -s /cache/artifacts "$ROOT/var/lib/pkg/cache"
ln -s /cache/sources "$ROOT/var/cache/pkg/sources"
export PKG_ROOT=$ROOT
"$ROOT/usr/bin/pkg" install -y --recipe-tree /src/ports linux wireless-regdb
"$ROOT/usr/bin/pkg" db check
[ -f "$ROOT/usr/lib/firmware/regulatory.db" ] || { echo "regulatory.db missing" >&2; exit 1; }
[ -f "$ROOT/usr/lib/firmware/regulatory.db.p7s" ] || { echo "regulatory.db signature missing" >&2; exit 1; }
grep -q '^CONFIG_CFG80211=m$' "$ROOT"/boot/config-*
grep -q '^CONFIG_MAC80211=m$' "$ROOT"/boot/config-*
rm -f "$ROOT/var/lib/pkg/cache" "$ROOT/var/cache/pkg/sources"
mkdir -p "$ROOT/var/lib/pkg/cache" "$ROOT/var/cache/pkg/sources"
find "$ROOT/var/lib/pkg/build" -mindepth 1 -delete
