| PROBE2.PRG - step markers for the board MiNT stop (MiNT's last TOS calls before
| "Installing BIOS keyboard table" in Hatari: Iorec(1), Rsconf(-2,..), Rsconf(1,..), Keytbl, Kbrate).
| Each finished step creates A:\P2_<n>.TXT, so the last file shows where it stops.
	.globl	_start
_start:	moveq	#'1',%d7
	bsr	mark
	move.w	#1,-(%sp)		| Iorec(1)
	move.w	#14,-(%sp)
	trap	#14
	addq.l	#4,%sp
	bsr	mark			| 2
	clr.l	-(%sp)			| Super
	move.w	#0x20,-(%sp)
	trap	#1
	addq.l	#6,%sp
	move.l	%d0,%d6
	lea	0xfffffa01.w,%a2
	movep.l	40(%a2),%d5		| as TOS Rsconf at $E0274C
	move.l	%d6,-(%sp)
	move.w	#0x20,-(%sp)
	trap	#1
	addq.l	#6,%sp
	bsr	mark			| 3
	move.l	#-1,-(%sp)		| Rsconf(-2,-1,-1,-1,-1,-1)
	move.l	#-1,-(%sp)
	move.l	#-1,-(%sp)
	move.w	#-2,-(%sp)
	move.w	#15,-(%sp)
	trap	#14
	lea	16(%sp),%sp
	bsr	mark			| 4
	move.l	#-1,-(%sp)		| Rsconf(1,$6756,$6AAE,-1,-1,-1) as MiNT in Hatari
	move.w	#-1,-(%sp)
	move.w	#0x6AAE,-(%sp)
	move.w	#0x6756,-(%sp)
	move.w	#1,-(%sp)
	move.w	#15,-(%sp)
	trap	#14
	lea	14(%sp),%sp
	bsr	mark			| 5
	move.l	#-1,-(%sp)		| Keytbl(-1,-1,-1)
	move.l	#-1,-(%sp)
	move.l	#-1,-(%sp)
	move.w	#16,-(%sp)
	trap	#14
	lea	14(%sp),%sp
	bsr	mark			| 6
	move.l	#0xffffffff,-(%sp)	| Kbrate(-1,-1)
	move.w	#35,-(%sp)
	trap	#14
	addq.l	#6,%sp
	bsr	mark			| 7
	clr.w	-(%sp)
	trap	#1
mark:	lea	fn+6(%pc),%a0
	move.b	%d7,(%a0)
	clr.w	-(%sp)
	pea	fn(%pc)
	move.w	#0x3c,-(%sp)
	trap	#1
	addq.l	#8,%sp
	tst.l	%d0
	bmi	1f
	move.w	%d0,-(%sp)
	move.w	#0x3e,-(%sp)
	trap	#1
	addq.l	#4,%sp
1:	addq.b	#1,%d7
	rts
fn:	.asciz	"A:\\P2_0.TXT"
	.even
