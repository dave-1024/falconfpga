/* see FreeRTOS.h in this directory (bare-metal shim) */
#ifndef AE350_RTOS_SHIM_TASK_H
#define AE350_RTOS_SHIM_TASK_H
#include "FreeRTOS.h"
/* single main loop: nothing to wait for, a notification is the IRQ poll */
static inline uint32_t ulTaskNotifyTake(BaseType_t clear, TickType_t wait) { (void)clear; (void)wait; return 1; }
#endif
