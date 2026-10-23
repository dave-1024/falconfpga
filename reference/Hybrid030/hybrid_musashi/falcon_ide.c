/* M14: every IDE trace family ([idet]/[idec]/[ided]/RAM-band) is now
 * gated on ide_dbg, which boots OFF and thereafter follows log_on
 * (F12). The IDE arc closed
 * at m11z, so these no longer earn permanent boot-log space; the D8
 * byte-swap investigation is still open, so they must stay AVAILABLE.
 * Budgets are inside the gate, so they tick only when actually printing
 * -- toggle F12 on at any time and the full 400/4096/1500 depths are
 * still banked. The one-off [ide] device-summary lines stay un-gated:
 * two lines at boot, and they are how you know a disk was seen at all.
 * ===================================================================
 * =====================================================================
 * falcon_ide.c -- Falcon IDE (ATA) device model. #included by falcon_m11q.c
 * the way falcon_blitter.c is, so the diff stays readable.
 *
 * Register map taken from EmuTOS's own struct IDE at 0xfff00000 with the
 * filler offsets computed out, and cross-checked against Hatari's Falcon
 * decode. NOT derived:
 *
 *   +0x00  data (16-bit)          +0x19  head/device
 *   +0x05  error / features       +0x1D  status / command
 *   +0x09  sector count           +0x39  alt status / device control
 *   +0x0D  sector number / LBA[7:0]
 *   +0x11  cylinder low  / LBA[15:8]
 *   +0x15  cylinder high / LBA[23:16]
 *
 * Registers sit on odd bytes at 4-byte spacing; the data register is the
 * only 16-bit one. +0x39 is what TOS 4.04 was BERRing on in every boot log
 * -- the alternate status register, the first door any driver knocks on.
 *
 * ONE interface only, 0xFFF00000..0xFFF0003F. EmuTOS probes four
 * (0x1D, 0x5D, 0x9D, 0xDD -- 0x40 apart); the others must keep bus-erroring
 * because a real Falcon has one interface.
 *
 * TWO devices, per-device register files. That is not a detail: EmuTOS
 * detects by writing 0xAA/0x55 into sector_number/sector_count and reading
 * back 0xAA55, so a SHARED register file would let the scribble written
 * while device 0 was selected still be sitting there when device 1 is
 * selected -- and both slots would detect, including absent ones. Real ATA
 * devices each own their registers and only the selected one answers.
 *
 * Absent devices answer status 0x00. Never 0xFF: that reads as BSY set and
 * sends a driver into a wait loop it never leaves -- the same trap as the
 * FDC pend, arrived at from the other side.
 *
 * After a reset each present device presents the ATA signature
 * scnt=1 snum=1 cyl=0, because EmuTOS re-checks for exactly 0x0101 and only
 * then decodes the device type. Miss it and the drive detects but never
 * resolves, which is a horrible failure to debug.
 *
 * Byte order: the data register hands over sector bytes in order, so a
 * guest read reproduces the image byte-for-byte. That is the Atari-native
 * convention. Hatari treats the swap as a per-IMAGE property applied in the
 * sector path rather than a bus property, which is what lets every driver
 * work; IDE_SWAP does the same here and defaults off.
 *
 * Commands execute instantly, so BSY is never observed set -- same model as
 * the FDC. Real seek timing is not modelled.
 * ===================================================================== */

#define IDE_BASE   0xFFF00000u
#define IDE_LIMIT  0xFFF00040u          /* interface 0 only              */

/* status */
#define IDE_ST_BSY  0x80u
#define IDE_ST_DRDY 0x40u
#define IDE_ST_DWF  0x20u
#define IDE_ST_DSC  0x10u
#define IDE_ST_DRQ  0x08u
#define IDE_ST_ERR  0x01u
/* error */
#define IDE_ER_IDNF 0x10u
#define IDE_ER_ABRT 0x04u

typedef struct {
    uint8_t  present, swap;
    uint8_t  pend;      /* M12d: 0=none, 1=DRQ setup pends (no INTRQ
                         * at expiry), 2=completion pends (INTRQ at
                         * expiry). Replaces the M11s bsy_once fake:
                         * status is genuinely BSY until done_at.     */
    uint8_t  pend_status;           /* status revealed at expiry         */
    uint64_t done_at;               /* wall deadline (ide_now units)     */
    uint8_t  err, feat, scnt, snum, clo, chi, head, status;
    uint8_t  buf[512];
    uint32_t bidx;                  /* byte cursor within buf            */
    uint8_t  drq_wr;                /* 1 = buf is being filled by host   */
    uint8_t  fmt;                   /* M12c: 1 = FORMAT TRACK drain (discard) */
    uint32_t lba, left;             /* current transfer                  */
    uint32_t sectors, cyls, heads, spt;
} ide_dev;

