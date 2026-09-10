# UniFi Dream Machine Pro: OS on SATA

The internal eMMC behind USB (ASM1142 + **GL3224**) can die: U-Boot runs `usb start` then `ext4load usb 0`, and Linux sees `/dev/boot` with **0 bytes**. The unit will not boot. SPI (U-Boot) is usually still intact.

This repo moves **UniFi OS onto the SATA drive in the Protect bay** and makes U-Boot boot from SCSI permanently. After that, firmware updates no longer need the dead eMMC — and they must **not** use Ubiquiti `fwupdate`, which still targets USB storage.

Tested: **UDM Pro** (not SE / Pro Max / base UDM), BOM rev 10, `fit_index=2`, UniFi OS 3.1.16 → 5.1.26, WDC WD10EFRX 1 TB HDD.

## Warning

- This **voids the warranty**.
- The Protect bay disk is wiped.
- A wrong `bootcmd` or `usb start` in U-Boot can leave the unit unbootable.
- Protect must **not** run on the same disk (`usd` destroys the OS GPT).
- This is not an official Ubiquiti method. Firmware `.bin` files belong to Ubiquiti; this repo only contains scripts.

Related hardware approach (desolder GL3224, USB stick on the internal bus):  
[Community thread](https://community.ui.com/questions/1797bd03-a422-4eb6-9594-6c69ed2525a3) (replies `replyId=3471a337-…` and photos `51c69809-…`).

---

## Who this is for

- UDM Pro no longer boots (USB eMMC dead or 0 bytes).
- Serial console works (115200 8N1).
- A **disposable** SATA HDD/SSD fits the Protect bay (2.5″/3.5″ depending on the cage).
- You have an official **`UDMPRO-*.bin`** (platform `al324`, not SE).

The **first** conversion needs serial. Once the SCSI `bootcmd` is stored in SPI, leave the console disconnected: later OS updates are SSH-only (`udm-sata-apply-bin`). Never the Web UI or `fwupdate`. Turn **off every automatic update under Control Plane** or the box will apply an official update and brick itself again.

---

## Do not

| Action | Why |
|---|---|
| Web UI “Update” / `fwupdate` / `ubnt-systool fwupdate` | Writes the dead eMMC (`/dev/boot` or `/dev/sdb2`). |
| Control Plane auto-updates | Same path as a manual UI update. The unit will brick itself on the next scheduled firmware. |
| Factory reset | Restores the USB `bootcmd`. |
| **`usb start`** in U-Boot | XHCI Event-33 crash on affected boards. |
| Expand GPT to the full 1 TB | `usd`/Protect would consume the rest of the disk. |
| Protect on the OS disk | UI storage daemon repartitions the HDD. |
| Remove the HDD | No disk means no OS. |
| `env default -a` | Wipes SCSI boot. |

---

## Architecture

Stock:

```
SPI 8 MiB (U-Boot + env) → usb start → eMMC (GL3224) → Debian/UniFi OS
```

This setup:

```
SPI 8 MiB → scsi init → HDD sda1 /uImage (FIT #udmpro@N) → sda3 /rootfs (squashfs)
```

GPT on the HDD (**do not grow it**):

| Part | Size | Label | Contents |
|---|---|---|---|
| sda1 | 64 MiB | boot | `uImage` file (FIT) |
| sda2 | 32 MiB | recovery | raw / optional |
| sda3 | 2 GiB | root | `rootfs` file (squashfs, **4K padding**) |
| sda4 | 1 GiB | log | `/var/log` |
| sda5 | 2 GiB | persistent | `/persistent` (scripts survive overlay wipe) |
| sda6 | 9.5 GiB | overlay | overlayfs |

`/dev/disk/by-partlabel/*` already points at `sda*`. Initramfs mounts by partlabel — the disk does **not** need to be named `/dev/boot`.

`fit_index` comes from the board (U-Boot line `model = udmpro, … fit_index = N`). Rev. 10 → **`2`** (`#udmpro@2`). Older BOM often `@1`. Wrong index → kernel will not start.

SPI env after conversion:

```
bootcmd=scsi init; ext4load scsi 0:1 ${loadaddr} /uImage; bootm ${loadaddr}#udmpro@${fit_index}
bootargs=pci=pcie_bus_perf console=ttyS0,115200 panic=3 reboot=cold systemd.mask=usd.service systemd.mask=usdbd.service
bootdelay=5
loadaddr=0x08000000
```

`systemd.mask=usd.service` in bootargs survives an empty overlay. Still run `install.sh` after every major update.

---

## Prerequisites

- USB serial adapter on the UDM Pro debug header, `115200`.  
  macOS: `screen /dev/tty.usbserial-* 115200`
- Ethernet: computer **directly on WAN (port 9)**, static e.g. `192.168.1.100/24`. U-Boot: `al_eth1`, `ipaddr=192.168.1.50`, `serverip=192.168.1.100`.
- LAN UI later on ports **1–8**, `https://192.168.1.1` — not WAN.
- Official `UDMPRO-x.y.z.bin` (header `UBNTUDMPRO.al324`).
- Optional for RAM boot: `recovery.img` (32 MiB FIT), e.g. a dump of the recovery partition from a matching UDM Pro, or community dumps. Without recovery you can TFTP the kernel FIT extracted from a `.bin` (`inspect-bin.py`).
- TFTP server on the computer (port 69) and/or `python3 -m http.server 8000`.

Check scripts on the computer first:

```sh
python3 sata-tools/inspect-bin.py /path/to/UDMPRO-x.y.z.bin
# must find a FIT with udmpro@2 and a large squashfs
```

---

## Step 1 — U-Boot, no USB

Cold boot, **Esc Esc** during `Autobooting in 5 seconds`.

```
setenv bootdelay 30
printenv fit_index
scsi init
scsi info
```

The HDD must show up as device 0. Do **not** `usb start`.

Network (WAN):

```
setenv ipaddr 192.168.1.50
setenv serverip 192.168.1.100
setenv ethact al_eth1
```

---

## Step 2 — Kernel to RAM only

TFTP a FIT (`recovery.img` or the uImage extracted via `inspect-bin.py`) to `0x08000000`.

```
tftpboot 0x08000000 recovery.img
setenv bootargs pci=pcie_bus_perf console=ttyS0,115200 panic=3 reboot=cold rdinit=/bin/sh
bootm 0x08000000#udmpro@2
```

Replace `@2` with your `fit_index`. Without `console=ttyS0,115200` the kernel is silent. `rdinit=/bin/sh` stops Debian from touching the overlay disk before it is formatted.

In the BusyBox shell:

```
mkdir -p /proc /sys /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
```

Initramfs NIC names vary (`eth0`–`eth3` or udev names). Bring up the interface with carrier to the computer:

```
ip addr add 192.168.1.50/24 dev eth1
ip link set eth1 up
```

HDD: `/dev/sda`.

---

## Step 3 — Create GPT and write firmware

The HDD is fully erased.

Serve scripts + `.bin` over HTTP from the computer:

```sh
# on the computer, in the folder with the .bin and sata-tools:
python3 -m http.server 8000 --bind 192.168.1.100
```

On the UDM (initramfs or later a running OS):

```sh
wget -O /tmp/format-os-disk.sh http://192.168.1.100:8000/sata-tools/format-os-disk.sh
sh /tmp/format-os-disk.sh /dev/sda
```

Firmware can be written from initramfs (mount `sda1`/`sda3`) or after a temporary SCSI boot. Practical path: put a minimal `uImage` on `sda1`, SCSI-boot, then run `udm-sata-apply-bin` on the running system.

Minimal shell path after `inspect-bin.py` prints offsets — Debian initramfs/BusyBox often has no Python:

1. `dd` the FIT out of the `.bin` (offsets from `inspect-bin.py`) onto `sda1` as `/uImage`.
2. Same for squashfs onto `sda3:/rootfs`, **pad to 4096 bytes**.
3. `sda4`–`sda6` empty ext4 is enough for first boot.

Example (offsets **differ per .bin**; always use `inspect-bin.py`):

```sh
# on the computer:
python3 sata-tools/inspect-bin.py UDMPRO.bin
# fit off=… size=…    rootfs off=… size=…

dd if=UDMPRO.bin bs=1 skip=$FIT_OFF count=$FIT_SIZE of=uImage
dd if=UDMPRO.bin bs=1 skip=$SQ_OFF count=$SQ_SIZE of=rootfs
# pad rootfs to a multiple of 4096
python3 - <<'PY'
from pathlib import Path
p = Path("rootfs")
n = p.stat().st_size
pad = (4096 - n % 4096) % 4096
if pad:
    p.write_bytes(p.read_bytes() + b"\x00" * pad)
print("padded", p.stat().st_size)
PY
```

HTTP the files onto the UDM, mount `sda1`/`sda3`, copy, `sync`.

Without 4K padding: `mount: ... squashfs ... Invalid argument` and a reboot loop (`panic=3`).

---

## Step 4 — Test SCSI boot, then save

U-Boot (**no** `saveenv` yet):

```
scsi init
ext4load scsi 0:1 0x08000000 /uImage
setenv bootargs pci=pcie_bus_perf console=ttyS0,115200 panic=3 reboot=cold systemd.mask=usd.service systemd.mask=usdbd.service
bootm 0x08000000#udmpro@2
```

When Debian/UniFi comes up:

```
setenv bootcmd 'scsi init; ext4load scsi 0:1 ${loadaddr} /uImage; bootm ${loadaddr}#udmpro@${fit_index}'
setenv bootargs pci=pcie_bus_perf console=ttyS0,115200 panic=3 reboot=cold systemd.mask=usd.service systemd.mask=usdbd.service
setenv bootdelay 5
saveenv
```

Save only after that boot worked. `loadaddr` is usually `0x08000000`.

---

## Step 5 — Install the guard

SSH or serial, as root. Copy scripts to `/tmp` or `/persistent`, then:

```sh
sh sata-tools/install.sh /path/to/sata-tools
udm-sata-env check    # scsi
```

This:

- writes SCSI env to **both** SPI copies (`mtd1`+`mtd2`)
- masks `usd.service` / `usdbd.service`
- installs the early-boot guard (hide USB eMMC, `/dev/boot` → `sda`)
- copies tools to `/persistent/udm-sata/bin/`

Web UI: LAN `https://192.168.1.1`. After an overlay wipe this is a fresh setup.

Immediately after the wizard: **Settings → Control Plane** and disable **all automatic updates** (UniFi OS and every application). If they stay on, the device will pull an official `.bin` and write the dead eMMC.

---

## Later firmware updates (SSH only, no serial)

After the initial conversion, the serial adapter can stay unplugged. SCSI `bootcmd` lives in SPI, so every reboot loads UniFi OS from the HDD without a console.

Apply later `UDMPRO-*.bin` files **over SSH** with `udm-sata-apply-bin`.

Do **not** use:

- the Web UI **Update** button
- `fwupdate`
- `ubnt-systool fwupdate`
- **Control Plane** automatic updates (UniFi OS or applications)

Those always write the dead USB eMMC (`/dev/boot` / `/dev/sdb2`), not SATA. The update will fail or brick the next boot. After every setup wizard, go to **Settings → Control Plane** and turn every auto-update **off**. Leave them on and the unit will destroy the SATA boot on its own.

```sh
# computer: check offsets
python3 sata-tools/inspect-bin.py UDMPRO-x.y.z.bin

scp UDMPRO-x.y.z.bin root@192.168.1.1:/persistent/udm-sata/incoming/
ssh root@192.168.1.1
udm-sata-env check
python3 /persistent/udm-sata/bin/udm-sata-apply-bin /persistent/udm-sata/incoming/UDMPRO-x.y.z.bin
```

The script finds FIT/squashfs itself, pads rootfs, restores SCSI env, wipes overlay (major jump), and reboots.

Same major, keep the account:

```sh
python3 /persistent/udm-sata/bin/udm-sata-apply-bin --keep-overlay /persistent/udm-sata/incoming/UDMPRO-x.y.z.bin
```

After overlay wipe: setup wizard, enable SSH, then:

```sh
sh /persistent/udm-sata/bin/install.sh /persistent/udm-sata/bin
```

`/persistent` is ~2 GiB. A ~900 MiB `.bin` fits; a full `sda3` backup often does not.

---

## Scripts

| File | Role |
|---|---|
| `inspect-bin.py` / `ubnt_bin.py` | Find FIT + squashfs in a `.bin` (computer) |
| `format-os-disk.sh` | Stock GPT on `/dev/sda` (wipes the disk) |
| `udm-sata-apply-bin` | `.bin` → `sda1`/`sda3`, env, optional overlay wipe |
| `udm-sata-env` | Read SPI env / restore SCSI |
| `udm-sata-guard` | Mask usd, hide USB eMMC, restore tools from `/persistent` |
| `install.sh` | Guard + env on a running box |

Env format: redundant U-Boot, CRC32 over payload only (not the flags byte), `ENV_SIZE=0x4000`. `flashcp` has no `-q`.

---

## Troubleshooting

**Reboot loop, serial `mount fail ... squashfs /mnt/.boot/rootfs`**  
Rootfs is not 4K-aligned. One-shot `rdinit=/bin/sh` in `bootargs` (**do not** `saveenv`), load `zstd_decompress` + `squashfs`, mount `sda3`, pad the file, reboot without `rdinit`.

**`fwupdate` → `failed writing part 'rootfs' to '/dev/sdb2'`**  
Expected. The USB boot carrier is the dead GL3224. Use `udm-sata-apply-bin` only.

**Wrong device tree / kernel hangs**  
`fit_index` / `#udmpro@N` must match the BOM. U-Boot prints it at start.

**Protect disk empty, OS gone**  
`usd` was not masked. Recreate GPT, rewrite firmware, reinstall guard + `systemd.mask` in SPI.

**SSH host key**  
Changes after overlay wipe. Do not trash `known_hosts`: use `UserKnownHostsFile=/dev/null` for this host.

---

## Credits

- Ubiquiti community: eMMC/GL3224 hardware, recovery dumps, desolder writeups.
- Alpine/U-Boot `2015.07-alpine_db` on AL324.

Scripts: MIT (see `LICENSE`). UniFi OS and `.bin` firmware are Ubiquiti property.
