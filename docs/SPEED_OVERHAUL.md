
## Progress log (overnight, UK time)

- 2026-11-04 00:10: F140 (back-to-back opcode read from the queue, fetch counts preserved: stale sequential prefetch is blocked while the decoder asks for an address the queue head does not match) plus F141 (early OW_REQ in INIT_EXEC_WB for register-only ops, gated by TRACE_MODE="00" and the new IRQ_HOT; MOVEQ no longer waits on an overwrite-only DR_IN_USE hazard; in the register file, a new in-use mark now wins over a release in the same clock). Both are uncommitted while run_rtl runs. Backup: /workspace/speedh/wip_f140_f141.patch.
- Harness (clocks/instr, manual / base / now): moveq 2/4/3, cmp.l 2/3/2.38, tst.l 2/3/2.38, move.l #imm 4/9/7, addi.l 6/10/6, lea d16 2/6/5, btst # 4/6/4, bra 6/11/10, bsr+rts 15/32/30, dbf_loop8 54/107/79, delay_loop8 72/110/101.
- Open bug: cmpa.l Dn,An is 3, but the manual says 4 (faster than the manual). CMPA is excluded from early issue. Step 4 will fix it.