static ide_dev ide[2];
static uint8_t ide_sel;             /* device selected by head bit 4     */
/* M11y (D9): ide_devctl and ide_intrq are declared in the MAIN file
 * above the MFP block (same pattern as fdc_intrq), so GPIP bit 5 can
 * mirror the INTRQ line: gpip5 low = fdc_intrq | (ide_intrq && !nIEN).
 * INTRQ set: read block ready, write block consumed, non-data
 * completion, abort. NOT set: write-command acceptance, DEVICE RESET.
 * Cleared: status read (+1d only, alt +39 does NOT clear), command
 * write, ide_signature(). Reflection-only -- no vectored MFP raise,
 * matching the FDC precedent; TOS404 ROM and AHDI poll the line.    */
static uint32_t ide_rd_cmds, ide_wr_cmds, ide_bad_cmds;
/* M11r: trace EVERY access. The first-touch io log keys on address, not
 * direction, so once fff0001d was seen as a write every status READ of
 * it became invisible -- which is exactly the traffic we need. Capped so
 * the UART blocking stays bounded; runs regardless of LOG=. */
static uint32_t ide_trc;
#define IDE_TRC_MAX 400u

/* M11x: [idec] -- one line per task-file COMMAND, for D8. Separate
 * budget from ide_trc: the access-level trace above burns its 400
 * slots on the first IDENTIFY's data phase, long before either
 * driver touches the disk. 4096 commands per power-on covers a whole
 * capture session; deliberately never reset at SRST -- one budget
 * per cold boot, so both sides of a warm reset share it. */
static uint32_t idec_n;
#define IDEC_MAX 4096u

/* M12d: REAL COMMAND LATENCY -- the third casualty of instant
 * completion, and the retirement of the fake-BSY era. Three reader
 * disciplines exist on this bus, all correct for real drives:
 *   (A) wait INTRQ, then ONE status read that must show completion
 *       (TOS404 ROM; M11y+M11z made this work);
 *   (B) poll status for a genuine BSY->ready transition (the M11s
 *       clientele -- fake BSY served them until M11z removed it);
 *   (C) issue, PEEK status once, THEN wait INTRQ (the 64xxx tool on
 *       m12c silicon: GPIP spin with the interrupt already consumed
 *       by the peek, because completion was instantaneous).
 * Real drives take real time, which is what reconciles all three:
 * on command acceptance status goes genuinely BSY and INTRQ stays
 * down for IDE_LAT of wall time; at the deadline the final status
 * appears and INTRQ asserts (pend==2) or DRQ appears silently
 * (pend==1: write/format data setup, no INTRQ per ATA). Mid-stream
 * block boundaries stay instant so drains are not throttled. */
#define IDE_LAT 80000ull       /* wall ticks: 100us at the 800MHz wall */
static uint64_t ide_now(void);        /* includer supplies (rd_wall64) */
#ifdef HOST_TEST
extern char *getenv(const char *);
extern unsigned long long strtoull(const char *, char **, int);
static uint64_t ide_lat_val(void)              /* diagnostic override  */
{
    static uint64_t v;
    if (!v) { const char *e = getenv("IDELAT");
              v = e ? strtoull(e, 0, 10) : IDE_LAT; }
    return v;
}
#else
#define ide_lat_val() IDE_LAT
#endif
static void ide_pend(ide_dev *d, uint8_t kind)
{
    d->pend_status = d->status;
    d->status  = IDE_ST_BSY;
    d->pend    = kind;
    d->done_at = ide_now() + ide_lat_val();
}
/* M12e: [ider] -- RAM-band register trace. The 400-access [idet] cap
 * dies in the ROM's boot drain every boot, leaving the RAM-resident
 * tool's conversation (AHDI's -- the one that fails) invisible. Gate
 * a compact full-value trace on the PC band instead: ROM (>=E00000)
 * and vector-page fetches stay silent, RAM programs print. Own
 * budget, ultra-compact lines to keep the 38400 UART cost ~5s. */
