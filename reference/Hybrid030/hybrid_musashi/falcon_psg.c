/* =====================================================================
 * falcon_psg.c -- YM2149 (PSG) synthesis for FalconFPGA.
 *
 * Sibling module in the falcon_blitter.c / falcon_ide.c family:
 * #included by the main firmware, self-contained state, HOST_TEST path.
 *
 * Ported from Hatari's src/sound.c as the EXECUTABLE SPEC (same method
 * as the blitter port from blitter.c). Hatari is GPL-2+; this is a
 * derived work -- fine for Dave's bench, relevant only if FalconFPGA
 * sources/bitstreams are ever distributed. Ledger it.
 *
 * Details taken from the spec that differ from the textbook YM2149 and
 * would have been WRONG from memory:
 *   - all period counters run at YM clock / 8 = 250 kHz (not /16)
 *   - the counter is incremented THEN compared, which is what makes
 *     per==0 behave like per==1 (measured on real hardware)
 *   - the noise counter is incremented at 125 kHz (half rate) but is
 *     COMPARED every 250 kHz cycle -- so per==0 noise runs at 250 kHz,
 *     asymmetric with tone. Replicated exactly; it is the spec.
 *   - noise LFSR is 17-stage, taps (17,14): x>>1 ^ 0x12000, out on bit 0
 *   - 4-bit fixed volume -> 5-bit internal is IRREGULAR at the bottom:
 *     {0,1,5,7,9,...,31}, not v*2+1
 *   - the 3 voices do NOT sum linearly: they share a grounded resistor,
 *     so the mix is a conductance-divider model (32x32x32 table)
 *   - envelopes are 3 blocks of 32 volumes; after block 2 the position
 *     wraps to block 1 (pos 96 -> 32), which is what makes shapes
 *     8/10/12/14 repeat and 9/11/13/15 hold
 *
 * Output: fs = 50e6/1024 = 48828.125 Hz, matching the REV13 I2S frame
 * rate exactly. 250000/48828.125 = 128/25 EXACTLY, so the decimator is
 * an exact integer ratio -- 25 output samples per 128 YM cycles, each
 * output being the box-average of the 5 or 6 YM samples inside it
 * (free anti-aliasing, no fractional-phase drift ever).
 *
 * A one-pole DC blocker follows, modelling the ST's output coupling
 * capacitor: the raw table output is 0..32767 (unipolar, as on real
 * hardware), which would waste headroom and push DC into a DC-coupled
 * Class-D bridge. After blocking, silence is 0 and a full-scale square
 * swings about +/-16k.
 * ===================================================================== */

#ifndef FALCON_PSG_C
#define FALCON_PSG_C

/* ---- decimation: EXACT 128:25 (250 kHz -> 48828.125 Hz) ------------- */
#define PSG_DEC_NUM   25u
#define PSG_DEC_DEN   128u

/* ---- tables (built once) -------------------------------------------- */
static int16_t  psg_out5[32768];        /* index C<<10|B<<5|A -> signed  */
static uint16_t psg_envwave[16][96];    /* 16 shapes x 3 blocks x 32     */
static int      psg_tables_ok = 0;

/* 4-bit fixed volume -> internal 5-bit (irregular at the bottom)        */
static const uint8_t psg_vol4to5[16] =
    { 0,1,5,7,9,11,13,15,17,19,21,23,25,27,29,31 };

