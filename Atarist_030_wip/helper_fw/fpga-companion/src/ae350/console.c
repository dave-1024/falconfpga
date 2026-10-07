/*
  console.c - COM4 command line of the AE350 FPGA-Companion port.

  There is no OSD yet (port step 5), so the companion's file selector and
  system menu are reachable as text commands on UART2 (U15/V14 -> BL616
  USB serial, COM4 on David's laptop). Every command ends with Enter.
  The same UART is the ST's $FFFB00 mailbox, so lines that are not commands
  are answered "helper: got N bytes: ..." like mailbox v4 (the self-test
  cartridge relies on that).

  Uses the unmodified FPGA-Companion sdc.c / sysctrl.c / inifile.c /
  config.c (Till Harbaum and the MiSTle-Dev contributors, Apache-2.0).
*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdint.h>
#include <ff.h>

#include "../mcu_hw.h"
#include "../sysctrl.h"
#include "../sdc.h"
#include "../config.h"
#include "../inifile.h"
#include "../menu.h"
#include "ae350_hw.h"

static const char *drive_name[4] = { "A:", "B:", "ACSI 0", "ACSI 1" };

static void help(void) {
  printf("commands (end each with Enter):\r\n"
         "  osd <ev> ... OSD menu as the keyboard would drive it (F12 opens it):\r\n"
         "               toggle (F12) up down left right select (Enter) back (Esc) pgup pgdn\r\n"
         "  usb          USB keyboard/mouse status (Console USB-A ports, fabric host)\r\n"
         "  s            core status over the companion link (SYS target)\r\n"
         "  i            core IRQ line and pending sources\r\n"
         "  w / c        reset / cold-boot the ST (sysctrl R=1 / R=3, then 0)\r\n"
         "  sd [init]    SD card and drive status [re-initialise the card]\r\n"
         "  ls [dir]     list an SD directory (default /sd)\r\n"
         "  mount <d> <file>  insert an image: d = a, b (floppy .st), h0, h1 (ACSI .hd/.img)\r\n"
         "  eject <d>    remove the image from drive d\r\n"
         "  save         write the mounted images to /sd/atarist.ini (mounted at boot)\r\n"
         "  cfg          dump the core's XML config\r\n"
         "  spd [n]      bit-bang delay per half SCK period (default 2)\r\n"
         "  xml [n]      link test: read the core's gzip'd XML config n times (default 1)\r\n"
         "  key <k> ...  press keys on the ST via the core's HID target: a-z 0-9 ret esc\r\n"
         "               space tab bs del up down left right f1-f10 help undo, alt+x ctrl+x shift+x\r\n"
         "  type <text>  type text on the ST (letters, digits, space, '.')\r\n"
         "  mouse <dx> <dy>  move the ST mouse;  click [2]  left click (2 = double)\r\n"
         "  put <f> / h <hex> / pend  upload a file to /sd (PC script, hex lines)\r\n"
         "  ?            this help; other lines are echoed in upper case\r\n");
}

static int sd_ready(void) {
  if(sdc_get_cwd(0)) return 1;
  printf("SD card not mounted (see 'sd'; 'sd init' retries)\r\n");
  return 0;
}

static int parse_drive(const char *s) {
  if(!s) return -1;
  if(!strcasecmp(s, "a") || !strcasecmp(s, "a:") || !strcmp(s, "0")) return 0;
  if(!strcasecmp(s, "b") || !strcasecmp(s, "b:") || !strcmp(s, "1")) return 1;
  if(!strcasecmp(s, "h0") || !strcasecmp(s, "hd0") || !strcmp(s, "2")) return 2;
  if(!strcasecmp(s, "h1") || !strcasecmp(s, "hd1") || !strcmp(s, "3")) return 3;
  return -1;
}

static void core_status(void) {
  unsigned char b0, b1, id, cb;
  mcu_hw_spi_begin();
  mcu_hw_spi_tx_u08(SPI_TARGET_SYS);
  mcu_hw_spi_tx_u08(SPI_SYS_STATUS);
  mcu_hw_spi_tx_u08(0);
  b0 = mcu_hw_spi_tx_u08(0);
  b1 = mcu_hw_spi_tx_u08(0);
  id = mcu_hw_spi_tx_u08(0);
  cb = mcu_hw_spi_tx_u08(0);
  mcu_hw_spi_end();
  printf("core status: %02X %02X id=%02X cb=%02X -> %s\r\n", b0, b1, id, cb,
         (b0 == 0x5C && b1 == 0x42) ? "link OK" : "no 5C 42, link FAIL");
}

static void irq_report(void) {
  unsigned msr = ae350_msr();
  unsigned char pend = sys_irq_ctrl(0);         /* ack nothing, read pending */
  printf("core IRQ# %s, pending sources %02X (bit0 sys, bit1 hid, bit3 sdc)\r\n",
         (msr & 0x80) ? "asserted" : "idle", pend);
}

