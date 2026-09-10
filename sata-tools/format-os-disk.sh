#!/bin/sh
# Create the UniFi OS GPT on /dev/sda. WIPES THE DISK.
# Sizes match stock UDM Pro eMMC layout. Do NOT expand to the full HDD.
set -eu
DEV="${1:-/dev/sda}"

if [ "$(id -u)" -ne 0 ]; then
    echo "run as root" >&2
    exit 1
fi

echo "This erases $DEV. Ctrl-C to abort."
sleep 3

sgdisk -Z "$DEV" || true
# sectors at 512 bytes; layout from stock whole.img
sgdisk -n 1:2048:133119    -c 1:boot       -t 1:8300 "$DEV"
sgdisk -n 2:133120:198655  -c 2:recovery   -t 2:8300 "$DEV"
sgdisk -n 3:198656:4392959 -c 3:root       -t 3:8300 "$DEV"
sgdisk -n 4:4392960:6490111 -c 4:log       -t 4:8300 "$DEV"
sgdisk -n 5:6490112:10684415 -c 5:persistent -t 5:8300 "$DEV"
sgdisk -n 6:10684416:30533631 -c 6:overlay -t 6:8300 "$DEV"
partprobe "$DEV" 2>/dev/null || true
sleep 1

mkfs.ext4 -F -L boot       "${DEV}1"
# recovery stays unformatted (raw image slot)
mkfs.ext4 -F -L root       "${DEV}3"
mkfs.ext4 -F -L log        "${DEV}4"
mkfs.ext4 -F -L persistent "${DEV}5"
mkfs.ext4 -F -L overlay    "${DEV}6"

mkdir -p /mnt/udm-sda1
mount "${DEV}1" /mnt/udm-sda1
touch /mnt/udm-sda1/uImage
umount /mnt/udm-sda1

echo "GPT ready on $DEV. Next: copy uImage + rootfs (udm-sata-apply-bin)."
sgdisk -p "$DEV"
