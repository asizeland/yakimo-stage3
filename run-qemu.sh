#!/bin/sh
# Boot the development image with its packaged kernel and a serial console.
set -eu

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    exec nix develop -c "$0" "$@"
fi

SNAPSHOT=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --snapshot) SNAPSHOT=1; shift ;;
        *) break ;;
    esac
done
OUT=$(readlink -f "${1:-image/out}")
IMAGE=$OUT/yakimo-dev.raw
KERNEL=$OUT/vmlinuz-yakimo
[ -f "$IMAGE" ] || { echo "missing image: $IMAGE" >&2; exit 1; }
[ -f "$KERNEL" ] || { echo "missing kernel: $KERNEL" >&2; exit 1; }

ACCEL=tcg
CPU=max
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL=kvm
    CPU=host
fi
set -- qemu-system-x86_64 \
    -machine "q35,accel=$ACCEL" -cpu "$CPU" \
    -m "${QEMU_MEMORY:-4G}" -smp "${QEMU_CPUS:-2}" \
    -drive "file=$IMAGE,if=virtio,format=raw" \
    -kernel "$KERNEL" \
    -append 'root=/dev/vda rootfstype=ext4 rw console=ttyS0' \
    -nographic -no-reboot
if [ "$SNAPSHOT" -eq 1 ]; then
    set -- "$@" -snapshot
fi
exec "$@"
