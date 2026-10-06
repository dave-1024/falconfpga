/*
  usb.c - USB keyboard/mouse for the AE350 port of FPGA-Companion (step 4)

  The BL616 is a USB host itself; the AE350 is not. On this board two
  usb_hid_host cores in the fabric (st_helper_usb.v, ST_HELPER_USB, nand2mario)
  run the Console's USB-A ports in HID boot protocol, and this file polls
  their latched reports over the companion link (HID target, command 0x40).
  Each report is rebuilt as the 8 byte keyboard / 3 byte mouse boot packet and
  handed to FPGA-Companion's own hid.c (kbd_parse, mouse_parse), which sends
  the key and mouse events back on the HID target exactly as on MiSTeryNano.
  Low-speed devices only, no hubs (usb_hid_host limits).
*/
#include <stdio.h>
#include <string.h>
#include "../mcu_hw.h"
#include "../spi.h"
#include "../hid.h"
#include "../debug.h"
#include "ae350_hw.h"
#include <FreeRTOS.h>

#define SPI_HID_USB_REPORT  0x40       /* st_helper_usb.v */
#define USB_POLL_MS         4

static const char *typ_name[4] = { "none", "keyboard", "mouse", "gamepad" };

static struct {
  unsigned char typ, cnt, seen;
  struct hid_kbd_state_S kbd;
} port[2];

static hid_report_t mouse_report;      /* boot protocol mouse layout */
static int usb_present = -1;           /* -1 unknown, 0 core without USB, 1 ok */
static unsigned usb_polls, usb_reports;

static int usb_read(int p, unsigned char *b) {
  mcu_hw_spi_begin();
  mcu_hw_spi_tx_u08(SPI_TARGET_HID);
  mcu_hw_spi_tx_u08(SPI_HID_USB_REPORT);
  mcu_hw_spi_tx_u08(p);
  for(int i = 0; i < 11; i++) b[i] = mcu_hw_spi_tx_u08(0);
  mcu_hw_spi_end();
  return b[0] == 0x5A;
}

void usb_init(void) {
  memset(port, 0, sizeof(port));
  memset(&mouse_report, 0, sizeof(mouse_report));
  mouse_report.type = REPORT_TYPE_MOUSE;
  mouse_report.report_size = 3;
  for(int i = 0; i < 3; i++) {
    mouse_report.joystick_mouse.button[i].byte_offset = 0;
    mouse_report.joystick_mouse.button[i].bitmask = 1 << i;
  }
  for(int i = 0; i < 2; i++) {
    mouse_report.joystick_mouse.axis[i].offset = 8 * (i + 1);
    mouse_report.joystick_mouse.axis[i].size = 8;
    mouse_report.joystick_mouse.axis[i].logical.min = (uint16_t)-127;  /* min > max: signed */
    mouse_report.joystick_mouse.axis[i].logical.max = 127;
  }
  unsigned char b[11];
  usb_present = usb_read(0, b);
  printf("USB: %s\r\n", usb_present ? "fabric USB host found (ST_HELPER_USB), polling both USB-A ports"
                                    : "core has no ST_HELPER_USB (no 5A on HID cmd 0x40), USB off");
}

static void usb_port(int p) {
  unsigned char b[11];
  if(!usb_read(p, b)) return;
  usb_polls++;
  unsigned char typ = b[1] & 3;
  if(typ != port[p].typ || !port[p].seen) {
    if(port[p].seen || typ)
      printf("USB port %d: %s%s\r\n", p + 1, typ ? typ_name[typ] : "disconnected",
             (b[1] & 0x80) ? " (connection error)" : "");
    /* release all keys of a keyboard that went away */
    if(port[p].typ == 1 && typ != 1) {
      unsigned char none[8] = { 0 };
      kbd_parse(NULL, &port[p].kbd, none, 8);
    }
    port[p].typ = typ; port[p].seen = 1;
    port[p].cnt = b[2];
    return;
  }
  if(b[2] == port[p].cnt) return;          /* no new report */
  port[p].cnt = b[2];
  usb_reports++;
  if(typ == 1) {
    unsigned char r[8] = { b[3], 0, b[4], b[5], b[6], b[7], 0, 0 };
    kbd_parse(NULL, &port[p].kbd, r, 8);
  } else if(typ == 2) {
    unsigned char r[3] = { b[8], b[9], b[10] };
    mouse_parse(&mouse_report, NULL, r, 3);
  }
}

void usb_poll(void) {
  static TickType_t last;
  if(usb_present != 1) return;
  TickType_t now = xTaskGetTickCount();
  if((TickType_t)(now - last) < USB_POLL_MS) return;
  last = now;
  usb_port(0);
  usb_port(1);
}

void usb_status(void) {
  if(usb_present != 1) { printf("USB: not available in this core\r\n"); return; }
  for(int p = 0; p < 2; p++) {
    unsigned char b[11];
    if(!usb_read(p, b)) { printf("USB port %d: read failed\r\n", p + 1); continue; }
    printf("USB port %d: %-8s%s reports %3u  mod %02X keys %02X %02X %02X %02X  mouse btn %02X\r\n",
           p + 1, typ_name[b[1] & 3], (b[1] & 0x80) ? " conerr" : "", b[2], b[3], b[4], b[5], b[6], b[7], b[8]);
  }
  printf("USB: %u polls, %u reports forwarded to hid.c\r\n", usb_polls, usb_reports);
}
