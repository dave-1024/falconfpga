/* AE350 serial proof. Not connected to the 030.
 * 115200 8N1 on UART2. "AE350 alive" means main started.
 * Flash at 0x0600000. Does not write the GPIO mark.
 */
#define UART_BASE 0xF0300000u

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
    wr(UART_BASE + 0x0Cu, 0x80u);          /* DLAB */
    wr(UART_BASE + 0x00u, 27u);            /* 50 MHz / (16*115200) */
    wr(UART_BASE + 0x04u, 0u);
    wr(UART_BASE + 0x0Cu, 0x03u);          /* 8N1 */
    wr(UART_BASE + 0x08u, 0x01u);          /* FIFO enable */
}

static void uart_putc(char c)
{
    while ((rd(UART_BASE + 0x14u) & 0x20u) == 0)
        ;
    wr(UART_BASE + 0x00u, (unsigned)c);
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
