# UniFi Dream Machine Pro: Betriebssystem auf SATA

Die interne eMMC hinter USB (ASM1142 + **GL3224**) kann sterben: U-Boot macht `usb start` und `ext4load usb 0`, Linux sieht `/dev/boot` mit **0 Byte**. Die Box bootet nicht mehr, SPI (U-Boot) ist aber intakt.

Dieses Repo beschreibt, das **UniFi OS auf die SATA-Platte im Protect-Schacht** zu legen und U-Boot dauerhaft per SCSI starten zu lassen. Danach gehen Firmware-Updates **ohne** die tote eMMC — und ohne Ubiquitis `fwupdate`, das weiterhin auf USB-Storage zielt.

Getestet: **UDM Pro** (nicht SE / Pro Max / UDM), BOM rev 10, `fit_index=2`, UniFi OS 3.1.16 → 5.1.26, HDD WDC WD10EFRX 1 TB.

## Warnung

- Das **voidet die Garantie**.
- Du löschst die Protect-Platte.
- Falscher `bootcmd` oder `usb start` in U-Boot kann die Box unbootbar machen.
- Protect darf **nicht** auf derselben Platte laufen (`usd` zerstört die OS-GPT).
- Keine offizielle Ubiquiti-Methode. Firmware-`.bin` gehören Ubiquiti; hier liegen nur Skripte.