#define IDER_MAX 1500u
static uint32_t ider_n;
static int pc_in_ram(void)
{
    uint32_t p = cur_pc();
    return p >= 0x1000u && p < 0x00E00000u;   /* not vectors, not ROM */
}
static int pc_in_ram_fwd(void) { return pc_in_ram(); }   /* M12e bridge */

static void ide_lat_poll(void)
{
    int u;
    for (u = 0; u < 2; u++) {
        ide_dev *d = &ide[u];
        if (d->pend && (int64_t)(ide_now() - d->done_at) >= 0) {
            d->status = d->pend_status;
            if (d->pend == 2u) ide_intrq = 1u;
            d->pend = 0u;
        }
    }
}

/* M12a: [ided] -- data-phase summary. The [idet] byte trace dies at
 * 400 accesses (the ROM's boot IDENTIFY eats it every boot), so a
 * later reader's data phase -- HDX's, the one in dispute -- is
 * structurally invisible. Tally the phase instead: bytes served and
 * consumed since the previous command, plus the first 8 bytes that
 * went over the wire, printed just before the next [idec] line and
 * at SRST. Rides the idec budget. */
static uint32_t ided_rd, ided_wr;
static uint32_t ided_phase;            /* a data phase was RAISED      */
static uint8_t  ided_f8[8];
static uint32_t ided_n8;
static void ided_flush(void)
{
    if ((ided_rd | ided_wr | ided_phase) == 0u) return;
    if (ide_dbg && idec_n < IDEC_MAX) { idec_n++;
        printf("[ided] prev r=%u w=%u first8=%02x %02x %02x %02x "
               "%02x %02x %02x %02x\r\n", ided_rd, ided_wr,
               ided_f8[0], ided_f8[1], ided_f8[2], ided_f8[3],
               ided_f8[4], ided_f8[5], ided_f8[6], ided_f8[7]); }
    ided_rd = 0u; ided_wr = 0u; ided_n8 = 0u; ided_phase = 0u;
    memset(ided_f8, 0, sizeof ided_f8);   /* r=0 lines show zeros, not stale */
}
/* M11u: the m11t trace showed the wait loop at a RAM pc watch the
 * BSY->DRQ transition happen and keep spinning ~4M passes anyway --
 * so its exit condition is none of the obvious ones and guessing has
 * a losing record here. The loop is guest code in our own ram[], and
 * Musashi links a disassembler: dump the loop ONCE, read the exit
 * condition off the log. */
static uint8_t ide_loop_dumped;
static void ide_dump_loop(uint32_t pc)
{
    uint32_t a, start, end;
    char dis[128];
    if (ide_loop_dumped || pc >= ST_RAM_SIZE) return;
    ide_loop_dumped = 1u;
    start = (pc > 0x60u) ? pc - 0x60u : 0u;
    end   = pc + 0x60u;
    printf("[idis] wait loop around pc=%x:\r\n", pc);
    for (a = start; a < end; ) {
        uint32_t n = m68k_disassemble(dis, a, M68K_CPU_TYPE_68030);
        printf("[idis] %s%06x: %s\r\n", (a == pc) ? ">" : " ", a, dis);
        a += n ? n : 2u;
    }
}

/* ---- geometry ------------------------------------------------------ */
static void ide_geom(ide_dev *d)
{
    d->heads = 16u;
    d->spt   = 63u;
    d->cyls  = d->sectors / (16u * 63u);
    if (d->cyls > 16383u) d->cyls = 16383u;   /* ATA CHS ceiling         */
    if (d->cyls == 0u)    d->cyls = 1u;
}

static void ide_signature(ide_dev *d)
{
    d->pend = 0u;       /* M12d: reset cancels pending          */
    d->scnt = 1u; d->snum = 1u; d->clo = 0u; d->chi = 0u;
    d->err  = 1u;                              /* diagnostics passed     */
    d->status = d->present ? (uint8_t)(IDE_ST_DRDY | IDE_ST_DSC) : 0u;
    d->bidx = 0u; d->left = 0u; d->drq_wr = 0u; d->fmt = 0u;
    ide_intrq = 0u;                    /* M11y: reset clears INTRQ     */
}

