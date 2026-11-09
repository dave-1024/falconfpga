# F157: the 3-clock issue loop (9 Nov 2026)

**Branch:** `speed` at `33ca26e` (F156). **No RTL change was committed.**

The goal was to issue register-to-register instructions in 2 clocks, matching
MC68030UM section 11 (I-cache case). F145 already raises `OW_REQ` in
`INIT_EXEC_WB` (`EARLY_ISSUE`, except ADDQ/SUBQ `#`,An). That is not enough:
MOVEQ / NOP stay at 3 clocks, MOVE.L / ADD.L / ADDQ stay at 4.

## What the third (and fourth) clocks are

A simple register op on this core is three exec-side states after it has been
decoded:

| Clock | `FETCH_STATE` | `EXEC_WB_STATE` | What happens |
|---|---|---|---|
| 0 | `START_OP` | (previous) | `OPD_ACK`; MOVEQ goes straight to `INIT_EXEC_WB` (no `DR_IN_USE` wait). |
| 1 | `INIT_EXEC_WB` | `IDLE` → `EXECUTE` | `ALU_INIT` latches operands. `ALU_REQ` is registered and rises on this edge (`P_BUSY` in `wf68k30L_alu.vhd`). Early `OW_REQ` is raised here. |
| 2 | `START_OP` (next) | `EXECUTE` | `ALU_REQ` is 1 for the whole clock. **`P_OUT` copies the ALU result into `RESULT` on this edge.** |
| 3 | `START_OP` / `INIT` (next) | `WRITEBACK` | `RESULT` is now valid. `DR_WR` / `CACR_WR` fire. `ALU_ACK` clears `ALU_BSY`. |

The next instruction’s `INIT_EXEC_WB` waits on `ALU_BSY`, so it cannot start
until clock 3 is over. Together with early `OW_REQ` that is still **3 clocks**
per MOVEQ.

A fourth clock appears when `START_OP` also waits on `DR_IN_USE`. MOVEQ skips
that wait (F141: overwrite-only). `MOVE.L Dn,Dn` and `ADD.L Dn,Dn` do not:
the dest register is checked via `DR_SEL_ADH_2`, so a write-after-write looks
like a hazard. That is the 4.00 in the F156 table.

`CMP` / `TST` have no `WRITEBACK` (`EXECUTE` → `IDLE`, `ALU_ACK` in the
`EXECUTE` clock). That is why F141 measured them at 2.38 rather than 3: they
only pay the issue handshake, plus an occasional pipe refill.

## Attempt 1: write in `EXECUTE` (wrong)

`F157_ISSUE2` folded `WRITEBACK` into `EXECUTE` for MOVEQ only: when
`ALU_REQ` was set, `NEXT_EXEC_WB_STATE` went to `IDLE` and `DR_WR` used a
`WB_CLK` that included that `EXECUTE` clock.

The speed harness then hung (`TIMEOUT`, `dbf d7,top` never expired, ~195
writes to `$3400`). A clock-by-clock dump of `FETCH_STATE`, `EXEC_WB_STATE`,
`ALU_REQ`, `ALU_ACK`, `DR_WR`, `DR_MARK_USED`, `UNMARK`, `OP_WB_I`, D7 and
CACR showed why.

Setup in `sim/speed/gen.py` is:

```
fcfff8  moveq #1,d7
fcfffa  movec d7,cacr
...
fd0016  moveq #1,d7
fd0018  top: move.w d7,$3400
...
fd003c  dbf d7,top
```

First MOVEQ write, folded into `EXECUTE` (`DR_IN1` is `ALU_RESULT`):

```
F157T D7=00000000 D0=00000000 CACR=00000000
      CACR_WR='0' DR_WR1='1' DR_IN1=XXXXXXXX OPSIZE_WB=long
      PC=00FCFFF8 BIW0=7E01 OPWB=moveq
```

The value written is **XXXXXXXX** (the previous `RESULT`, still unset). D7
becomes X. The following `movec d7,cacr` therefore writes X:

```
F157T D7=XXXXXXXX CACR_WR='1' DR_IN1=XXXXXXXX
      PC=00FCFFFA BIW0=4E7B OPWB=movec
```

CACR becomes `0000XXXX`, so the I-cache never enables. Later, after
`move.l #0x12345,d0`, the pre-loop `moveq #1,d7` writes the **stale** ALU
result `00012345` instead of 1:

