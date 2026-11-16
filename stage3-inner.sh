#!/bin/sh
set -eu

OUT=/out
ROOT=$OUT/.stage3-root.tmp
FINAL=$OUT/stage3-root
ARCHIVE=$OUT/yakimo-stage3-0.1.0-x86_64.tar.xz
TEMP_ARCHIVE=$OUT/.yakimo-stage3-0.1.0-x86_64.tar.xz.tmp
PKG=/src/release/v0.1.0/pkg

rm -rf "$ROOT"
rm -f "$TEMP_ARCHIVE"
mkdir -p "$ROOT/etc/pkg" "$ROOT/var/lib/pkg" "$ROOT/var/cache/pkg"
ln -s /cache/artifacts "$ROOT/var/lib/pkg/cache"
ln -s /cache/sources "$ROOT/var/cache/pkg/sources"
printf '[build]\njobs = %s\nmax_pkg_jobs = 4\n' "${YAKIMO_JOBS:-4}" \
    > "$ROOT/etc/pkg/config.toml"
export PKG_ROOT=$ROOT
export YAKIMO_IMAGE_ROOT=$ROOT
mkdir -p /tmp/yakimo-bwrap
ln -sf /src/image/debian-bwrap.py /tmp/yakimo-bwrap/bwrap
export PATH=/tmp/yakimo-bwrap:$PATH

set -- $(cat /src/image/stage3-packages.txt)
"$PKG" install -y --recipe-tree /src/ports "$@"
/usr/bin/bwrap --die-with-parent --unshare-all --bind "$ROOT" / \
    --proc /proc --dev /dev --tmpfs /run --tmpfs /tmp \
    -- /sbin/ldconfig
"$PKG" db check

for manifest in /src/ports/*/*/pkg-meta.toml; do
    package_dir=${manifest%/pkg-meta.toml}
    name=${package_dir##*/}
    mkdir -p "$ROOT/var/lib/pkg/recipes/$name"
    cp "$manifest" "$ROOT/var/lib/pkg/recipes/$name/pkg-meta.toml"
done

printf 'yakimo\n' > "$ROOT/etc/hostname"
cat > "$ROOT/etc/hosts" <<'EOF'
127.0.0.1 localhost yakimo
::1 localhost yakimo
EOF
cat > "$ROOT/etc/fstab" <<'EOF'
# Set the real root UUID before booting, for example:
# UUID=CHANGE_ME / ext4 rw,relatime 0 1
EOF
cat > "$ROOT/etc/inittab" <<'EOF'
id:3:initdefault:
si::sysinit:/sbin/openrc sysinit
bo::bootwait:/sbin/openrc boot
rc:3:wait:/sbin/openrc default
c1:3:respawn:/usr/bin/bash -c 'exec </dev/tty1 >/dev/tty1 2>&1; exec /usr/bin/bash --login'
cS:3:respawn:/usr/bin/bash -c 'exec </dev/ttyS0 >/dev/ttyS0 2>&1; echo YAKIMO_QEMU_READY; exec /usr/bin/bash --login'
EOF

add_service() {
    runlevel=$1
    service=$2
    [ -x "$ROOT/etc/init.d/$service" ] || {
        echo "missing OpenRC service: $service" >&2
        exit 1
    }
    mkdir -p "$ROOT/etc/runlevels/$runlevel"
    ln -sfn "../../init.d/$service" "$ROOT/etc/runlevels/$runlevel/$service"
}
for service in devfs sysfs procfs udev; do
    add_service sysinit "$service"
done
for service in hostname localmount; do
    add_service boot "$service"
done
for service in dbus NetworkManager; do
    add_service default "$service"
done

rm -f "$ROOT/var/lib/pkg/cache" "$ROOT/var/cache/pkg/sources"
mkdir -p "$ROOT/var/lib/pkg/cache" "$ROOT/var/cache/pkg/sources" \
    "$ROOT/var/lib/pkg/build" "$ROOT/var/cache/pkg/index"
find "$ROOT/var/lib/pkg/build" -mindepth 1 -delete
for directory in run tmp var/tmp var/log; do
    find "$ROOT/$directory" -mindepth 1 -delete
done
chmod 1777 "$ROOT/tmp" "$ROOT/var/tmp"

mkdir -p "$ROOT/usr/lib/yakimo"
cp /src/image/stage3-packages.txt "$ROOT/usr/lib/yakimo/stage3-packages.txt"
MAIN_REV=$(git -c safe.directory='*' -C /src rev-parse HEAD 2>/dev/null || echo unknown)
PORTS_REV=$(git -c safe.directory='*' -C /src/ports rev-parse HEAD 2>/dev/null || echo unknown)
{
    printf 'version = "0.1.0"\n'
    printf 'architecture = "x86_64"\n'
    printf 'yakimo_revision = "%s"\n' "$MAIN_REV"
    printf 'ports_revision = "%s"\n' "$PORTS_REV"
    printf 'package_selection = "/usr/lib/yakimo/stage3-packages.txt"\n'
} > "$ROOT/usr/lib/yakimo/stage3-build-info"

"$PKG" db check
tar --numeric-owner -C "$ROOT" -cJf "$TEMP_ARCHIVE" .
mv -f "$TEMP_ARCHIVE" "$ARCHIVE"
rm -rf "$FINAL"
mv "$ROOT" "$FINAL"
(
    cd "$OUT"
    sha256sum yakimo-stage3-0.1.0-x86_64.tar.xz \
        > yakimo-stage3-0.1.0-x86_64.tar.xz.sha256
)
printf 'stage 3 root: %s\nstage 3 archive: %s\n' "$FINAL" "$ARCHIVE"
