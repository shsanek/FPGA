#!/usr/bin/env python3
"""
Prepend FLASH_LOADER header to a binary file.

Header format (12 bytes, little-endian):
  [4B magic:     0xB007C0DE]
  [4B size:      file size in bytes, padded to 4]
  [4B load_addr: DDR address to load at]

Usage: python prepend_header.py input.bin output.bin [load_addr_hex]
  load_addr defaults to 0x07F00000 (Stage 1 in upper DDR)
"""
import struct
import sys

if len(sys.argv) < 3:
    print(f"Usage: {sys.argv[0]} input.bin output.bin [load_addr_hex]")
    sys.exit(1)

load_addr = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x07F00000

data = open(sys.argv[1], 'rb').read()

# Pad to 4-byte alignment
while len(data) % 4 != 0:
    data += b'\x00'

header = struct.pack('<III', 0xB007C0DE, len(data), load_addr)
open(sys.argv[2], 'wb').write(header + data)

print(f"Header: magic=0xB007C0DE size={len(data)} ({len(data):#x}) load_addr=0x{load_addr:08X}")
print(f"Total: {len(header) + len(data)} bytes")