static void st_reset(int cold) {
  printf(cold ? "ST cold boot via sysctrl R=3\r\n" : "ST reset via sysctrl R=1\r\n");
  sys_set_val('R', cold ? 3 : 1);
  vTaskDelay(pdMS_TO_TICKS(100));
  sys_set_val('R', 0);
}

static void sd_status(void) {
  unsigned char st;
  static const char *type[] = { "UNKNOWN", "SDv1", "SDv2", "SDHCv2" };
  mcu_hw_spi_begin();
  mcu_hw_spi_tx_u08(SPI_TARGET_SDC);
  mcu_hw_spi_tx_u08(SPI_SDC_STATUS);
  st = mcu_hw_spi_tx_u08(0);
  mcu_hw_spi_end();
  printf("SD (core sd_card.v): status %02X, card state %d (%s), type %s\r\n", st, st >> 4,
         ((st & 0xF0) == 0x80) ? "ready" : "not ready: no card, card not routed to the FPGA, or init failed",
         type[(st >> 2) & 3]);
  printf("FAT: %s\r\n", sdc_get_cwd(0) ? "mounted as /sd" : "not mounted");
  for(int d = 0; d < 4; d++) {
    char *n = sdc_get_image_name(d);
    printf("  drive %d %-7s %s%s%s\r\n", d, drive_name[d], n ? sdc_get_cwd(d) : "", n ? "/" : "", n ? n : "(empty)");
  }
}

static void sd_ls(const char *path) {
  DIR dir; FILINFO fno; int n = 0;
  if(!sd_ready()) return;
  if(!path) path = sdc_get_cwd(0);
  sdc_lock();
  FRESULT r = f_opendir(&dir, path);
  if(r != FR_OK) { sdc_unlock(); printf("ls %s: error %d\r\n", path, r); return; }
  printf("directory %s:\r\n", path);
  for(;;) {
    if(f_readdir(&dir, &fno) != FR_OK || !fno.fname[0]) break;
    const char *dot = strrchr(fno.fname, '.');
    const char *tag = "";
    if(dot && !strcasecmp(dot, ".st")) tag = "  [floppy: mount a/b]";
    else if(dot && (!strcasecmp(dot, ".hd") || !strcasecmp(dot, ".img"))) tag = "  [hard disk: mount h0/h1]";
    else if(dot && !strcasecmp(dot, ".msa")) tag = "  [MSA: convert to .ST first]";
    if(fno.fattrib & AM_DIR) printf("  %-40s  <DIR>\r\n", fno.fname);
    else printf("  %-40s %10lu%s\r\n", fno.fname, (unsigned long)fno.fsize, tag);
    n++;
  }
  f_closedir(&dir);
  sdc_unlock();
  printf("%d entries\r\n", n);
}

static void sd_mount(int drive, const char *file) {
  if(!sd_ready()) return;
  const char *dot = strrchr(file, '.');
  if(dot && !strcasecmp(dot, ".msa")) {
    printf("MSA images are compressed; the core reads raw sectors (.ST) like MiSTeryNano.\r\n"
           "Convert it on the PC first (e.g. Hatari: hmsa file.msa -> file.st).\r\n");
    return;
  }
  /* full path below /sd, or relative to the drive's current directory */
  char full[300];
  if(file[0] == '/') snprintf(full, sizeof(full), "%s", file);
  else snprintf(full, sizeof(full), "%s/%s", sdc_get_cwd(drive), file);
  if(strncasecmp(full, CARD_MOUNTPOINT "/", strlen(CARD_MOUNTPOINT) + 1)) {
    printf("path must be below %s\r\n", CARD_MOUNTPOINT);
    return;
  }
  sdc_set_default(drive, full);                 /* splits into cwd + name */
  char *n = sdc_get_image_name(drive);
  if(!n) { printf("bad file name\r\n"); return; }
  char name[strlen(n) + 1];
  strcpy(name, n);                              /* sdc_image_open frees its copy */
  if(sdc_image_open(drive, name) == 0)
    printf("drive %d (%s): %s mounted\r\n", drive, drive_name[drive], full);
  else
    printf("drive %d (%s): mounting %s FAILED (file missing?)\r\n", drive, drive_name[drive], full);
}