```
F157T D7=XXXXXXXX D0=00000000 CACR=0000XXXX
      DR_WR1='1' DR_IN1=00012345 PC=00FD0016 BIW0=7E01 OPWB=moveq
```

`$3400` then counts `2345`, `2344`, `2343`, … — the low word of `0x12345`.
`dbf` is working; it is decrementing the wrong starting value. With
`MAXCLK=20000` that looks like a hang.

**Path that depends on `WRITEBACK`:** `P_OUT` in `wf68k30L_alu.vhd` (~1112):

```vhdl
P_OUT: process
begin
    wait until CLK = '1' and CLK'event;
    if ALU_REQ = '1' then
        RESULT <= ...;  -- MOVEQ uses OP2 & RESULT_OTHERS
    end if;
end process P_OUT;
```

`RESULT` (hence `DR_IN_1` / `DATA_IN_EXH` for CACR) is registered on the
**same** edge where `EXECUTE` has `ALU_REQ = '1'`. The register-file write
samples the old `RESULT`. `WRITEBACK` exists so the write happens one clock
later, when that register has updated.

`CACR_WR` itself is also qualified with `EXEC_WB_STATE = WRITEBACK`
(`wf68k30L_control.vhd`). Folding MOVEC (or accidentally folding it via an
out-of-range `BIW_0_WB(13 downto 12)` test — `BIW_0_WB` is only bits 11:0)
would skip the CACR write even with valid data. The MOVEQ-only fold did not
change MOVEC’s state; CACR failed because D7 was X, not because `CACR_WR`
was suppressed.

With `F157_ISSUE2` forced off, the same wiring restored F156 (`nop` 65 vs 41
→ 3.00). The switch is equivalent when down.

## Attempt 2: overlap next `INIT` with this `WRITEBACK` (correct data, still 3 clocks)

This keeps the write in `WRITEBACK` (when `RESULT` is valid) and tries to
start the next `ALU_INIT` in that same clock:

- `ALU_TRIG` may fire while `ALU_BSY = '1'` if `EXEC_WB_STATE = WRITEBACK`
  and the new `OP` is MOVEQ (MOVEQ does not read its destination, so a
  same-edge write + `ALU_INIT` does not need forwarding).
- `INIT_EXEC_WB` may leave for `START_OP` in that situation.
- `WRITEBACK` goes to `EXECUTE` rather than `IDLE` when `ALU_INIT_I = '1'`,
  so the next ALU is not dropped.
- `UNMARK` also fires on `WRITEBACK` → `EXECUTE`.

That sequence is functionally right:

```
WRITEBACK moveq: DR_WR1='1' DR_IN1=00000001   (correct)
movec WRITEBACK: D7=00000001 CACR_WR='1'        (cache on)
later:           CACR=00000001
dbf WRITEBACK:   D7=00000001 → DR_IN1=00000000
$3400 writes:    0001, then 0000, then FFFF
DONE marker at clk 344
```

It does **not** save a clock. Consecutive MOVEQs look like this (condensed):

```
INIT_EXEC_WB  EXEC=idle       ALU_INIT OW_REQ     → next START, next EXECUTE
START_OP      EXEC=execute    ALU_REQ  OPD_ACK=0  → next WRITEBACK
START_OP      EXEC=writeback  DR_WR    OPD_ACK=1  → next IDLE, next INIT
INIT_EXEC_WB  EXEC=idle       ALU_INIT            ← one clock after the write
```

`OPD_ACK` for the next MOVEQ arrives in the **writeback** clock, not the
execute clock. `FETCH` therefore enters `INIT_EXEC_WB` only after
`WRITEBACK` has already gone `IDLE`. The overlap condition (`FETCH` in
`INIT` while `EXEC` is in `WRITEBACK`) never holds.

Early `OW_REQ` is already raised in `INIT` of the current MOVEQ. The decoder
only asserts `OPD_ACK` when `OW_REQ = '1'` and `PIPE_RDY = '1'`. For a
level-D opcode `PIPE_RDY` needs `IPIPE_PNTR > 1`. Taking the current MOVEQ
pops one word, so the pipe often has a single word when the early request
is made. The next word arrives a clock later; `OPD_ACK` slips into
`WRITEBACK`. That is the same “one opcode word per two clocks” limit
described as cause 2 in `docs/SPEED_OVERHAUL.md` (F140).

