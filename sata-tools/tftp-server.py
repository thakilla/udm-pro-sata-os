#!/usr/bin/env python3
"""Minimal TFTP RRQ server (octet + optional blksize). Same helper used for the first RAM boot."""
import os
import socket
import struct
import sys

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
BIND = sys.argv[2] if len(sys.argv) > 2 else "0.0.0.0"
PORT = int(sys.argv[3]) if len(sys.argv) > 3 else 69
DEFAULT_BLOCK = 512
MAX_BLOCK = 1428
OP_RRQ, OP_DATA, OP_ACK, OP_ERR, OP_OACK = 1, 3, 4, 5, 6


def parse_rrq(data):
    parts = data[2:].split(b"\x00")
    filename = parts[0].decode("ascii", "replace").lstrip("/")
    mode = parts[1].decode("ascii", "replace").lower() if len(parts) > 1 else "octet"
    opts = {}
    i = 2
    while i + 1 < len(parts) and parts[i]:
        opts[parts[i].decode("ascii", "replace").lower()] = parts[i + 1].decode(
            "ascii", "replace"
        )
        i += 2
    return filename, mode, opts


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((BIND, PORT))
    print(f"tftp serving {ROOT} on {BIND}:{PORT}", flush=True)
    while True:
        data, addr = sock.recvfrom(65536)
        if len(data) < 4:
            continue
        opcode = struct.unpack("!H", data[:2])[0]
        if opcode != OP_RRQ:
            continue
        filename, mode, opts = parse_rrq(data)
        path = os.path.normpath(os.path.join(ROOT, filename))
        if not path.startswith(ROOT + os.sep) and path != ROOT:
            sock.sendto(struct.pack("!HH", OP_ERR, 2) + b"Access denied\x00", addr)
            print(f"deny {filename} from {addr}", flush=True)
            continue
        if not os.path.isfile(path):
            sock.sendto(struct.pack("!HH", OP_ERR, 1) + b"File not found\x00", addr)
            print(f"missing {filename} from {addr}", flush=True)
            continue
        blksize = DEFAULT_BLOCK
        if "blksize" in opts:
            try:
                blksize = max(8, min(MAX_BLOCK, int(opts["blksize"])))
            except ValueError:
                blksize = DEFAULT_BLOCK
        size = os.path.getsize(path)
        print(f"RRQ {filename} {size}B blksize={blksize} from {addr}", flush=True)
        tsock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        tsock.settimeout(5)
        if "blksize" in opts:
            oack = struct.pack("!H", OP_OACK) + b"blksize\x00" + str(blksize).encode() + b"\x00"
            tsock.sendto(oack, addr)
            try:
                ack, a2 = tsock.recvfrom(65536)
            except socket.timeout:
                print("OACK timeout", flush=True)
                tsock.close()
                continue
            if a2 != addr or len(ack) < 4 or struct.unpack("!HH", ack[:4]) != (OP_ACK, 0):
                print(f"bad OACK ack {ack[:8]!r}", flush=True)
                tsock.close()
                continue
        with open(path, "rb") as f:
            block = 1
            while True:
                chunk = f.read(blksize)
                pkt = struct.pack("!HH", OP_DATA, block) + chunk
                for attempt in range(8):
                    tsock.sendto(pkt, addr)
                    try:
                        ack, a2 = tsock.recvfrom(65536)
                    except socket.timeout:
                        continue
                    if a2 != addr or len(ack) < 4:
                        continue
                    aop, ablk = struct.unpack("!HH", ack[:4])
                    if aop == OP_ACK and ablk == block:
                        break
                else:
                    print(f"timeout block {block}", flush=True)
                    break
                if len(chunk) < blksize:
                    print(f"done {filename} last block {block}", flush=True)
                    break
                block = (block + 1) & 0xFFFF
        tsock.close()


if __name__ == "__main__":
    main()
