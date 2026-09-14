---
name: udm-pro-sata
description: >-
  Updates and recovers a UniFi Dream Machine Pro whose internal eMMC is dead
  and whose OS lives on the SATA HDD (SCSI U-Boot, FIT udmpro@2). Use when the
  user mentions UDM Pro, UDMPRO, UniFi OS firmware, a UDMPRO-*.bin, fwupdate,
  ubnt-systool, SATA boot, GL3224, usd/Protect wiping GPT, or serial/U-Boot on
  this unit. Never apply stock Ubiquiti updaters to this device.
license: MIT
---

# UDM Pro SATA OS

USB-eMMC (GL3224) is dead. OS is on the Protect-bay HDD (`/dev/sda`).
U-Boot loads `sda1:/uImage` via SCSI (`fit_index=2`, `#udmpro@2`).

Scripts live in this repo under `sata-tools/`. On the device: `/persistent/udm-sata/bin/`.

Read [references/reference.md](references/reference.md) for GPT, SPI env, and unbrick notes. First conversion is the repo `README.md` (serial + TFTP). Later updates are SSH-only.

## Hard rules

Do **not**:

- Web-UI **UniFi OS / firmware** update or factory reset
- Leave Control Plane **UniFi OS** automatic updates on (the unit bricks itself)
- `fwupdate`, `ubnt-systool fwupdate`, `udm-sata-update`
- `usb start` in U-Boot (XHCI crash)
- Unmask `usd` / `usdbd` (that daemon repartitions the whole HDD)
- Expand OS partitions sda1–6 to fill the whole disk
- Remove the HDD
- `env default -a` in U-Boot
- Flash a `.bin` that is not `UBNTUDMPRO.al324` or that lacks `udmpro@2`
- Guess SSH passwords
- Patch `FIT_OFF` / `FIT_SIZE` in any script — `udm-sata-apply-bin` calls `inspect()` itself

Always:

- Keep SPI `bootcmd` SCSI and `bootargs` with `systemd.mask=usd.service systemd.mask=usdbd.service`
- Pad `/rootfs` on `sda3` to a **4 KiB** multiple
- After **every** `apply-bin` reboot (including `--keep-overlay`), run `install.sh` from `/persistent`

## Firmware update (SSH only)

1. On the computer: `python3 sata-tools/inspect-bin.py <bin>`
   Confirm header `UBNTUDMPRO.al324` and a FIT with `udmpro@2` (~10–20 MiB, not the tiny DTBs).
2. SSH `root@192.168.1.1` (LAN 1–8). Password from `$UDM_PASS` if set; otherwise **ask the user**. Keyboard-interactive. Throwaway `UserKnownHostsFile` (host key changes after overlay wipe). Do not use serial for an update.
3. `udm-sata-env check` must print `scsi`. If PATH is empty after a reboot, use `/persistent/udm-sata/bin/udm-sata-env`.
4. `scp` the `.bin` to `/persistent/udm-sata/incoming/` (`/persistent` is ~2 GiB; a ~900 MiB `.bin` fits). Skip a full `sda3` backup.
5. Run `python3 /persistent/udm-sata/bin/udm-sata-apply-bin [--keep-overlay] <bin>`.
   Same major (e.g. 5.1.26 → 5.1.33): `--keep-overlay` (keeps UI account). Major jump: default wipe.
6. Wait for ping + SSH (`reboot -f` takes a few minutes).
7. **Always** `sh /persistent/udm-sata/bin/install.sh /persistent/udm-sata/bin`.
   A new squashfs drops `/usr/local/sbin` even when the overlay is kept. `install.sh` restores PATH tools and the guard.
8. Verify: `/etc/version` (or `/usr/lib/version`), `udm-sata-env check` / `show` (`scsi`, `fit_index=2`, usd masked), `systemctl start` + `is-active udm-sata-guard`, `/dev/boot` → `sda`, LAN UI `https://192.168.1.1`. Remind: **UniFi OS** auto-update stays **off**. Application updates (Network, Protect, …) from the UI are allowed.

Do not run `inspect-bin.py` on the UDM as a required step — `apply-bin` already inspects.

## If boot fails

Do not run `usb start`. See [references/reference.md](references/reference.md). Typical squashfs loop: pad `sda3:/rootfs` to 4096 from `rdinit=/bin/sh` (do not `saveenv` with `rdinit`).
