/* Tiny AE350 helper. Signals the fabric by driving GPIO[7:0] = 0xA5.
 * The fabric latches that, resets this core, and releases the 68030.
 * Linked like the hybrid firmware so the Gowin boot ROM can load it
 * from external flash at 0x0600000 into DDR3.
 */
#define GPIO_BASE 0xF0700000u
#define GPIO_DOUT  (GPIO_BASE + 0x24u)
#define GPIO_DIR   (GPIO_BASE + 0x28u)

static inline void wr(unsigned addr, unsigned val)
{
    *(volatile unsigned *)addr = val;
}

int main(void)
{
    wr(GPIO_DIR, 0x000000FFu);
    wr(GPIO_DOUT, 0x000000A5u);
    for (;;)
        ;
    return 0;
}
