| fnop4.s - FNOP / Line-F frame probe for the 68030 core (TOS .PRG, position independent).
| Runs FNOP ($F280 $0000) three times under Supexec with private vector 11 (Line-F) and
| vector 2 (bus error) handlers, interrupts masked. The Line-F handler records the stacked
| SR, PC and format/vector word, writes the skip address into 2(sp) and does RTE (the same
| thing AUTOFPU.BIN does). Expected on a 68030 without FPU: kind F, word 002C (format 0,
| offset $2C), stacked PC = address of the FNOP, and RTE lands on skip (ret=Y).
	.text
start:
	moveq	#2,%d7
loop:
	pea	super(%pc)
	move.w	#38,-(%sp)
	trap	#14			| Supexec
	addq.l	#6,%sp
	bsr	report
	dbra	%d7,loop
	pea	msgkey(%pc)
	move.w	#9,-(%sp)
	trap	#1
	addq.l	#6,%sp
	move.w	#7,-(%sp)		| Crawcin: wait for a key
	trap	#1
	addq.l	#2,%sp
	clr.w	-(%sp)
	trap	#1

super:
	move.w	%sr,-(%sp)
	ori.w	#0x0700,%sr
	lea	vars(%pc),%a1
	move.l	0x2c.w,(%a1)		| save vectors
	move.l	0x08.w,4(%a1)
	move.l	%sp,8(%a1)		| sp for the bus error escape
	clr.w	12(%a1)			| kind
	clr.w	14(%a1)			| format word
	clr.l	16(%a1)			| stacked pc
	clr.w	20(%a1)			| stacked sr
	clr.w	22(%a1)			| ret flag
	lea	fnop(%pc),%a0
	move.l	%a0,24(%a1)		| address of the FNOP
	lea	linef(%pc),%a0
	move.l	%a0,0x2c.w
	lea	berr(%pc),%a0
	move.l	%a0,0x08.w
	lea	skip(%pc),%a2
fnop:	.word	0xf280,0x0000		| FNOP
	move.w	#0x4e,22(%a1)		| 'N': fell through, no exception
	bra.s	out
skip:	move.w	#0x59,22(%a1)		| 'Y': RTE returned to the patched PC
out:	move.l	(%a1),0x2c.w
	move.l	4(%a1),0x08.w
	move.w	(%sp)+,%sr
	rts

linef:	lea	vars(%pc),%a1
	move.w	#0x46,12(%a1)		| 'F'
	move.w	(%sp),20(%a1)
	move.l	2(%sp),16(%a1)
	move.w	6(%sp),14(%a1)
	move.l	%a2,2(%sp)
	rte

berr:	lea	vars(%pc),%a1
	move.w	#0x42,12(%a1)		| 'B'
	move.w	(%sp),20(%a1)
	move.l	2(%sp),16(%a1)
	move.w	6(%sp),14(%a1)
	move.w	#0x58,22(%a1)		| 'X': escaped from the bus error
	move.l	8(%a1),%sp
	bra.s	out

| print "kind=K word=WWWW pc=PPPPPPPP fnop=AAAAAAAA sr=SSSS ret=R\r\n"
report:
	lea	vars(%pc),%a1
	lea	line(%pc),%a0
	move.b	13(%a1),5(%a0)
	move.w	14(%a1),%d0
	lea	12(%a0),%a3
	moveq	#3,%d1
	bsr	hex
	move.l	16(%a1),%d0
	lea	20(%a0),%a3
	moveq	#7,%d1
	bsr	hex
	move.l	24(%a1),%d0
	lea	34(%a0),%a3
	moveq	#7,%d1
	bsr	hex
	move.w	20(%a1),%d0
	lea	46(%a0),%a3
	moveq	#3,%d1
	bsr	hex
	move.b	23(%a1),55(%a0)
	move.l	%a0,-(%sp)
	move.w	#9,-(%sp)
	trap	#1
	addq.l	#6,%sp
	rts
| d0 value, d1 digits-1, a3 -> last digit position + 1 counted from the left digit
hex:	lea	1(%a3,%d1.w),%a3
1:	move.b	%d0,%d2
	andi.b	#15,%d2
	addi.b	#0x30,%d2
	cmpi.b	#0x39,%d2
	bls.s	2f
	addq.b	#7,%d2
2:	move.b	%d2,-(%a3)
	lsr.l	#4,%d0
	dbra	%d1,1b
	rts

vars:	.space	28
line:	.ascii	"kind=K word=0000 pc=00000000 fnop=00000000 sr=0000 ret=?\r\n"
	.byte	0
msgkey:	.ascii	"FNOP4 done (3 runs). Press a key.\r\n"
	.byte	0
	.even