static void sd_eject(int drive) {
  if(!sd_ready()) return;
  sdc_image_open(drive, NULL);
  printf("drive %d (%s): ejected\r\n", drive, drive_name[drive]);
}

/* ---- HID target: what hid.c sends once USB HID (port step 4) exists.
   Until then these commands let the PC drive the ST's keyboard and mouse
   through the same frames (misc/hid.v: key code = USB HID usage, modifiers
   at 0x68+, bit 7 = released). ---- */
static void kbd_tx(uint8_t code) {
  mcu_hw_spi_begin();
  mcu_hw_spi_tx_u08(SPI_TARGET_HID);
  mcu_hw_spi_tx_u08(SPI_HID_KEYBOARD);
  mcu_hw_spi_tx_u08(code);
  mcu_hw_spi_end();
}

static int key_code(const char *k) {
  static const struct { const char *n; uint8_t c; } names[] = {
    {"ret",0x28},{"enter",0x28},{"esc",0x29},{"bs",0x2a},{"tab",0x2b},{"space",0x2c},
    {"del",0x4c},{"ins",0x49},{"home",0x4a},{"help",0x4b},{"undo",0x4e},
    {"right",0x4f},{"left",0x50},{"down",0x51},{"up",0x52},{".",0x37},{"-",0x2d},{"/",0x38},
    {NULL,0}
  };
  if(!k[1] && k[0] >= 'a' && k[0] <= 'z') return 0x04 + k[0] - 'a';
  if(!k[1] && k[0] >= '1' && k[0] <= '9') return 0x1e + k[0] - '1';
  if(!k[1] && k[0] == '0') return 0x27;
  if((k[0] == 'f' || k[0] == 'F') && k[1] >= '1' && k[1] <= '9') {
    int n = atoi(k + 1);
    if(n >= 1 && n <= 10) return 0x3a + n - 1;
  }
  for(int i = 0; names[i].n; i++) if(!strcasecmp(k, names[i].n)) return names[i].c;
  return -1;
}

/* one key with optional modifier prefixes ("alt+a", "shift+ctrl+x") */
static int key_press(const char *tok) {
  uint8_t mods[3]; int nm = 0;
  char t[24]; snprintf(t, sizeof(t), "%s", tok);
  char *k = t, *plus;
  while((plus = strchr(k, '+')) && plus[1]) {
    *plus = 0;
    if(!strcasecmp(k, "ctrl")) mods[nm++] = 0x68;
    else if(!strcasecmp(k, "shift")) mods[nm++] = 0x69;
    else if(!strcasecmp(k, "alt")) mods[nm++] = 0x6a;
    else return -1;
    k = plus + 1;
    if(nm == 3) break;
  }
  int c = key_code(k);
  if(c < 0) return -1;
  for(int i = 0; i < nm; i++) { kbd_tx(mods[i]); vTaskDelay(30); }
  kbd_tx((uint8_t)c); vTaskDelay(80);
  kbd_tx(0x80 | (uint8_t)c); vTaskDelay(30);
  for(int i = nm - 1; i >= 0; i--) { kbd_tx(0x80 | mods[i]); vTaskDelay(30); }
  vTaskDelay(50);
  return 0;
}

static void type_text(const char *s) {
  for(; *s; s++) {
    char k[16];
    if(*s >= 'A' && *s <= 'Z') snprintf(k, sizeof(k), "shift+%c", *s - 'A' + 'a');
    else if(*s == ' ') snprintf(k, sizeof(k), "space");
    else snprintf(k, sizeof(k), "%c", *s);
    if(key_press(k)) printf("cannot type '%c'\r\n", *s);
  }
}

