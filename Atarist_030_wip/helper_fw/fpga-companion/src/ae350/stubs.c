/*
  stubs.c - placeholders for the FPGA-Companion parts that come in later
  steps of the AE350 port (docs/ST_HELPER.md section 7):
    step 4: USB keyboard/mouse/joystick (hid.c, usb_hid_host.v in the fabric)
    step 5: OSD menu (menu.c, osd_u8g2.c, u8g2)
  Each function keeps the signature of the real one so that sysctrl.c,
  sdc.c and inifile.c build unmodified. FPGA-Companion: Till Harbaum and the
  MiSTle-Dev contributors, Apache-2.0.
*/
#include <stdio.h>
#include <stdlib.h>
#include "../menu.h"
#include "../osd.h"
#include "../hid.h"
#include "../debug.h"

/* ---- at_wifi.c: no network on the AE350 ---- */
void at_wifi_port_byte(unsigned char b) { (void)b; }

