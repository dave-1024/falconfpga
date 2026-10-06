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

TaskHandle_t menu_handle = NULL;

/* ---- menu.c (step 5). The variables an ini file sets ('var X=n') are
   kept, so 'save' writes them back, but they are not sent to the core:
   in the original they are applied while the init action holds the ST in
   reset, and here the ST is already running when the helper starts. ---- */
static menu_variable_t *vars = NULL;

menu_variable_t *menu_get_variables(void) { return vars; }

void menu_set_value(unsigned char id, int8_t value) {
  if(id == 'R') { menu_debugf("suppressing 'R' reset variable"); return; }
  menu_variable_t *v = vars;
  while(v && v->id != (char)id) v = v->next;
  if(!v) {
    v = malloc(sizeof(menu_variable_t));
    v->id = id; v->next = vars; vars = v;
  }
  v->value = value;
  menu_debugf("var %c = %d kept (not applied until the OSD port)", id, value);
}

void menu_button_state(unsigned char state) { menu_debugf("core button %d (OSD not ported yet)", state); }
void menu_run_current_image_action(void) { }
void menu_notify(unsigned long msg) { (void)msg; }

/* ---- osd (step 5) ---- */
void osd_enable(char en) { (void)en; }

/* ---- hid.c (step 4) ---- */

/* ---- at_wifi.c: no network on the AE350 ---- */
void at_wifi_port_byte(unsigned char b) { (void)b; }

/* OSD (step 5) not ported yet: hid.c forwards every key to the core */
int osd_is_visible(void) { return 0; }
void menu_joystick_state(unsigned char state) { (void)state; }
