# UniFi Dream Machine Pro: OS on SATA

The internal eMMC behind USB (ASM1142 + **GL3224**) can die: U-Boot runs `usb start` then `ext4load usb 0`, and Linux sees `/dev/boot` with **0 bytes**. The unit will not boot. SPI (U-Boot) is usually still intact.

This repo moves **UniFi OS onto the SATA drive in the Protect bay** and makes U-Boot boot from SCSI permanently. After that, firmware updates no longer need the dead eMMC — and they must **not** use Ubiquiti `fwupdate`, which still targets USB storage.

**You do not need a donor dump.** No `recovery.img`, no `whole.img`, no community eMMC images. Download the latest official UniFi OS firmware for UDM Pro from [ui.com/download/software/udm-pro](https://ui.com/download/software/udm-pro) (`UDMPRO-*.bin`, platform `al324`). That one file is the RAM-boot FIT, the kernel, and the squashfs.

This procedure is written so an **AI agent with serial-console access** can run it (U-Boot timing, TFTP, `rdinit`, `saveenv`). Hand-typing works, but the 2-second Esc window and the USB/`usb start` traps are easy to miss. Point the agent at this README plus `AGENTS.md`.

After the first conversion, a later firmware apply does **not** need serial. Give the agent the `.bin` and the skill at `.agents/skills/udm-pro-sata/` (SSH-only update: inspect, `udm-sata-apply-bin`, reinstall guard).

Tested: **UDM Pro** (not SE / Pro Max / base UDM), BOM rev 10, `fit_index=2`, UniFi OS 3.1.16 → 5.1.33, WDC WD10EFRX 1 TB HDD. Scripts and the serial flow were developed on **macOS** with a [Waveshare Industrial USB to TTL (C) 6-pin cable (FT232RNL)](https://www.amazon.de/dp/B0CX55K4RG) (`/dev/tty.usbserial-*`, 115200).

## Warning

- This **voids the warranty**.
- The Protect bay disk is wiped.
- A wrong `bootcmd` or `usb start` in U-Boot can leave the unit unbootable.
- Protect must **not** be handed the whole disk via `usd` (`usd` destroys the OS GPT). Leftover space as `sda7` → `/volume1` with `usd` still masked is how extra apps use the rest of the disk (`udm-sata-volume setup`).
- This is not an official Ubiquiti method. Firmware `.bin` files belong to Ubiquiti; this repo only contains scripts.

Related hardware approach (desolder GL3224, USB stick on the internal bus):  
[Community thread](https://community.ui.com/questions/1797bd03-a422-4eb6-9594-6c69ed2525a3) (replies `replyId=3471a337-…` and photos `51c69809-…`).

---

## Who this is for

- UDM Pro no longer boots (USB eMMC dead or 0 bytes).
- Serial console works (115200 8N1).
- A **disposable** SATA HDD/SSD fits the Protect bay (2.5″/3.5″ depending on the cage).
- The latest **`UDMPRO-*.bin`** from [ui.com/download/software/udm-pro](https://ui.com/download/software/udm-pro) (platform `al324`, not SE). No extra dumps.

The **first** conversion needs serial (best run by an agent that can drive that console). Once the SCSI `bootcmd` is stored in SPI, leave the console disconnected: later OS updates are SSH-only via the skill / `udm-sata-apply-bin`. Never the Web UI or `fwupdate`. Turn **off every automatic update under Control Plane** or the box will apply an official update and brick itself again.

---

## Do not

| Action | Why |
|---|---|
| Web UI “Update” / `fwupdate` / `ubnt-systool fwupdate` | Writes the dead eMMC (`/dev/boot` or `/dev/sdb2`). |
| Control Plane auto-updates | Same path as a manual UI update. The unit will brick itself on the next scheduled firmware. |
| Factory reset | Restores the USB `bootcmd`. |
| **`usb start`** in U-Boot | XHCI Event-33 crash on affected boards. |
| Expand OS partitions to fill the disk | `usd` would treat the disk as its volume and wipe GPT. Leftover **after** sda6 is `udm-sata-volume`. |
| Unmask `usd` / `usdbd` | UI storage daemon repartitions the HDD. |
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

GPT on the HDD (**do not grow sda1–6**):

| Part | Size | Label | Contents |
|---|---|---|---|
| sda1 | 64 MiB | boot | `uImage` file (FIT) |
| sda2 | 32 MiB | recovery | raw / optional |
| sda3 | 2 GiB | root | `rootfs` file (squashfs, **4K padding**) |
| sda4 | 1 GiB | log | `/var/log` |
| sda5 | 2 GiB | persistent | `/persistent` (scripts survive overlay wipe) |
| sda6 | 9.5 GiB | overlay | overlayfs |
| sda7 | rest of disk | volume1 | optional `/volume1` (`udm-sata-volume`; usd stays masked) |

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
  Developed on a Mac with this adapter: [Waveshare Industrial USB to TTL (C), FT232RNL](https://www.amazon.de/dp/B0CX55K4RG) (`screen /dev/tty.usbserial-* 115200`). Any 3.3 V TTL UART at 115200 8N1 should work.
- Ethernet: computer **directly on WAN (port 9)** — not LAN 1–8. Static IPv4 on the computer, no DHCP, no gateway:

  | | Address |
  |---|---|
  | Computer (TFTP/HTTP server) | `192.168.1.100/24` |
  | Netmask | `255.255.255.0` |
  | UDM U-Boot (`ipaddr`) | `192.168.1.50` |
  | UDM `serverip` | `192.168.1.100` |

  On macOS the USB-C NIC was `en14` (“USB 10/100/1000 LAN”):

  ```sh
  networksetup -listallhardwareports   # find the USB Ethernet device
  sudo ifconfig en14 inet 192.168.1.100 netmask 255.255.255.0
  # or: networksetup -setmanual "USB 10/100/1000 LAN" 192.168.1.100 255.255.255.0
  ifconfig en14   # inet 192.168.1.100, status: active
  ```

  U-Boot uses `al_eth1` for WAN. If `ping 192.168.1.100` fails, try `setenv ethact al_eth3`.
- LAN UI later on ports **1–8**, `https://192.168.1.1` — not WAN.
- Latest `UDMPRO-x.y.z.bin` from [ui.com/download/software/udm-pro](https://ui.com/download/software/udm-pro) (header `UBNTUDMPRO.al324`). Same file for TFTP RAM-boot and for writing `sda1`/`sda3`. Do not hunt for `recovery.img` or other dumps.
- TFTP: use `sata-tools/tftp-server.py` (see Step 2). HTTP `:8000` is only after Linux is already in RAM.

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

---

## Step 2 — TFTP the OS FIT into RAM

Extract the FIT from the same official `.bin` you downloaded (kernel + board DTs + initramfs with `parted`, `mkfs.ext4`, `wget`). Nothing else.

```sh
mkdir -p /tmp/udm-tftp
python3 sata-tools/inspect-bin.py /path/to/UDMPRO-x.y.z.bin --extract-fit /tmp/udm-tftp/uImage
# expect ~14 MiB, udmpro@2: yes

# U-Boot talks to UDP 69. macOS needs sudo for that bind.
sudo python3 sata-tools/tftp-server.py /tmp/udm-tftp 192.168.1.100 69

# same files, unprivileged extra listener (leave it running; does not replace :69)
python3 sata-tools/tftp-server.py /tmp/udm-tftp 192.168.1.100 6969
```

Both listeners share `/tmp/udm-tftp`. The first successful `tftpboot` used **:69**. :6969 is only a fallback if you later set `tftpdstp` on a build that honors it. This Alpine U-Boot usually ignores `tftpdstp` and still hits 69 — so without the `sudo` process, U-Boot prints `TFTP server died`.

U-Boot, WAN (port 9). Persist a long `bootdelay` **now** (`saveenv`) if the SPI env is still stock USB — the ramdisk `reboot` comes back with `bootdelay=2` and will `usb start` unless you catch Esc Esc. Try `al_eth1` first; if `ping` fails, `al_eth3`:

```
setenv bootdelay 30
saveenv
setenv ethact al_eth1
setenv ipaddr 192.168.1.50
setenv serverip 192.168.1.100
setenv netmask 255.255.255.0
ping 192.168.1.100
tftpboot 0x08000000 uImage
```

Expect `Bytes transferred` ≈ the FIT size from `inspect-bin.py` (~14 MiB, not 32 MiB). Then boot from RAM only — **do not** `saveenv` yet:

```
setenv bootargs pci=pcie_bus_perf console=ttyS0,115200 panic=3 reboot=cold rdinit=/bin/sh
bootm 0x08000000#udmpro@2
```

Replace `@2` with your `fit_index`. Without `console=ttyS0,115200` the kernel is silent. `rdinit=/bin/sh` stops the ramdisk from continuing into Debian and touching the disk before it is formatted. The BusyBox prompt is that initramfs, not a separate open-source recovery OS.

In the BusyBox shell:

```
mkdir -p /proc /sys /dev /tmp
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
```

`/tmp` does **not** exist until you create it (`wget -O /tmp/...` otherwise fails). This ramdisk has `parted`, `mkfs.ext4`, `wget` — **not** `sgdisk` or Python. `format-os-disk.sh` falls back to `parted`.

Initramfs NIC names vary (`eth0`–`eth3` or udev names). Bring up the interface with carrier to the computer:

```
ip addr add 192.168.1.50/24 dev eth1
ip link set eth1 up
```

HDD: `/dev/sda`.

---

## Step 3 — Create GPT and write firmware

The HDD is fully erased.

Build the GPT with `format-os-disk.sh` and write FIT + squashfs from the official `.bin`. TFTP in Step 2 is only the ~14 MiB FIT from that file — not a donor disk image.

Serve scripts + `.bin` over HTTP from the computer:

```sh
# on the computer, in the folder with the .bin and sata-tools:
python3 -m http.server 8000 --bind 192.168.1.100
```

On the UDM (recovery shell). Extract FIT + padded squashfs **on the computer** first (`inspect-bin.py`), serve `uImage` / `rootfs` / `sata-tools` on `:8000`:

```sh
mkdir -p /tmp
wget -O /tmp/format-os-disk.sh http://192.168.1.100:8000/sata-tools/format-os-disk.sh
sh /tmp/format-os-disk.sh /dev/sda
```

Then copy the extracted files onto the new ext4 partitions (recovery has no Python, so do **not** wait for a later `udm-sata-apply-bin` for the first write):

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

On the UDM:

```sh
mkdir -p /mnt/b /mnt/r
mount /dev/sda1 /mnt/b
mount /dev/sda3 /mnt/r
wget -O /mnt/b/uImage http://192.168.1.100:8000/uImage
wget -O /mnt/r/rootfs http://192.168.1.100:8000/rootfs
sync
umount /mnt/b /mnt/r
```

Recovery BusyBox `reboot` often does **nothing**. Use `reboot -f`, or `echo 1 > /proc/sys/kernel/sysrq; echo b > /proc/sysrq-trigger`. Then Esc Esc for U-Boot (Step 4).

Without 4K padding: `mount: ... squashfs ... Invalid argument` and a reboot loop (`panic=3`).

---

## Step 4 — Test SCSI load, then `saveenv` (still in U-Boot)

A fresh overlay has **no serial root password**. You cannot `saveenv` from Debian. After `reboot` the stock env still has `bootdelay=2` and USB `bootcmd` — miss Esc Esc and `usb start` crashes.

So: prove `ext4load` works, **then save SCSI env immediately**, then boot Linux.

```
scsi init
ext4load scsi 0:1 0x08000000 /uImage
```

If that prints a ~14 MiB read:

```
setenv bootcmd 'scsi init; ext4load scsi 0:1 ${loadaddr} /uImage; bootm ${loadaddr}#udmpro@${fit_index}'
setenv bootargs pci=pcie_bus_perf console=ttyS0,115200 panic=3 reboot=cold systemd.mask=usd.service systemd.mask=usdbd.service
setenv bootdelay 5
saveenv
boot
```

`loadaddr` is usually `0x08000000`. Do not `bootm` the full OS first and only then try to persist env.

---

## Step 5 — Install the guard

Serial `root` has no password until the setup wizard. Use **SSH after the wizard** (LAN ports 1–8). Copy the tools onto the box first — `/persistent/udm-sata/bin` is empty on a new disk; `install.sh` cannot install from itself.

```sh
# computer
COPYFILE_DISABLE=1 tar -C sata-tools -czf /tmp/sata-tools.tgz .
scp /tmp/sata-tools.tgz root@192.168.1.1:/tmp/

# UDM
tar -C /tmp -xzf /tmp/sata-tools.tgz
# or: mkdir -p /tmp/sata-tools && tar -C /tmp/sata-tools -xzf /tmp/sata-tools.tgz
sh /tmp/sata-tools/install.sh /tmp/sata-tools
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

A new squashfs drops `/usr/local/sbin` even with `--keep-overlay`. After **every** apply reboot, before calling it done:

```sh
sh /persistent/udm-sata/bin/install.sh /persistent/udm-sata/bin
systemctl start udm-sata-guard.service
udm-sata-env check
```

After overlay wipe: setup wizard, enable SSH, then the same `install.sh`.

`/persistent` is ~2 GiB. A ~900 MiB `.bin` fits; a full `sda3` backup often does not.

---

## Optional: leftover disk as `/volume1`

`format-os-disk.sh` only creates sda1–6 (~15 GiB). The rest of the drive (512 GB, 1 TB, 8 TB, …) is for extra apps: **Protect, Talk, Access**, and the other UniFi OS applications that store data under `/srv`. Network (the controller) stays on `/data` and does not need this partition.

To use that leftover **without unmasking `usd`**:

```sh
sh /persistent/udm-sata/bin/install.sh /persistent/udm-sata/bin
udm-sata-volume setup
```

That adds **sda7** (`volume1`) from the first free sector after overlay to **the end of this disk**, formats ext4, mounts `/volume1`, and points `/srv` at `/volume1/.srv`. Protect recordings go to `/srv/unifi-protect/video` on that volume. Run `setup` again after swapping in a larger drive: it grows sda7 and `resize2fs`. The guard remounts it after overlay wipe. `usd` / `usdbd` stay masked.

Those apps **do run** with this layout. Storage Budgeting in the UI may still say **No Drives Found**: that screen talks to `usd`/`ustated`, not to the `/volume1` mount. Recordings still land on the leftover partition. Do **not** unmask `usd` to “fix” the empty drive list — it will wipe GPT.

---

## Scripts

Agent skill for a later firmware update (SSH, no serial): `.agents/skills/udm-pro-sata/`. First conversion: this README + `AGENTS.md`.

| File | Role |
|---|---|
| `inspect-bin.py` / `ubnt_bin.py` | Find FIT + squashfs in a `.bin` (computer) |
| `tftp-server.py` | TFTP RRQ helper: `:69` (sudo) + optional `:6969` |
| `format-os-disk.sh` | Stock GPT on `/dev/sda` (wipes the disk) |
| `udm-sata-apply-bin` | `.bin` → `sda1`/`sda3`, env, optional overlay wipe |
| `udm-sata-env` | Read SPI env / restore SCSI |
| `udm-sata-guard` | Mask usd, hide USB eMMC, restore tools, remount `/volume1` |
| `udm-sata-volume` | Leftover GPT `sda7` → `/volume1` + `/srv` (usd stays masked) |
| `install.sh` | Guard + env on a running box |

Env format: redundant U-Boot, CRC32 over payload only (not the flags byte), `ENV_SIZE=0x4000`. `flashcp` has no `-q`.

---

## Troubleshooting

**`TFTP server died` / `Retry count exceeded`**  
Nothing is bound on UDP 69. The :6969 process is not enough. Start `sudo python3 sata-tools/tftp-server.py /tmp/udm-tftp 192.168.1.100 69`, confirm `ping 192.168.1.100` on `al_eth1` (or `al_eth3`), then `tftpboot` again. Do not use YModem/`loady` for the FIT.

**`wget: can't open '/tmp/...'`**  
The ramdisk has no `/tmp` until `mkdir -p /tmp`.

**`format-os-disk.sh`: `sgdisk: not found`**  
Expected in this ramdisk. Current script uses `parted` in that case. Re-copy the script from this repo.

**`reboot` in recovery does nothing**  
Use `reboot -f` or sysrq `b`. Plain `reboot` stays in the ramdisk.

**Serial `Login incorrect` / no root password**  
Fresh overlay. Do not hunt for a Unix password. `saveenv` from U-Boot (Step 4). After the LAN wizard, use SSH and `install.sh`.

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

- Ubiquiti community: eMMC/GL3224 hardware and desolder writeups. Firmware comes from [ui.com/download/software/udm-pro](https://ui.com/download/software/udm-pro), not from dumps.
- Alpine/U-Boot `2015.07-alpine_db` on AL324.

Scripts: MIT (see `LICENSE`). UniFi OS and `.bin` firmware are Ubiquiti property.
