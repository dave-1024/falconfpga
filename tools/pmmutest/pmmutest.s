| PMMUTEST.PRG - 68030 PMMU checks against MC68030UM (falconfpga, branch pmmu)
| Build: ./build.sh  (GNU as, MIT syntax, position independent, no relocations)
| Each test prints "PASS"/"FAIL"/"DEV" (known, documented deviation of the current stage) + values.
| Results also go to A:\PMMUTEST.TXT.  Add later stages as new T_xxx routines in the table at "tests".
	.text
	.globl _start
_start:
start:	move.l	4(%sp),%a0		| basepage (unused)
	lea	ustk_end(%pc),%sp
	clr.l	-(%sp)
	move.w	#0x20,-(%sp)		| Super(0)
	trap	#1
	addq.l	#6,%sp
	lea	oldssp(%pc),%a0
	move.l	%d0,(%a0)
	lea	sstk_end(%pc),%sp	| private supervisor stack
	lea	outp(%pc),%a0
	lea	outbuf(%pc),%a1
	move.l	%a1,(%a0)
	lea	s_title(%pc),%a0
	bsr	puts
| save state
	lea	sv(%pc),%a5
	pmove	%tc,(%a5)
	pmove	%tt0,4(%a5)
	pmove	%tt1,8(%a5)
	movec	%cacr,%d0
	move.l	%d0,12(%a5)
	pmove	%crp,16(%a5)
	pmove	%srp,24(%a5)
	move.l	0x20,32(%a5)
	move.l	0x2c,36(%a5)
	move.l	0xe0,40(%a5)
	lea	h_exc8(%pc),%a0
	move.l	%a0,0x20
	lea	h_exc2c(%pc),%a0
	move.l	%a0,0x2c
	lea	h_exce0(%pc),%a0
	move.l	%a0,0xe0
| run tests
	lea	tests(%pc),%a4
1:	move.w	(%a4)+,%d0
	beq	2f
	lea	tests(%pc),%a0
	adda.w	%d0,%a0
	movem.l	%a4,-(%sp)
	jsr	(%a0)
	movem.l	(%sp)+,%a4
	bra	1b
2:
| restore
	lea	sv(%pc),%a5
	pmove	4(%a5),%tt0
	pmove	8(%a5),%tt1
	pmove	16(%a5),%crp
	pmove	24(%a5),%srp
	pmove	(%a5),%tc
	move.l	12(%a5),%d0
	movec	%d0,%cacr
	move.l	32(%a5),0x20
	move.l	36(%a5),0x2c
	move.l	40(%a5),0xe0
	lea	s_sum1(%pc),%a0
	bsr	puts
	move.w	nfail(%pc),%d0
	bsr	putdec
	lea	s_sum2(%pc),%a0
	bsr	puts
	move.w	ndev(%pc),%d0
	bsr	putdec
	lea	s_nl(%pc),%a0
	bsr	puts
	bsr	savefile
	move.l	oldssp(%pc),-(%sp)
	move.w	#0x20,-(%sp)
	trap	#1
	addq.l	#6,%sp
	lea	ustk_end(%pc),%sp
	lea	s_key(%pc),%a0
	bsr	conws
	move.w	#7,-(%sp)		| Crawcin
	trap	#1
	addq.l	#2,%sp
	clr.w	-(%sp)
	trap	#1

| ---- test table: offsets from "tests" (add stage 2+ tests here) ----
tests:	.word	T_tc-tests, T_tt0-tests, T_tt1-tests, T_mmusr-tests
	.word	T_crp-tests, T_srp-tests, T_tcinv-tests, T_tcreset-tests
	.word	T_priv-tests, T_ttci-tests
	.word	0

| d6 = expected, d7 = got, a0 = name -> PASS/FAIL line
check:	move.l	%a0,-(%sp)
	cmp.l	%d6,%d7
	bne	1f
	lea	s_pass(%pc),%a0
	bra	2f
1:	lea	nfail(%pc),%a0
	addq.w	#1,(%a0)
	lea	s_fail(%pc),%a0
2:	bsr	puts
	move.l	(%sp)+,%a0
	bsr	puts
	lea	s_exp(%pc),%a0
	bsr	puts
	move.l	%d6,%d0
	bsr	puthex
	lea	s_got(%pc),%a0
	bsr	puts
	move.l	%d7,%d0
	bsr	puthex
	lea	s_nl(%pc),%a0
	bra	puts

| 9.7.1 p9-52/53 TC: write all ones with E=0, unused bits read 0 (mask $83FFFFFF)
T_tc:	lea	tmp(%pc),%a0
	move.l	#0x7fffffff,(%a0)
	pmove	(%a0),%tc
	clr.l	(%a0)
	pmove	%tc,(%a0)
	move.l	(%a0),%d7
	move.l	#0x03ffffff,%d6
	lea	n_tc(%pc),%a0
	bsr	check
	clr.l	-(%sp)
	pmove	(%sp),%tc
	addq.l	#4,%sp
	rts
