/* see FreeRTOS.h in this directory (bare-metal shim) and coop.c */
#ifndef AE350_RTOS_SHIM_QUEUE_H
#define AE350_RTOS_SHIM_QUEUE_H
#include "FreeRTOS.h"
QueueHandle_t xQueueCreate(UBaseType_t len, UBaseType_t size);
BaseType_t xQueueSendToBack(QueueHandle_t q, const void *item, TickType_t wait);
BaseType_t xQueueReceive(QueueHandle_t q, void *item, TickType_t wait);
#define xQueueSend(q, i, w)                    xQueueSendToBack(q, i, w)
#define xQueueSendToBackFromISR(q, i, w)       xQueueSendToBack(q, i, 0)
#define xQueueSendFromISR(q, i, w)             xQueueSendToBack(q, i, 0)
#endif
