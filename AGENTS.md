# Agent instructions

This repo puts UniFi OS on the UDM Pro SATA disk. Stock Ubiquiti updaters write the dead USB eMMC and brick the unit.

Before firmware, serial, U-Boot, or disk work, follow the skill at `.agents/skills/udm-pro-sata/SKILL.md` (Agent Skills layout, not vendor-specific). GPT, SPI env, and unbrick notes: `.agents/skills/udm-pro-sata/references/reference.md`.

First conversion: follow `README.md` with serial-console access (U-Boot, TFTP, `saveenv`). Later firmware updates: the skill above (SSH only). Scripts: `sata-tools/`. Do not commit `*.bin` / `*.img`.