static void ide_attach(int unit)
{
    ide_dev *d = &ide[unit];
    memset(d, 0, sizeof(*d));
    if (unit >= 0 && unit < 2 && hdf[unit].mounted) {
        d->present = 1u;
        d->sectors = hdf[unit].sectors;
        ide_geom(d);
        printf("[ide] device %d: %u sectors, CHS %u/%u/%u%s\r\n",
               unit, d->sectors, d->cyls, d->heads, d->spt,
               d->sectors > d->cyls * d->heads * d->spt
                 ? " (LBA reaches the tail CHS cannot)" : "");
    } else {
        printf("[ide] device %d: absent\r\n", unit);
    }
    ide_signature(d);
}

/* ---- IDENTIFY DEVICE ----------------------------------------------- */
static void ide_put_str(uint8_t *b, int woff, const char *s, int words)
{
    int i;
    /* M11t: ATA puts the first char of each pair in bits 15:8. Our bus
     * hands bytes over in order (first byte = bits 15:8), so natural
     * order is correct; the ^1 swap was for little-endian delivery and
     * double-swapped here. */
    for (i = 0; i < words * 2; i++) {
        char c = s[i] ? s[i] : ' ';
        b[woff * 2 + i] = (uint8_t)c;
        if (!s[i]) { int j; for (j = i; j < words * 2; j++)
                        b[woff * 2 + j] = ' '; break; }
    }
}

static void ide_put16(uint8_t *b, int woff, uint32_t v)
{
    /* M11t: BIG-endian. The guest reads the data register a byte at a
     * time and assembles each word 68k-style, first byte = bits 15:8.
     * M11s stored these little-endian; IDENTIFY drained successfully
     * and then AHDI rejected the device because every word was
     * byte-swapped (word 0 read back 0x8a84 instead of 0x0040). */
    b[woff * 2 + 0] = (uint8_t)((v >> 8) & 0xFFu);
    b[woff * 2 + 1] = (uint8_t)(v & 0xFFu);
}

/* M12g: dynamic model string. Priority: HDnNAME= from FALCON.CFG
 * (<=40 chars), else the hardfile's 8.3 stem (HD0.IMG -> "HD0"),
 * else the historic default. Serial stays FIXED (drivers key on
 * it); rev field finally unstuck from "M11Q". Truncated-unit-box
 * evidence (HDX shows 20-odd chars) is why short names matter. */
static void ide_model_name(int unit, char *out40)
{
    int i, n = 0;
    const char *ov = cfg_hdname[unit & 1];
    for (i = 0; i < 40; i++) out40[i] = ' ';
    if (ov[0]) { while (n < 40 && ov[n]) { out40[n] = ov[n]; n++; } return; }
    if (cfg_hd[unit & 1][0]) {                    /* 8.3 "NAME    EXT"   */
        for (i = 0; i < 8 && cfg_hd[unit & 1][i] != ' '; i++)
            out40[n++] = cfg_hd[unit & 1][i];
        if (n) return;
    }
    { const char *df = "FalconFPGA SD-backed hardfile";
      while (n < 40 && df[n]) { out40[n] = df[n]; n++; } }
}

static void ide_identify(ide_dev *d, int unit)
{
    uint32_t chs = d->cyls * d->heads * d->spt;
    memset(d->buf, 0, 512);
    ide_put16(d->buf,  0, 0x0040u);              /* fixed device          */
    ide_put16(d->buf,  1, d->cyls);
    ide_put16(d->buf,  3, d->heads);
    ide_put16(d->buf,  6, d->spt);
    ide_put_str(d->buf, 10, unit ? "FALCONFPGA-HD1" : "FALCONFPGA-HD0", 10);
    ide_put_str(d->buf, 23, "M12G", 4);           /* M12g: rev unstuck   */
    { char nm[40]; ide_model_name(unit, nm);      /* M12g: dynamic name  */
      ide_put_str(d->buf, 27, nm, 20); }
    ide_put16(d->buf, 47, 1u);                   /* 1 sector per int      */
    ide_put16(d->buf, 49, 0x0200u);              /* LBA supported         */
    ide_put16(d->buf, 53, 0x0001u);              /* words 54-58 valid     */
    ide_put16(d->buf, 54, d->cyls);
    ide_put16(d->buf, 55, d->heads);
    ide_put16(d->buf, 56, d->spt);
    ide_put16(d->buf, 57, chs & 0xFFFFu);
    ide_put16(d->buf, 58, chs >> 16);
    ide_put16(d->buf, 60, d->sectors & 0xFFFFu); /* LBA28 total           */
    ide_put16(d->buf, 61, d->sectors >> 16);
    /* M12b (D8b): Atari HDX reads CHS geometry from the VENDOR words
     * 130/131, not the ATA-standard 54-56, matching the Conner CP-era
     * drives it was written for (disassembly of hdx.prg: geometry
     * extractor at 0x22c90 reads ($104,A1)=w130 cyls, ($106/$107,A1)
     * =w131 heads/sectors, then issues 0x91). We zeroed >61, so HDX
     * saw 0/0/0 -> dashes + "Cannot format". Mirror geometry there. */
    ide_put16(d->buf, 130, d->cyls);
    ide_put16(d->buf, 131, (uint16_t)((d->heads << 8) | (d->spt & 0xFFu)));
    d->bidx = 0u; d->drq_wr = 0u; d->left = 0u;
    d->status = IDE_ST_DRDY | IDE_ST_DSC | IDE_ST_DRQ;
}

