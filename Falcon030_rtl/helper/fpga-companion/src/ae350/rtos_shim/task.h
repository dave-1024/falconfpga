/* see FreeRTOS.h in this directory (bare-metal shim) and coop.c */
#ifndef AE350_RTOS_SHIM_TASK_H
#define AE350_RTOS_SHIM_TASK_H
#include "FreeRTOS.h"
typedef void (*TaskFunction_t)(void *);
/* single main loop: nothing to wait for, a notification is the IRQ poll */
static inline uint32_t ulTaskNotifyTake(BaseType_t clear, TickType_t wait) { (void)clear; (void)wait; return 1; }
BaseType_t xTaskCreate(TaskFunction_t fn, const char *name, uint32_t stack_words,
                       void *parm, UBaseType_t prio, TaskHandle_t *handle);
#endif