| 9.7.3 p9-57/58 TTx: mask $FFFF8777. Write with E=0 so nothing is matched.
T_tt0:	move.l	#0xffff7fff,%d0
	lea	tmp(%pc),%a0
	move.l	%d0,(%a0)
	pmove	(%a0),%tt0
	clr.l	(%a0)
	pmove	%tt0,(%a0)
	move.l	(%a0),%d7
	move.l	#0xffff0777,%d6
	lea	n_tt0(%pc),%a0
	bsr	check
	clr.l	-(%sp)
	pmove	(%sp),%tt0
	addq.l	#4,%sp
	rts
T_tt1:	move.l	#0xffff7fff,%d0
	lea	tmp(%pc),%a0
	move.l	%d0,(%a0)
	pmove	(%a0),%tt1
	clr.l	(%a0)
	pmove	%tt1,(%a0)
	move.l	(%a0),%d7
	move.l	#0xffff0777,%d6
	lea	n_tt1(%pc),%a0
	bsr	check
	clr.l	-(%sp)
	pmove	(%sp),%tt1
	addq.l	#4,%sp
	rts
| 9.7.4 p9-59/60 MMUSR word: mask $EE47
T_mmusr: lea	tmp(%pc),%a0
	move.w	#0xffff,(%a0)
	pmove	(%a0),%psr
	clr.w	(%a0)
	pmove	%psr,(%a0)
	moveq	#0,%d7
	move.w	(%a0),%d7
	move.l	#0xee47,%d6
	lea	n_mmusr(%pc),%a0
	bsr	check
	clr.w	-(%sp)
	pmove	(%sp),%psr
	addq.l	#2,%sp
	rts
| 9.7.2 p9-54..56 CRP/SRP 64 bit: mask $FFFF0003_FFFFFFF0 (DT=0 is invalid, so write DT=3)
T_crp:	lea	tmp(%pc),%a0
	moveq	#-1,%d0
	move.l	%d0,(%a0)
	move.l	%d0,4(%a0)
	pmove	(%a0),%crp
	clr.l	(%a0)
	clr.l	4(%a0)
	pmove	%crp,(%a0)
	move.l	(%a0),%d7
	move.l	#0xffff0003,%d6
	lea	n_crph(%pc),%a0
	bsr	check
	lea	tmp(%pc),%a0
	move.l	4(%a0),%d7
	move.l	#0xfffffff0,%d6
	lea	n_crpl(%pc),%a0
	bra	check
T_srp:	lea	tmp(%pc),%a0
	moveq	#-1,%d0
	move.l	%d0,(%a0)
	move.l	%d0,4(%a0)
	pmove	(%a0),%srp
	clr.l	(%a0)
	clr.l	4(%a0)
	pmove	%srp,(%a0)
	move.l	(%a0),%d7
	move.l	#0xffff0003,%d6
	lea	n_srph(%pc),%a0
	bsr	check
	lea	tmp(%pc),%a0
	move.l	4(%a0),%d7
	move.l	#0xfffffff0,%d6
	lea	n_srpl(%pc),%a0
	bra	check
| 9.7.1 p9-53 / 9.8 p9-64: invalid TC with E=1 (PS=0 <8) -> MMU configuration exception (vector 56)
| and E stays 0.  Stage 1 stores TC with E cleared but takes no exception: reported as DEV.
T_tcinv: lea	exv(%pc),%a0
	clr.w	(%a0)
	lea	tmp(%pc),%a0
	move.l	#0x80000000,(%a0)
	lea	tcinv_i(%pc),%a1
	lea	expc(%pc),%a2
	move.l	%a1,(%a2)
tcinv_i: pmove	(%a0),%tc
	pmove	%tc,(%a0)
	move.l	(%a0),%d7
	moveq	#0,%d6
	lea	n_tcinvE(%pc),%a0
	bsr	check
	moveq	#0,%d7
	move.w	exv(%pc),%d7
	cmp.w	#0xe0,%d7
	beq	1f
	lea	ndev(%pc),%a0
	addq.w	#1,(%a0)
	lea	s_dev(%pc),%a0
	bsr	puts
	lea	n_tcinvX(%pc),%a0
	bsr	puts
	move.l	%d7,%d0
	bsr	puthex
	lea	s_nl(%pc),%a0
	bra	puts
1:	move.l	%d7,%d6
	lea	n_tcinvX(%pc),%a0
	bra	check
