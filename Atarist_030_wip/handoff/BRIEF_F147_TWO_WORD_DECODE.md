# Brief: F147 take two opcode words in one clock after a restart (WF68K30L)

Repo falconfpga, branch `speed` (HEAD = the commit that adds this file), core `Atarist_030_wip/hdl/cpu030`
(WF68K30L 68030 VHDL, Gowin GW5AST-138, Gowin V1.9.12.03; clk_cpu030 now 21.3 MHz, floor 16 MHz).

## Goal
Save 1 clock per change of flow (BRA/BSR/JMP/JSR/RTS/DBcc taken, any IPIPE_FLUSH refill). Measured today (I-cache
hit, sim): flush at t; t+1 IC_MTAKE loads the target long from the I-cache into the prefetch queue (F144);
t+2 OPCODE_RDY (registered strobe) gives word 1; t+3 IPIPE_PNTR 0->1; t+4 1->2, PIPE_RDY; t+5 OPD_ACK, decode.
Wanted: when the queue already holds two words after a restart, deliver both in one OPCODE_RDY clock
(IPIPE_PNTR 0->2 or 1->3), so PIPE_RDY comes 1 clock earlier.
**Never faster than MC68030UM section 11** (cache-case timings); anything faster is a bug, so say for BRA, BSR+RTS,
JSR+RTS and DBcc what the new clock count is and that it is not below the manual.

## Required change
1. Bus interface: a second opcode word output (OPCODE_TO_CORE_2, 16 bit), valid/fault (OPCODE_VALID_2) and a
   strobe or flag (OPCODE_RDY_2: this OPCODE_RDY also carries the following word), set only when the queue holds
   the following word as a queue hit (Q_HIT/Q_NMATCH path, F140), never to start a bus cycle. Pop two words:
   Q_CNT - 2, queue address + 4, Q_C / Q_W shift by two.
2. Top and package: wire the new ports (top ~1355/1495/1906; component declarations in wf68k30L_pkg.vhd).
3. Decoder: in the IPIPE fill process add the 0->2 and 1->3 transitions (C/D or B/C/D words and their
   *_FAULT bits) when OPCODE_RDY and OPCODE_RDY_2 are both set; request the 2nd word only in the clock after a
   restart (or generally when IPIPE_PNTR < 2 and the control unit demands words, same as OPC_RD_NEXT; state which
   you choose and why).

## Constraints
- VHDL-93-compatible style as the current code (`process` with explicit sensitivity lists, complete them),
  `bit`/`std_logic` as used. Tag every change `[F147]` and add a revision line `--   2026-11-xx F147: ...`
  in each file's header list. Keep the licence headers.
- No relaxed constraints and no new multicycle paths. Minimal combinational depth: OPCODE_RDY_2 must come from
  registered state plus the existing queue-hit compare, not from decoder/control combinational outputs.
- Do not change EARLY_ISSUE / EARLY_OW (F141/F143/F145) or the F144 COF_BLK / IC_MISS_LK logic beyond what is needed.
- Do not invent signals: if you need one that is not in the excerpts, state the assumption and where it should come from.

## Edge cases (handle and explain each)
- Bus error / access fault on the 2nd word (fault bit must travel with that word only; the 1st word stays valid).
- Odd queue address (OPC_ADR(0)), 16-bit port, a word pair split across a long or a cache line end.
- MMU fault (PMMU) on the 2nd word; CIIN/uncached stream (queue fed by bus cycles, not the cache).
- Trace / interrupt / exception pending during the refill (BUSY_EXH, IRQ); IPIPE_FLUSH or OPCODE_FLUSH /
  OPCODE_DISMISS in the same clock as a two-word delivery; loop mode (LOOP_BSY/LOOP_ATN, DBcc loop, F-line).
- BKPT insertion path and the RESET path in the fill process.

## Deliverable
One unified diff against speed HEAD, file `handoff/F147.patch` (paths relative to the repo root,
`Atarist_030_wip/hdl/cpu030/...`), plus a short explanation, the expected clock savings, and a ranked risk list.
Verification here: GHDL tb030 RTL suite (run_rtl.sh), irq/grpb differential tests, the speed timing table,
then a board build (Fmax >= 16 MHz, timing_pairs) and Linux boot.

## Current code

