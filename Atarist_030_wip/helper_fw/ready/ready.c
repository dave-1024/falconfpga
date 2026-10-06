/* AE350 serial proof. Not connected to the 030.
 * 115200 8N1 on UART2. "AE350 alive" means main started.
 * Flash at 0x0600000. Does not write the GPIO mark.
 *
 * UART2 is an Andes ATCUART100 (MUG1029 Table 7-1), not a bare 16550:
 * the 16550 registers start at +0x20. Offsets 0x00-0x1C are IDREV/CFG/
 * OSCR. The old stub polled +0x14 (OSCR, reset 0x10, bit 5 never set)
 * as if it were LSR, so it spun before the first character.
 *
 * UCLK is assumed to be APB_CLK = 50 MHz (gowin_pll_ae350 clkout3).
 * If the text arrives garbled, the baud is wrong, not the boot.
 */
#define UART_BASE   0xF0300000u
#define UART_OSCR   (UART_BASE + 0x14u)
#define UART_THR    (UART_BASE + 0x20u)   /* DLL when DLAB=1 */
#define UART_IER    (UART_BASE + 0x24u)   /* DLM when DLAB=1 */
#define UART_FCR    (UART_BASE + 0x28u)
#define UART_LCR    (UART_BASE + 0x2Cu)
#define UART_MCR    (UART_BASE + 0x30u)
#define UART_LSR    (UART_BASE + 0x34u)

#ifndef UCLK_HZ
#define UCLK_HZ     50000000u
#endif
#define BAUD        115200u
#define OVERSAMPLE  16u

static inline void wr(unsigned addr, unsigned val)
{
    *(volatile unsigned *)addr = val;
}
static inline unsigned rd(unsigned addr)
{
    return *(volatile unsigned *)addr;
}

static void uart_init(void)
{
    unsigned div = (UCLK_HZ + (OVERSAMPLE * BAUD) / 2u) / (OVERSAMPLE * BAUD); /* 27 */

    wr(UART_OSCR, OVERSAMPLE);             /* reset value, set explicitly */
    wr(UART_IER, 0u);                      /* no interrupts (DLAB=0) */
    wr(UART_LCR, 0x80u);                   /* DLAB */
    wr(UART_THR, div & 0xFFu);             /* DLL */
    wr(UART_IER, (div >> 8) & 0xFFu);      /* DLM */
    wr(UART_LCR, 0x03u);                   /* 8N1, DLAB off */
    wr(UART_FCR, 0x07u);                   /* FIFO on, clear RX/TX */
    wr(UART_MCR, 0u);
}

static void uart_putc(char c)
{
    while ((rd(UART_LSR) & 0x20u) == 0)    /* THRE */
        ;
    wr(UART_THR, (unsigned)c);
}

static void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

int main(void)
{
    uart_init();
    uart_puts("AE350 alive\r\n");
    for (;;)
        ;
    return 0;
}
