#!/usr/bin/env python3
"""Make the AE350 serial-proof copy of the SoC netlist.

Input : Atarist_030_wip/helper/riscv_ae350_soc/riscv_ae350_soc.v
        (commit 949bd27 replaced the six FLASH_SPI IOBUFs and GPIO[7:0]
        IOBUFs with assigns, for the desktop image.)
Output: Atarist_030_wip/helper/riscv_ae350_soc_serial/riscv_ae350_soc.v
        Same file with the six FLASH_SPI IOBUFs put back exactly as Gowin
        generated them (byte-identical to 168ktest / Hybrid030). GPIO[7:0]
        stay fabric wires so the ready mark is still readable.
Run from the repo root. Only the plaintext wrapper after the encrypted
block is touched.
"""
import sys, os

SRC = "Atarist_030_wip/helper/riscv_ae350_soc/riscv_ae350_soc.v"
DST = "Atarist_030_wip/helper/riscv_ae350_soc_serial/riscv_ae350_soc.v"

OLD = """  assign FLASH_SPI_CSN = spi1_csn_out;
  assign FLASH_SPI_CSN_in = spi1_csn_out;
  assign FLASH_SPI_MISO_in = FLASH_SPI_MISO;
  assign FLASH_SPI_MOSI = spi_out_r[0];
  assign FLASH_SPI_MOSI_in = spi_out_r[0];
  assign FLASH_SPI_CLK = n250_3;
  assign FLASH_SPI_CLK_in = n250_3;
  assign FLASH_SPI_HOLDN = VCC;
  assign FLASH_SPI_HOLDN_in = VCC;
  assign FLASH_SPI_WPN = VCC;
  assign FLASH_SPI_WPN_in = VCC;
"""

NEW = """  IOBUF FLASH_SPI_CSN_iobuf (
    .O(FLASH_SPI_CSN_in),
    .IO(FLASH_SPI_CSN),
    .I(spi1_csn_out),
    .OEN(GND) 
);
  IOBUF FLASH_SPI_MISO_iobuf (
    .O(FLASH_SPI_MISO_in),
    .IO(FLASH_SPI_MISO),
    .I(VCC),
    .OEN(IO_7_77) 
);
  IOBUF FLASH_SPI_MOSI_iobuf (
    .O(FLASH_SPI_MOSI_in),
    .IO(FLASH_SPI_MOSI),
    .I(spi_out_r[0]),
    .OEN(GND) 
);
  IOBUF FLASH_SPI_CLK_iobuf (
    .O(FLASH_SPI_CLK_in),
    .IO(FLASH_SPI_CLK),
    .I(n250_3),
    .OEN(GND) 
);
  IOBUF FLASH_SPI_HOLDN_iobuf (
    .O(FLASH_SPI_HOLDN_in),
    .IO(FLASH_SPI_HOLDN),
    .I(VCC),
    .OEN(GND) 
);
  IOBUF FLASH_SPI_WPN_iobuf (
    .O(FLASH_SPI_WPN_in),
    .IO(FLASH_SPI_WPN),
    .I(VCC),
    .OEN(GND) 
);
"""

data = open(SRC, "rb").read().decode("latin-1")
eol = "\r\n" if "\r\n" in data else "\n"
old = OLD.replace("\n", eol)
new = NEW.replace("\n", eol)
if data.count(old) != 1:
    sys.exit("flash assign block not found exactly once; netlist changed, stop")
os.makedirs(os.path.dirname(DST), exist_ok=True)
open(DST, "wb").write(data.replace(old, new).encode("latin-1"))
print("wrote", DST)