/* ---- addressing ---------------------------------------------------- */
static uint32_t ide_target_lba(ide_dev *d)
{
    if (d->head & 0x40u)                          /* LBA mode            */
        return ((uint32_t)(d->head & 0x0Fu) << 24)
             | ((uint32_t)d->chi << 16)
             | ((uint32_t)d->clo << 8)
             |  (uint32_t)d->snum;
    /* CHS: exact, and consistent with what IDENTIFY published */
    return (((uint32_t)d->chi << 8 | d->clo) * d->heads
            + (uint32_t)(d->head & 0x0Fu)) * d->spt
           + (uint32_t)d->snum - 1u;
}

static void ide_abort(ide_dev *d, uint8_t ecode)
{
    d->err = ecode;
    d->status = IDE_ST_DRDY | IDE_ST_DSC | IDE_ST_ERR;
    d->left = 0u; d->bidx = 0u; d->drq_wr = 0u;
    ide_bad_cmds++;
    ide_pend(d, 2u);                   /* M12d: error completion, lat  */
}

static void ide_swapbuf(ide_dev *d)
{
    uint32_t i; uint8_t t;
    for (i = 0; i + 1u < 512u; i += 2u) {
        t = d->buf[i]; d->buf[i] = d->buf[i + 1u]; d->buf[i + 1u] = t;
    }
}

/* load the next sector of a read transfer into buf */
static int ide_fill(ide_dev *d, int unit)
{
    if (hdd_read(unit, d->lba, d->buf)) { ide_abort(d, IDE_ER_IDNF); return -1; }
    if (d->swap) ide_swapbuf(d);
    d->bidx = 0u;
    d->status = IDE_ST_DRDY | IDE_ST_DSC | IDE_ST_DRQ;
    return 0;
}

