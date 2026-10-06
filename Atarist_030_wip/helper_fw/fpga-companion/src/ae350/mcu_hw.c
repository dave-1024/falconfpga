/*
  mcu_hw.c - AE350 (Gowin GW5AST RiscV_AE350_SOC) hardware layer for
  FPGA-Companion, ST_HELPER build of the falconfpga Atari ST core on the
  Tang Console 138K.

  FPGA-Companion is (c) Till Harbaum and the MiSTle-Dev contributors,
  Apache-2.0 (../../LICENSE). This file plays the role of bl616/mcu_hw.c,
  rp2040/mcu_hw.c and esp32/mcu_hw.c: everything the shared sources need
  from the MCU, nothing else. The AE350 takes over the BL616's job; the
  BL616 stays on its stock firmware and off the companion link.

  Hardware (core side: st_helper_mculink.v, st_helper_ctrl.v; see
  docs/ST_HELPER.md sections 1, 2 and 5a):
   - the image runs from DDR3 (BUILD_BURN loader.c copied it from flash
     0x600000). GPIO[7:0] = 0xA5 hands the SPI flash to the ST for good,
     after that the flash must never be read again.
   - companion SPI (the core's misc/mcu_spi.v, MODE1) is bit-banged:
       SS# = GPIO[0], SCK = GPIO[1], MOSI = GPIO[2], MISO = UART2 MSR.CTS
     The SoC's SPI controller registers are not reachable in this SoC
     (0xF0F00000 reads 0, 0xF0B00000 hangs the bus): never touch them.
   - core IRQ# = UART2 MSR.DCD (1 = pending), link up = MSR.DSR,
     MSR.RI = the SoC flash CS# is low (diagnostic only).
   - UART2 (ATCUART100, 16550 registers at +0x20) 115200 8N1 is the console:
     TX goes to U15 (BL616 USB serial, COM4 on David's laptop) and into the
     ST's $FFFB00 mailbox, RX is the PC (V14) AND the mailbox.
   - no interrupts: the main loop polls MSR.DCD (bare-metal, see main.c).
*/

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>

#include "../mcu_hw.h"
#include "ae350_hw.h"
#include <FreeRTOS.h>
#include <task.h>

/* ---------------- registers ---------------- */
#define UART_BASE   0xF0300000u
#define UART_OSCR   (UART_BASE + 0x14u)
#define UART_THR    (UART_BASE + 0x20u)   /* RBR/THR, DLL when DLAB=1 */
#define UART_IER    (UART_BASE + 0x24u)   /* DLM when DLAB=1 */
#define UART_FCR    (UART_BASE + 0x28u)
#define UART_LCR    (UART_BASE + 0x2Cu)
#define UART_MCR    (UART_BASE + 0x30u)
#define UART_LSR    (UART_BASE + 0x34u)
#define UART_MSR    (UART_BASE + 0x38u)
#define MSR_CTS     0x10u                 /* MISO level */
#define MSR_DSR     0x20u                 /* fabric: companion link up */
#define MSR_RI      0x40u                 /* fabric: SoC flash CS# low */
#define MSR_DCD     0x80u                 /* fabric: core IRQ# asserted */

#define GPIO_BASE   0xF0700000u           /* ATCGPIO100 */
#define GPIO_DOUT   (GPIO_BASE + 0x24u)
#define GPIO_DIR    (GPIO_BASE + 0x28u)

#define PLMT_MTIME  0xE6000000u           /* machine timer, 32768 Hz on AE350 */

#define HS_CODE     0xA5u
#define UCLK_HZ     50000000u             /* REF_TEST_CLK: APB/UART 50 MHz */
#define BAUD        115200u

#define GP_SS       0x01u
#define GP_SCK      0x02u
#define GP_MOSI     0x04u

static inline void wr(unsigned a, unsigned v) { *(volatile unsigned *)a = v; }
static inline unsigned rd(unsigned a) { return *(volatile unsigned *)a; }

