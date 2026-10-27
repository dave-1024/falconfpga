# Replaying MiNT's set_mmu on the RTL core
1. Hatari (STE, TOS 2.06, 030+MMU, 4 MB, mint_scr.st) with a debugger breakpoint at $5CE8E
   (`pmove 12(sp),tc` in mint030 set_mmu, normal_set path): `b pc = $5ce8e :once :file bp.ini`, where bp.ini
   does `r` and `savebin ram4m.bin 0 $400000`. CRP = $7FFF0003 000BC000, TC = $80D04447, SSP $9947E.
2. Put `mint_setmmu_stub.s` (linked at $3FF000: Hatari's registers, CRP, jmp $5CE8E) into the RAM image.
3. tb030: `-gST=1 -gROMFILE=tos.hex (TOS 2.06 UK, 256K) -gRAMFILE=ramstub.hex -gRSSP=627838 -gRPC=4190208`.
Result (27 Oct, pmmu 46d3eee core): at WS 0/1/3 and WS 1 + WSRND 3 the core turns translation on, walks the
4-level long tables (8K pages) and runs on through the same TOS calls as Hatari (Logbase, Iorec, Rsconf x2,
Keytbl, Kbrate, GEMDOS) with no bus error. The board halts at this point (see PMMU_PROGRESS).
