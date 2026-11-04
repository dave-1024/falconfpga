| lpm: DBcc loop mode (one-word body) with register-only ops; checksum to $3300.
        .org 0
        dc.l    0x2000, start
start:  move.w  #0x2700,%sr
        lea     0x1000,%sp
        moveq   #0,%d7
        moveq   #1,%d1
        move.w  #50,%d2
1:      add.l   %d1,%d7
        dbf     %d2,1b
        move.w  #40,%d2
1:      lsl.l   #1,%d1
        dbf     %d2,1b
        add.l   %d1,%d7
        moveq   #3,%d1
        move.w  #33,%d2
1:      eor.l   %d2,%d1
        dbf     %d2,1b
        add.l   %d1,%d7
        move.w  #20,%d2
        moveq   #-1,%d0
1:      tst.l   %d0
        dbeq    %d2,1b
        add.l   %d2,%d7
        move.w  #20,%d2
        moveq   #0,%d3
1:      addq.l  #2,%d3
        dbf     %d2,1b
        add.l   %d3,%d7
        move.w  #15,%d2
        moveq   #5,%d3
1:      swap    %d3
        dbf     %d2,1b
        add.l   %d3,%d7
        move.w  #12,%d2
1:      moveq   #9,%d4
        dbf     %d2,1b
        add.l   %d4,%d7
        move.w  #12,%d2
        moveq   #0,%d5
1:      cmp.l   %d5,%d2
        dbeq    %d2,1b
        add.l   %d2,%d7
        move.l  %d7,0x3300
2:      bra.s   2b