### Queue hit / Q_MISS / I-cache miss lock: `hdl/cpu030/wf68k30L_bus_interface.vhd` lines 905-945
```vhdl
    -- cycles (4n+2, 4n+4) on the 16-bit port, like a misaligned long operand, instead of an
    -- aligned long whose first word is thrown away (that made the TOS 2.06 vblank sync loop
    -- at E013F6 too slow to finish in the 60 Hz blank: black screen at boot). A bus error is kept
    -- per word and only reported (OPCODE_VALID = 0) when the decoder takes that word, as on
    -- a 68030 where a prefetch fault is signalled only if the word is used. Odd addresses
    -- still take the ordinary opcode cycle path to raise the address error. A write that
    -- touches the queued or in-flight long words flushes the queue.
    OPC_LEGACY <= OPCODE_REQ and not RMC_HOLD when PREFETCH_Q = 0 else -- [RMC1] no opcode cycle inside the RMC sequence
                  OPCODE_REQ and To_Bit(OPC_ADR(0)) and not RMC_HOLD; -- [C3]
    Q_MATCH <= '1' when PREFETCH_Q /= 0 and S_VALID = '1' and Q_ADR = OPC_ADR(31 downto 1) and Q_FC = OPC_FC else '0';
    -- [F140] Back to back: in a ready clock the decoder's PC_L still points at the word being delivered, so the
    -- next word (PC_L + 2) is matched against the queue head (Q_NMATCH). Only a hit is served this way; a miss
    -- waits for the next clock and goes through Q_MISS with the updated address as before. Only words the
    -- instruction cache delivered (Q_C) are served back to back: a stream from the bus keeps the old pace, so the
    -- queue's refill point and the bus prefetch placement (run_icache prefetch counts) do not change.
    Q_NMATCH <= '1' when PREFETCH_Q /= 0 and S_VALID = '1' and Q_ADR = OPC_ADR(31 downto 1) + '1' and Q_FC = OPC_FC else '0';
    Q_HIT <= '1' when Q_MATCH = '1' and OPC_RD = '1' and OPC_ADR(0) = '0' and OPCODE_RDY_I = '0' and Q_DISMISS = '0' and Q_CNT /= 0 else
             '1' when Q_NMATCH = '1' and Q_C(0) = '1' and OPC_RD_NEXT = '1' and OPC_ADR(0) = '0' and OPCODE_RDY_I = '1' and Q_DISMISS = '0' and Q_CNT /= 0 else '0';
    Q_MISS <= '1' when PREFETCH_Q /= 0 and OPC_RD = '1' and OPC_ADR(0) = '0' and OPCODE_RDY_I = '0' and Q_DISMISS = '0' and
                       not (Q_MATCH = '1' and (Q_CNT /= 0 or (INFL = '1' and INFL_STALE = '0') or S_FAULTED = '0')) else '0';
    Q_DUMMY <= '1' when PREFETCH_Q /= 0 and OPC_RD = '1' and OPCODE_RDY_I = '0' and Q_DISMISS = '1' else '0';
    PF_REQ_RAW <= '1' when PREFETCH_Q /= 0 and S_VALID = '1' and S_FAULTED = '0' and INFL = '0' and (Q_CNT <= 1 or (Q_CNT = 2 and BUSY_EXH = '0' and PF_NOEARLY = '0' and PIPE_FULL = '0')) and PF_HOLD = '0' and
                       not (OPC_RD = '1' and Q_MATCH = '0') else '0'; -- [PFCOF] [F140] no stream fetch while the decoder waits for another address (after a flush)
    -- [F140] Not with the decoder pipe full: three pipe words plus two queued words is the 68030's look-ahead
    -- (stages B/C/D and the cache holding register); back-to-back delivery would otherwise run one long further.
    -- [XH1] A long is requested while the queue still holds two words (was Q_CNT <= 1), so the stream keeps the
    -- bus busy across operand cycles (W->R, R->R, MOVEM.W, stack). Exception processing keeps the old threshold.
    -- [IC] A long word the instruction cache holds is taken from the cache (P_QUEUE) and never starts a bus
    -- cycle. With nothing cached (CIIN asserted on every cycle) IC_HIT is 0 and PF_REQ is the old request.
    PF_REQ <= PF_REQ_RAW and not To_Bit(IC_HIT) and not RMC_HOLD; -- [RMC1] no prefetch between the locked read and its write
    IC_TAKE <= PF_REQ_RAW and To_Bit(IC_HIT) and not Q_MISS and not RESET_CPU_I;
    -- [F144] Stream restart (branch target, Q_MISS) with no prefetch in flight: look the requested long up in the
    -- instruction cache in the restart clock and queue it at once (IC_MTAKE), one clock earlier than the IC_TAKE
    -- of the next clock. The 68030 starts the target fetch from the cache when the branch resolves.
    IC_MISS_LK <= '1' when Q_MISS = '1' and INFL = '0' and RMC_HOLD = '0' and RESET_CPU_I = '0' else '0';
    IC_MTAKE <= IC_MISS_LK and To_Bit(IC_HIT);
    IC_LK_ADR <= OPC_ADR(31 downto 2) when IC_MISS_LK = '1' else F_ADR(31 downto 2);
    IC_LK_FC2 <= OPC_FC(2) when IC_MISS_LK = '1' else Q_FC(2); -- [F144]
    -- [IC] Fill: every bus prefetch long reports its end with, per word, "no bus error and CIIN negated on its
    -- portion" (MC68030UM 5.7.1, 6.1.3.1 single entry mode). The cache fills aligned longs whose two words are
    -- OK, assembles the longs of a misaligned stream (4n+2 start) from consecutive fetches, and checks EI, FI
```