static void ide_command(int unit, uint8_t cmd)
{
    ide_dev *d = &ide[unit];
    if (!d->present) { d->status = 0u; return; }
    d->pend = 0u;       /* M12d: new command cancels stale pend */

    ided_flush();                      /* M12a: summarize prev phase   */

    /* M11x: task file BEFORE dispatch mutates it. The lba field is
     * only meaningful for data commands (20/30/40/C4/C5 families);
     * for 0x91/EC/etc it is whatever the stale task file computes --
     * ignore it there. */
    if (ide_dbg && idec_n < IDEC_MAX) { idec_n++;
        printf("[idec] dev%d cmd=%02x %s tf: cnt=%02x snum=%02x "
               "cyl=%04x hd=%x lba=%u geom=%u/%u/%u pc=%x\r\n",
               unit, cmd, (d->head & 0x40u) ? "LBA" : "CHS",
               d->scnt, d->snum,
               (unsigned)(((uint32_t)d->chi << 8) | d->clo),
               d->head & 0x0Fu, ide_target_lba(d),
               d->cyls, d->heads, d->spt, cur_pc()); }

    switch (cmd) {
    case 0x08u:                                   /* DEVICE RESET        */
        ide_signature(d);
        ide_pend(d, 1u); return;                           /* M12d     */

    case 0x10u: case 0x11u: case 0x12u: case 0x13u:
    case 0x14u: case 0x15u: case 0x16u: case 0x17u:
    case 0x18u: case 0x19u: case 0x1Au: case 0x1Bu:
    case 0x1Cu: case 0x1Du: case 0x1Eu: case 0x1Fu: /* RECALIBRATE       */
        d->err = 0u; d->status = IDE_ST_DRDY | IDE_ST_DSC;
        ide_pend(d, 2u); return;                           /* M12d     */

    case 0x20u: case 0x21u:                       /* READ SECTORS        */
    case 0xC4u:                                   /* READ MULTIPLE       */
        d->lba  = ide_target_lba(d);
        d->left = d->scnt ? d->scnt : 256u;
        d->drq_wr = 0u;
        ide_rd_cmds++;
        if (!ide_fill(d, unit)) {      /* abort inside fill already pends */
            ided_phase = 1u;
            ide_pend(d, 2u);           /* M12d: block1 ready after lat  */
        }
        return;

    case 0xE0u: case 0xE1u: case 0xE2u: case 0xE3u:  /* STANDBY/IDLE     */
    case 0xE6u: case 0x94u: case 0x95u: case 0x96u:  /* + SLEEP + aliases */
    case 0x97u:
        /* M12g: power-management family. Atari's own driver issues
         * AWTO ($E3); Hatari accepts the family; we aborted. No-op
         * success -- a file-backed drive is always awake. */
        d->err = 0u;
        d->status = IDE_ST_DRDY | IDE_ST_DSC;
        ide_pend(d, 2u); return;
    case 0xE5u: case 0x98u:                       /* CHECK POWER MODE    */
        d->err = 0u; d->scnt = 0xFFu;             /* 0xFF = active       */
        d->status = IDE_ST_DRDY | IDE_ST_DSC;
        ide_pend(d, 2u); return;
    case 0x50u:                                   /* FORMAT TRACK        */
        /* M12c: file-backed image has no physical tracks. Accept the
         * command, run ONE DRQ write phase to consume HDX's sector-
         * descriptor buffer, discard it (writing it as sector data
         * would corrupt the image), complete OK. This is the command
         * Atari HDX's format loop (hdx.prg 0x22ce0) issues per track;
         * without it we aborted -> "Cannot format unit 0". */
        d->left = 1u;                  /* one descriptor-buffer phase   */
        d->bidx = 0u; d->drq_wr = 1u; d->fmt = 1u;
        ided_phase = 1u;
        d->status = IDE_ST_DRDY | IDE_ST_DSC | IDE_ST_DRQ;
        ide_pend(d, 1u);                                   /* M12d     */
        return;
    case 0x30u: case 0x31u:                       /* WRITE SECTORS       */
    case 0xC5u:                                   /* WRITE MULTIPLE      */
        d->lba  = ide_target_lba(d);
        d->left = d->scnt ? d->scnt : 256u;
        d->bidx = 0u; d->drq_wr = 1u;
        ided_phase = 1u;               /* M12a */
        ide_wr_cmds++;
        d->status = IDE_ST_DRDY | IDE_ST_DSC | IDE_ST_DRQ;
        ide_pend(d, 1u);                                   /* M12d     */
        return;

    case 0x40u: case 0x41u:                       /* READ VERIFY         */
        d->lba = ide_target_lba(d);
        if (d->lba >= d->sectors) { ide_abort(d, IDE_ER_IDNF); return; }
        d->err = 0u; d->status = IDE_ST_DRDY | IDE_ST_DSC;
        ide_pend(d, 2u); return;                           /* M12d     */

    case 0x91u:                                   /* INIT DEVICE PARAMS  */
        /* the driver dictates the translation it wants to use */
        d->spt   = d->scnt ? d->scnt : 63u;
        d->heads = (uint32_t)(d->head & 0x0Fu) + 1u;
        if (d->spt && d->heads)
            d->cyls = d->sectors / (d->spt * d->heads);
        if (d->cyls == 0u) d->cyls = 1u;
        if (ide_dbg && idec_n < IDEC_MAX) { idec_n++;
            printf("[idec] dev%d 0x91 -> geom=%u/%u/%u\r\n",
                   unit, d->cyls, d->heads, d->spt); }
        d->err = 0u; d->status = IDE_ST_DRDY | IDE_ST_DSC;
        ide_pend(d, 2u); return;                           /* M12d     */

    case 0xE7u:                                   /* FLUSH CACHE         */
        /* write-through: nothing is ever held back, so this is a no-op   */
        d->err = 0u; d->status = IDE_ST_DRDY | IDE_ST_DSC;
        ide_pend(d, 2u); return;                           /* M12d     */

    case 0xECu:                                   /* IDENTIFY DEVICE     */
        d->err = 0u; ide_identify(d, unit);
        ided_phase = 1u;
        ide_pend(d, 2u); return;                           /* M12d     */

    case 0xEFu:                                   /* SET FEATURES        */
        d->err = 0u; d->status = IDE_ST_DRDY | IDE_ST_DSC;
        ide_pend(d, 2u); return;                           /* M12d     */

    default:
        ide_abort(d, IDE_ER_ABRT); return;
    }
}