/* envelope block kinds */
#define PSG_E_GODOWN 0
#define PSG_E_GOUP   1
#define PSG_E_DOWN   2
#define PSG_E_UP     3
static const uint8_t psg_envdef[16][3] = {
    {PSG_E_GODOWN,PSG_E_DOWN,  PSG_E_DOWN  },  /* 0 \___ */
    {PSG_E_GODOWN,PSG_E_DOWN,  PSG_E_DOWN  },  /* 1 \___ */
    {PSG_E_GODOWN,PSG_E_DOWN,  PSG_E_DOWN  },  /* 2 \___ */
    {PSG_E_GODOWN,PSG_E_DOWN,  PSG_E_DOWN  },  /* 3 \___ */
    {PSG_E_GOUP,  PSG_E_DOWN,  PSG_E_DOWN  },  /* 4 /___ */
    {PSG_E_GOUP,  PSG_E_DOWN,  PSG_E_DOWN  },  /* 5 /___ */
    {PSG_E_GOUP,  PSG_E_DOWN,  PSG_E_DOWN  },  /* 6 /___ */
    {PSG_E_GOUP,  PSG_E_DOWN,  PSG_E_DOWN  },  /* 7 /___ */
    {PSG_E_GODOWN,PSG_E_GODOWN,PSG_E_GODOWN},  /* 8 \\\\ */
    {PSG_E_GODOWN,PSG_E_DOWN,  PSG_E_DOWN  },  /* 9 \___ */
    {PSG_E_GODOWN,PSG_E_GOUP,  PSG_E_GODOWN},  /* A \/\/ */
    {PSG_E_GODOWN,PSG_E_UP,    PSG_E_UP    },  /* B \--- */
    {PSG_E_GOUP,  PSG_E_GOUP,  PSG_E_GOUP  },  /* C //// */
    {PSG_E_GOUP,  PSG_E_UP,    PSG_E_UP    },  /* D /--- */
    {PSG_E_GOUP,  PSG_E_GODOWN,PSG_E_GOUP  },  /* E /\/\ */
    {PSG_E_GOUP,  PSG_E_DOWN,  PSG_E_DOWN  }   /* F /___ */
};

/* ---- live state ------------------------------------------------------ */
static uint8_t  psg_sr[14];             /* sound regs 0..13 (own copy)   */
static uint16_t psg_perA, psg_perB, psg_perC, psg_perN;
static uint32_t psg_perE;
static uint16_t psg_cntA, psg_cntB, psg_cntC, psg_cntN;
static uint32_t psg_cntE;
static uint16_t psg_valA, psg_valB, psg_valC;   /* 0 or 0x1f             */
static uint32_t psg_valN;                        /* 0 or 0xffff           */
static uint32_t psg_rnd;                         /* 17-bit LFSR           */
static uint8_t  psg_div2;
static uint16_t psg_envpos, psg_envshape;
static uint32_t psg_mTA,psg_mTB,psg_mTC,psg_mNA,psg_mNB,psg_mNC;
static uint16_t psg_envmask3, psg_vol3;
static uint32_t psg_dec;
static int32_t  psg_dc_x1, psg_dc_y1;

static void psg_build_tables(void)
{
    int e, b, i, j, k;
    double cond, c_[32], maxd;
    uint16_t umax;

    if (psg_tables_ok) return;

    /* envelopes: 3 blocks of 32, each entry replicated to all 3 voices */
    for (e = 0; e < 16; e++)
        for (b = 0; b < 3; b++) {
            int vol = 0, inc = 0;
            switch (psg_envdef[e][b]) {
                case PSG_E_GODOWN: vol = 31; inc = -1; break;
                case PSG_E_GOUP:   vol = 0;  inc =  1; break;
                case PSG_E_DOWN:   vol = 0;  inc =  0; break;
                default:           vol = 31; inc =  0; break;
            }
            for (i = 0; i < 32; i++) {
                psg_envwave[e][b*32 + i] =
                    (uint16_t)((vol << 10) | (vol << 5) | vol);
                vol += inc;
            }
        }

    /* conductance ladder (YM2149 AC+DC model, WARP/FOURTH2 per spec) */
    cond = 2.0/3.0/(1.0 - 1.0/1.666666666666666667) - 2.0/3.0;
    for (i = 31; i >= 1; i--) {
        c_[i] = cond/2.0;
        cond  = 1.0/(1.0 - 1.0/1.19/(1.0/cond + 1.0)) - 1.0;
    }
    c_[0] = 1.0e-8;                       /* avoid divide by zero        */

    /* max is all three voices at 31; scale [0,max] -> [0,32767] like the
     * spec does (u16 round, then integer scale)                         */
    maxd = (65535.0*1.666666666666666667) /
           (1.0 + 1.0/(c_[31] + c_[31] + c_[31]));
    umax = (uint16_t)(0.5 + maxd);
    for (i = 0; i < 32; i++)
        for (j = 0; j < 32; j++)
            for (k = 0; k < 32; k++) {
                double v = (65535.0*1.666666666666666667) /
                           (1.0 + 1.0/(c_[i] + c_[j] + c_[k]));
                uint16_t u = (uint16_t)(0.5 + v);
                psg_out5[(i<<10)|(j<<5)|k] =
                    (int16_t)(((uint32_t)u * 0x7fffu) / umax);
            }
    psg_tables_ok = 1;
}

