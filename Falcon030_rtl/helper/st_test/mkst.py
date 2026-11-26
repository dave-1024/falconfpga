#!/usr/bin/env python3
"""Make a 720 KB Atari ST floppy image (FAT12, 2 sides, 9 sectors, 80 tracks)
holding the given files in its root directory, e.g.
    python3 mkst.py MBXTERM.ST MBXTERM.PRG
For the SD card once the AE350 companion port can mount floppy images."""
import struct, sys, os
out, files = sys.argv[1], sys.argv[2:]
BPS, SPC, RES, NF, NDIR, NSEC, SPF, SPT, NH = 512, 2, 1, 2, 112, 1440, 3, 9, 2
img = bytearray(NSEC * BPS)
bs = bytearray(BPS)
bs[0:2] = b'\x60\x38'; bs[2:8] = b'FALCON'; bs[8:11] = b'\x12\x34\x56'
struct.pack_into('<HBHBHHBHHHH', bs, 11, BPS, SPC, RES, NF, NDIR, NSEC, 0xF9, SPF, SPT, NH, 0)
if sum(struct.unpack('>256H', bs)) & 0xffff == 0x1234: bs[30] ^= 1  # never bootable
img[0:BPS] = bs
fat = [0xFF9, 0xFFF]
root = bytearray(NDIR * 32); data0 = (RES + NF * SPF + NDIR * 32 // BPS); clus = 2
for i, f in enumerate(files):
    d = open(f, 'rb').read(); n = max(1, -(-len(d) // (SPC * BPS)))
    for k in range(n): fat.append(clus + k + 1 if k < n - 1 else 0xFFF)
    off = (data0 + (clus - 2) * SPC) * BPS; img[off:off + len(d)] = d
    b, e = os.path.splitext(os.path.basename(f).upper())
    name = (b[:8].ljust(8) + e[1:4].ljust(3)).encode()
    struct.pack_into('<11sB10sHHHI', root, i * 32, name, 0x20, b'', 0, (46 << 9) | (10 << 5) | 6, clus, len(d))
    clus += n
fb = bytearray(SPF * BPS)
for j, v in enumerate(fat):
    o = j * 3 // 2
    if j & 1: fb[o] |= (v << 4) & 0xF0; fb[o + 1] = v >> 4
    else: fb[o] = v & 0xFF; fb[o + 1] |= v >> 8
for k in range(NF): img[(RES + k * SPF) * BPS:(RES + (k + 1) * SPF) * BPS] = fb
img[(RES + NF * SPF) * BPS:data0 * BPS] = root
open(out, 'wb').write(img)
print(out, len(img), 'bytes,', len(files), 'file(s)')
