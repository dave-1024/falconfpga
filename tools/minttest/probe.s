| PROBE.PRG - AUTO probe before MINT030.PRG (diagnostic for the board MiNT stop):
| records Bcostat(AUX), how many of 64 AUX bytes are accepted (polling Bcostat, bounded),
| MFP TSR/RSR/UCR, CACR before/after the writes MiNT's ccw_set does, and writes A:\PROBE.TXT.
	.globl	_start
_start:	lea	buf(%pc),%a4
	move.w	#1,-(%sp)		| Bcostat(1)
	move.w	#8,-(%sp)
	trap	#13
	addq.l	#4,%sp
	lea	s_bco(%pc),%a0
	bsr	puts
	bsr	puthex
	bsr	nl
| try 64 bytes to AUX, give up on a byte after 20000 Bcostat polls
	moveq	#0,%d6			| accepted
	moveq	#63,%d5
1:	move.l	#20000,%d4
2:	move.w	#1,-(%sp)
	move.w	#8,-(%sp)
	trap	#13
	addq.l	#4,%sp
	tst.w	%d0
	bne	3f
	subq.l	#1,%d4
	bne	2b
	bra	4f
3:	move.w	#'.',-(%sp)
	move.w	#1,-(%sp)
	move.w	#3,-(%sp)		| Bconout(1,'.')
	trap	#13
	addq.l	#6,%sp
	addq.l	#1,%d6
	dbra	%d5,1b
4:	lea	s_acc(%pc),%a0
	bsr	puts
	move.l	%d6,%d0
	bsr	puthex
	bsr	nl
| supervisor part
	clr.l	-(%sp)
	move.w	#0x20,-(%sp)		| Super(0)
	trap	#1
	addq.l	#6,%sp
	move.l	%d0,%d7
	moveq	#0,%d0
	move.b	0xfffffa2d.w,%d0	| TSR
	lsl.l	#8,%d0
	move.b	0xfffffa2b.w,%d0	| RSR
	lsl.l	#8,%d0
	move.b	0xfffffa29.w,%d0	| UCR
	lea	s_mfp(%pc),%a0
	bsr	puts
	bsr	puthex
	bsr	nl
	movec	%cacr,%d0
	move.l	%d0,%d3
	lea	s_c0(%pc),%a0
	bsr	puts
	bsr	puthex
	bsr	nl
	move.l	#0x0808,%d0		| clear + disable (MiNT CACHE_OFF style)
	movec	%d0,%cacr
	movec	%cacr,%d0
	lea	s_c1(%pc),%a0
	bsr	puts
	bsr	puthex
	bsr	nl
	move.l	#0x3111,%d0		| WA|DBE|ED|IBE|EI (all on)
	movec	%d0,%cacr
	movec	%cacr,%d0
	lea	s_c2(%pc),%a0
	bsr	puts
	bsr	puthex
	bsr	nl
	movec	%d3,%cacr
	movec	%vbr,%d0
	lea	s_vbr(%pc),%a0
	bsr	puts
	bsr	puthex
	bsr	nl
	move.l	%d7,-(%sp)
	move.w	#0x20,-(%sp)
	trap	#1
	addq.l	#6,%sp
| write file
	clr.w	-(%sp)
	pea	fn(%pc)
	move.w	#0x3c,-(%sp)
	trap	#1
	addq.l	#8,%sp
	tst.l	%d0
	bmi	9f
	move.w	%d0,%d3
	pea	buf(%pc)
	move.l	%a4,%d0
	lea	buf(%pc),%a0
	sub.l	%a0,%d0
	move.l	%d0,-(%sp)
	move.w	%d3,-(%sp)
	move.w	#0x40,-(%sp)
	trap	#1
	lea	12(%sp),%sp
	move.w	%d3,-(%sp)
	move.w	#0x3e,-(%sp)
	trap	#1
	addq.l	#4,%sp
9:	clr.w	-(%sp)
	trap	#1
nl:	lea	s_nl(%pc),%a0
puts:	move.b	(%a0)+,(%a4)+
	bne	puts
	subq.l	#1,%a4
	rts
puthex:	movem.l	%d0-%d2,-(%sp)
	moveq	#7,%d2
1:	rol.l	#4,%d0
	move.w	%d0,%d1
	and.w	#15,%d1
	move.b	hexd(%pc,%d1.w),(%a4)+
	dbra	%d2,1b
	movem.l	(%sp)+,%d0-%d2
	rts
hexd:	.ascii	"0123456789ABCDEF"
fn:	.asciz	"A:\\PROBE.TXT"
s_bco:	.asciz	"Bcostat(AUX)="
s_acc:	.asciz	"AUX bytes accepted of 64="
s_mfp:	.asciz	"MFP TSR/RSR/UCR="
s_c0:	.asciz	"CACR at entry="
s_c1:	.asciz	"CACR after $0808="
s_c2:	.asciz	"CACR after $3111="
s_vbr:	.asciz	"VBR="
s_nl:	.asciz	"\r\n"
	.even
buf:	.space	512
