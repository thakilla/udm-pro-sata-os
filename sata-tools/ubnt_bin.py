#!/usr/bin/python3
"""Locate FIT uImage and squashfs rootfs inside an official UDMPRO-*.bin."""
from __future__ import annotations

import struct
from pathlib import Path

FDT = bytes.fromhex("d00dfeed")
SQ = b"hsqs"


def find_fits(data: bytes) -> list[tuple[int, int, bool]]:
    """Return (offset, size, has_udmpro_at_2) for FIT blobs >= 1 MiB."""
    hits: list[tuple[int, int, bool]] = []
    i = 0
    while True:
        j = data.find(FDT, i)
        if j < 0 or j + 8 > len(data):
            break
        size = int.from_bytes(data[j + 4 : j + 8], "big")
        if 1024 * 1024 <= size <= 64 * 1024 * 1024 and j + size <= len(data):
            blob = data[j : j + size]
            hits.append((j, size, b"udmpro@2" in blob))
        i = j + 4
    return hits


def pick_fit(hits: list[tuple[int, int, bool]]) -> tuple[int, int]:
    with_cfg = [h for h in hits if h[2]]
    pool = with_cfg or hits
    if not pool:
        raise SystemExit("no FIT (>=1 MiB) found in firmware")
    off, size, has2 = max(pool, key=lambda h: h[1])
    if not has2:
        raise SystemExit("FIT found but it has no udmpro@2; refuse to flash")
    return off, size


def find_squashfs(data: bytes) -> tuple[int, int]:
    best: tuple[int, int] | None = None
    i = 0
    while True:
        j = data.find(SQ, i)
        if j < 0:
            break
        if j + 48 <= len(data):
            used = struct.unpack_from("<Q", data, j + 40)[0]
            if 32 * 1024 * 1024 <= used <= len(data) - j:
                if best is None or used > best[1]:
                    best = (j, used)
        i = j + 4
    if best is None:
        raise SystemExit("no large squashfs (hsqs) found in firmware")
    return best


def inspect(path: Path) -> tuple[int, int, int, int]:
    data = path.read_bytes()
    if not data.startswith(b"UBNTUDMPRO"):
        raise SystemExit(f"{path}: not a UDMPRO firmware (header {data[:16]!r})")
    fit_off, fit_size = pick_fit(find_fits(data))
    sq_off, sq_size = find_squashfs(data)
    return fit_off, fit_size, sq_off, sq_size


def main() -> None:
    import argparse
    import sys

    p = argparse.ArgumentParser(description="Show FIT/squashfs offsets in a UDMPRO .bin")
    p.add_argument("firmware")
    args = p.parse_args()
    path = Path(args.firmware)
    fit_off, fit_size, sq_off, sq_size = inspect(path)
    print(f"file\t{path} ({path.stat().st_size} bytes)")
    print(f"fit\toff={fit_off} size={fit_size} ({fit_size / 1024 / 1024:.2f} MiB)")
    print(f"rootfs\toff={sq_off} size={sq_size} ({sq_size / 1024 / 1024:.1f} MiB)")
    print("udmpro@2: yes")
    sys.exit(0)


if __name__ == "__main__":
    main()
