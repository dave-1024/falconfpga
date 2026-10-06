/* AE350 helper, mailbox v2 (build option ST_HELPER, build_st_helper.tcl).
 * Flash output/helper_mailbox.bin at 0x0600000 (leading 0, not 0x6000000).
 *
 * 1. "Done with flash": GPIO[7:0] = 0xA5 (after flash_release()). This image runs from DDR3 (the
 *    BUILD_BURN loader in loader.c copied it there), so from here on the
 *    flash is never touched. The fabric (st_helper_ctrl.v) then waits for
 *    our flash CS# to be idle, gives the flash pins to the ST for good and
 *    releases the 68030 (TOS boots).
 * 2. Companion link: once UART2 MSR.DSR = 1 (fabric: link up) our idle flash
 *    SPI controller (SPI1, ATCSPI200) is wired to the core's mcu_spi, the
 *    port the BL616 / FPGA-Companion normally drives (st_helper_mculink.v):
 *      SS#  = GPIO[0] (frame select, mcu_hw_spi_begin/end)
 *      SCK/MOSI/MISO = SPI1, MODE1, one byte per transfer
 *      IRQ# = UART2 MSR.DCD (1 = core interrupt pending)
 *    The link test sends the FPGA-Companion sys_status_is_valid() frame
 *    (sysctrl.c) and expects 5C 42.
 * 3. Mailbox: UART2 RX carries bytes the ST wrote to $FFFB07 and what David
 *    types in the PC terminal (BL616 USB serial TX, V14); UART2 TX goes to
 *    U15 (USB serial) and into the ST's RX FIFO ($FFFB09). Every byte is
 *    echoed; on CR the line is answered. Commands: "s" link status, "i" IRQ
 *    line, "?" help; anything else is echoed back in upper case.
 *
 * UART2 is an ATCUART100: the 16550 registers start at +0x20 (ready.c).
 */
#define UART_BASE   0xF0300000u
#define UART_OSCR   (UART_BASE + 0x14u)
#define UART_THR    (UART_BASE + 0x20u)   /* RBR/THR, DLL when DLAB=1 */
#define UART_IER    (UART_BASE + 0x24u)   /* DLM when DLAB=1 */
#define UART_FCR    (UART_BASE + 0x28u)
#define UART_LCR    (UART_BASE + 0x2Cu)
#define UART_MCR    (UART_BASE + 0x30u)
#define UART_LSR    (UART_BASE + 0x34u)
#define UART_MSR    (UART_BASE + 0x38u)
#define MSR_DSR     0x20u                 /* fabric: companion link up */
#define MSR_RI      0x40u                 /* fabric: our flash CS# is low (asserted) */
#define MSR_DCD     0x80u                 /* fabric: core IRQ# asserted */

#define GPIO_BASE   0xF0700000u           /* ATCGPIO100 */
#define GPIO_DOUT   (GPIO_BASE + 0x24u)
#define GPIO_DIR    (GPIO_BASE + 0x28u)

/* Flash SPI controller (ATCSPI200, memory-mapped at 0x80000000; "spi1" in
 * the SoC netlist, FLASH_SPI_* ports). The Gowin AE350 BSP (ae350.h,
 * SPI_BASE) puts the SoC's only SPI at 0xF0F00000. The Andes reference map
 * has a flash SPI at 0xF0B00000, but in this SoC nothing answers there: v1
 * read it and the bus hung (hardware, 6 Oct 2026). */
#ifndef SPI1_BASE
#define SPI1_BASE   0xF0F00000u
#endif
#define SPI_IDREV   (SPI1_BASE + 0x00u)
#define SPI_FMT     (SPI1_BASE + 0x10u)
#define SPI_TCTRL   (SPI1_BASE + 0x20u)
#define SPI_CMD     (SPI1_BASE + 0x24u)
#define SPI_DATA    (SPI1_BASE + 0x2Cu)
#define SPI_CTRL    (SPI1_BASE + 0x30u)
#define SPI_STATUS  (SPI1_BASE + 0x34u)
#define SPI_INTREN  (SPI1_BASE + 0x38u)
#define SPI_TIMING  (SPI1_BASE + 0x40u)
#ifndef SPI_SCLK_DIV
#define SPI_SCLK_DIV 15u                  /* spi_clk / 32, see st_helper_mculink.v */
#endif

#define HS_CODE     0xA5u
#define UCLK_HZ     50000000u
#define BAUD        115200u

static inline void wr(unsigned a, unsigned v) { *(volatile unsigned *)a = v; }
static inline unsigned rd(unsigned a) { return *(volatile unsigned *)a; }