static uint32_t psg_rnd_step(void)
{
    if (psg_rnd & 1u) { psg_rnd = (psg_rnd >> 1) ^ 0x12000u; return 0xffffu; }
    psg_rnd >>= 1; return 0u;
}

static void psg_snd_reset(void)
{
    int i;
    psg_build_tables();
    for (i = 0; i < 14; i++) psg_sr[i] = 0;
    psg_perA = psg_perB = psg_perC = psg_perN = 0; psg_perE = 0;
    psg_cntA = psg_cntB = psg_cntC = psg_cntN = 0; psg_cntE = 0;
    psg_valA = psg_valB = psg_valC = 0; psg_valN = 0;
    psg_rnd = 1u; psg_div2 = 0;
    psg_envpos = 0; psg_envshape = 0;
    /* mixer bits are ACTIVE LOW: reset value 0 = everything enabled, so
     * masks start 0 (not 0xffff) exactly as a real chip powers up      */
    psg_mTA = psg_mTB = psg_mTC = psg_mNA = psg_mNB = psg_mNC = 0;
    psg_envmask3 = 0; psg_vol3 = 0;
    psg_dec = 0; psg_dc_x1 = 0; psg_dc_y1 = 0;
}

/* called on every write to a sound register (0..13) */
static void psg_snd_write(uint8_t reg, uint8_t data)
{
    if (reg > 13u) return;
    switch (reg) {
    case 0: psg_sr[0] = data;
            psg_perA = (uint16_t)(((psg_sr[1] & 0x0fu) << 8) | psg_sr[0]); break;
    case 1: psg_sr[1] = data & 0x0fu;
            psg_perA = (uint16_t)(((psg_sr[1] & 0x0fu) << 8) | psg_sr[0]); break;
    case 2: psg_sr[2] = data;
            psg_perB = (uint16_t)(((psg_sr[3] & 0x0fu) << 8) | psg_sr[2]); break;
    case 3: psg_sr[3] = data & 0x0fu;
            psg_perB = (uint16_t)(((psg_sr[3] & 0x0fu) << 8) | psg_sr[2]); break;
    case 4: psg_sr[4] = data;
            psg_perC = (uint16_t)(((psg_sr[5] & 0x0fu) << 8) | psg_sr[4]); break;
    case 5: psg_sr[5] = data & 0x0fu;
            psg_perC = (uint16_t)(((psg_sr[5] & 0x0fu) << 8) | psg_sr[4]); break;
    case 6: psg_sr[6] = data & 0x1fu; psg_perN = psg_sr[6]; break;
    case 7: psg_sr[7] = data & 0x3fu;              /* bits 6,7 = ports  */
            psg_mTA = (data & 0x01u) ? 0xffffu : 0u;
            psg_mTB = (data & 0x02u) ? 0xffffu : 0u;
            psg_mTC = (data & 0x04u) ? 0xffffu : 0u;
            psg_mNA = (data & 0x08u) ? 0xffffu : 0u;
            psg_mNB = (data & 0x10u) ? 0xffffu : 0u;
            psg_mNC = (data & 0x20u) ? 0xffffu : 0u; break;
    case 8: psg_sr[8] = data & 0x1fu;
            if (data & 0x10u) { psg_envmask3 |= 0x1fu; psg_vol3 &= ~0x1fu; }
            else { psg_envmask3 &= ~0x1fu; psg_vol3 &= ~0x1fu;
                   psg_vol3 |= psg_vol4to5[psg_sr[8] & 0x0fu]; } break;
    case 9: psg_sr[9] = data & 0x1fu;
            if (data & 0x10u) { psg_envmask3 |= (0x1fu<<5); psg_vol3 &= ~(0x1fu<<5); }
            else { psg_envmask3 &= ~(0x1fu<<5); psg_vol3 &= ~(0x1fu<<5);
                   psg_vol3 |= (uint16_t)(psg_vol4to5[psg_sr[9] & 0x0fu] << 5); } break;
    case 10: psg_sr[10] = data & 0x1fu;
            if (data & 0x10u) { psg_envmask3 |= (0x1fu<<10); psg_vol3 &= ~(0x1fu<<10); }
            else { psg_envmask3 &= ~(0x1fu<<10); psg_vol3 &= ~(0x1fu<<10);
                   psg_vol3 |= (uint16_t)(psg_vol4to5[psg_sr[10] & 0x0fu] << 10); } break;
    case 11: psg_sr[11] = data;
             psg_perE = (uint32_t)((psg_sr[12] << 8) | psg_sr[11]); break;
    case 12: psg_sr[12] = data;
             psg_perE = (uint32_t)((psg_sr[12] << 8) | psg_sr[11]); break;
    case 13: psg_sr[13] = data & 0x0fu;            /* writing retriggers */
             psg_envpos = 0; psg_cntE = 0; psg_envshape = psg_sr[13]; break;
    default: break;
    }
}

