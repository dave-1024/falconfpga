| SYSDUMP.PRG - AUTO, before MINT030.PRG: system variables, cookie jar and free memory, to A:\SYSDUMP.TXT,
| so the board and Hatari can be compared (F85 MiNT allocation lead).
	.globl	_start
_start:	lea	buf(%pc),%a4
	clr.l	-(%sp)
	move.w	#0x20,-(%sp)		| Super(0)
	trap	#1
	addq.l	#6,%sp
	move.l	%d0,%d7
	lea	vars(%pc),%a3
1:	move.w	(%a3)+,%d6		| address (word, sign-extended), 0 = end
	beq	2f
	move.w	%d6,%d0
	ext.l	%d0
	bsr	puthex
	move.b	#'=',(%a4)+
	move.w	%d6,%a0
	move.l	(%a0),%d0
	bsr	puthex
	bsr	nl
	bra	1b
2:	move.b	#'V',(%a4)+		| video base hi/mid/lo, shifter mode
	move.b	#'=',(%a4)+
	moveq	#0,%d0
	move.b	0xffff8201.w,%d0
	lsl.l	#8,%d0
	move.b	0xffff8203.w,%d0
	lsl.l	#8,%d0
	move.b	0xffff820d.w,%d0
	bsr	puthex
	move.b	#' ',(%a4)+
	moveq	#0,%d0
	move.b	0xffff8260.w,%d0
	bsr	puthex
	bsr	nl
	lea	s_ck(%pc),%a0		| cookies
	bsr	puts
	move.l	0x5a0.w,%a3
	move.l	%a3,%d0
	bsr	puthex
	bsr	nl
	move.l	%a3,%d0
	beq	4f
	moveq	#63,%d5
3:	move.l	(%a3)+,%d0
	beq	4f
	move.l	%d0,(%a4)+
	move.b	#'=',(%a4)+
	move.l	(%a3)+,%d0
	bsr	puthex
	bsr	nl
	dbra	%d5,3b
4:	move.l	(%a3),%d0		| end marker value = jar size
	lea	s_sz(%pc),%a0
	bsr	puts
	bsr	puthex
	bsr	nl
	move.l	%d7,-(%sp)
	move.w	#0x20,-(%sp)
	trap	#1
	addq.l	#6,%sp
	lea	s_m1(%pc),%a0		| Malloc(-1)
	bsr	puts
	pea	-1.w
	move.w	#0x48,-(%sp)
	trap	#1
	addq.l	#6,%sp
	bsr	puthex
	bsr	nl
	moveq	#0,%d5			| Mxalloc(-1, 0..3)
5:	lea	s_mx(%pc),%a0
	bsr	puts
	move.l	%d5,%d0
	bsr	puthex
	move.b	#'=',(%a4)+
	move.w	%d5,-(%sp)
	pea	-1.w
	move.w	#0x44,-(%sp)
	trap	#1
	addq.l	#8,%sp
	bsr	puthex
	bsr	nl
	addq.w	#1,%d5
	cmp.w	#4,%d5
	bne	5b
	lea	s_bp(%pc),%a0		| own basepage (TPA start) and TPA end
	bsr	puts
	move.l	4(%sp),%a0
	move.l	(%a0),%d0
	bsr	puthex
	move.b	#' ',(%a4)+
	move.l	4(%a0),%d0
	bsr	puthex
	bsr	nl
	clr.w	-(%sp)			| write file
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
| phystop membot memtop v_bas_ad screenpt bootdev drvbits sysbase _cmdload? p_cookies ramtop ramvalid longframe/_cpu(59E) themd($48E) hz_200
vars:	.word	0x42e,0x432,0x436,0x44e,0x45e,0x446,0x4c2,0x4c4,0x4f2,0x5a0,0x5a4,0x5a8,0x59e,0x48e,0x492,0x496,0x49a,0x4ba,0
hexd:	.ascii	"0123456789ABCDEF"
fn:	.asciz	"A:\\SYSDUMP.TXT"
s_ck:	.asciz	"cookies@"
s_sz:	.asciz	"jar end value="
s_m1:	.asciz	"Malloc(-1)="
s_mx:	.asciz	"Mxalloc(-1,"
s_bp:	.asciz	"TPA="
s_nl:	.asciz	"\r\n"
	.even
buf:	.space	2048
