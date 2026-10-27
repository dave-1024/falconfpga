| MPTEST.PRG - FreeMiNT memory protection test, run as INIT= from mint.cnf.
| Parent: checks Ssystem(S_OSFEATURES) bit 0 (MP on), keeps a private word "secret",
| starts a child "V<addr>" that writes to the parent's secret (must get SIGBUS/SIGSEGV from
| MiNT's memory protection: the child's handler exits with $50+signal), and three
| children "W" that run side by side and checksum their own memory (exit 0).
| Results go to the console and to X:\MPTEST.TXT (X = drive the program was found on).
| All code is PC relative; GEMDOS header without relocations (build.sh).
	.text
	.globl	_start
_start:
start:	move.l	4(%sp),%a5		| basepage
	lea	stack_top(%pc),%sp
	move.l	#0x100,%d0		| Mshrink to basepage+text+data+bss
	add.l	12(%a5),%d0
	add.l	20(%a5),%d0
	add.l	28(%a5),%d0
	move.l	%d0,-(%sp)
	move.l	%a5,-(%sp)
	clr.w	-(%sp)
	move.w	#0x4a,-(%sp)
	trap	#1
	lea	12(%sp),%sp
	lea	0x81(%a5),%a0		| command tail
	cmp.b	#'V',(%a0)
	beq	child_v
	cmp.b	#'W',(%a0)
	beq	child_w
| ---------------- parent ----------------
	lea	outbuf(%pc),%a0
	lea	outp(%pc),%a1
	move.l	%a0,(%a1)
	bsr	finddrv
	lea	s_title(%pc),%a0
	bsr	puts
				| Ssystem(S_OSFEATURES=7, 0, 0)
	clr.l	-(%sp)
	clr.l	-(%sp)
	move.w	#7,-(%sp)
	move.w	#0x154,-(%sp)
	trap	#1
	lea	12(%sp),%sp
	lea	s_feat(%pc),%a0
	bsr	puts
	bsr	puthex
	lea	s_nl(%pc),%a0
	bsr	puts
	btst	#0,%d0
	sne	%d1
	lea	n_mp(%pc),%a0
	bsr	result
| secret is in our own (private) bss
	lea	secret(%pc),%a3
	move.l	#0x5EC2E7AA,(%a3)
	lea	s_addr(%pc),%a0
	bsr	puts
	move.l	%a3,%d0
	bsr	puthex
	lea	s_nl(%pc),%a0
	bsr	puts
| child V: tail = len, 'V', 8 hex digits
	lea	tail(%pc),%a0
	move.b	#9,(%a0)+
	move.b	#'V',(%a0)+
	move.l	%a3,%d0
	moveq	#7,%d2
1:	rol.l	#4,%d0
	move.w	%d0,%d1
	and.w	#15,%d1
	move.b	hexd(%pc,%d1.w),(%a0)+
	dbra	%d2,1b
	clr.b	(%a0)
	bsr	spawn
	move.l	%d0,%d6			| pid
	lea	s_vpid(%pc),%a0
	bsr	puts
	bsr	puthex
	lea	s_nl(%pc),%a0
	bsr	puts
	move.l	%d6,%d0
	bsr	wait
	move.l	%d0,%d7
	lea	s_vst(%pc),%a0
	bsr	puts
	bsr	puthex
	lea	s_nl(%pc),%a0
	bsr	puts
	and.w	#0xffff,%d7		| exit $5A (SIGBUS) or $5B (SIGSEGV) from the child's handler
	cmp.w	#0x5A,%d7
	seq	%d1
	cmp.w	#0x5B,%d7
	seq	%d2
	or.b	%d2,%d1
	tst.l	%d6
	bgt	2f
	clr.b	%d1
2:	lea	n_viol(%pc),%a0
	bsr	result
	cmp.l	#0x5EC2E7AA,(%a3)
	seq	%d1
	lea	n_secret(%pc),%a0
	bsr	result
| three W children side by side
	lea	tail(%pc),%a0
	move.b	#1,(%a0)+
	move.b	#'W',(%a0)+
	clr.b	(%a0)
	lea	pids(%pc),%a4
	moveq	#2,%d5