T_tcreset: rts				| reserved: reset behaviour needs a reboot, see PMMU_TESTING.md
| 9.8 p9-65: MMU instructions are privileged: user mode -> privilege violation (vector 8, $20)
T_priv:	lea	exv(%pc),%a0
	clr.w	(%a0)
	lea	ustk2_end(%pc),%a0
	move.l	%a0,%usp
	lea	priv_i(%pc),%a1
	lea	expc(%pc),%a2
	move.l	%a1,(%a2)
	lea	tmp(%pc),%a0
	andi.w	#0xdfff,%sr		| -> user mode
priv_i:	pmove	%tc,(%a0)		| handler returns to supervisor mode after it
	moveq	#0,%d7
	move.w	exv(%pc),%d7
	moveq	#0x20,%d6
	lea	n_priv(%pc),%a0
	bra	check
| 9.7.3 p9-57 + 11.x: TT0/TT1 match with CI=1 -> cache inhibited. Measured with the 200 Hz timer:
| a loop with caches on, then with TT0 (CI, all FC) over the loop, then TT1, then TT0 not matching (FC mask 0).
T_ttci:	move.l	#0x3111,%d0		| ICache+DCache on, burst bits as TOS would
	movec	%d0,%cacr
	moveq	#0,%d0
	bsr	ttloop
	move.l	%d0,%d5			| cached ticks
	lea	n_tm0(%pc),%a0
	bsr	puts
	move.l	%d5,%d0
	bsr	putdec
	lea	s_nl(%pc),%a0
	bsr	puts
	lea	ttloop(%pc),%a0
	move.l	%a0,%d1
	and.l	#0xff000000,%d1
	or.l	#0x00008507,%d1		| E, CI, RWM, FC mask 7
	lea	tmp(%pc),%a0
	move.l	%d1,(%a0)
	pmove	(%a0),%tt0
	bsr	ttloop
	move.l	%d0,%d4
	clr.l	(%a0)
	lea	tmp(%pc),%a0
	clr.l	(%a0)
	pmove	(%a0),%tt0
	lea	n_tm1(%pc),%a0
	bsr	ratio
	lea	tmp(%pc),%a0
	move.l	%d1,(%a0)
	pmove	(%a0),%tt1
	bsr	ttloop
	move.l	%d0,%d4
	lea	tmp(%pc),%a0
	clr.l	(%a0)
	pmove	(%a0),%tt1
	lea	n_tm2(%pc),%a0
	bsr	ratio
	and.l	#0xfffffff8,%d1		| FC mask 0, FC base 0: never matches (no FC0 accesses)
	lea	tmp(%pc),%a0
	move.l	%d1,(%a0)
	pmove	(%a0),%tt0
	bsr	ttloop
	move.l	%d0,%d4
	lea	tmp(%pc),%a0
	clr.l	(%a0)
	pmove	(%a0),%tt0
	lea	n_tm3(%pc),%a0
	bsr	puts
	move.l	%d4,%d0
	bsr	putdec
	lea	s_nl(%pc),%a0
	bsr	puts
	move.l	%d5,%d6			| expect within 25% of cached
	lsr.l	#2,%d6
	add.l	%d5,%d6
	moveq	#0,%d7			| PASS if d4 <= d6
	cmp.l	%d6,%d4
	bls	1f
	moveq	#1,%d7
1:	moveq	#0,%d6
	lea	n_tm4(%pc),%a0
	bra	check
| d4 = ticks with TT, d5 = cached; PASS if d4 >= 2*d5
ratio:	move.l	%a0,-(%sp)
	bsr	puts
	move.l	%d4,%d0
	bsr	putdec
	lea	s_nl(%pc),%a0
	bsr	puts
	move.l	(%sp)+,%a0
	move.l	%d5,%d6
	add.l	%d6,%d6
	moveq	#0,%d7
	cmp.l	%d6,%d4
	bcc	1f
	moveq	#1,%d7
1:	moveq	#0,%d6
	lea	n_tmr(%pc),%a0
	bra	check
| loop: returns 200 Hz ticks in d0 (preserves d1)
ttloop:	move.l	0x4ba,%d2
1:	cmp.l	0x4ba,%d2
	beq	1b
	move.l	0x4ba,%d2
	move.l	#1000000,%d3
2:	subq.l	#1,%d3
	bne	2b
	move.l	0x4ba,%d0
	sub.l	%d2,%d0
	rts

| exception handlers: record vector offset, skip the 4-byte instruction if the stacked PC = expc,
| return in supervisor mode
h_exc8:	move.w	#0x20,-(%sp)
	bra	hcom
h_exc2c: move.w	#0x2c,-(%sp)
	bra	hcom
h_exce0: move.w	#0xe0,-(%sp)
hcom:	move.l	%a0,-(%sp)
	lea	exv(%pc),%a0
	move.w	4(%sp),(%a0)
	move.l	8(%sp),%a0		| stacked PC (frame starts at sp+6)
	cmp.l	expc(%pc),%a0
	bne	1f
	addq.l	#4,8(%sp)
