/*
  main.c - FPGA-Companion on the AE350 (falconfpga ST_HELPER build).

  Follows the com_task() start-up order of ../rp2040/main.c and
  ../bl616 (FPGA-Companion by Till Harbaum and the MiSTle-Dev
  contributors, Apache-2.0), in one bare-metal loop instead of FreeRTOS
  tasks (see rtos_shim/FreeRTOS.h and docs/ST_HELPER.md section 7):

    sys_wait4fpga -> sdc_init -> XML config (SD card, else the core's own
    gzip'd atarist.xml) -> pending IRQs -> "init" action (loads
    atarist.ini) -> sdc_mount_defaults -> main loop (core IRQ, console)

  One difference on purpose: on the BL616 the "init" action holds the ST in
  reset (R=1) and "ready" releases it. Here the fabric releases the 68030
  right after the flash handoff, before the helper can talk to the core,
  so R is never set at start-up. The core's sd_ready still delays the ST
  boot by up to 2 s until an image is inserted, which gives the default
  floppy (atarist.ini drive0) the same chance to be there at boot as on
  MiSTeryNano.
*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../mcu_hw.h"
#include "../config.h"
#include "../sysctrl.h"
#include "../sdc.h"
#include "../inifile.h"
#include "../xml.h"
#include "../debug.h"
#include "ae350_hw.h"

#define FW_VERSION "port1"

static void load_config(void) {
  FIL fil;
  if(sdc_get_cwd(0) && f_open(&fil, sys_get_config_name(), FA_OPEN_EXISTING | FA_READ) == FR_OK) {
    UINT br; char c;
    config_init();
    debugf("Loading XML config from file %s", sys_get_config_name());
    FRESULT r = f_read(&fil, &c, 1, &br);
    while(r == FR_OK && br) { xml_parse(c); r = f_read(&fil, &c, 1, &br); }
    f_close(&fil);
  } else {
    char *cfg_str = sys_get_config();
    if(cfg_str) {
      debugf("Loading XML config from core");
      config_init();
      for(char *c = cfg_str; *c; c++) xml_parse(*c);
      vPortFree(cfg_str);
    } else
      debugf("No valid config found, neither on sd card nor in core");
  }
  if(cfg) debugf("config '%s' loaded ('cfg' on the console dumps it)", cfg->name ? cfg->name : "?");
}

/* sys_run_action() without the reset: see the header comment */
static void run_action_no_reset(config_action_t *action, int depth) {
  if(!action || depth > 4) return;
  sys_debugf("Running action '%s' (AE350: R is left alone, the ST is already running)", action->name);
  for(config_action_command_t *c = action->commands; c; c = c->next) {
    switch(c->code) {
    case CONFIG_ACTION_COMMAND_SET:
      if(c->set.id == 'R') sys_debugf("skip SET('R',%d)", c->set.value);
      else sys_set_val(c->set.id, c->set.value);
      break;
    case CONFIG_ACTION_COMMAND_DELAY: vTaskDelay(pdMS_TO_TICKS(c->delay.ms)); break;
    case CONFIG_ACTION_COMMAND_LOAD:
      if(sdc_get_cwd(0)) inifile_read(c->filename);
      else sys_debugf("skip LOAD %s (no SD card)", c->filename);
      break;
    case CONFIG_ACTION_COMMAND_LINK: run_action_no_reset(c->action, depth + 1); break;
    default: break;                               /* SAVE, HIDE, EXEC: OSD only */
    }
  }
}

int main(void) {
  mcu_hw_init();
  printf(LOGO);
  printf("FPGA-Companion for the AE350 (" FW_VERSION ", " __DATE__ " " __TIME__ ")\r\n");

  if(ae350_link_up() && sys_wait4fpga()) {
    sdc_init();
    load_config();

    /* pending interrupts; irq 0 at this point is the FPGA cold boot flag */
    sys_handle_interrupts(sys_irq_ctrl(0xff), true);

    if(cfg) run_action_no_reset(config_get_action("init"), 0);

    if(sdc_get_cwd(0)) sdc_mount_defaults();
    debugf("Start-up done after %lu ms, entering main loop", (unsigned long)xTaskGetTickCount());
  }

  if(ae350_link_up()) usb_init();
  console_init();
  for(;;) {
    if(mcu_hw_irq_pending())
      sys_handle_interrupts(sys_irq_ctrl(0xff), false);
    usb_poll();
    console_poll();
  }
  return 0;
}