/* one 250 kHz YM cycle -> raw table sample */
static int32_t psg_ym_cycle(void)
{
    uint32_t bt; uint16_t t3, e3;

    /* noise: incremented at 125 kHz, but COMPARED every cycle (spec) */
    psg_div2 ^= 1u;
    if (psg_div2 == 0u) psg_cntN++;
    if (psg_cntN >= psg_perN) { psg_cntN = 0; psg_valN = psg_rnd_step(); }

    psg_cntA++; if (psg_cntA >= psg_perA) { psg_cntA = 0; psg_valA ^= 0x1fu; }
    psg_cntB++; if (psg_cntB >= psg_perB) { psg_cntB = 0; psg_valB ^= 0x1fu; }
    psg_cntC++; if (psg_cntC >= psg_perC) { psg_cntC = 0; psg_valC ^= 0x1fu; }

    psg_cntE++;
    if (psg_cntE >= psg_perE) {
        psg_cntE = 0; psg_envpos++;
        if (psg_envpos >= 96u) psg_envpos -= 64u;   /* loop blocks 1,2   */
    }

    e3 = (uint16_t)(psg_envwave[psg_envshape][psg_envpos] & psg_envmask3);
    bt = (psg_valA | psg_mTA) & (psg_valN | psg_mNA); t3  = (uint16_t)(bt & 0x1fu);
    bt = (psg_valB | psg_mTB) & (psg_valN | psg_mNB); t3 |= (uint16_t)((bt & 0x1fu) << 5);
    bt = (psg_valC | psg_mTC) & (psg_valN | psg_mNC); t3 |= (uint16_t)((bt & 0x1fu) << 10);
    t3 &= (uint16_t)(e3 | psg_vol3);
    return psg_out5[t3];
}

/* one output sample at fs, box-averaged then DC-blocked */
static int16_t psg_sample(void)
{
    int32_t sum = 0, avg, y; int cnt = 0;
    for (;;) {
        sum += psg_ym_cycle(); cnt++;
        psg_dec += PSG_DEC_NUM;
        if (psg_dec >= PSG_DEC_DEN) { psg_dec -= PSG_DEC_DEN; break; }
    }
    avg = sum / cnt;
    /* y[n] = x[n] - x[n-1] + (1023/1024) y[n-1]  (models the coupling cap,
     * fc ~ 7.6 Hz). State is kept in Q8: a plain integer implementation
     * truncates toward -inf on the arithmetic shift every sample, which
     * injects a systematic NEGATIVE DC bias (measured -309, i.e. ~2% of
     * peak) -- precisely the DC this filter exists to remove, and
     * unwelcome in a DC-coupled Class-D bridge. Q8 state cuts that
     * truncation error by 256x. Caught by PSGTEST v7a.                 */
    psg_dc_y1 = (int32_t)(((int64_t)psg_dc_y1 * 1023) >> 10)
              + ((avg - psg_dc_x1) << 8);
    psg_dc_x1 = avg;
    y = psg_dc_y1 >> 8;
    if (y >  32767) y =  32767;
    if (y < -32768) y = -32768;
    return (int16_t)y;
}

/* =====================================================================
 * HOST_TEST: PSGTEST
 * Structural + independent-method differential. The strongest vector is
 * v3: the counter state machine is checked against a CLOSED-FORM model
 * (parity of floor(t/per)) -- a genuinely different method, so it
 * catches off-by-one and reset-ordering bugs that a transcribed mirror
 * of the same algorithm never would.
 * ===================================================================== */