static unsigned gpio_shadow;
static int link_ok;
static int spi_usable;               /* SPI1 probed OK and link up */

static void delay(unsigned n) { while (n--) __asm__ volatile ("nop"); }

/* ---------------- UART2 ---------------- */
static void uart_init(void)
{
    unsigned div = (UCLK_HZ + 8u * BAUD) / (16u * BAUD);   /* 27 */
    wr(UART_OSCR, 16u);
    wr(UART_IER, 0u);
    wr(UART_LCR, 0x80u);
    wr(UART_THR, div & 0xFFu);
    wr(UART_IER, (div >> 8) & 0xFFu);
    wr(UART_LCR, 0x03u);
    wr(UART_FCR, 0x07u);
    wr(UART_MCR, 0u);
}
static void putc_(char c)
{
    while ((rd(UART_LSR) & 0x20u) == 0) ;
    wr(UART_THR, (unsigned char)c);
}
static void puts_(const char *s) { while (*s) putc_(*s++); }
static void puthex(unsigned v, int digits)
{
    while (digits--) putc_("0123456789ABCDEF"[(v >> (digits * 4)) & 0xFu]);
}
static void putdec(unsigned v)
{
    char b[11]; int i = 0;
    do { b[i++] = (char)('0' + v % 10u); v /= 10u; } while (v);
    while (i) putc_(b[--i]);
}
/* UART2 RX is the ST mailbox AND the PC terminal (V14). Bytes with a
 * framing/parity error or break, and NULs, are dropped, so an idle-low or
 * noisy line cannot flood the echo. */
static int getc_nb(void)
{
    unsigned lsr = rd(UART_LSR);
    if (lsr & 0x01u) {
        unsigned c = rd(UART_THR) & 0xFFu;
        if ((lsr & 0x1Cu) || c == 0u) return -1;   /* PE, FE, BI */
        return (int)c;
    }
    return -1;
}

/* ---------------- companion SPI (mcu_hw_spi_* equivalents) ---------------- */
static void gpio_set(unsigned v) { gpio_shadow = v; wr(GPIO_DOUT, v); }

static void spi_init(void)
{
    while (rd(SPI_STATUS) & 1u) ;                    /* idle */
    wr(SPI_INTREN, 0u);
    wr(SPI_FMT, (7u << 8) | 1u);                     /* 8 bit, MSB first, CPHA=1 CPOL=0 (MODE1) */
    wr(SPI_CTRL, rd(SPI_CTRL) | 0x6u);               /* reset RX and TX FIFO */
    while (rd(SPI_CTRL) & 0x6u) ;
    wr(SPI_TIMING, (rd(SPI_TIMING) & ~0xFFu) | SPI_SCLK_DIV);
}
static void mcu_spi_begin(void) { gpio_set(gpio_shadow & ~1u); }   /* SS# low */
static void mcu_spi_end(void)   { gpio_set(gpio_shadow |  1u); }   /* SS# high */
static unsigned char mcu_spi_tx_u08(unsigned char b)
{
    wr(SPI_TCTRL, 0u);              /* no cmd/addr, write&read, 1 byte each way */
    wr(SPI_CMD, 0u);                /* start */
    while (rd(SPI_STATUS) & (1u << 23)) ;            /* TX FIFO full */
    wr(SPI_DATA, b);
    while (rd(SPI_STATUS) & 1u) ;                    /* transfer done */
    while (rd(SPI_STATUS) & (1u << 14)) ;            /* RX FIFO empty */
    return (unsigned char)rd(SPI_DATA);
}

/* FPGA-Companion sysctrl.c sys_status_is_valid(), byte for byte */
static int core_status(int verbose)
{
    unsigned char b0, b1, id, cb;
    mcu_spi_begin();
    mcu_spi_tx_u08(0);              /* SPI_TARGET_SYS */
    mcu_spi_tx_u08(0);              /* SPI_SYS_STATUS */
    mcu_spi_tx_u08(0);
    b0 = mcu_spi_tx_u08(0);
    b1 = mcu_spi_tx_u08(0);
    id = mcu_spi_tx_u08(0);
    cb = mcu_spi_tx_u08(0);
    mcu_spi_end();
    if (verbose) {
        puts_("core status: "); puthex(b0, 2); putc_(' '); puthex(b1, 2);
        puts_(" id="); puthex(id, 2); puts_(" cb="); puthex(cb, 2);
        puts_((b0 == 0x5C && b1 == 0x42) ? " -> link OK\r\n" : " -> no 5C 42, link FAIL\r\n");
    }
    return b0 == 0x5C && b1 == 0x42;
}

