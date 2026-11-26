/* see FreeRTOS.h in this directory (bare-metal shim) and coop.c */
#ifndef AE350_RTOS_SHIM_TIMERS_H
#define AE350_RTOS_SHIM_TIMERS_H
#include "FreeRTOS.h"
typedef void (*TimerCallbackFunction_t)(TimerHandle_t);
TimerHandle_t xTimerCreate(const char *name, TickType_t period, UBaseType_t reload,
                           void *id, TimerCallbackFunction_t cb);
BaseType_t xTimerStart(TimerHandle_t t, TickType_t wait);
BaseType_t xTimerStop(TimerHandle_t t, TickType_t wait);
BaseType_t xTimerChangePeriod(TimerHandle_t t, TickType_t period, TickType_t wait);
BaseType_t xTimerIsTimerActive(TimerHandle_t t);
BaseType_t xTimerReset(TimerHandle_t t, TickType_t wait);
void *pvTimerGetTimerID(TimerHandle_t t);
#endif
