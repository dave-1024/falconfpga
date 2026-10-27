| STAGE0.PRG - AUTO marker run before MINT030.PRG: writes A:\STAGE0.TXT so a board run shows
| that TOS reached the AUTO folder (no screen needed). PC relative, no relocations.
	.globl	_start
_start:	clr.w	-(%sp)
	pea	fn(%pc)
	move.w	#0x3c,-(%sp)
	trap	#1
	addq.l	#8,%sp
	tst.l	%d0
	bmi	1f
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
1:	clr.w	-(%sp)
	trap	#1
fn:	.asciz	"A:\\STAGE0.TXT"
msg:	.ascii	"AUTO reached, starting MINT030.PRG\r\n"
msgend:
	.even