/* ---------------- console (UART2) ---------------- */
static void uart_init(void) {
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

/* RX is drained into a ring whenever we wait for anything (TX space, SPI
   bits, delays), so a line from the ST mailbox or the PC is not lost to the
   16 byte UART FIFO while the companion code is busy. */
static unsigned char rxq[512];
static volatile unsigned rxh, rxt;
void ae350_rx_poll(void) {
  unsigned lsr, c;
  while((lsr = rd(UART_LSR)) & 0x01u) {
    c = rd(UART_THR) & 0xFFu;
    if((lsr & 0x1Cu) || c == 0u) continue;          /* PE, FE, BI, NUL */
    if(((rxh + 1u) & 511u) != rxt) { rxq[rxh] = (unsigned char)c; rxh = (rxh + 1u) & 511u; }
  }
}

int ae350_getc_nb(void) {
  int c;
  ae350_rx_poll();
  if(rxh == rxt) return -1;
  c = rxq[rxt];
  rxt = (rxt + 1u) & 511u;
  return c;
}

void ae350_putc(char c) {
  while((rd(UART_LSR) & 0x20u) == 0) ae350_rx_poll();
  wr(UART_THR, (unsigned char)c);
}

void ae350_puts(const char *s) { while(*s) ae350_putc(*s++); }

/* ---------------- time base ----------------
   FreeRTOS ticks (1 ms) for the timeouts in sdc.c/sysctrl.c. The CPU cycle
   counter is calibrated against the UART at boot (one character = 10 bits
   at 115200 Bd, the one clock on this board that is known to be right).
   Fallbacks: the PLMT mtime (32768 Hz) if mcycle does not count, else a
   crude per-call counter so that no timeout loop can hang forever. */
static uint32_t cyc_per_ms;
static int tick_src;                    /* 0 = mcycle, 1 = mtime, 2 = counter */
static uint32_t soft_ticks;

static uint64_t rd_mcycle(void) {
  uint32_t hi, lo, hi2;
  do {
    __asm__ volatile ("csrr %0, mcycleh" : "=r"(hi));
    __asm__ volatile ("csrr %0, mcycle"  : "=r"(lo));
    __asm__ volatile ("csrr %0, mcycleh" : "=r"(hi2));
  } while(hi != hi2);
  return ((uint64_t)hi << 32) | lo;
}

static uint32_t rd_mtime_lo(void) { return rd(PLMT_MTIME); }

TickType_t xTaskGetTickCount(void) {
  if(tick_src == 0) return (TickType_t)(rd_mcycle() / cyc_per_ms);
  if(tick_src == 1) return (TickType_t)(((uint64_t)rd_mtime_lo() * 1000u) >> 15);
  return (TickType_t)(++soft_ticks >> 4);
}

void vTaskDelay(TickType_t ticks) {
  TickType_t t0 = xTaskGetTickCount();
  while((TickType_t)(xTaskGetTickCount() - t0) < ticks) ae350_rx_poll();
}

uint32_t ae350_cycles_per_ms(void) { return cyc_per_ms; }
int ae350_tick_source(void) { return tick_src; }

/* send s and measure how long the UART needs for it */
static void calibrate_with(const char *s) {
  unsigned n = strlen(s);
  while(!(rd(UART_LSR) & 0x40u)) ;               /* TEMT: shifter idle */
  uint64_t c0 = rd_mcycle();
  uint32_t m0 = rd_mtime_lo();
  ae350_puts(s);
  while(!(rd(UART_LSR) & 0x40u)) ae350_rx_poll();
  uint64_t d = rd_mcycle() - c0;
  uint32_t dm = rd_mtime_lo() - m0;
  /* n chars * 10 bits / 115200 Bd  ->  cycles per ms = d * 11520 / (n * 1000) */
  uint64_t cpm = (d * 11520u) / ((uint64_t)n * 1000u);
  if(cpm > 1000u) { tick_src = 0; cyc_per_ms = (uint32_t)cpm; }
  else if(dm)     { tick_src = 1; }
  else            { tick_src = 2; }
  (void)dm;
  printf("time base: %s, %lu CPU cycles/ms (%lu MHz), mtime +%lu in %u chars\r\n",
         tick_src == 0 ? "mcycle" : tick_src == 1 ? "PLMT mtime" : "software counter",
         (unsigned long)cpm, (unsigned long)(cpm / 1000u), (unsigned long)dm, n);
}

/* ---------------- companion SPI, bit-banged ----------------
   MODE1 like the BL616: MOSI changes with the rising edge, mcu_spi samples
   it on the falling edge and drives MISO after the rising edge, so MISO is
   read just before the falling edge. Each half period waits bb_div UART MSR
   reads (blocking APB reads, ~100 ns each); bb_div = 8 is the value proven
   on the board with mailbox v3/v4. st_helper_mculink.v re-registers the
   pins on the 50 MHz AHB clock and needs two equal samples per level, so
   the absolute floor is ~80 ns per half period (passed simulation at
   6.25 MHz). Console command "spd <n>" changes bb_div at run time. */
static unsigned gpio_shadow;
static unsigned bb_div = 2;   /* 6 Oct: xml link test 20/20 OK at 4, 2 and 1;
                                 2 keeps a 2x margin (XML read 63 ms at 8, 22 ms at 1) */
static int link_up;

static void gpio_set(unsigned v) { gpio_shadow = v; wr(GPIO_DOUT, v); }
static inline void bb_wait(void) { unsigned i; for(i = 0; i < bb_div; i++) (void)rd(UART_MSR); }

void mcu_hw_spi_begin(void) {
  ae350_rx_poll();
  gpio_set(gpio_shadow & ~(GP_SS | GP_SCK));
  bb_wait();
}

unsigned char mcu_hw_spi_tx_u08(unsigned char b) {
  unsigned r = 0, v;
  int i;
  for(i = 7; i >= 0; i--) {
    v = (gpio_shadow & ~(GP_SCK | GP_MOSI)) | (((b >> i) & 1u) ? GP_MOSI : 0u);
    gpio_set(v | GP_SCK);                         /* rising edge, MOSI valid */
    bb_wait();
    r = (r << 1) | ((rd(UART_MSR) & MSR_CTS) ? 1u : 0u);
    gpio_set(v);                                  /* falling edge: core samples */
    bb_wait();
  }
  /* one LSR read per byte keeps the console RX FIFO drained during long
     transfers (a 512 byte sector takes several ms) */
  if(rd(UART_LSR) & 0x01u) ae350_rx_poll();
  return (unsigned char)r;
}

void mcu_hw_spi_end(void) {
  bb_wait();
  gpio_set((gpio_shadow & ~GP_SCK) | GP_SS);
  bb_wait();
}

unsigned ae350_spi_div(void) { return bb_div; }
void ae350_spi_set_div(unsigned d) { if(d < 1) d = 1; if(d > 200) d = 200; bb_div = d; }

/* ---------------- core interrupt ----------------
   The BL616 port takes a GPIO interrupt and notifies the com task; here the
   main loop polls the level (sysctrl.v keeps int_out_n low until acked via
   SPI_SYS_IRQ_CTRL). */
int mcu_hw_irq_pending(void) { return link_up && (rd(UART_MSR) & MSR_DCD) != 0; }
void mcu_hw_irq_ack(void) { /* level polled, nothing to re-arm */ }

unsigned ae350_msr(void) { return rd(UART_MSR) & 0xFFu; }
int ae350_link_up(void) { return link_up; }

/* ---------------- init: flash handoff, link ---------------- */
void mcu_hw_init(void) {
  unsigned t;

  uart_init();
  gpio_set(GP_SS);                                /* SS# idle high */
  wr(GPIO_DIR, rd(GPIO_DIR) | 0xFFu);

  /* done with the flash: everything from here on runs from DDR3. The
     fabric waits up to 2 s for 0xA5, so do this before anything slow. */
  calibrate_with("\r\nAE350 FPGA-Companion (ST_HELPER port, steps 1-3), running from DDR3\r\n");
  printf("flash CS# before 0xA5: %s\r\n", (rd(UART_MSR) & MSR_RI) ? "LOW (asserted)" : "high");
  gpio_set(HS_CODE);                              /* 0xA5, bit 0 = SS# high */
  printf("0xA5 sent, flash handed to the ST\r\n");

  for(t = 0; t < 2000u && !(rd(UART_MSR) & MSR_DSR); t++) vTaskDelay(1);
  if(!(rd(UART_MSR) & MSR_DSR)) {
    printf("link: DSR never set by the fabric, companion link not used\r\n");
    return;
  }
  gpio_set(GP_SS);                                /* SS# high, SCK low, MOSI low */
  link_up = 1;
  printf("link: fabric says up, MSR %02x, bit-bang divider %u\r\n", ae350_msr(), bb_div);
}

/* The BL616 port reboots the MCU (FPGA cold boot IRQ, long button press).
   This image cannot be reloaded: the flash belongs to the ST after 0xA5. */
void mcu_hw_reset(void) {
  printf("MCU reset requested: ignored (AE350 cannot reload after the flash handoff)\r\n");
}

/* ---------------- no USB on the AE350 (yet) ----------------
   USB HID (port step 4) comes from usb_hid_host.v in the fabric; USB mass
   storage and core upload are not planned. */
bool mcu_hw_hid_present(void) { return false; }
bool mcu_hw_usb_msc_present(void) { return false; }
void mcu_hw_usb_sector_read(void *buffer, int sector, int count) { (void)buffer; (void)sector; (void)count; }
void mcu_hw_upload_core(char *name) { printf("core upload (%s) not supported on the AE350\r\n", name ? name : "?"); }
void mcu_hw_port_byte(unsigned char b) { (void)b; }

/* ---------------- C library glue (newlib / picolibc) ---------------- */
extern char _end[];                               /* ae350-ddr.ld */
#define HEAP_MAX   (8u * 1024u * 1024u)           /* stack is at 0x08000000 */
static char *heap_top;

void *_sbrk(ptrdiff_t incr) {
  char *prev;
  if(!heap_top) heap_top = _end;
  if((size_t)(heap_top + incr - _end) > HEAP_MAX) { errno = ENOMEM; return (void *)-1; }
  prev = heap_top;
  heap_top += incr;
  return prev;
}
void *sbrk(ptrdiff_t incr) { return _sbrk(incr); }