Verwandter Hardware-Weg (GL3224 ablöten, USB-Stick intern):  
[Community-Thread](https://community.ui.com/questions/1797bd03-a422-4eb6-9594-6c69ed2525a3) (Antworten mit `replyId=3471a337-…` und Fotos `51c69809-…`).

---

## Für wen das ist

- UDM Pro startet nicht mehr (USB-eMMC tot oder 0 Byte).
- Serial-Konsole geht (115200 8N1).
- Eine **entbehrliche** SATA-HDD/SSD passt in den Protect-Schacht (2,5″/3,5″ je nach Käfig).
- Du hast ein offizielles **`UDMPRO-*.bin`** (gleiche Plattform `al324`, nicht SE).

Die **erste** Umstellung braucht Serial. Wenn SCSI-`bootcmd` einmal in SPI steht, gehen spätere OS-Updates per SSH.

---

## Was nicht tun

| Aktion | Warum |
|---|---|
| Web-UI „Update“ / `fwupdate` / `ubnt-systool fwupdate` | Schreibt die tote eMMC (`/dev/boot` oder `/dev/sdb2`). |
| Factory Reset | Stellt USB-`bootcmd` wieder her. |
| In U-Boot **`usb start`** | XHCI Event-33 Crash auf betroffenen Boards. |
| GPT auf volle 1 TB aufblasen | `usd`/Protect würde den Rest der Platte fressen. |
| Protect auf der OS-Platte | UI Storage Daemon repartitioniert die HDD. |
| HDD ziehen | Ohne Platte kein OS. |
| `env default -a` | Löscht den SCSI-Boot. |

---

## Architektur

Stock:

```
SPI 8 MiB (U-Boot + Env) → usb start → eMMC (GL3224) → Debian/UniFi OS
```

Dieses Setup:

```
SPI 8 MiB → scsi init → HDD sda1 /uImage (FIT #udmpro@N) → sda3 /rootfs (squashfs)
```

GPT auf der HDD (**nicht** vergrößern):

| Teil | Größe | Label | Inhalt |
|---|---|---|---|
| sda1 | 64 MiB | boot | Datei `uImage` (FIT) |
| sda2 | 32 MiB | recovery | roh / optional |
| sda3 | 2 GiB | root | Datei `rootfs` (Squashfs, **4K-padding**) |
| sda4 | 1 GiB | log | `/var/log` |
| sda5 | 2 GiB | persistent | `/persistent` (Skripte überleben Overlay-Wipe) |
| sda6 | 9,5 GiB | overlay | overlayfs |

`/dev/disk/by-partlabel/*` zeigt auf `sda*`. Initramfs mountet darüber — die Platte muss **nicht** `/dev/boot` heißen.

`fit_index` kommt aus dem Board (U-Boot-Zeile `model = udmpro, … fit_index = N`). Rev. 10 → **`2`** (`#udmpro@2`). Ältere BOM oft `@1`. Falsch → Kernel startet nicht.

SPI-Env nach der Umstellung:

```
bootcmd=scsi init; ext4load scsi 0:1 ${loadaddr} /uImage; bootm ${loadaddr}#udmpro@${fit_index}
bootargs=pci=pcie_bus_perf console=ttyS0,115200 panic=3 reboot=cold systemd.mask=usd.service systemd.mask=usdbd.service
bootdelay=5
loadaddr=0x08000000
```

`systemd.mask=usd.service` in den Bootargs überlebt ein leeres Overlay. Trotzdem nach jedem Major-Update `install.sh` laufen lassen.

---

## Voraussetzungen

- USB-Serial-Adapter an der UDM-Pro-Debug-Leiste, `115200`.
  macOS: `screen /dev/tty.usbserial-* 115200`
- Ethernet: Mac **direkt an WAN (Port 9)**, statisch z. B. `192.168.1.100/24`. U-Boot: `al_eth1`, `ipaddr=192.168.1.50`, `serverip=192.168.1.100`.
- LAN-UI später an Port **1–8**, `https://192.168.1.1` — nicht WAN.
- Offizielles `UDMPRO-x.y.z.bin` (Header `UBNTUDMPRO.al324`).
- Optional zum RAM-Boot: `recovery.img` (32 MiB FIT), z. B. Dump der Recovery-Partition einer gleichen UDM Pro, oder Community-Dumps. Ohne Recovery kommst du mit einem Kernel-FIT aus einem `.bin` ebenfalls nach RAM (`inspect-bin.py`, dann TFTP nur des FIT).
- TFTP-Server auf dem Mac (Port 69) und/oder `python3 -m http.server 8000`.

Skripte in `sata-tools/` zuerst auf dem Mac prüfen:

```sh
python3 sata-tools/inspect-bin.py /pfad/UDMPRO-x.y.z.bin
# muss FIT mit udmpro@2 und ein großes squashfs finden
```

---

## Schritt 1 — U-Boot, kein USB

Kaltstart, **Esc Esc** während `Autobooting in 5 seconds`.

```
setenv bootdelay 30
printenv fit_index
scsi init
scsi info
```

Die HDD muss als Device 0 erscheinen. **Nicht** `usb start`.

Netz (WAN):

```
setenv ipaddr 192.168.1.50
setenv serverip 192.168.1.100
setenv ethact al_eth1
```

---

## Schritt 2 — Kernel nur nach RAM

TFTP eines FIT (`recovery.img` oder das aus `inspect-bin.py` extrahierte uImage) nach `0x08000000`.

```
tftpboot 0x08000000 recovery.img
setenv bootargs pci=pcie_bus_perf console=ttyS0,115200 panic=3 reboot=cold rdinit=/bin/sh
bootm 0x08000000#udmpro@2
```

`@2` durch deinen `fit_index` ersetzen. Ohne `console=ttyS0,115200` bleibt der Kernel stumm. `rdinit=/bin/sh` verhindert, dass Debian die Overlay-Platte anfasst, bevor sie formatiert ist.

In der BusyBox-Shell:

```
mkdir -p /proc /sys /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
```

Netz in der Initramfs (Namen variieren: `eth0`–`eth3` oder udev-Namen). Interface mit Carrier zum Mac:

```
ip addr add 192.168.1.50/24 dev eth1
ip link set eth1 up
```

HDD: `/dev/sda`.

---

## Schritt 3 — GPT anlegen und Firmware schreiben

Die HDD wird vollständig gelöscht.

Skripte + `.bin` per HTTP vom Mac:

```sh
# auf dem Mac, im Ordner mit .bin und sata-tools:
python3 -m http.server 8000 --bind 192.168.1.100
```

Auf der UDM (Initramfs oder später laufendes OS):

```sh
wget -O /tmp/format-os-disk.sh http://192.168.1.100:8000/sata-tools/format-os-disk.sh
sh /tmp/format-os-disk.sh /dev/sda
```

Firmware auf die neuen Partitionen (geht aus der Initramfs, wenn `sda1`/`sda3` gemountet werden, oder nach einem temporären SCSI-Boot). Bequemer: erst minimales `uImage` nach `sda1`, SCSI-booten, dann `udm-sata-apply-bin` im laufenden System.

Minimal aus der Shell, nachdem `inspect-bin.py` Offsets gedruckt hat — oder das Apply-Skript nutzen, sobald Python3 da ist (Debian-Initramfs hat oft keins; Recovery-BusyBox ebenfalls). Praktischer Weg:

1. FIT mit `dd` aus dem `.bin` schneiden (Offsets von `inspect-bin.py`) und als `/uImage` nach `sda1` kopieren.
2. Squashfs ebenso nach `sda3:/rootfs`, **auf 4096 Byte auffüllen**.
3. `sda4`–`sda6` sind leer formatiert — reichen für den ersten Start.

Beispiel (Offsets sind **pro .bin anders**; nicht kopieren, sondern `inspect-bin.py` nehmen):

```sh
# auf dem Mac:
python3 sata-tools/inspect-bin.py UDMPRO.bin
# fit off=… size=…    rootfs off=… size=…

dd if=UDMPRO.bin bs=1 skip=$FIT_OFF count=$FIT_SIZE of=uImage
dd if=UDMPRO.bin bs=1 skip=$SQ_OFF count=$SQ_SIZE of=rootfs
# rootfs auf Vielfaches von 4096 padden
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

Per HTTP auf die UDM, `sda1`/`sda3` mounten, Dateien hinlegen, `sync`.

Ohne 4K-Padding: `mount: ... squashfs ... Invalid argument` und Reboot-Loop (`panic=3`).

---

## Schritt 4 — SCSI-Boot testen, dann speichern

U-Boot (noch **kein** `saveenv`):

```
scsi init
ext4load scsi 0:1 0x08000000 /uImage
setenv bootargs pci=pcie_bus_perf console=ttyS0,115200 panic=3 reboot=cold systemd.mask=usd.service systemd.mask=usdbd.service
bootm 0x08000000#udmpro@2
```

Wenn Debian/UniFi hochkommt:

```
setenv bootcmd 'scsi init; ext4load scsi 0:1 ${loadaddr} /uImage; bootm ${loadaddr}#udmpro@${fit_index}'
setenv bootargs pci=pcie_bus_perf console=ttyS0,115200 panic=3 reboot=cold systemd.mask=usd.service systemd.mask=usdbd.service
setenv bootdelay 5
saveenv
```

Erst speichern, wenn dieser Boot geklappt hat. `loadaddr` ist üblicherweise `0x08000000`.

---

## Schritt 5 — Guard installieren

SSH oder Serial, als root. Skripte nach `/tmp` oder `/persistent` kopieren, dann:

```sh
sh sata-tools/install.sh /pfad/zu/sata-tools
udm-sata-env check    # scsi
```

Das setzt:

- SCSI-Env auf **beide** SPI-Kopien (`mtd1`+`mtd2`)
- Masken für `usd.service` / `usdbd.service`
- Early-Boot-Guard (USB-eMMC ausblenden, `/dev/boot` → `sda`)
- Kopie unter `/persistent/udm-sata/bin/`

Web-UI: LAN `https://192.168.1.1`. Nach Overlay-Wipe ist das ein frisches Setup.

---

## Spätere Firmware-Updates (ohne Serial)

Nicht die UI, nicht `fwupdate`.

```sh
# Mac: Offsets prüfen
python3 sata-tools/inspect-bin.py UDMPRO-x.y.z.bin

scp UDMPRO-x.y.z.bin root@192.168.1.1:/persistent/udm-sata/incoming/
ssh root@192.168.1.1
udm-sata-env check
python3 /persistent/udm-sata/bin/udm-sata-apply-bin /persistent/udm-sata/incoming/UDMPRO-x.y.z.bin
```

Das Skript findet FIT/Squashfs selbst, paddet Rootfs, stellt SCSI-Env wieder her, leert das Overlay (Major-Sprung) und rebootet.

Gleiche Major, Account behalten:

```sh
python3 /persistent/udm-sata/bin/udm-sata-apply-bin --keep-overlay /persistent/udm-sata/incoming/UDMPRO-x.y.z.bin
```

Nach Overlay-Wipe: Setup-Wizard, SSH an, dann:

```sh
sh /persistent/udm-sata/bin/install.sh /persistent/udm-sata/bin
```

`/persistent` hat ~2 GiB. Eine ~900 MiB-`.bin` passt; ein Full-Backup von `sda3` oft nicht.

---

## Skripte

| Datei | Rolle |
|---|---|
| `inspect-bin.py` / `ubnt_bin.py` | FIT + Squashfs in einer `.bin` finden (Mac) |
| `format-os-disk.sh` | Stock-GPT auf `/dev/sda` (löscht die Platte) |
| `udm-sata-apply-bin` | `.bin` → `sda1`/`sda3`, Env, optional Overlay-Wipe |
| `udm-sata-env` | SPI-Env lesen/SCSI wiederherstellen |
| `udm-sata-guard` | usd maskieren, USB-eMMC weg, Tools aus `/persistent` |
| `install.sh` | Guard + Env auf der laufenden Box |

Env-Format: redundantes U-Boot, CRC32 nur über Payload (ohne Flags-Byte), `ENV_SIZE=0x4000`. `flashcp` kennt kein `-q`.

---

## Troubleshooting

**Reboot-Loop, Serial `mount fail ... squashfs /mnt/.boot/rootfs`**  
Rootfs nicht 4K-aligned. Einmalig `rdinit=/bin/sh` in `bootargs` (**nicht** `saveenv`), `zstd_decompress` + `squashfs` laden, `sda3` mounten, Datei padden, ohne `rdinit` neu starten.

**`fwupdate` → `failed writing part 'rootfs' to '/dev/sdb2'`**  
Erwartetes Verhalten. USB-Bootcarrier ist die tote GL3224. Nur `udm-sata-apply-bin`.

**Falsches Device-Tree / Kernel hängt**  
`fit_index` / `#udmpro@N` muss zur BOM passen. U-Boot druckt das beim Start.

**Protect-Platte leer, OS weg**  
`usd` war nicht maskiert. GPT neu, Firmware neu, Guard + `systemd.mask` in SPI.

**SSH Host-Key**  
Nach Overlay-Wipe ändert sich der Key. Nicht `known_hosts` kaputtmachen: `UserKnownHostsFile=/dev/null` für diesen Host.

---

## Credits

- Ubiquiti-Community: eMMC-/GL3224-Hardware, Recovery-Dumps, Desolder-Writeups.
- Alpine/U-Boot `2015.07-alpine_db` auf AL324.

Lizenz der Skripte: MIT (siehe `LICENSE`). UniFi OS und `.bin`-Firmware sind Eigentum von Ubiquiti.