### OPCODE_RDY_I strobe process: `hdl/cpu030/wf68k30L_bus_interface.vhd` lines 1605-1645
```vhdl

    PREFETCH_BUFFERS: process
    -- These are the data and the operation code input registers. After a last read to the registered
    -- input multiplexer, the respective data is copied from the input multiplexer to these buffers.
    -- The opcode buffer is always written with 32 bit data. The data buffers may contain invalid bytes
    -- in case of word or byte data size.
    variable DBUFFER_MEM    : std_logic_vector(31 downto 8) := x"000000";
    variable RDY_VAR        : bit := '0';
    begin
        wait until CLK = '1' and CLK' event;
        --
        OPCODE_RDY_I <= '0'; -- This is a strobe.
        DATA_RDY_I <= '0'; -- This is a strobe.
        --
        -- The following variable is responsible, that the _RDY signals are
        -- always strobes.
        if OP_CHAIN_GO = '1' or DP_CHAIN_GO = '1' or RA_GO = '1' then -- [PH2] [PH2-WP] First: a posted write's DATA_RDY can
            RDY_VAR := '1';                                 -- be high on the chain edge (never the case before).
        elsif DATA_RDY_I = '1' and RA_GO_D = '1' then
            null; -- [F2] DATA_RDY of the read that rolled into the read-ahead: the read-ahead keeps its ready.
        elsif DATA_RDY_I = '1' or (PREFETCH_Q = 0 and OPCODE_RDY_I = '1') then -- [F62] Queue hits do not end a bus cycle.
            RDY_VAR := '0';
        elsif BUS_CTRL_STATE = START_CYCLE then
            RDY_VAR := '1';
        end if;
        -- Opcode cycle:
        if AERR_I = '1' then
            OPCODE_RDY_I <= '1';
        elsif PREFETCH_Q /= 0 then -- [F62] Served from the prefetch queue (P_QUEUE).
            if Q_DUMMY = '1' then
                OPCODE_RDY_I <= '1'; -- Dismissed by the decoder (pipe flush with a pending request).
            elsif Q_HIT = '1' then
                OBUFFER <= Q_W(0);
                OPCODE_RDY_I <= '1';
            end if;
        elsif OPCODE_ACCESS = '1' and BUS_CTRL_STATE = DATA_C1C4 and BUS_CYC_RDY = '1' and SIZE_N = "000" then
            -- Instruction prefetches are always long and on word boundaries.
            -- The word is available after the first word read.
            OBUFFER <= DATA_INMUX(15 downto 0);
            OPCODE_RDY_I <= RDY_VAR;
        end if;
```

### OPC_RD_NEXT (F140): `hdl/cpu030/wf68k30L_opcode_decoder.vhd` lines 270-284
```vhdl
        end if;
    end process P_OPCODE_FLUSH;

    OPCODE_RD <= OPCODE_RD_I;
    PIPE_FULL <= '1' when IPIPE_PNTR = 3 else '0'; -- [F140]
    -- [F140] OPCODE_RD_I is cleared by OPCODE_RDY, so a word could only be requested every other clock.
    -- In the clock of a ready strobe, ask the prefetch queue for the next word as well when the pipe has
    -- room for it after this one is loaded (pointer below 2), so a queue holding words (cache hits)
    -- fills the pipe at one word per clock as the 68030 pipeline. Not during flush, dismissal,
    -- exceptions or loop mode; the bus interface uses it only for queue hits, never to start a bus cycle.
    -- Only on demand (the control unit waits for an operation or extension word), so the pipe does not run
    -- further ahead of execution than before and the stream prefetch placement is unchanged.
    OPC_RD_NEXT <= '1' when OPCODE_RDY = '1' and OPCODE_FLUSH = '0' and IPIPE_FLUSH = '0' and BUSY_EXH = '0' and
                            IPIPE_PNTR < 2 and (OW_REQ = '1' or EW_REQ = '1') and LOOP_ATN = false and LOOP_BSY_I = false else '0';
    OPCODE_DISMISS <= OPCODE_FLUSH; -- [F62c]
```

