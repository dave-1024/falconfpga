| placed at xaaes.km text+0x10886 (over the unused "no moose.adi" message)
	.text
h:	lea	slot(%pc),%a1
	move.l	(%sp)+,(%a1)
	jsr	(%a0)			| kernel strlen
	move.l	%d0,%d1			| d0 right after the return
	move.l	%a2,%a1
l:	tst.b	(%a1)+
	bne.s	l
	suba.l	%a2,%a1
	subq.l	#1,%a1			| a1 = real length
	cmp.l	%a1,%d1
	bne.s	bad1
	move.l	%a2,%a1
	lea	(1,%a2,%d0.l),%a2	| the original instruction
	addq.l	#1,%a1
	adda.l	%d1,%a1
	cmp.l	%a1,%a2
	bne.s	bad2
	adda.w	#12,%sp
	lea	slot(%pc),%a1
	move.l	(%a1),%a1
	jmp	(%a1)
bad1:	move.l	%d1,%a1			| d0 wrong on return: AA = 0x40000000 + d0
	adda.l	#0x40000000,%a1
	move.b	%d0,(%a1)
	bra.s	bad1
bad2:	move.l	%a2,%a1			| lea wrong: AA = 0x50000000 + new a2
	adda.l	#0x50000000,%a1
	move.b	%d0,(%a1)
	bra.s	bad2
	.even
slot:	.long	0
