#!/usr/bin/env python3
"""MBXCART.BIN -> tang/console138k/st_helper_cart.hex (512 words, $readmemh
format, padded with FFFF) for st_helper_cart_rom.v. Run by build.sh."""
import sys
data = open(sys.argv[1], 'rb').read()
if len(data) % 2: data += b'\xff'
words = [(data[i] << 8) | data[i+1] for i in range(0, len(data), 2)]
assert len(words) <= 512, "cartridge image larger than the 1 KB ROM"
words += [0xFFFF] * (512 - len(words))
open(sys.argv[2], 'w').write("".join("%04X\n" % w for w in words))
print("%s: %d bytes of code" % (sys.argv[2], len(data)))