### IPIPE fill process: `hdl/cpu030/wf68k30L_opcode_decoder.vhd` lines 362-480
```vhdl
    -- These are the instruction pipe FIFO registers. The opcodes are stored in IPIPE.B, IPIPE.C
    -- and IPIPE.D which is copied to the instruction register or to the respective extension when
    -- read. Be aware, that the pipe is always completely refilled to determine the correct INSTR_LVL
    -- before it is copied to the execution unit.
    variable IPIPE_D_VAR    : std_logic_vector(15 downto 0);
    begin
        wait until CLK = '1' and CLK' event;
        if IPIPE_FLUSH = '1' then
            IPIPE.D <= (others => '0');
            IPIPE.C <= (others => '0');
            IPIPE.B <= (others => '0');
            IPIPE_PNTR <= 0;
        elsif BKPT_INSERT = '1' then
            IPIPE_D_VAR := IPIPE.D;
            IPIPE.D <= BKPT_DATA; -- Insert the breakpoint data.
            BKPT_REQ <= '1';
        elsif OW_REQ = '1' and BKPT_REQ = '1' then
            IPIPE.D <= IPIPE_D_VAR; -- Restore from breakpoint.
            BKPT_REQ <= '0';
        elsif LOOP_ATN = true and OPCODE_RD_I = '1' then
            null; -- Wait for pending opcodes.
        elsif OW_REQ = '1' and PIPE_RDY = '1' and OP_I = DBcc and LOOP_OP = true and IPIPE.C = x"FFFC" then -- Initialize the loop.
            IPIPE.D <= BIW_0; -- This is the LEVEL D operation for the loop.
        elsif OW_REQ = '1' and LOOP_BSY_I = true then
            IPIPE.D <= BIW_0; -- Recycle the loop operations.
        elsif LOOP_BSY_I = true then
            null; -- Do not change the pipe during the loop.
        elsif OW_REQ = '1' and INSTR_LVL = D and PIPE_RDY = '1' and IPIPE_PNTR = 2 then
            if OPCODE_RDY_I = '1' then
                IPIPE.D <= IPIPE.C;
                IPIPE.C <= OPCODE_DATA;
                IPIPE_D_FAULT <= IPIPE_C_FAULT;
                IPIPE_C_FAULT <= not OPCODE_VALID;
            else
                IPIPE.D <= IPIPE.C;
                IPIPE_D_FAULT <= IPIPE_C_FAULT;
                IPIPE_PNTR <= IPIPE_PNTR - 1;
            end if;
        elsif OW_REQ = '1' and INSTR_LVL = D and PIPE_RDY = '1' and IPIPE_PNTR = 3 then
            if OPCODE_RDY_I = '1' then
                IPIPE.D <= IPIPE.C;
                IPIPE.C <= IPIPE.B;
                IPIPE.B <= OPCODE_DATA;
                IPIPE_D_FAULT <= IPIPE_C_FAULT;
                IPIPE_C_FAULT <= IPIPE_B_FAULT;
                IPIPE_B_FAULT <= not OPCODE_VALID;
            else
                IPIPE.D <= IPIPE.C;
                IPIPE.C <= IPIPE.B;
                IPIPE_D_FAULT <= IPIPE_C_FAULT;
                IPIPE_C_FAULT <= IPIPE_B_FAULT;
                IPIPE_PNTR <= IPIPE_PNTR - 1;
            end if;
        elsif OW_REQ = '1' and INSTR_LVL = C and PIPE_RDY = '1' and IPIPE_PNTR = 2 then
            if OPCODE_RDY_I = '1' then
                IPIPE.D <= OPCODE_DATA;
                IPIPE_D_FAULT <= not OPCODE_VALID;
                IPIPE_PNTR <= IPIPE_PNTR - 1;
            else
                IPIPE_PNTR <= 0;
            end if;
        elsif OW_REQ = '1' and INSTR_LVL = C and PIPE_RDY = '1' and IPIPE_PNTR = 3 then
            if OPCODE_RDY_I = '1' then
                IPIPE.D <= IPIPE.B;
                IPIPE.C <= OPCODE_DATA;
                IPIPE_D_FAULT <= IPIPE_B_FAULT;
                IPIPE_C_FAULT <= not OPCODE_VALID;
                IPIPE_PNTR <= IPIPE_PNTR - 1;
            else
                IPIPE.D <= IPIPE.B;
                IPIPE_D_FAULT <= IPIPE_B_FAULT;
                IPIPE_PNTR <= IPIPE_PNTR - 2;
            end if;
        elsif OW_REQ = '1' and INSTR_LVL = B and PIPE_RDY = '1' then -- IPIPE_PNTR = 3.
            if OPCODE_RDY_I = '1' then
                IPIPE.D <= OPCODE_DATA;
                IPIPE_D_FAULT <= not OPCODE_VALID;
                IPIPE_PNTR <= IPIPE_PNTR - 2;
            else
                IPIPE_PNTR <= 0;
            end if;
        elsif EW_REQ = '1' and IPIPE_PNTR >= 1 then
            case IPIPE_PNTR is
                when 3 =>
                    if OPCODE_RDY_I = '1' then
                        IPIPE.D <= IPIPE.C;
                        IPIPE.C <= IPIPE.B;
                        IPIPE.B <= OPCODE_DATA;
                        IPIPE_D_FAULT <= IPIPE_C_FAULT;
                        IPIPE_C_FAULT <= IPIPE_B_FAULT;
                        IPIPE_B_FAULT <= not OPCODE_VALID;
                    else
                        IPIPE.D <= IPIPE.C;
                        IPIPE.C <= IPIPE.B;
                        IPIPE_D_FAULT <= IPIPE_C_FAULT;
                        IPIPE_C_FAULT <= IPIPE_B_FAULT;
                        IPIPE_PNTR <= IPIPE_PNTR - 1;
                    end if;
                when 2 =>
                    if OPCODE_RDY_I = '1' then
                        IPIPE.D <= IPIPE.C;
                        IPIPE.C <= OPCODE_DATA;
                        IPIPE_D_FAULT <= IPIPE_C_FAULT;
                        IPIPE_C_FAULT <= not OPCODE_VALID;
                    else
                        IPIPE.D <= IPIPE.C;
                        IPIPE_D_FAULT <= IPIPE_C_FAULT;
                        IPIPE_PNTR <= IPIPE_PNTR - 1;
                    end if;
                when 1 =>
                    if OPCODE_RDY_I = '1' then
                        IPIPE.D <= OPCODE_DATA;
                        IPIPE_D_FAULT <= not OPCODE_VALID;
                    else
                        IPIPE_PNTR <= 0;
                    end if;
                when others => null;
            end case;
        elsif OPCODE_RDY_I = '1' then
```

