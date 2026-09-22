#!/usr/bin/env python3
# license:MIT
#
# Extracts the HD44780U "A00" character-generator ROM table (4096 bytes, 256
# characters x 16 bytes, of which the first 8 bytes/character are the 5x8 dot
# pattern MAME's hd44780u_device actually uses) from a page image of the
# official Hitachi datasheet, by locating the table's grid lines and sampling
# each of the 5x8 dot positions per character cell.
#
# Why this exists: MAME's hd44780_device requires a "hd44780u_a00.bin" ROM
# file that MAME's own git repository does not ship (MAME ships only
# checksums, never ROM binaries - see mame/README.md). The checksum in
# src/devices/video/hd44780.cpp is itself marked BAD_DUMP and, per the
# comment there, was transcribed from page 17 of the 1999 HD44780U datasheet
# - i.e. MAME's own "dump" of this ROM is already a datasheet transcription,
# not a silicon dump. This script performs the same kind of transcription
# independently, so our own copy does not depend on finding MAME's binary
# anywhere. It will therefore NOT match MAME's checksum bit-for-bit (a
# different, independent transcription), but produces a genuine, legible
# character set - verified by rendering real firmware output through it, see
# mame/README.md section "hd44780u_a00.bin (Zeichensatz-ROM)".
#
# Datasheet source used: doc/tech-spec/HD44780.pdf from the MIT-licensed
# https://github.com/rm-hull/luma.lcd repository (a reproduction of the
# public Hitachi HD44780U datasheet), page 17, "Table 4 Correspondence
# between Character Codes and Character Patterns (ROM Code: A00)".
#
# Usage:
#   pip install pillow numpy
#   curl -sL -o HD44780.pdf https://raw.githubusercontent.com/rm-hull/luma.lcd/main/doc/tech-spec/HD44780.pdf
#   pdftoppm -r 400 -f 17 -l 17 -png HD44780.pdf page17
#   python3 extract_hd44780_charset.py page17-17.png hd44780u_a00.bin
#
# The pixel coordinates below (row/column grid line positions, dot pitch)
# were measured once against that exact 400 dpi render of page 17 and are
# specific to it; a different render resolution needs re-calibration (see
# system-spec.md / mame/README.md for how this was done: detect long
# horizontal/vertical black runs to find the table's rule lines, then
# calibrate the 5x8 dot grid against the solid-block glyph at code 0xFF).

import sys
from PIL import Image
import numpy as np

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <page17-400dpi.png> <hd44780u_a00.bin>")
        sys.exit(1)

    im = Image.open(sys.argv[1]).convert('L')
    a = np.array(im)

    # Table grid lines, measured on the 400 dpi render of datasheet page 17.
    row_tops = [822, 993, 1163, 1334, 1504, 1675, 1845, 2016,
                2186, 2357, 2527, 2697, 2867, 3038, 3208, 3379]
    row_bots = [958, 1128, 1299, 1469, 1639, 1810, 1980, 2151,
                2321, 2491, 2661, 2832, 3002, 3173, 3343, 3513]
    cols = [696, 829, 963, 1097, 1230, 1364, 1497, 1631, 1764,
            1898, 2031, 2165, 2304, 2437, 2571, 2704, 2837]

    # Dot-grid calibration from the solid block glyph (row 1111, col 1111 = code 0xFF).
    x_centers = [34, 50, 66, 82, 98]
    y_centers = [10.5 + i * (125.5 - 10.5) / 7 for i in range(8)]

    rom = bytearray(4096)

    for lower in range(16):
        rt, rb = row_tops[lower], row_bots[lower]
        for upper in range(16):
            cl, cr = cols[upper], cols[upper + 1]
            code = (upper << 4) | lower
            cell = a[rt:rb, cl:cr]
            for r, y in enumerate(y_centers):
                byte = 0
                for xi, x in enumerate(x_centers):
                    yi0, yi1 = int(y - 4), int(y + 5)
                    xi0, xi1 = int(x - 4), int(x + 5)
                    patch = cell[max(0, yi0):yi1, max(0, xi0):xi1]
                    if patch.size and patch.mean() < 128:
                        byte |= 1 << (4 - xi)
                rom[code * 16 + r] = byte

    # Codes 0x00-0x1F are the CGRAM-mapped slots (user-definable on the real
    # chip) and are shown blank in the datasheet table; force them to zero
    # rather than keep whatever faint grid-line bleed the sampling picked up.
    for code in range(0x00, 0x20):
        for r in range(16):
            rom[code * 16 + r] = 0

    with open(sys.argv[2], 'wb') as f:
        f.write(rom)

    import zlib, hashlib
    print(f"wrote {sys.argv[2]}: {len(rom)} bytes")
    print(f"crc32 {zlib.crc32(rom) & 0xffffffff:08x}")
    print(f"sha1  {hashlib.sha1(rom).hexdigest()}")

if __name__ == '__main__':
    main()
