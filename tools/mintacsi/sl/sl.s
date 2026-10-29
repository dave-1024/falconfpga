| SLTEST.PRG: MiNT xaaes env loop: d0=strcpy ret (dest ptr); jsr strlen (ends move.l a0,d0; rts); lea (1,a2,d0.l),a2
	.text
	pea	sup(%pc)
	move.w	#38,-(%sp)
	trap	#14
	addq.l	#6,%sp
	pea	out(%pc)
	move.w	#9,-(%sp)
	trap	#1
	addq.l	#6,%sp
	move.w	#7,-(%sp)
	trap	#1
	addq.l	#2,%sp
	clr.w	-(%sp)
	trap	#1
sup:	lea	strlen(%pc),%a0
	lea	tab(%pc),%a1
	move.l	%a0,(%a1)
	lea	out(%pc),%a5
	moveq	#0,%d7
	moveq	#0,%d6			| first bad iteration
	move.w	#4999,%d5
lp:	lea	buf(%pc),%a2
	lea	str(%pc),%a0
	move.l	%a2,%d0			| d0 = dest pointer (as strcpy returns)
	pea	(%a2)
	lea	strlen(%pc),%a0
	jsr	(%a0)
	lea	(1,%a2,%d0.l),%a2
	addq.l	#4,%sp
	lea	buf+6(%pc),%a3		| strlen("hello")=5 -> buf+6
	cmp.l	%a2,%a3
	beq	ok
	addq.l	#1,%d7
	tst.l	%d6
	bne	ok
	move.l	%a2,%d6
ok:	dbra	%d5,lp
| variant 2: kentry-style indirect call through table
	move.w	#4999,%d5
lp2:	lea	buf(%pc),%a2
	move.l	%a2,%d0
	pea	(%a2)
	lea	tab(%pc),%a0
	move.l	(%a0),%a0
	jsr	(%a0)
	lea	(1,%a2,%d0.l),%a2
	addq.l	#4,%sp
	lea	buf+6(%pc),%a3
	cmp.l	%a2,%a3
	beq	ok2
	addq.l	#1,%d7
	tst.l	%d6
	bne	ok2
	move.l	%a2,%d6
ok2:	dbra	%d5,lp2
	move.b	#'E',(%a5)+
	move.l	%d7,%d0
	bsr	hex8
	move.b	#' ',(%a5)+
	move.l	%d6,%d0
	bsr	hex8
	lea	okm(%pc),%a0
	tst.l	%d7
	beq	cp
	lea	badm(%pc),%a0
cp:	move.b	(%a0)+,(%a5)+
	bne	cp
	rts
| MiNT kernel strlen (text+5246c)
strlen:	move.l	(4,%sp),%a0
	addq.l	#1,%a0
	move.l	%a0,%d0
	tst.b	(-1,%a0)
	beq.s	s2
s1:	addq.l	#1,%a0
	tst.b	(-1,%a0)
	bne.s	s1
s2:	suba.l	%d0,%a0
	move.l	%a0,%d0
	rts
hex8:	movem.l	%d0-%d3,-(%sp)
	moveq	#7,%d3
h1:	rol.l	#4,%d0
	move.b	%d0,%d1
	and.b	#15,%d1
	add.b	#'0',%d1
	cmp.b	#'9',%d1
	bls	h2
	addq.b	#7,%d1
h2:	move.b	%d1,(%a5)+
	dbra	%d3,h1
	movem.l	(%sp)+,%d0-%d3
	rts
okm:	.asciz	" SLTEST PASS\r\n"
badm:	.asciz	" SLTEST FAIL\r\n"
	.even
tab:	.long	0
buf:	.asciz	"hello"
	.ds.b	16
str:	.asciz	"x"
	.even
out:	.ds.b	256