1:	or.w	#0x2000,6(%sp)		| back to supervisor
	move.l	(%sp)+,%a0
	addq.l	#2,%sp
	rte

| ---- output: append to outbuf and print with Cconws ----
puts:	movem.l	%d0/%a0-%a2,-(%sp)
	move.l	%a0,%a2
	move.l	outp(%pc),%a1
1:	move.b	(%a0)+,(%a1)+
	bne	1b
	subq.l	#1,%a1
	lea	outp(%pc),%a0
	move.l	%a1,(%a0)
	move.l	%a2,%a0
	bsr	conws
	movem.l	(%sp)+,%d0/%a0-%a2
	rts
conws:	movem.l	%d0-%d2/%a0-%a2,-(%sp)
	move.l	%a0,-(%sp)
	move.w	#9,-(%sp)
	trap	#1
	addq.l	#6,%sp
	movem.l	(%sp)+,%d0-%d2/%a0-%a2
	rts
puthex:	movem.l	%d0-%d2/%a0,-(%sp)
	lea	numbuf(%pc),%a0
	moveq	#7,%d2
1:	rol.l	#4,%d0
	move.b	%d0,%d1
	and.w	#15,%d1
	move.b	hexd(%pc,%d1.w),(%a0)+
	dbra	%d2,1b
	clr.b	(%a0)
	lea	numbuf(%pc),%a0
	bsr	puts
	movem.l	(%sp)+,%d0-%d2/%a0
	rts
hexd:	.ascii	"0123456789ABCDEF"
putdec:	movem.l	%d0-%d2/%a0,-(%sp)
	lea	numbuf+12(%pc),%a0
	clr.b	-(%a0)
	and.l	#0xffff,%d0
1:	divu	#10,%d0
	swap	%d0
	add.b	#'0',%d0
	move.b	%d0,-(%a0)
	clr.w	%d0
	swap	%d0
	bne	1b
	bsr	puts
	movem.l	(%sp)+,%d0-%d2/%a0
	rts
savefile: lea	outbuf(%pc),%a0
	move.l	outp(%pc),%d3
	sub.l	%a0,%d3
	clr.w	-(%sp)
	pea	fname(%pc)
	move.w	#60,-(%sp)		| Fcreate
	trap	#1
	addq.l	#8,%sp
	tst.w	%d0
	bmi	1f
	move.w	%d0,%d4
	pea	outbuf(%pc)
	move.l	%d3,-(%sp)
	move.w	%d4,-(%sp)
	move.w	#64,-(%sp)		| Fwrite
	trap	#1
	lea	12(%sp),%sp
	move.w	%d4,-(%sp)
	move.w	#62,-(%sp)		| Fclose
	trap	#1
	addq.l	#4,%sp
1:	rts

s_title: .asciz	"\33EPMMUTEST stage 1 (MC68030UM)\r\n"
s_pass:	.asciz	"PASS "
s_fail:	.asciz	"FAIL "
s_dev:	.asciz	"DEV  "
s_exp:	.asciz	" exp="
s_got:	.asciz	" got="
s_nl:	.asciz	"\r\n"
s_sum1:	.asciz	"FAILS="
s_sum2:	.asciz	" DEVS="
s_key:	.asciz	"press a key\r\n"
n_tc:	.asciz	"TC mask p9-52"
n_tt0:	.asciz	"TT0 mask p9-57"
n_tt1:	.asciz	"TT1 mask p9-57"
n_mmusr: .asciz	"MMUSR mask p9-59"
n_crph:	.asciz	"CRP hi p9-54"
n_crpl:	.asciz	"CRP lo p9-54"
n_srph:	.asciz	"SRP hi p9-54"
n_srpl:	.asciz	"SRP lo p9-54"
n_tcinvE: .asciz "TC invalid E=0 p9-53"
n_tcinvX: .asciz "TC invalid -> vec 56 (p9-64) got vector off="
n_priv:	.asciz	"user PMOVE -> priv viol p9-65"
n_tm0:	.asciz	"     ticks cached     "
n_tm1:	.asciz	"     ticks TT0 CI     "
n_tm2:	.asciz	"     ticks TT1 CI     "
n_tm3:	.asciz	"     ticks TT0 nomatch "
n_tmr:	.asciz	"TT CI slows loop >=2x p9-57"
n_tm4:	.asciz	"TT FC no-match stays cached"
fname:	.asciz	"PMMUTEST.TXT"
	.even
nfail:	.word	0
ndev:	.word	0
exv:	.word	0
	.even
expc:	.long	0
oldssp:	.long	0
outp:	.long	0
tmp:	.long	0,0
sv:	.space	48
numbuf:	.space	16
outbuf:	.space	4096
	.space	1024
ustk2_end:
	.space	2048
ustk_end:
	.space	2048
sstk_end:
