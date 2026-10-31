| TTMEM.PRG: TT-RAM pattern test (Mxalloc alt-only), 6 passes, prints errors
	.text
	lea	out(%pc),%a5
	move.w	#1,-(%sp)
	pea	-1
	move.w	#0x44,-(%sp)
	trap	#1
	addq.l	#8,%sp
	sub.l	#65536,%d0
	and.l	#0xfffffff0,%d0
	move.l	%d0,%d5			| size
	move.w	#1,-(%sp)
	move.l	%d0,-(%sp)
	move.w	#0x44,-(%sp)
	trap	#1
	addq.l	#8,%sp
	move.l	%d0,%a4			| base
	move.b	#'B',(%a5)+
	bsr	hex8
	move.b	#' ',(%a5)+
	move.l	%d5,%d0
	bsr	hex8
	bsr	crlf
	moveq	#0,%d7			| total errors
	lea	nerr(%pc),%a6
	moveq	#0,%d6			| pass
pass:	move.l	%d6,%d0
	mulu.l	#0x9E3779B9,%d0
	move.l	%d0,%d4			| xor key
| write: pass even = move.l, odd = movem 8 longs
	move.l	%a4,%a0
	move.l	%d5,%d3
	lsr.l	#5,%d3			| 32-byte blocks
	btst	#0,%d6
	bne	wm
w1:	moveq	#7,%d2
w2:	move.l	%a0,%d0
	eor.l	%d4,%d0
	move.l	%d0,(%a0)+
	dbra	%d2,w2
	subq.l	#1,%d3
	bne	w1
	bra	rd
wm:	move.l	%a0,%d0
	eor.l	%d4,%d0
	move.l	%d0,%d1
	not.l	%d1
	move.l	%d0,%a1
	movem.l	%d0-%d1,(%a0)
	addq.l	#8,%a0
	move.l	%a0,%d0
	eor.l	%d4,%d0
	move.l	%d0,%d1
	not.l	%d1
	movem.l	%d0-%d1,(%a0)
	addq.l	#8,%a0
	move.l	%a0,%d0
	eor.l	%d4,%d0
	move.l	%d0,%d1
	not.l	%d1
	movem.l	%d0-%d1,(%a0)
	addq.l	#8,%a0
	move.l	%a0,%d0
	eor.l	%d4,%d0
	move.l	%d0,%d1
	not.l	%d1
	movem.l	%d0-%d1,(%a0)
	addq.l	#8,%a0
	subq.l	#1,%d3
	bne	wm
| read and compare
rd:	move.l	%a4,%a0
	move.l	%d5,%d3
	lsr.l	#2,%d3
r1:	move.l	%a0,%d0
	btst	#0,%d6
	beq	r2
	btst	#2,%d0
	beq	r2
	subq.l	#4,%d0			| odd pass: odd longs hold ~(addr-4 ^ key)
	eor.l	%d4,%d0
	not.l	%d0
	bra	r3
r2:	eor.l	%d4,%d0
r3:	move.l	(%a0)+,%d1
	cmp.l	%d0,%d1
	beq	r4
	addq.l	#1,%d7
	cmp.l	#12,%d7
	bgt	r4
	move.l	%d0,-(%sp)
	move.l	%a0,%d0
	subq.l	#4,%d0
	bsr	hex8
	move.b	#' ',(%a5)+
	move.l	(%sp)+,%d0
	bsr	hex8
	move.b	#' ',(%a5)+
	move.l	%d1,%d0
	bsr	hex8
	bsr	crlf
r4:	subq.l	#1,%d3
	bne	r1
	addq.l	#1,%d6
	cmp.l	#6,%d6
	bne	pass
	move.b	#'E',(%a5)+
	move.l	%d7,%d0
	bsr	hex8
	lea	okm(%pc),%a0
	tst.l	%d7
	beq	cp
	lea	badm(%pc),%a0
cp:	move.b	(%a0)+,(%a5)+
	bne	cp
	pea	out(%pc)
	move.w	#9,-(%sp)
	trap	#1
	addq.l	#6,%sp
	move.w	#7,-(%sp)
	trap	#1
	addq.l	#2,%sp
	clr.w	-(%sp)
	trap	#1
crlf:	move.b	#13,(%a5)+
	move.b	#10,(%a5)+
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
okm:	.asciz	" TTMEM PASS\r\n"
badm:	.asciz	" TTMEM FAIL\r\n"
	.even
nerr:	.long	0
out:	.ds.b	1024