/* ---- data register ------------------------------------------------- */
static uint32_t ide_data_read8(int unit)
{
    ide_dev *d = &ide[unit];
    uint8_t v;
    ide_lat_poll();                    /* M12d */
    if (!d->present || !(d->status & IDE_ST_DRQ)) return 0xFFu;
    v = d->buf[d->bidx++];
    ided_rd++; if (ided_n8 < 8u) ided_f8[ided_n8++] = (uint8_t)v;  /* M12a */
    if (d->bidx >= 512u) {
        if (d->left) d->left--;
        if (d->left) { d->lba++;
            if (!ide_fill(d, unit)) ide_intrq = 1u;  /* M12d: instant  */
        }
        else { d->status = IDE_ST_DRDY | IDE_ST_DSC; d->bidx = 0u; }
    }
    return v;
}

static void ide_data_write8(int unit, uint8_t v)
{
    ide_dev *d = &ide[unit];
    ide_lat_poll();                    /* M12d */
    if (!d->present || !(d->status & IDE_ST_DRQ) || !d->drq_wr) return;
    d->buf[d->bidx++] = v;
    ided_wr++; if (ided_n8 < 8u) ided_f8[ided_n8++] = (uint8_t)v;  /* M12a */
    if (d->bidx >= 512u) {
        if (!d->fmt) {
            if (d->swap) ide_swapbuf(d);
            if (hdd_write(unit, d->lba, d->buf)) { ide_abort(d, IDE_ER_IDNF); return; }
        }
        d->bidx = 0u;
        if (d->left) d->left--;
        if (d->left) { d->lba++;
            d->status = IDE_ST_DRDY|IDE_ST_DSC|IDE_ST_DRQ;
            ide_intrq = 1u;            /* M12d: per-block, instant     */
        } else {
            d->status = IDE_ST_DRDY | IDE_ST_DSC; d->drq_wr = 0u; d->fmt = 0u;
            ide_pend(d, 2u);           /* M12d: completion after lat   */
        }
    }
}

/* ---- bus interface ------------------------------------------------- */
static int is_ide(uint32_t a)                  /* M12g: 24-bit alias   */
{   /* real Falcon decodes the IDE in 24-bit space; $00F00000 and
     * $FFF00000 are the same device (Hatari: addr &= 0x00ffffff).
     * The blitter got this mask in m12f; the CPU path gets it here. */
    return ((a & 0x00FFFFFFu) - 0x00F00000u) < 0x40u;
}

