#!/bin/sh
# Create the UniFi OS GPT on /dev/sda. WIPES THE DISK.
# Sizes match stock UDM Pro eMMC layout for sda1–6. Do NOT grow those
# partitions. sda7 is the rest of the disk (volume1); mkfs is udm-sata-volume.
# The .bin FIT ramdisk has GNU parted + mkfs.ext4, not sgdisk.
set -eu
DEV="${1:-/dev/sda}"

if [ "$(id -u)" -ne 0 ]; then
    echo "run as root" >&2
    exit 1
fi

echo "This erases $DEV. Ctrl-C to abort."
sleep 3

# sectors at 512 bytes; layout from stock whole.img
# 1 boot 64MiB  2 recovery 32MiB  3 root 2GiB  4 log 1GiB  5 persistent 2GiB  6 overlay 9.5GiB  7 volume1 rest of disk
if command -v sgdisk >/dev/null 2>&1; then
    sgdisk -Z "$DEV" || true
    sgdisk -n 1:2048:133119     -c 1:boot       -t 1:8300 "$DEV"
    sgdisk -n 2:133120:198655   -c 2:recovery   -t 2:8300 "$DEV"
    sgdisk -n 3:198656:4392959  -c 3:root       -t 3:8300 "$DEV"
    sgdisk -n 4:4392960:6490111 -c 4:log        -t 4:8300 "$DEV"
    sgdisk -n 5:6490112:10684415 -c 5:persistent -t 5:8300 "$DEV"
    sgdisk -n 6:10684416:30533631 -c 6:overlay  -t 6:8300 "$DEV"
    sgdisk -n 7:30533632:0        -c 7:volume1  -t 7:8300 "$DEV"
else
    command -v parted >/dev/null 2>&1 || {
        echo "need sgdisk or parted" >&2
        exit 1
    }
    parted -s "$DEV" mklabel gpt
    parted -s "$DEV" unit s mkpart boot 2048 133119
    parted -s "$DEV" unit s mkpart recovery 133120 198655
    parted -s "$DEV" unit s mkpart root 198656 4392959
    parted -s "$DEV" unit s mkpart log 4392960 6490111
    parted -s "$DEV" unit s mkpart persistent 6490112 10684415
    parted -s "$DEV" unit s mkpart overlay 10684416 30533631
    parted -s "$DEV" unit s mkpart volume1 30533632 100%
    parted -s "$DEV" name 1 boot
    parted -s "$DEV" name 2 recovery
    parted -s "$DEV" name 3 root
    parted -s "$DEV" name 4 log
    parted -s "$DEV" name 5 persistent
    parted -s "$DEV" name 6 overlay
    parted -s "$DEV" name 7 volume1
fi

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

echo "GPT ready on $DEV. Next: copy uImage + rootfs."
if command -v sgdisk >/dev/null 2>&1; then
    sgdisk -p "$DEV"
else
    parted -s "$DEV" unit s print
fi