/* End any memory-mapped flash access so the controller lets CS# go high:
 * one register-mode, command-only transfer (WRDI 0x04, harmless). On
 * hardware v1 the fabric saw CS# stay low after the boot loader's copy
 * although the CPU ran from DDR3, and fell back ('C'). */
static void flash_release(void)
{
    unsigned t;
    for (t = 0; t < 1000000u && (rd(SPI_STATUS) & 1u); t++) ;
    wr(SPI_TCTRL, (1u << 30) | (7u << 24));          /* CmdEn, TransMode 7 = no data */
    wr(SPI_CMD, 0x04u);                              /* WRDI, starts the transfer */
    for (t = 0; t < 1000000u && (rd(SPI_STATUS) & 1u); t++) ;
}
static void cs_report(const char *when)
{
    puts_("flash CS# "); puts_(when); puts_(": ");
    puts_((rd(UART_MSR) & MSR_RI) ? "LOW (asserted)" : "high");
    puts_("\r\n");
}

static void irq_report(void)
{
    puts_("core IRQ# ");
    puts_((rd(UART_MSR) & MSR_DCD) ? "asserted (pending, not acked by this test)\r\n" : "idle\r\n");
}

static void link_bringup(void)
{
    unsigned t, id;
    for (t = 0; t < 2000u && !(rd(UART_MSR) & MSR_DSR); t++)
        delay(10000u);
    if (!(rd(UART_MSR) & MSR_DSR)) {
        puts_("link: DSR never set by the fabric, companion link not used\r\n");
        return;
    }
    puts_("link: fabric says up (MSR "); puthex(rd(UART_MSR), 2); puts_(")\r\n");
    id = rd(SPI_IDREV);
    puts_("SPI IDREV "); puthex(id, 8);
    if ((id >> 16) != 0x0200u) {
        puts_(" (not an ATCSPI200, link not used)\r\n");
        return;
    }
    puts_("\r\n");
    spi_init();
    spi_usable = 1;
    link_ok = core_status(1);
    irq_report();
}

static void help(void)
{
    puts_("commands: s = core status over the companion SPI link, "
          "i = core IRQ line, ? = this; other lines are echoed in upper case\r\n");
}

int main(void)
{
    char line[64];
    unsigned n = 0;

    /* 1. done with flash: everything below runs from DDR3. The fabric waits
     *    up to 2 s for 0xA5, so there is time to report first. */
    uart_init();
    gpio_set(0x01u);                                 /* SS# (GPIO[0]) idle high */
    wr(GPIO_DIR, rd(GPIO_DIR) | 0xFFu);
    puts_("\r\nAE350 helper mailbox v2 (running from DDR3)\r\n");
    puts_("flash SPI @"); puthex(SPI1_BASE, 8); puts_(": IDREV ");
    puthex(rd(SPI_IDREV), 8);
    puts_(" MEMCTRL "); puthex(rd(SPI1_BASE + 0x50u), 8);
    puts_(" STATUS "); puthex(rd(SPI_STATUS), 8); puts_("\r\n");
    cs_report("after boot copy");
    flash_release();
    cs_report("after release");
    gpio_set(HS_CODE);                               /* 0xA5: done with flash */
    puts_("0xA5 sent, flash handed to the ST\r\n");
    link_bringup();
    help();
    puts_("> ");

    for (;;) {
        int c = getc_nb();
        if (c < 0) continue;
        if (c == '\r' || c == '\n') {
            line[n] = 0;
            puts_("\r\n");
            if (n == 1 && line[0] == 's') {
                if (spi_usable)
                    link_ok = core_status(1);
                else
                    puts_("companion link not up (see boot messages)\r\n");
            } else if (n == 1 && line[0] == 'i') {
                irq_report();
            } else if (n == 1 && line[0] == '?') {
                help();
            } else if (n) {
                unsigned i;
                puts_("helper: got "); putdec(n); puts_(" bytes: ");
                for (i = 0; i < n; i++) {
                    char u = line[i];
                    if (u >= 'a' && u <= 'z') u = (char)(u - 32);
                    putc_(u);
                }
                puts_("\r\n");
            }
            n = 0;
            puts_("> ");
        } else if (c == 8 || c == 127) {
            if (n) { n--; puts_("\b \b"); }
        } else {
            putc_((char)c);                          /* echo */
            if (n < sizeof(line) - 1) line[n++] = (char)c;
        }
    }
    return 0;
}