### OPCODE_TO_CORE: `hdl/cpu030/wf68k30L_top.vhd` lines 1353-1356
```vhdl
    IC_BUS_REQ     <= OPCODE_REQ;
    OPCODE_RDY     <= BUS_OPCODE_RDY;
    OPCODE_TO_CORE <= BUS_OPCODE_WORD;
    DC_BUS_REQ     <= RD_REQ;
```

### bus interface port map (part): `hdl/cpu030/wf68k30L_top.vhd` lines 1490-1500
```vhdl

            DATA_PORT_IN        => DATA_IN,
            DATA_PORT_OUT       => C_DOUT,
            DATA_FROM_CORE      => DATA_FROM_CORE,
            DATA_TO_CORE        => BUS_DATA_WORD,
            OPCODE_TO_CORE      => BUS_OPCODE_WORD,

            DATA_PORT_EN        => C_DEN,
            BUS_EN              => C_BEN,

            SIZE                => C_SIZE_O,
```

### decoder port map (part): `hdl/cpu030/wf68k30L_top.vhd` lines 1900-1910
```vhdl

            OPCODE_RD               => OPCODE_RD,
            OPC_RD_NEXT             => OPC_RD_NEXT, -- [F140]
            PIPE_FULL               => PIPE_FULL, -- [F140]
            OPCODE_RDY              => OPCODE_RDY,
            OPCODE_VALID            => OPCODE_VALID,
            OPCODE_DATA             => OPCODE_TO_CORE,

            IPIPE_FILL              => IPIPE_FILL,
            IPIPE_FLUSH             => IPIPE_FLUSH,
            OPCODE_DISMISS          => OPC_DISMISS, -- [F62c]
```

### Package: `hdl/cpu030/wf68k30L_pkg.vhd` lines mentioning OPCODE_RDY
```vhdl
288:         OPCODE_RDY          : out bit;
581:         OPCODE_RDY          : in bit;
663:         OPCODE_RDY          : in bit;
```
