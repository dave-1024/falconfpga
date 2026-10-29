| at xaaes.km text+0x10886; site text+0x6ceb8 (move.l d0,-(sp); move.l a2,-(sp); movea.l (408,a0),a0; jsr (a0))
| checks the strcpy destination a2 BEFORE strcpy. Bad (>=0x2000000) -> write fault at AA=(d2.w<<28)+a2, PC inside km.
	.text
h:	lea	slot(%pc),%a1
	move.l	(%sp)+,(%a1)
	move.l	%d0,-(%sp)
	move.l	%a2,-(%sp)
	cmpa.l	#0x2000000,%a2
	bcs.s	ok
	moveq	#0,%d1
	move.w	%d2,%d1
	ror.l	#4,%d1
	add.l	%a2,%d1
	move.l	%d1,%a1
	move.b	%d0,(%a1)
ok:	movea.l	(408,%a0),%a0
	jsr	(%a0)
	lea	slot(%pc),%a1
	move.l	(%a1),%a1
	jmp	(%a1)
	.even
slot:	.long	0
