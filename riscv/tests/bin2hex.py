#!/usr/bin/env python3
"""Convert raw RV32I binary to $readmemh hex format (one word per line, little-endian)."""
import sys

if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} <input.bin> <output.hex>", file=sys.stderr)
    sys.exit(1)

data = open(sys.argv[1], 'rb').read()

# Pad to word boundary
while len(data) % 4:
    data += b'\x00'

with open(sys.argv[2], 'w') as f:
    for i in range(0, len(data), 4):
        word = int.from_bytes(data[i:i+4], 'little')
        f.write(f'{word:08x}\n')

print(f"Converted {len(data)} bytes → {len(data)//4} words → {sys.argv[2]}", file=sys.stderr)