static uint32_t ide_read8(uint32_t a)
{
    uint32_t off = (a & 0x00FFFFFFu) - 0x00F00000u;  /* M12g alias */
    ide_dev *d = &ide[ide_sel];
    uint32_t rv;
    if (off <= 3u) {   /* M11v: data register spans fff00000..03.
        * EmuTOS's Falcon driver reads it with MOVE.L (32-bit
        * transfers, two ATA words per access): on real hardware the
        * longword access runs two bus cycles, both hitting the
        * 16-bit data register. Decoding only bytes 0-1 fed EmuTOS
        * 0040 0000 0020 0000... -- every second word zero, buffer
        * advancing 2 bytes per 4-byte read, IDENTIFY shredded,
        * mount declined. Seen directly in the silicon trace: four
        * byte-reads from one pc, the last two hitting +02/+03. */
        rv = ide_data_read8(ide_sel);
        if (ide_dbg && ide_trc < IDE_TRC_MAX) { ide_trc++;
            printf("  [idet] R data -> %02x  bidx=%u left=%u st=%02x "
                   "pc=%x\r\n", (unsigned)rv, d->bidx, d->left,
                   d->status, cur_pc()); }
        if (ide_dbg && pc_in_ram() && ider_n < IDER_MAX) { ider_n++;
            printf("rD=%02x\r\n", (unsigned)rv); }          /* M12e */
        return rv;
    }
    /* An absent device answers 0x00 everywhere -- notably NOT 0xFF, which
     * would read as BSY and hang the driver. It also means the 0xAA/0x55
     * scribble cannot read back, so detection correctly fails. */
    if (!d->present) {
        if (ide_dbg && ide_trc < IDE_TRC_MAX) { ide_trc++;
            printf("  [idet] R +%02x -> 00  dev%u ABSENT pc=%x\r\n",
                   off, ide_sel, cur_pc()); }
        if (ide_dbg && pc_in_ram() && ider_n < IDER_MAX) { ider_n++;
            printf("rR%02x=00!\r\n", off); }                /* M12e */
        return 0x00u;
    }
    switch (off) {
    case 0x05u: rv = d->err;  break;
    case 0x09u: rv = d->scnt; break;
    case 0x0Du: rv = d->snum; break;
    case 0x11u: rv = d->clo;  break;
    case 0x15u: rv = d->chi;  break;
    case 0x19u: rv = (uint32_t)(d->head | 0xA0u | (ide_sel ? 0x10u : 0u));
                break;
    case 0x1Du:                        /* status: read clears INTRQ    */
        ide_lat_poll();                /* M12d: latency may expire now */
        rv = d->status;
        ide_intrq = 0u;                /* M11y                         */
        break;
    case 0x39u:                        /* alt status: NO INTRQ clear   */
        ide_lat_poll();                /* M12d                         */
        rv = d->status;
        break;
    default:    rv = 0x00u;     break;
    }
    if (ide_dbg && ide_trc < IDE_TRC_MAX) { ide_trc++;
        printf("  [idet] R +%02x -> %02x  dev%u err=%02x drq=%u bidx=%u "
               "pc=%x\r\n", off, (unsigned)rv, ide_sel, d->err,
               (d->status & IDE_ST_DRQ) ? 1u : 0u, d->bidx, cur_pc()); }
    if (ide_dbg && pc_in_ram() && ider_n < IDER_MAX) { ider_n++;
        printf("rR%02x=%02x\r\n", off, (unsigned)rv); }     /* M12e */
    if (ide_dbg && ide_trc == 40u) ide_dump_loop(cur_pc());   /* M11u */
    return rv;
}

static void ide_write8(uint32_t a, uint8_t v)
{
    uint32_t off = (a & 0x00FFFFFFu) - 0x00F00000u;  /* M12g alias */
    if (ide_dbg && ide_trc < IDE_TRC_MAX) { ide_trc++;
        printf("  [idet] W +%02x = %02x  dev%u st=%02x pc=%x\r\n",
               off, v, ide_sel, ide[ide_sel].status, cur_pc()); }
    if (ide_dbg && pc_in_ram() && ider_n < IDER_MAX) { ider_n++;
        printf("rW%02x=%02x\r\n", off, v); }                /* M12e */
    if (off <= 3u) { ide_data_write8(ide_sel, v); return; }  /* M11v */
    if (off == 0x19u) {                   /* head/device: selects, always */
        ide_sel = (uint8_t)((v >> 4) & 1u);
        ide[ide_sel].head = v;
        return;
    }
    if (off == 0x39u) {
        uint8_t old = ide_devctl;
        ide_devctl = v;
        if ((v & 0x04u) && !(old & 0x04u)) {      /* SRST asserted        */
            ided_flush();                          /* M12a                 */
            ide_signature(&ide[0]); ide_signature(&ide[1]);
            if (ide_dbg && idec_n < IDEC_MAX) { idec_n++;
                printf("[idec] SRST: geom kept dev0=%u/%u/%u dev1=%u/%u/%u\r\n",
                       ide[0].cyls, ide[0].heads, ide[0].spt,
                       ide[1].cyls, ide[1].heads, ide[1].spt); }
        }
        return;
    }
    /* Everything else lands in the SELECTED device's own register file.
     * Absent devices must not retain it, or EmuTOS's 0xAA/0x55 scribble
     * reads back and a phantom drive appears. */
    if (!ide[ide_sel].present) return;
    switch (off) {
    case 0x05u: ide[ide_sel].feat = v; break;
    case 0x09u: ide[ide_sel].scnt = v; break;
    case 0x0Du: ide[ide_sel].snum = v; break;
    case 0x11u: ide[ide_sel].clo  = v; break;
    case 0x15u: ide[ide_sel].chi  = v; break;
    case 0x1Du: ide_intrq = 0u;        /* M11y: new cmd clears INTRQ   */
                ide_command(ide_sel, v); break;
    default: break;
    }
}

static void ide_init(void)
{
    ide_sel = 0u; ide_devctl = 0u;
    ide_attach(0);
    ide_attach(1);
}
