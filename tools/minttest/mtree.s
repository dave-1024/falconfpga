| MTREE.PRG - MiNT 1.19 mint030 page-table layout and TC on the board, under TOS (no MiNT):
| TC $80D04447 (PS 8K, IS 0, TIA/TIB/TIC/TID 4/4/4/7), CRP $7FFF0003 -> long table A, all long
| descriptors with MiNT's unused bits set (page $7FFFFC19, CI page $7FFFFC59, pointer $7FFFFC0B).
| Identity map of 4 MB ST RAM (8K pages), $400000-$DFFFFF and $E0/$F0 1 MB early-termination pages at C,
| A[1..14] 256 MB pages, A[15] -> BF table (CI pages, BF[15] = B0[0]). Runs translated with
| interrupts at IPL 3 for ~2 s (200 Hz ticks), sums RAM, turns TC off, writes A:\MTREE.TXT.
| Step files A:\MT_<n>.TXT mark progress (1 tables built, 2 TC on returned, 3 TC off).
	.globl	_start
_start:	move.l	4(%sp),%a5
	move.l	#0x100,%d0
	add.l	12(%a5),%d0
	add.l	20(%a5),%d0
	add.l	28(%a5),%d0
	move.l	%d0,-(%sp)
	move.l	%a5,-(%sp)
	clr.w	-(%sp)
	move.w	#0x4a,-(%sp)
	trap	#1
	lea	12(%sp),%sp
	move.l	#0x5000,-(%sp)		| Malloc 20 KB for tables
	move.w	#0x48,-(%sp)
	trap	#1
	addq.l	#6,%sp
	add.l	#255,%d0
	and.w	#0xff00,%d0
	move.l	%d0,%a4			| a4 = A, +$80 B0, +$100 BF, +$180 C, +$200.. D0..D3 (each $400)
	moveq	#'1',%d7
| A
	move.l	%a4,%a0
	move.l	#0x7ffffc0b,(%a0)+
	lea	0x80(%a4),%a1
	move.l	%a1,(%a0)+
	moveq	#1,%d1
1:	move.l	#0x7ffffd19,(%a0)+	| s_page (S=1), 256 MB
	move.l	%d1,%d2
	ror.l	#4,%d2
	move.l	%d2,(%a0)+
	addq.l	#1,%d1
	cmp.w	#15,%d1
	bne	1b
	move.l	#0x7ffffc0b,(%a0)+
	lea	0x100(%a4),%a1
	move.l	%a1,(%a0)+
| B0: [0] -> C, rest invalid
	lea	0x80(%a4),%a0
	move.l	#0x7ffffc0b,(%a0)+
	lea	0x180(%a4),%a1
	move.l	%a1,(%a0)+
	moveq	#14,%d1
2:	move.l	#0x7ffffc18,(%a0)+	| invalid (DT 0)
	clr.l	(%a0)+
	dbra	%d1,2b
| BF: CI pages $Fx000000, [15] = B0[0]
	lea	0x100(%a4),%a0
	moveq	#0,%d1
3:	move.l	#0x7ffffc59,(%a0)+
	move.l	%d1,%d2
	lsl.l	#8,%d2
	lsl.l	#8,%d2
	lsl.l	#8,%d2
	or.l	#0xf0000000,%d2
	move.l	%d2,(%a0)+
	addq.l	#1,%d1
	cmp.w	#15,%d1
	bne	3b
	move.l	0x80(%a4),(%a0)+
	move.l	0x84(%a4),(%a0)+
| C: [0..3] -> D tables, [4..13] g_page 1 MB, [14] g_page $E00000, [15] ci $F00000
	lea	0x180(%a4),%a0
	lea	0x200(%a4),%a1
	moveq	#3,%d1
4:	move.l	#0x7ffffc0b,(%a0)+
	move.l	%a1,(%a0)+
	lea	0x400(%a1),%a1
	dbra	%d1,4b
	move.l	#0x400000,%d2
	moveq	#10,%d1
5:	move.l	#0x7ffffc19,(%a0)+
	move.l	%d2,(%a0)+
	add.l	#0x100000,%d2
	dbra	%d1,5b
	move.l	#0x7ffffc59,(%a0)+
	move.l	%d2,(%a0)+
| D: 512 pages of 8K identity
	lea	0x200(%a4),%a0
	moveq	#0,%d2
	move.w	#511,%d1
6:	move.l	#0x7ffffc19,(%a0)+
	move.l	%d2,(%a0)+
	add.l	#0x2000,%d2
	dbra	%d1,6b
	bsr	mark			| MT_1
| supervisor, CRP, TC on
	clr.l	-(%sp)
	move.w	#0x20,-(%sp)
	trap	#1
	addq.l	#6,%sp
	move.l	%d0,%d6
	lea	crpv(%pc),%a0
	move.l	%a4,4(%a0)
	move.w	%sr,-(%sp)
	move.w	#0x2300,%sr
	lea	nulv(%pc),%a0
	pmove	(%a0),%tc
	pmove	(%a0),%tt0
	pmove	(%a0),%tt1
	lea	crpv(%pc),%a0
	pmove	(%a0),%crp
	pflusha
	lea	tcv(%pc),%a0
	pmove	(%a0),%tc
	bsr	sub1			| bsr/rts through the translated stack, as set_mmu's rts
	move.l	0x4ba.w,%d4		| ~2 s translated, IRQs on, sum the first 1 MB
	add.l	#400,%d4
	moveq	#0,%d5
7:	move.l	#0,%a0
	move.w	#16383,%d1
8:	add.l	(%a0)+,%d5
	dbra	%d1,8b
	cmp.l	0x4ba.w,%d4
	bhi	7b
	lea	nulv(%pc),%a0
	pmove	(%a0),%tc
	move.w	(%sp)+,%sr
	move.l	%d6,-(%sp)
	move.w	#0x20,-(%sp)
	trap	#1
	addq.l	#6,%sp
	bsr	mark			| MT_3
	clr.w	-(%sp)
	pea	fn(%pc)
	move.w	#0x3c,-(%sp)
	trap	#1
	addq.l	#8,%sp
	move.w	%d0,%d3
	pea	msg(%pc)
	move.l	#msgend-msg,-(%sp)
	move.w	%d3,-(%sp)
	move.w	#0x40,-(%sp)
	trap	#1
	lea	12(%sp),%sp
	move.w	%d3,-(%sp)
	move.w	#0x3e,-(%sp)
	trap	#1
	addq.l	#4,%sp
	clr.w	-(%sp)
	trap	#1
sub1:	rts
| mark: create A:\MT_<d7>.TXT (in supervisor or user mode; TOS GEMDOS only with TC off)
mark:	lea	mfn+6(%pc),%a0
	move.b	%d7,(%a0)
	clr.w	-(%sp)
	pea	mfn(%pc)
	move.w	#0x3c,-(%sp)
	trap	#1
	addq.l	#8,%sp
	tst.l	%d0
	bmi	1f
	move.w	%d0,-(%sp)
	move.w	#0x3e,-(%sp)
	trap	#1
	addq.l	#4,%sp
1:	addq.b	#2,%d7
	rts
	.even
nulv:	.long	0
tcv:	.long	0x80d04447
crpv:	.long	0x7fff0003,0
fn:	.asciz	"A:\\MTREE.TXT"
mfn:	.asciz	"A:\\MT_0.TXT"
msg:	.ascii	"MTREE: MiNT table layout + TC $80D04447 ran ~2 s translated with IRQs and returned\r\n"
msgend:
	.even