So the remaining issue-loop beat is **not only** writeback occupancy. It is
writeback occupancy **plus** the pipe not being ready in time for the early
`OW_REQ` to be acknowledged during `EXECUTE`.

## Why ADD.L cannot reach 2 clocks without extra work

`add.l d1,d0` reads D0 (dest is a source) and writes D0. Back-to-back copies
are a read-after-write on D0.

If `ALU_INIT` of N+1 shares the clock edge with `WRITEBACK` of N, both the
register-file write and the ALU operand latch sample the **old** D0.
VHDL/hardware does not apply the write before the read on the same edge.
Getting the new value into that `ALU_INIT` is ALU-result forwarding, which
this attempt was not allowed to add as a workaround.

Ways to make ADD 2 clocks without a same-edge race:

1. Present `RESULT` during `EXECUTE` (see below) and write then; `ALU_INIT`
   of N+1 is the following clock and sees the written register.
2. Forward `RESULT` / `RESULT_INTOP` into the ALU operand mux when the
   next instruction reads the register being written.

## Concrete proposed design

Two pieces are both required for a 2-clock MOVEQ/MOVE.L stream. Neither is a
small, isolated control-unit fold.

### A. Keep the opcode pipe at two words during sequential issue

So that `OW_REQ` in `INIT_EXEC_WB` of N produces `OPD_ACK` in `EXECUTE` of N
(the next `START_OP` is one clock, not two). This is the F140 next-word /
queue-hit path, with the prefetch-count and board lessons from F140–F144
kept in mind. Without it, overlap of `INIT` with `WRITEBACK` never lines up.

### B. Either overlap `INIT` with `WRITEBACK`, or retiming `P_OUT`

**B1 (preferred if A is in place).** Leave `P_OUT` and the write in
`WRITEBACK`. During that clock, allow `ALU_INIT` of a following instruction
that does **not** read the register being written (MOVEQ, `MOVE.L D1,D0` as
a WAW on D0, not a RAW on D1). `WRITEBACK` → `EXECUTE` when `ALU_INIT_I`
is set; `UNMARK` on that transition; `ALU_TRIG` not blocked by `ALU_BSY`.
Attempt 2 is this design; it only needs A so that `FETCH` is actually in
`INIT` during `WRITEBACK`.

**B2.** Make `RESULT` valid in the `EXECUTE` / `ALU_REQ` clock — either
drive the write port from the already-combinational `RESULT_OTHERS` /
`RESULT_INTOP` (computed from operands latched at `ALU_INIT`), or register
`P_OUT` earlier — and then write in `EXECUTE`. That is what attempt 1
tried, without waiting for `P_OUT`. It would also let a following RAW
`ALU_INIT` happen the clock after the write (2-clock ADD) without a
forwarding mux. It lengthens the `EXECUTE` combinational path into the
register file and must be checked against `clk_cpu030 >= 16 MHz`.

Do not write in `EXECUTE` while `P_OUT` still updates `RESULT` on that
same `ALU_REQ` edge.

### Order, if this is taken up again

1. Prove A on its own (pipe ready at early `OW_REQ`) with the existing
   `expect_icache_*` prefetch counts and `sim/speed/irq/run_lt_tt.sh`.
2. Add B1 for MOVEQ, then `MOVE.L Dn,Dn` (WAW only). Measure the speed
   table: nothing faster than the manual. `ext.l` / `swap` / `scc` / `adda.w`
   / `cmpa.l` are already at the manual floor (4) and must not be included.
3. ADD/SUB/AND/OR/EOR.L and ADDQ/SUBQ to Dn: either accept 3 clocks without
   forwarding (still better than 4 if the `DR_IN_USE` WAW wait is removed
   only when the write has completed) or add B2 / explicit forwarding.
4. Leave ADDQ/SUBQ `#`,An out (F145 board). Do not touch Gowin version,
   constraints, or the board until the table, `run_rtl.sh`, `expect_mmut`
   and the irq cached-TT-RAM harness are clean.

## What was not done

- No RTL left in the tree (the dumps and both attempts were reverted).
- No Gowin build, no `.fs`, no board load.
- `origin/speed` gains only this note.