3:	bsr	spawn
	move.l	%d0,(%a4)+
	dbra	%d5,3b
	lea	pids(%pc),%a4
	moveq	#2,%d5
4:	move.l	(%a4)+,%d0
	move.l	%d0,%d6
	bsr	wait
	move.l	%d0,%d7
	lea	s_wst(%pc),%a0
	bsr	puts
	bsr	puthex
	lea	s_nl(%pc),%a0
	bsr	puts
	tst.w	%d7
	seq	%d1
	tst.l	%d6
	bgt	5f
	clr.b	%d1
5:	lea	n_side(%pc),%a0
	bsr	result
	dbra	%d5,4b
| summary
	lea	s_sum(%pc),%a0
	bsr	puts
	moveq	#0,%d0
	move.w	nfail(%pc),%d0
	bsr	puthex
	lea	s_nl(%pc),%a0
	bsr	puts
	bsr	savefile
	lea	s_done(%pc),%a0
	bsr	cputs
9:	move.w	#0xff,-(%sp)		| Syield forever (we are init)
	trap	#1
	addq.l	#2,%sp
	bra	9b

| ---------------- child V ----------------
child_v: lea	0x82(%a5),%a0
	moveq	#0,%d0
	moveq	#7,%d2
1:	moveq	#0,%d1
	move.b	(%a0)+,%d1
	sub.b	#'0',%d1
	cmp.b	#9,%d1
	bls	2f
	sub.b	#7,%d1
2:	lsl.l	#4,%d0
	or.b	%d1,%d0
	dbra	%d2,1b
	move.l	%d0,%a3
	pea	vhand(%pc)		| Psignal(SIGBUS) and Psignal(SIGSEGV)
	move.w	#10,-(%sp)
	move.w	#0x112,-(%sp)
	trap	#1
	addq.l	#8,%sp
	pea	vhand11(%pc)
	move.w	#11,-(%sp)
	move.w	#0x112,-(%sp)
	trap	#1
	addq.l	#8,%sp
	move.l	#0xBADBAD00,(%a3)	| must fault
	move.w	#0x77,-(%sp)		| escaped: exit $77
	move.w	#0x4c,-(%sp)
	trap	#1
vhand:	move.w	#0x5A,-(%sp)
	move.w	#0x4c,-(%sp)
	trap	#1
vhand11: move.w	#0x5B,-(%sp)
	move.w	#0x4c,-(%sp)
	trap	#1

| ---------------- child W ----------------
child_w: lea	wbuf(%pc),%a0		| fill 16 KB with a pattern, yield, re-check, 20 rounds
	moveq	#19,%d5
1:	move.l	%a0,%a1
	move.w	#4095,%d2
	move.l	%d5,%d0
	mulu	#0x1235,%d0
2:	move.l	%d0,(%a1)+
	add.l	#0x01010101,%d0
	dbra	%d2,2b
	move.w	#0xff,-(%sp)
	trap	#1
	addq.l	#2,%sp
	lea	wbuf(%pc),%a0
	move.l	%a0,%a1
	move.w	#4095,%d2
	move.l	%d5,%d0
	mulu	#0x1235,%d0
3:	cmp.l	(%a1)+,%d0
	bne	8f
	add.l	#0x01010101,%d0
	dbra	%d2,3b
	dbra	%d5,1b
	clr.w	-(%sp)
	move.w	#0x4c,-(%sp)
	trap	#1
8:	move.w	#0x66,-(%sp)
	move.w	#0x4c,-(%sp)
	trap	#1

| ---------------- helpers ----------------
| finddrv: progname = "A:\MPTEST.PRG" if it exists, else C:
finddrv: lea	pname(%pc),%a0
	moveq	#'A',%d3
1:	move.b	%d3,(%a0)
	lea	lname(%pc),%a1
	move.b	%d3,(%a1)
	clr.w	-(%sp)
	move.l	%a0,-(%sp)
	move.w	#0x3d,-(%sp)		| Fopen
	trap	#1
	addq.l	#8,%sp
	tst.l	%d0
	bmi	2f
	move.w	%d0,-(%sp)
	move.w	#0x3e,-(%sp)
	trap	#1
	addq.l	#4,%sp
	rts
2:	addq.b	#1,%d3
	cmp.b	#'D',%d3
	bne	1b
	rts