static void mouse_tx(uint8_t btns, int8_t dx, int8_t dy) {
  mcu_hw_spi_begin();
  mcu_hw_spi_tx_u08(SPI_TARGET_HID);
  mcu_hw_spi_tx_u08(SPI_HID_MOUSE);
  mcu_hw_spi_tx_u08(btns);
  mcu_hw_spi_tx_u08((uint8_t)dx);
  mcu_hw_spi_tx_u08((uint8_t)dy);
  mcu_hw_spi_end();
}

/* hid.v plays the counts out as quadrature steps (one per ~1 ms), so big
   moves go in chunks */
static void mouse_move(int dx, int dy) {
  while(dx || dy) {
    int sx = dx > 60 ? 60 : dx < -60 ? -60 : dx;
    int sy = dy > 60 ? 60 : dy < -60 ? -60 : dy;
    mouse_tx(0, (int8_t)sx, (int8_t)sy);
    dx -= sx; dy -= sy;
    vTaskDelay(80);
  }
}

static void mouse_click(int n) {
  for(int i = 0; i < n; i++) {
    mouse_tx(1, 0, 0); vTaskDelay(60);
    mouse_tx(0, 0, 0); vTaskDelay(80);
  }
}

/* Link integrity and speed test: SPI_SYS_READ_CFG streams the core's
   gzip'd atarist.xml (~1 KB) and puff() inflates it twice (size pass,
   then data pass), so a single wrong bit fails the inflate or changes the
   FNV-1a hash of the result. */
static void xml_test(int n) {
  static uint32_t ref_hash; static unsigned ref_len;
  int ok = 0;
  for(int i = 0; i < n; i++) {
    TickType_t t0 = xTaskGetTickCount();
    char *x = sys_get_config();
    TickType_t dt = xTaskGetTickCount() - t0;
    if(!x) { printf("xml %d: read/inflate FAILED (%lu ms)\r\n", i, (unsigned long)dt); continue; }
    uint32_t h = 2166136261u; unsigned len = 0;
    for(char *c = x; *c; c++, len++) h = (h ^ (unsigned char)*c) * 16777619u;
    vPortFree(x);
    if(!ref_len) { ref_len = len; ref_hash = h; }
    int same = (len == ref_len && h == ref_hash);
    ok += same;
    if(n == 1 || !same)
      printf("xml %d: %u bytes, hash %08lx, %lu ms at spd %u -> %s\r\n", i, len, (unsigned long)h,
             (unsigned long)dt, ae350_spi_div(), same ? "OK" : "MISMATCH");
  }
  if(n > 1) printf("xml: %d/%d OK at spd %u\r\n", ok, n, ae350_spi_div());
}


static void osd_events(const char *q) {
  static const struct { const char *n; unsigned long e; } ev[] = {
    {"toggle",MENU_EVENT_TOGGLE},{"f12",MENU_EVENT_TOGGLE},{"up",MENU_EVENT_UP},{"down",MENU_EVENT_DOWN},
    {"left",MENU_EVENT_LEFT},{"right",MENU_EVENT_RIGHT},{"select",MENU_EVENT_SELECT},{"enter",MENU_EVENT_SELECT},
    {"back",MENU_EVENT_BACK},{"esc",MENU_EVENT_BACK},{"pgup",MENU_EVENT_PGUP},{"pgdn",MENU_EVENT_PGDOWN},
    {"system",MENU_EVENT_SYSTEM},{NULL,0}
  };
  char tok[16];
  while(*q) {
    while(*q == ' ') q++;
    int i = 0;
    while(*q && *q != ' ' && i < 15) tok[i++] = *q++;
    tok[i] = 0;
    if(!i) break;
    int k;
    for(k = 0; ev[k].n && strcasecmp(tok, ev[k].n); k++);
    if(!ev[k].n) { printf("unknown osd event '%s'\r\n", tok); continue; }
    menu_notify(ev[k].e);
    vTaskDelay(60);                     /* main context: the menu task runs from rtos_poll */
    extern void rtos_poll(void);
    for(int n = 0; n < 20; n++) rtos_poll();
    if(ev[k].e <= MENU_EVENT_BACK) menu_notify(MENU_EVENT_KEY_RELEASE);
    for(int n = 0; n < 20; n++) rtos_poll();
    vTaskDelay(150);
  }
}

