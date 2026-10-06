/* see FreeRTOS.h in this directory (bare-metal shim). One thread of
 * execution: a mutex can never be contended, so take/give only count, which
 * keeps the nesting visible when debugging. */
#ifndef AE350_RTOS_SHIM_SEMPHR_H
#define AE350_RTOS_SHIM_SEMPHR_H
#include "FreeRTOS.h"
static inline SemaphoreHandle_t xSemaphoreCreateMutex(void) { return (SemaphoreHandle_t)calloc(1, sizeof(int)); }
static inline BaseType_t xSemaphoreTake(SemaphoreHandle_t s, TickType_t t) { (void)t; if (s) (*s)++; return pdTRUE; }
static inline BaseType_t xSemaphoreGive(SemaphoreHandle_t s) { if (s && *s) (*s)--; return pdTRUE; }
#endif