| spawn: Pexec(100, pname, tail, 0) -> d0 pid
spawn:	clr.l	-(%sp)
	pea	tail(%pc)
	pea	pname(%pc)
	move.w	#100,-(%sp)
	move.w	#0x4b,-(%sp)
	trap	#1
	lea	16(%sp),%sp
	rts
| wait: Pwaitpid(d0, 0, 0) -> d0
wait:	clr.l	-(%sp)
	clr.w	-(%sp)
	move.w	%d0,-(%sp)
	move.w	#0x13a,-(%sp)
	trap	#1
	lea	10(%sp),%sp
	rts
| result: a0 = name, d1.b = $FF pass
result:	move.l	%a0,-(%sp)
	tst.b	%d1
	bne	1f
	lea	nfail(%pc),%a0
	addq.w	#1,(%a0)
	lea	s_fail(%pc),%a0
	bra	2f
1:	lea	s_pass(%pc),%a0
2:	bsr	puts
	move.l	(%sp)+,%a0
	bsr	puts
	lea	s_nl(%pc),%a0
	bra	puts
| puts: console + log buffer
puts:	movem.l	%d0-%d2/%a0-%a2,-(%sp)
	move.l	outp(%pc),%a1
	move.l	%a0,%a2
1:	move.b	(%a2)+,(%a1)+
	bne	1b
	subq.l	#1,%a1
	lea	outp(%pc),%a2
	move.l	%a1,(%a2)
	bsr	cputs
	movem.l	(%sp)+,%d0-%d2/%a0-%a2
	rts
cputs:	movem.l	%d0-%d2/%a0-%a2,-(%sp)
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
	move.w	%d0,%d1
	and.w	#15,%d1
	move.b	hexd(%pc,%d1.w),(%a0)+
	dbra	%d2,1b
	clr.b	(%a0)
	lea	numbuf(%pc),%a0
	bsr	puts
	movem.l	(%sp)+,%d0-%d2/%a0
	rts
hexd:	.ascii	"0123456789ABCDEF"
savefile: lea	outbuf(%pc),%a0
	move.l	outp(%pc),%d3
	sub.l	%a0,%d3
	clr.w	-(%sp)
	pea	lname(%pc)
	move.w	#0x3c,-(%sp)		| Fcreate
	trap	#1
	addq.l	#8,%sp
	tst.l	%d0
	bmi	1f
	move.w	%d0,%d4
	pea	outbuf(%pc)
	move.l	%d3,-(%sp)
	move.w	%d4,-(%sp)
	move.w	#0x40,-(%sp)		| Fwrite
	trap	#1
	lea	12(%sp),%sp
	move.w	%d4,-(%sp)
	move.w	#0x3e,-(%sp)
	trap	#1
	addq.l	#4,%sp
1:	rts

s_title: .asciz	"MPTEST FreeMiNT memory protection (PMMU)\r\n"
s_feat:	.asciz	"Ssystem(S_OSFEATURES)="
s_addr:	.asciz	"parent secret at "
s_vpid:	.asciz	"child V pid="
s_vst:	.asciz	"child V Pwaitpid="
s_wst:	.asciz	"child W Pwaitpid="
s_pass:	.asciz	"PASS "
s_fail:	.asciz	"FAIL "
s_nl:	.asciz	"\r\n"
s_sum:	.asciz	"MPTEST FAILS="
s_done:	.asciz	"MPTEST.TXT written\r\n"
n_mp:	.asciz	"memory protection on (OSFEATURES bit 0)"
n_viol:	.asciz	"child write to parent memory -> SIGBUS/SIGSEGV, child exits $5A/$5B"
n_secret: .asciz "parent memory unchanged"
n_side:	.asciz	"W child ran side by side, own memory intact, exit 0"
pname:	.asciz	"A:\\MPTEST.PRG"
lname:	.asciz	"A:\\MPTEST.TXT"
	.even
nfail:	.word	0
	.even
outp:	.long	0
pids:	.long	0,0,0
tail:	.space	16
numbuf:	.space	12
	| (no .bss: kept in .text so PC-relative offsets match the GEMDOS layout)
	.even
secret:	.long	0
outbuf:	.space	4096
wbuf:	.space	16384
stack:	.space	4096
stack_top:
