/* AE350 ready stub. 115200 8N1 on UART2, then GPIO 0xA5.
 * "alive" means main started. "release" means the mark is being written.
 */
#define UART_BASE 0xF0300000u
#define GPIO_BASE 0xF0700000u
#define GPIO_DOUT (GPIO_BASE + 0x24u)
#define GPIO_DIR  (GPIO_BASE + 0x28u)

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
    uart_puts("alive\r\n");
    uart_puts("release\r\n");
    wr(GPIO_DIR, 0x000000FFu);
    wr(GPIO_DOUT, 0x000000A5u);
    for (;;)
        ;
    return 0;
}
