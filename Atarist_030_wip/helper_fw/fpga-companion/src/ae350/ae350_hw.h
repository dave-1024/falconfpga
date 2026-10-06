/* ae350_hw.h - AE350-only helpers of the FPGA-Companion port (mcu_hw.c).
   FPGA-Companion: Till Harbaum and the MiSTle-Dev contributors, Apache-2.0. */
#ifndef AE350_HW_H
#define AE350_HW_H
#include <stdint.h>

void ae350_rx_poll(void);
int  ae350_getc_nb(void);
void ae350_putc(char c);
void ae350_puts(const char *s);

int  mcu_hw_irq_pending(void);
unsigned ae350_msr(void);
int  ae350_link_up(void);
unsigned ae350_spi_div(void);
void ae350_spi_set_div(unsigned d);
uint32_t ae350_cycles_per_ms(void);
int  ae350_tick_source(void);

/* console.c */
void console_init(void);
void console_poll(void);

#endif
