#!/bin/sh
# Build a development root disk from a complete PKG_ROOT.
set -eu

SOURCE=$(readlink -f "${1:-/tmp/pkg-e2e-ports/root}")
OUT=$(readlink -f "${2:-image/out}")
SIZE=${IMAGE_SIZE:-40G}
IMAGE=$OUT/yakimo-dev.raw
TEMP_IMAGE=$OUT/.yakimo-dev.raw.tmp

case "$SOURCE" in
    ""|/) echo "refusing an empty or host root source" >&2; exit 2 ;;
esac
case "$OUT" in
    "$SOURCE"|"$SOURCE"/*) echo "output directory must be outside the source root" >&2; exit 2 ;;
esac

[ -x "$SOURCE/sbin/init" ] || { echo "$SOURCE has no /sbin/init" >&2; exit 1; }
[ -x "$SOURCE/usr/bin/pkg" ] || { echo "$SOURCE has no /usr/bin/pkg" >&2; exit 1; }
[ -d "$SOURCE/usr/lib/pkg/.store" ] || { echo "$SOURCE has no package store" >&2; exit 1; }
[ -d "$SOURCE/var/lib/pkg/recipes" ] || { echo "$SOURCE has no installed recipes" >&2; exit 1; }
set -- "$SOURCE"/boot/vmlinuz-*
[ "$#" -eq 1 ] && [ -f "$1" ] || { echo "expected exactly one packaged kernel" >&2; exit 1; }
KERNEL_SOURCE=$1

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

mkdir -p "$OUT"
OUT=$(readlink -f "$OUT")
MOUNT_DIR=$(mktemp -d /tmp/yakimo-image-mount.XXXXXX)
MOUNTED=0
cleanup() {
    status=$?
    if [ "$MOUNTED" -eq 1 ]; then
        as_root umount "$MOUNT_DIR" || true
    fi
    rm -rf "$MOUNT_DIR"
    if [ "$status" -ne 0 ]; then
        rm -f "$TEMP_IMAGE"
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

as_root true
rm -f "$TEMP_IMAGE"
truncate -s "$SIZE" "$TEMP_IMAGE"
mkfs.ext4 -F -L yakimo-root "$TEMP_IMAGE"
as_root mount -o loop "$TEMP_IMAGE" "$MOUNT_DIR"
MOUNTED=1

as_root tar --numeric-owner --owner=0 --group=0 \
    --exclude='./var/lib/pkg/build/*' \
    --exclude='./var/lib/pkg/cache/*' \
    --exclude='./var/cache/pkg/sources/*' \
    --exclude='./var/cache/pkg/index/*' \
    --exclude='./var/log/*' \
    --exclude='./run/*' --exclude='./tmp/*' --exclude='./var/tmp/*' \
    -C "$SOURCE" -cpf - . \
    | as_root tar --numeric-owner -C "$MOUNT_DIR" -xpf -
as_root mkdir -p "$MOUNT_DIR/var/lib/pkg/build" "$MOUNT_DIR/var/lib/pkg/cache" \
    "$MOUNT_DIR/var/cache/pkg/sources" "$MOUNT_DIR/var/cache/pkg/index"
as_root chmod 1777 "$MOUNT_DIR/tmp" "$MOUNT_DIR/var/tmp"

printf 'yakimo-dev\n' | as_root tee "$MOUNT_DIR/etc/hostname" >/dev/null
as_root tee "$MOUNT_DIR/etc/hosts" >/dev/null <<'EOF'
127.0.0.1 localhost yakimo-dev
::1 localhost yakimo-dev
EOF
as_root tee "$MOUNT_DIR/etc/fstab" >/dev/null <<'EOF'
/dev/vda / ext4 rw,relatime 0 1
EOF
as_root tee "$MOUNT_DIR/etc/inittab" >/dev/null <<'EOF'
id:3:initdefault:
si::sysinit:/sbin/openrc sysinit
bo::bootwait:/sbin/openrc boot
rc:3:wait:/sbin/openrc default
c1:3:respawn:/usr/bin/bash -c 'exec </dev/ttyS0 >/dev/ttyS0 2>&1; echo YAKIMO_QEMU_READY; exec /usr/bin/bash --login'
EOF

add_service() {
    runlevel=$1
    service=$2
    [ -x "$MOUNT_DIR/etc/init.d/$service" ] || {
        echo "missing OpenRC service: $service" >&2
        exit 1
    }
    as_root mkdir -p "$MOUNT_DIR/etc/runlevels/$runlevel"
    as_root ln -sfn "../../init.d/$service" \
        "$MOUNT_DIR/etc/runlevels/$runlevel/$service"
}
for service in devfs sysfs procfs; do
    add_service sysinit "$service"
done
add_service boot hostname
add_service boot localmount

sync
as_root umount "$MOUNT_DIR"
MOUNTED=0
mv -f "$TEMP_IMAGE" "$IMAGE"
cp "$KERNEL_SOURCE" "$OUT/vmlinuz-yakimo"
cp "$SOURCE"/boot/config-* "$OUT/kernel-config-yakimo"
(
    cd "$OUT"
    sha256sum yakimo-dev.raw vmlinuz-yakimo kernel-config-yakimo > SHA256SUMS
)
printf 'image: %s\nkernel: %s\n' "$IMAGE" "$OUT/vmlinuz-yakimo"