/* ---- file upload to the SD card (hex lines, acked, for a PC script) ----
   put <file>   create/overwrite /sd/<file> (refuses atarist.ini)
   h <hex>      append bytes (up to 64, 2 hex digits each); "h0" = 64 zeros
   pend         close; prints size and CRC32
   Each h line answers "k <total>" or "e <reason>"; echo is off meanwhile. */
static FIL up_f; static int up_open; static uint32_t up_len, up_crc;
static void up_crc_add(const uint8_t *b, unsigned n) {
  while(n--) { up_crc ^= *b++; for(int k = 0; k < 8; k++) up_crc = (up_crc >> 1) ^ (0xEDB88320u & -(up_crc & 1u)); }
}
static int hexv(int c) { return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1; }
static void up_put(const char *name) {
  char path[96];
  if(!sd_ready()) return;
  if(!name || !*name || strchr(name, '/') || !strcasecmp(name, "atarist.ini")) { printf("e name\r\n"); return; }
  if(up_open) { f_close(&up_f); up_open = 0; }
  snprintf(path, sizeof(path), "%s/%s", CARD_MOUNTPOINT, name);
  if(f_open(&up_f, path, FA_WRITE | FA_CREATE_ALWAYS) != FR_OK) { printf("e open\r\n"); return; }
  up_open = 1; up_len = 0; up_crc = 0xFFFFFFFFu;
  printf("k 0\r\n");
}
static void up_hex(const char *q) {
  uint8_t b[64]; unsigned n = 0; UINT w;
  if(!up_open) { printf("e notopen\r\n"); return; }
  if(q[0] == '0' && !q[1]) { memset(b, 0, 64); n = 64; }
  else while(q[0] && q[1] && n < 64) {
    int h = hexv(q[0]), l = hexv(q[1]);
    if(h < 0 || l < 0) { printf("e hex\r\n"); return; }
    b[n++] = (uint8_t)(h << 4 | l); q += 2;
  }
  if(*q) { printf("e len\r\n"); return; }
  if(f_write(&up_f, b, n, &w) != FR_OK || w != n) { printf("e write\r\n"); return; }
  up_crc_add(b, n); up_len += n;
  printf("k %lu\r\n", (unsigned long)up_len);
}
static void up_end(void) {
  if(!up_open) { printf("e notopen\r\n"); return; }
  f_close(&up_f); up_open = 0;
  printf("done %lu bytes crc32 %08lx\r\n", (unsigned long)up_len, (unsigned long)(up_crc ^ 0xFFFFFFFFu));
}

