# UDM Pro SATA — reference

Board: `alpine_v2_ubnt udm pro v6.0`, BOM rev 10, sysid `ea15`, `fit_index=2`.
Protect-bay disk = `/dev/sda`. Web UI on **LAN 1–8**, `https://192.168.1.1` (not WAN).

## GPT (do not grow)

| Part | Size | Label | Role |
|---|---|---|---|
| sda1 | 64 MiB | boot | `/uImage` FIT |
| sda2 | 32 MiB | recovery | unused by SCSI bootcmd |
| sda3 | 2 GiB | root | `/rootfs` squashfs file |
| sda4 | 1 GiB | log | `/var/log` |
| sda5 | 2 GiB | persistent | `/persistent` (tools survive overlay wipe) |
| sda6 | 9.5 GiB | overlay | overlayfs upper |
| sda7 | rest of disk | volume1 | optional `/volume1` (any HDD size after the ~15 GiB OS GPT); **usd stays masked**. `udm-sata-volume setup` |

## SPI U-Boot env (mtd1 + mtd2)

Redundant env: CRC32 LE over payload only, flags byte at offset 4, `ENV_SIZE=0x4000`.
Use `udm-sata-env` (`show` / `check` / `restore`). `flashcp` has no `-q`.

```
bootcmd=scsi init; ext4load scsi 0:1 ${loadaddr} /uImage; bootm ${loadaddr}#udmpro@${fit_index}
bootargs=pci=pcie_bus_perf console=ttyS0,115200 panic=3 reboot=cold systemd.mask=usd.service systemd.mask=usdbd.service
bootdelay=5
loadaddr=0x08000000
fit_index=2
```

One-shot U-Boot (no `saveenv` unless env is already SCSI):

```
scsi init
ext4load scsi 0:1 0x08000000 /uImage
bootm 0x08000000#udmpro@2
```

## Apply-bin offsets

`udm-sata-apply-bin` calls `ubnt_bin.inspect()` on **this** file. Do not patch hardcoded `FIT_OFF` / `SQ_OFF`. Check on the computer with `sata-tools/inspect-bin.py` before upload.

Historical 5.1.26 only (do not reuse): FIT `1499296`/`14574646`, squashfs `16074006`/`925339113`.

Squashfs must be padded to 4 KiB or loop-mount returns `EINVAL`.

After every apply (keep-overlay included): `/usr/local/sbin` is gone. Re-run `sh /persistent/udm-sata/bin/install.sh /persistent/udm-sata/bin`. The guard unit must `ExecStart` `/persistent/udm-sata/bin/udm-sata-guard` and run `After=local-fs.target` so persistent is mounted.

## Unbrick squashfs (rdinit)

`bootargs` += `rdinit=/bin/sh`, **do not saveenv**. Then:

```
mkdir -p /proc /sys /dev /boot
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
modprobe loop; modprobe zstd_decompress; modprobe squashfs
mount -t ext4 /dev/sda3 /boot
# pad /boot/rootfs to next 4096, sync, reboot
```
