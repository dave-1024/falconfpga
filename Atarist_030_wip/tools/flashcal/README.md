flash_cal sim (iverilog). img_crc.py IMG N writes img.hex (first N words) and prints the expected CRC32 (MSB first, poly 04C11DB7, init FFFFFFFF, no final xor).
  iverilog -g2012 -DIMGON=1 -DTCO=9 -DW0=0 -DW1=0 -DW2=0 -o t tb_flash_cal.v ../../hdl/tang/console138k/flash_cal.v && vvp -n t
Synthetic headers: -DIMGON=0 -DW0=16'h602E -DW1=16'h0206 -DW2=16'h00E0. TCO = flash output delay after SCK fall (ns).
Results (F85b): TOS 2.06, EmuTOS 192k and 256k at TCO 3/9/13: picked point CRC == image CRC; bad header -> fixed point 0.
