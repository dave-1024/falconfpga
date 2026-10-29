# FreeMiNT 030 on an ACSI FAT16 disk, booted by EmuTOS (29 Oct 2026)
- Floppy etos.st: AUTO/EMU256UK.PRG (EmuTOS 1.4 prg256, RAM version over TOS 2.06; flash untouched). On SD.
- Disk mint030.hd (6 MB, MBR, one FAT16 partition type 06 at sector 2048): AUTO/MINT-4A6.PRG + mint/1-19-4a6
  (mint030.prg, xaaes, sys-root/opt/GEM/teradesk, sys-root/etc) from freemint-1-19-4a6b3e82-tt_falcon_clones.zip;
  toswin2 run line commented out. Built on linserver ~/acsi with mtools/sfdisk/mkfs.fat.
- Board (f93n in SRAM): `mount a etos.st`, `mount h0 mint030.hd`, `c` -> EmuTOS boots from C: (ACSI emulation OK),
  mint030 starts, reads u:/C/mint/1-19-4a6/mint.cnf, then stops (07:15 UTC).
- Rebuilt as mint030b.hd: exec 040sp/060sp lines removed (suspect), echo markers, mint.ini WRITE_BOOT=YES. Uploading (~31 min).
