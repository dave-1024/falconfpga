	.text
	pea	m0(%pc); move.w #9,-(%sp); trap #1; addq.l #6,%sp
	move.l	#65536,-(%sp); move.w #0x48,-(%sp); trap #1; addq.l #6,%sp
	move.l	%d0,%a5
	tst.l	%d0; beq	err
	clr.w	-(%sp); pea src(%pc); move.w #0x3d,-(%sp); trap #1; addq.l #8,%sp
	move.w	%d0,%d6; bmi	err
	clr.w	-(%sp); pea dst(%pc); move.w #0x3c,-(%sp); trap #1; addq.l #8,%sp
	move.w	%d0,%d7; bmi	err
	moveq	#0,%d5
lp:	move.l	%a5,-(%sp); move.l #65536,-(%sp); move.w %d6,-(%sp); move.w #0x3f,-(%sp); trap #1; lea 12(%sp),%sp
	tst.l	%d0; bmi err; beq dn
	move.l	%d0,%d4; add.l %d0,%d5
	move.l	%a5,-(%sp); move.l %d4,-(%sp); move.w %d7,-(%sp); move.w #0x40,-(%sp); trap #1; lea 12(%sp),%sp
	cmp.l	%d4,%d0; bne err
	bra	lp
dn:	move.w	%d7,-(%sp); move.w #0x3e,-(%sp); trap #1; addq.l #4,%sp
	cmp.l	#526047,%d5; bne err
	pea	m1(%pc); move.w #9,-(%sp); trap #1; addq.l #6,%sp
	bra	ex
err:	pea	m2(%pc); move.w #9,-(%sp); trap #1; addq.l #6,%sp
ex:	move.w	#1000,%d7
vs:	move.w	#37,-(%sp); trap #14; addq.l #2,%sp
	dbra	%d7,vs
	clr.w	-(%sp); trap #1
m0:	.asciz	"KMCOPY: A:\\XAAES.KM -> C:\r\n"
m1:	.asciz	"KMCOPY OK 526047 bytes. Remove floppy, reset.\r\n"
m2:	.asciz	"KMCOPY ERROR\r\n"
src:	.asciz	"A:\\XAAES.KM"
dst:	.asciz	"C:\\MINT\\1-19-4A6\\XAAES\\XAAES.KM"
	.even
