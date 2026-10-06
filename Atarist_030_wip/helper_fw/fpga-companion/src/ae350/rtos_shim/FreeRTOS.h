/* FreeRTOS API shim for the bare-metal AE350 port of FPGA-Companion.
 *
 * FPGA-Companion (Till Harbaum and the MiSTle-Dev contributors) is written
 * against FreeRTOS. Steps 1-3 of the ST_HELPER port (link, SYS target, SD
 * card / floppy / ACSI) run in one bare-metal main loop on the AE350, so
 * this header maps the few FreeRTOS calls the shared sources use onto that
 * loop. The companion sources stay unmodified; when the USB HID and OSD
 * steps need real tasks, drop this directory from the include path and link
 * the AE350 SDK's FreeRTOS (library/3rd_party/freertos) instead.
 */
#ifndef AE350_RTOS_SHIM_FREERTOS_H
#define AE350_RTOS_SHIM_FREERTOS_H

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

typedef uint32_t TickType_t;
typedef long BaseType_t;
typedef unsigned long UBaseType_t;
typedef void *TaskHandle_t;
typedef void *TimerHandle_t;
typedef void *QueueHandle_t;
typedef int *SemaphoreHandle_t;

#define configTICK_RATE_HZ       1000u
#define configMAX_PRIORITIES     8
#define portMAX_DELAY            0xffffffffUL
#define pdTRUE                   1
#define pdFALSE                  0
#define pdPASS                   1
#define pdFAIL                   0
#define pdMS_TO_TICKS(ms)        ((TickType_t)(ms))   /* 1 tick = 1 ms */
#define portTICK_PERIOD_MS       1u

/* implemented in ae350/mcu_hw.c */
TickType_t xTaskGetTickCount(void);
void vTaskDelay(TickType_t ticks);

static inline void *pvPortMalloc(size_t n) { return malloc(n); }
static inline void vPortFree(void *p) { free(p); }

#endif
