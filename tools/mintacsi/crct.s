| CRCT.PRG: CRC32 files on C: via GEMDOS, print + write C:\CRC.TXT
        .text
start:  lea     names(%pc),%a4          | a4 = name list
        lea     out(%pc),%a5            | a5 = text out ptr
nextf:  tst.b   (%a4)
        beq     done
        move.w  #0,-(%sp)
        move.l  %a4,-(%sp)
        move.w  #0x3d,-(%sp)            | Fopen
        trap    #1
        addq.l  #8,%sp
        move.l  %d0,%d6                 | handle
        moveq   #-1,%d7                 | crc
        moveq   #0,%d5                  | size
        tst.l   %d6
        bmi     wrname
rd:     pea     buf(%pc)
        move.l  #32768,-(%sp)
        move.w  %d6,-(%sp)
        move.w  #0x3f,-(%sp)            | Fread
        trap    #1
        lea     12(%sp),%sp
        tst.l   %d0
        ble     cls
        add.l   %d0,%d5
        lea     buf(%pc),%a0
        move.l  %d0,%d4
        subq.l  #1,%d4
byte:   moveq   #0,%d1
        move.b  (%a0)+,%d1
        eor.l   %d1,%d7
        moveq   #7,%d2
bit:    lsr.l   #1,%d7
        bcc     nb
        eor.l   #0xEDB88320,%d7
nb:     dbra    %d2,bit
        subq.l  #1,%d4
        bpl     byte
        bra     rd
cls:    move.w  %d6,-(%sp)
        move.w  #0x3e,-(%sp)            | Fclose
        trap    #1
        addq.l  #4,%sp
        not.l   %d7
wrname: move.b  (%a4)+,(%a5)+           | copy name
        bne     wrname
        move.b  #' ',-1(%a5)
        move.l  %d7,%d0
        bsr     hex8
        move.b  #' ',(%a5)+
        move.l  %d5,%d0
        bsr     hex8
        move.b  #' ',(%a5)+
        move.l  %d6,%d0
        bsr     hex8
        move.b  #13,(%a5)+
        move.b  #10,(%a5)+
        bra     nextf
done:   clr.b   (%a5)
        pea     out(%pc)
        move.w  #9,-(%sp)               | Cconws
        trap    #1
        addq.l  #6,%sp
        move.w  #0,-(%sp)
        pea     oname(%pc)
        move.w  #0x3c,-(%sp)            | Fcreate
        trap    #1
        addq.l  #8,%sp
        move.l  %d0,%d6
        bmi     quit
        lea     out(%pc),%a0
        move.l  %a5,%d0
        sub.l   %a0,%d0
        pea     out(%pc)
        move.l  %d0,-(%sp)
        move.w  %d6,-(%sp)
        move.w  #0x40,-(%sp)            | Fwrite
        trap    #1
        lea     12(%sp),%sp
        move.w  %d6,-(%sp)
        move.w  #0x3e,-(%sp)
        trap    #1
        addq.l  #4,%sp
quit:   clr.w   -(%sp)
        trap    #1
hex8:   moveq   #7,%d3
h1:     rol.l   #4,%d0
        move.b  %d0,%d1
        and.b   #15,%d1
        add.b   #'0',%d1
        cmp.b   #'9',%d1
        bls     h2
        addq.b  #7,%d1
h2:     move.b  %d1,(%a5)+
        dbra    %d3,h1
        rts
oname:  .asciz  "C:\\CRC.TXT"
names:  .asciz  "C:\\AUTO\\MINT-4A6.PRG"
        .asciz  "C:\\MINT\\1-19-4A6\\MINT030.PRG"
        .asciz  "C:\\MINT\\1-19-4A6\\XAAES\\XALOADER.PRG"
        .asciz  "C:\\MINT\\1-19-4A6\\XAAES\\XAAES.KM"
        .asciz  "C:\\MINT\\1-19-4A6\\SYS-ROOT\\OPT\\GEM\\TERADESK\\DESKTOP.PRG"
        .asciz  "C:\\MINT\\1-19-4A6\\MINT.CNF"
        .byte   0
        .even
out:    .space  1024
        .even
buf:    .space  32768