#ifdef HOST_TEST
static int psgtest(void)
{
    int bad = 0;

    psg_snd_reset();

    /* v1: 17-stage LFSR must have full period 2^17-1 = 131071 */
    { uint32_t seen = 0, s0; psg_rnd = 1u; s0 = psg_rnd;
      do { psg_rnd_step(); seen++; } while (psg_rnd != s0 && seen <= 200000u);
      if (seen != 131071u) {
          printf("PSGTEST FAIL v1: LFSR period %u != 131071\r\n", seen); bad++; }
    }

    /* v2: tone frequency. Counter at 250 kHz toggles every `per` ticks,
     * so a full square cycle is 2*per ticks: f = 250000/(2*per).
     * Independent literals: per=256 -> 488.28 Hz, per=125 -> 1000 Hz.  */
    { struct { uint16_t per; int mhz; } t[2] = { {256, 48828}, {125, 100000} };
      int q;
      for (q = 0; q < 2; q++) {
          uint32_t i, toggles = 0; uint16_t prev;
          psg_snd_reset();
          psg_snd_write(0, (uint8_t)(t[q].per & 0xffu));
          psg_snd_write(1, (uint8_t)(t[q].per >> 8));
          psg_snd_write(7, 0x3eu);            /* tone A only            */
          psg_snd_write(8, 15u);
          prev = psg_valA;
          for (i = 0; i < 250000u; i++) {     /* exactly 1 second       */
              psg_ym_cycle();
              if (psg_valA != prev) { toggles++; prev = psg_valA; }
          }
          /* toggles/2 = cycles/sec, in 1/100 Hz to keep it integer     */
          { int mhz = (int)(toggles * 50u);   /* (toggles/2)*100        */
            int want = t[q].mhz;
            if (mhz < want - 200 || mhz > want + 200) {
                printf("PSGTEST FAIL v2: per=%u got %d.%02d Hz want %d.%02d\r\n",
                       t[q].per, mhz/100, mhz%100, want/100, want%100); bad++; }
          }
      }
    }

    /* v3: DIFFERENTIAL -- counter state machine vs closed form.
     * With period p, the square's level at cycle t is parity of the
     * number of toggles = floor(t/p) (p>=1). Checked over 400k cycles
     * for several periods, tone A only, no noise/env.                  */
    { uint16_t pers[5] = { 1, 2, 7, 255, 4095 }; int q;
      for (q = 0; q < 5; q++) {
          uint32_t p = pers[q], t, mism = 0; uint16_t exp0;
          psg_snd_reset();
          psg_snd_write(0, (uint8_t)(p & 0xffu));
          psg_snd_write(1, (uint8_t)(p >> 8));
          exp0 = psg_valA;                    /* starting level         */
          for (t = 1; t <= 400000u; t++) {
              uint16_t want, got;
              psg_ym_cycle();
              want = (uint16_t)(((t / p) & 1u) ? (exp0 ^ 0x1fu) : exp0);
              got  = psg_valA;
              if (want != got) { mism++; if (mism < 3)
                  printf("PSGTEST v3 per=%u t=%u want=%x got=%x\r\n",
                         (unsigned)p, t, want, got); }
          }
          if (mism) { printf("PSGTEST FAIL v3: per=%u %u mismatches\r\n",
                             (unsigned)p, mism); bad++; }
      }
    }

    /* v4: envelope shapes. Literal expectations from the datasheet:
     * shape 8 repeats a falling ramp (pos 32..95 all descending),
     * shape 12 repeats a rising ramp, shape 11 holds HIGH after the
     * first fall, shape 9 holds LOW, shape 10 is a triangle.          */
    { int q;
      struct { int shape; int pos; int vol; } v[6] = {
          { 8, 32, 31 }, { 8, 63,  0 },      /* \\\\ restarts at 31    */
          {12, 32,  0 }, {12, 63, 31 },      /* //// restarts at 0     */
          {11, 40, 31 },                     /* \--- holds high        */
          { 9, 40,  0 }                      /* \___ holds low         */
      };
      for (q = 0; q < 6; q++) {
          int got = psg_envwave[v[q].shape][v[q].pos] & 0x1f;
          if (got != v[q].vol) {
              printf("PSGTEST FAIL v4: shape %d pos %d vol %d != %d\r\n",
                     v[q].shape, v[q].pos, got, v[q].vol); bad++; }
      }
    }

    /* v5: volume table -- silence is 0, max is 32767, monotonic in each
     * axis, and NON-LINEAR (3 voices at full != 3x one voice).         */
    { int i, j; int nonmono = 0;
      if (psg_out5[0] != 0) {
          printf("PSGTEST FAIL v5a: silence %d != 0\r\n", psg_out5[0]); bad++; }
      if (psg_out5[(31<<10)|(31<<5)|31] != 32767) {
          printf("PSGTEST FAIL v5b: max %d != 32767\r\n",
                 psg_out5[(31<<10)|(31<<5)|31]); bad++; }
      for (i = 0; i < 31; i++)
          if (psg_out5[i+1] < psg_out5[i]) nonmono++;
      if (nonmono) { printf("PSGTEST FAIL v5c: non-monotonic\r\n"); bad++; }
      /* one voice at 31 vs three at 31: linear would be exactly 3x     */
      i = psg_out5[31]; j = psg_out5[(31<<10)|(31<<5)|31];
      if (j >= 3*i) {
          printf("PSGTEST FAIL v5d: mix is linear (%d vs 3x%d)\r\n", j, i); bad++; }
    }

    /* v6: silence really is silent (all volumes 0) and DC-free         */
    { uint32_t i; int nz = 0;
      psg_snd_reset();
      psg_snd_write(7, 0x3fu);                /* everything off         */
      psg_snd_write(8, 0); psg_snd_write(9, 0); psg_snd_write(10, 0);
      for (i = 0; i < 4096u; i++) if (psg_sample() != 0) nz++;
      if (nz) { printf("PSGTEST FAIL v6: %u non-zero silent samples\r\n", nz); bad++; }
    }

    /* v7: a real tone renders with sane amplitude and no DC offset
     * (the coupling-cap model must centre it). Literals: |mean| < 200,
     * peak in [4000, 20000] for one channel at full volume.           */
    { uint32_t i; int32_t mn = 0; int32_t pk = 0; int16_t s;
      psg_snd_reset();
      psg_snd_write(0, 0x00u); psg_snd_write(1, 0x01u);  /* per 256     */
      psg_snd_write(7, 0x3eu);               /* tone A only            */
      psg_snd_write(8, 15u);                 /* full fixed volume      */
      for (i = 0; i < 2000u; i++) psg_sample();          /* settle     */
      for (i = 0; i < 48828u; i++) {
          s = psg_sample(); mn += s;
          if (s > pk) pk = s; if (-s > pk) pk = -s;
      }
      mn /= 48828;
      if (mn < -100 || mn > 100) {
          printf("PSGTEST FAIL v7a: DC offset %d\r\n", (int)mn); bad++; }
      if (pk < 4000 || pk > 20000) {
          printf("PSGTEST FAIL v7b: peak %d\r\n", (int)pk); bad++; }
    }

    /* v8: noise runs, and is not a stuck value                         */
    { uint32_t i; int changes = 0; int16_t prev, s;
      psg_snd_reset();
      psg_snd_write(6, 5u);                  /* noise period           */
      psg_snd_write(7, 0x37u);               /* noise on A only        */
      psg_snd_write(8, 15u);
      prev = psg_sample();
      for (i = 0; i < 20000u; i++) { s = psg_sample(); if (s != prev) changes++; prev = s; }
      if (changes < 1000) {
          printf("PSGTEST FAIL v8: noise static (%d changes)\r\n", changes); bad++; }
    }

    /* v9: envelope retrigger -- writing R13 restarts the envelope      */
    { psg_snd_reset();
      psg_snd_write(11, 0x00u); psg_snd_write(12, 0x10u);  /* slow env  */
      psg_snd_write(13, 8u);
      { uint32_t i; for (i = 0; i < 100000u; i++) psg_ym_cycle(); }
      if (psg_envpos == 0u) {
          printf("PSGTEST FAIL v9a: envelope never advanced\r\n"); bad++; }
      psg_snd_write(13, 8u);                 /* retrigger              */
      if (psg_envpos != 0u || psg_cntE != 0u) {
          printf("PSGTEST FAIL v9b: retrigger pos=%u cnt=%u\r\n",
                 psg_envpos, (unsigned)psg_cntE); bad++; }
    }

    if (!bad) printf("PSGTEST OK (9 vectors)\r\n");
    return bad;
}
#endif /* HOST_TEST */

#endif /* FALCON_PSG_C */