static void run_line(const char *line) {
  char *argv[4]; int argc = 0;
  char buf[160];
  snprintf(buf, sizeof(buf), "%s", line);       /* split a copy, echo the raw line */
  char *p = buf;
  while(argc < 4) {
    while(*p == ' ' || *p == '\t') p++;
    if(!*p) break;
    argv[argc++] = p;
    /* the last argument of mount keeps its spaces (long file names) */
    if(argc == 3 && !strcasecmp(argv[0], "mount")) break;
    while(*p && *p != ' ' && *p != '\t') p++;
    if(*p) *p++ = 0;
  }
  if(!argc) return;
  const char *c = argv[0];
  if(!strcmp(c, "h")) { up_hex(argc > 1 ? argv[1] : ""); return; }
  if(!strcmp(c, "put")) { up_put(argc > 1 ? argv[1] : NULL); return; }
  if(!strcmp(c, "pend")) { up_end(); return; }
  int link = ae350_link_up();

  if(!strcmp(c, "?") || !strcasecmp(c, "help")) { help(); return; }
  if(!strcmp(c, "spd")) {
    if(argc > 1) ae350_spi_set_div((unsigned)atoi(argv[1]));
    printf("bit-bang delay %u MSR reads per half period\r\n", ae350_spi_div());
    return;
  }
  if(!link && (!strcmp(c, "s") || !strcmp(c, "i") || !strcmp(c, "w") || !strcmp(c, "c") ||
               !strcmp(c, "sd") || !strcmp(c, "ls") || !strcmp(c, "mount") ||
               !strcmp(c, "eject") || !strcmp(c, "save"))) {
    printf("companion link not up (see boot messages)\r\n");
    return;
  }
  if(!strcmp(c, "osd")) {
    if(!link) { printf("companion link not up\r\n"); return; }
    const char *q = line; while(*q == ' ') q++; q += 3;
    osd_events(q); printf("ok\r\n"); return;
  }
  if(!strcmp(c, "s")) { core_status(); return; }
  if(!strcmp(c, "usb")) { if(link) usb_status(); else printf("companion link not up\r\n"); return; }
  if(!strcmp(c, "i")) { irq_report(); return; }
  if(!strcmp(c, "w") || !strcmp(c, "c")) { st_reset(c[0] == 'c'); return; }
  if(!strcmp(c, "sd")) {
    if(argc > 1 && !strcmp(argv[1], "init")) sdc_init();
    sd_status();
    return;
  }
  if(!strcmp(c, "ls")) { sd_ls(argc > 1 ? argv[1] : NULL); return; }
  if(!strcmp(c, "mount")) {
    int d = parse_drive(argc > 1 ? argv[1] : NULL);
    if(d < 0 || argc < 3) { printf("usage: mount a|b|h0|h1 <file>\r\n"); return; }
    sd_mount(d, argv[2]);
    return;
  }
  if(!strcmp(c, "eject")) {
    int d = parse_drive(argc > 1 ? argv[1] : NULL);
    if(d < 0) { printf("usage: eject a|b|h0|h1\r\n"); return; }
    sd_eject(d);
    return;
  }
  if(!strcmp(c, "save")) {
    if(!sd_ready()) return;
    inifile_write("atarist.ini");
    printf("settings written to %s/atarist.ini\r\n", CARD_MOUNTPOINT);
    return;
  }
  if(!strcmp(c, "key") || !strcmp(c, "type") || !strcmp(c, "mouse") || !strcmp(c, "click")) {
    if(!link) { printf("companion link not up (see boot messages)\r\n"); return; }
    if(!strcmp(c, "key")) {
      /* argv holds at most 3 tokens: walk the raw line instead */
      const char *q = line; while(*q == ' ') q++; q += 3;
      char tok[24];
      while(*q) {
        while(*q == ' ') q++;
        int i = 0;
        while(*q && *q != ' ' && i < 23) tok[i++] = *q++;
        tok[i] = 0;
        if(i && key_press(tok)) printf("unknown key '%s'\r\n", tok);
      }
    } else if(!strcmp(c, "type")) {
      const char *q = line; while(*q == ' ') q++; q += 4; if(*q == ' ') q++;
      type_text(q);
    } else if(!strcmp(c, "mouse")) {
      if(argc < 3) { printf("usage: mouse <dx> <dy>\r\n"); return; }
      mouse_move(atoi(argv[1]), atoi(argv[2]));
    } else mouse_click(argc > 1 ? atoi(argv[1]) : 1);
    printf("ok\r\n");
    return;
  }
  if(!strcmp(c, "xml")) {
    if(!link) { printf("companion link not up (see boot messages)\r\n"); return; }
    xml_test(argc > 1 ? atoi(argv[1]) : 1);
    return;
  }
  if(!strcmp(c, "cfg")) {
    if(cfg) config_dump(); else printf("no core config loaded\r\n");
    return;
  }

  /* not a command: mailbox echo (v4 behaviour, used by the cartridge) */
  printf("helper: got %u bytes: ", (unsigned)strlen(line));
  for(const char *q = line; *q; q++) ae350_putc((*q >= 'a' && *q <= 'z') ? *q - 32 : *q);
  printf("\r\n");
}

static char line[160];
static unsigned n;

void console_init(void) {
  help();
  ae350_puts("> ");
}

void console_poll(void) {
  int c;
  while((c = ae350_getc_nb()) >= 0) {
    if(c == '\r' || c == '\n') {
      if(c == '\n' && n == 0) continue;           /* CR LF */
      line[n] = 0;
      if(!up_open) ae350_puts("\r\n");
      if(n) run_line(line);
      n = 0;
      if(!up_open) ae350_puts("> ");
    } else if(c == 8 || c == 127) {
      if(n) { n--; ae350_puts("\b \b"); }
    } else if(c >= 32) {
      if(!up_open) ae350_putc((char)c);
      if(n < sizeof(line) - 1) line[n++] = (char)c;
    }
  }
}
