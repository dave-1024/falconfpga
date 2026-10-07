/*
  coop.c - cooperative stand-in for the FreeRTOS pieces FPGA-Companion's
  menu.c uses (one task, software timers, queues), AE350 port step 5.

  The menu task runs on its own stack and gives the CPU back only where a
  FreeRTOS task would block: xQueueReceive on an empty queue and vTaskDelay.
  The main loop calls rtos_poll(), which fires due timers and resumes the
  task. Nothing is preempted, so an SPI frame or a FatFs call is never cut in
  half and no locking is needed.
*/
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include "FreeRTOS.h"
#include "task.h"
#include "timers.h"
#include "queue.h"

/* ---- context switch: callee-saved registers on the old stack ---- */
#if defined(__riscv_float_abi_double)
#define FRAME 160
#elif defined(__riscv_float_abi_single)
#define FRAME 112
#else
#define FRAME 64
#endif
#define S_(x) #x
#define S(x) S_(x)
void coop_switch(uint32_t *save_sp, uint32_t new_sp);
__asm__(
  ".text\n.align 2\n.globl coop_switch\ncoop_switch:\n"
  "addi sp,sp,-" S(FRAME) "\n"
  "sw ra,0(sp)\n sw s0,4(sp)\n sw s1,8(sp)\n sw s2,12(sp)\n sw s3,16(sp)\n sw s4,20(sp)\n"
  "sw s5,24(sp)\n sw s6,28(sp)\n sw s7,32(sp)\n sw s8,36(sp)\n sw s9,40(sp)\n sw s10,44(sp)\n sw s11,48(sp)\n"
#if defined(__riscv_float_abi_double)
  "fsd fs0,64(sp)\n fsd fs1,72(sp)\n fsd fs2,80(sp)\n fsd fs3,88(sp)\n fsd fs4,96(sp)\n fsd fs5,104(sp)\n"
  "fsd fs6,112(sp)\n fsd fs7,120(sp)\n fsd fs8,128(sp)\n fsd fs9,136(sp)\n fsd fs10,144(sp)\n fsd fs11,152(sp)\n"
#elif defined(__riscv_float_abi_single)
  "fsw fs0,64(sp)\n fsw fs1,68(sp)\n fsw fs2,72(sp)\n fsw fs3,76(sp)\n fsw fs4,80(sp)\n fsw fs5,84(sp)\n"
  "fsw fs6,88(sp)\n fsw fs7,92(sp)\n fsw fs8,96(sp)\n fsw fs9,100(sp)\n fsw fs10,104(sp)\n fsw fs11,108(sp)\n"
#endif
  "sw sp,0(a0)\n mv sp,a1\n"
  "lw ra,0(sp)\n lw s0,4(sp)\n lw s1,8(sp)\n lw s2,12(sp)\n lw s3,16(sp)\n lw s4,20(sp)\n"
  "lw s5,24(sp)\n lw s6,28(sp)\n lw s7,32(sp)\n lw s8,36(sp)\n lw s9,40(sp)\n lw s10,44(sp)\n lw s11,48(sp)\n"
#if defined(__riscv_float_abi_double)
  "fld fs0,64(sp)\n fld fs1,72(sp)\n fld fs2,80(sp)\n fld fs3,88(sp)\n fld fs4,96(sp)\n fld fs5,104(sp)\n"
  "fld fs6,112(sp)\n fld fs7,120(sp)\n fld fs8,128(sp)\n fld fs9,136(sp)\n fld fs10,144(sp)\n fld fs11,152(sp)\n"
#elif defined(__riscv_float_abi_single)
  "flw fs0,64(sp)\n flw fs1,68(sp)\n flw fs2,72(sp)\n flw fs3,76(sp)\n flw fs4,80(sp)\n flw fs5,84(sp)\n"
  "flw fs6,88(sp)\n flw fs7,92(sp)\n flw fs8,96(sp)\n flw fs9,100(sp)\n flw fs10,104(sp)\n flw fs11,108(sp)\n"
#endif
  "addi sp,sp," S(FRAME) "\n ret\n");

#define TASK_STACK  (32u * 1024u)
static uint32_t task_stack[TASK_STACK / 4] __attribute__((aligned(16)));
static uint32_t main_sp, task_sp;
static int in_task, task_alive;
static TaskFunction_t task_fn;
static void *task_parm;

static void task_entry(void) {
  task_fn(task_parm);
  task_alive = 0;                      /* a FreeRTOS task must not return */
  for(;;) coop_switch(&task_sp, main_sp);
}

BaseType_t xTaskCreate(TaskFunction_t fn, const char *name, uint32_t stack_words,
                       void *parm, UBaseType_t prio, TaskHandle_t *handle) {
  (void)name; (void)stack_words; (void)prio;
  if(task_alive) return pdFAIL;        /* one task is all menu.c needs */
  task_fn = fn; task_parm = parm;
  uint32_t *sp = &task_stack[TASK_STACK / 4] - FRAME / 4;
  memset(sp, 0, FRAME);
  sp[0] = (uint32_t)task_entry;        /* ra */
  task_sp = (uint32_t)sp;
  task_alive = 1;
  if(handle) *handle = (TaskHandle_t)task_stack;
  return pdPASS;
}

/* called by the task where FreeRTOS would block */
static void task_yield(void) { if(in_task) coop_switch(&task_sp, main_sp); }

void vTaskDelay(TickType_t ticks) {
  TickType_t t0 = xTaskGetTickCount();
  extern void ae350_rx_poll(void);
  while((TickType_t)(xTaskGetTickCount() - t0) < ticks) {
    if(in_task) task_yield(); else ae350_rx_poll();
  }
}

/* ---- software timers (callbacks run in the main loop) ---- */
typedef struct tmr { TickType_t period, due; int active, reload; void *id;
                     TimerCallbackFunction_t cb; struct tmr *next; } tmr_t;
static tmr_t *timers;

TimerHandle_t xTimerCreate(const char *name, TickType_t period, UBaseType_t reload,
                           void *id, TimerCallbackFunction_t cb) {
  (void)name;
  tmr_t *t = calloc(1, sizeof(*t));
  if(!t) return NULL;
  t->period = period ? period : 1; t->reload = reload; t->id = id; t->cb = cb;
  t->next = timers; timers = t;
  return t;
}
BaseType_t xTimerStart(TimerHandle_t h, TickType_t w) {
  tmr_t *t = h; (void)w; if(!t) return pdFAIL;
  t->due = xTaskGetTickCount() + t->period; t->active = 1; return pdPASS;
}
BaseType_t xTimerReset(TimerHandle_t h, TickType_t w) { return xTimerStart(h, w); }
BaseType_t xTimerStop(TimerHandle_t h, TickType_t w) { tmr_t *t = h; (void)w; if(t) t->active = 0; return pdPASS; }
BaseType_t xTimerChangePeriod(TimerHandle_t h, TickType_t p, TickType_t w) {
  tmr_t *t = h; if(!t) return pdFAIL; t->period = p ? p : 1; return xTimerStart(h, w);
}
BaseType_t xTimerIsTimerActive(TimerHandle_t h) { tmr_t *t = h; return (t && t->active) ? pdTRUE : pdFALSE; }
void *pvTimerGetTimerID(TimerHandle_t h) { tmr_t *t = h; return t ? t->id : NULL; }

/* ---- queues ---- */
typedef struct { unsigned len, size, head, count; unsigned char data[]; } q_t;

QueueHandle_t xQueueCreate(UBaseType_t len, UBaseType_t size) {
  q_t *q = calloc(1, sizeof(q_t) + len * size);
  if(q) { q->len = len; q->size = size; }
  return q;
}
BaseType_t xQueueSendToBack(QueueHandle_t h, const void *item, TickType_t w) {
  q_t *q = h; (void)w;
  if(!q || q->count == q->len) return pdFAIL;
  memcpy(q->data + ((q->head + q->count) % q->len) * q->size, item, q->size);
  q->count++;
  return pdPASS;
}
BaseType_t xQueueReceive(QueueHandle_t h, void *item, TickType_t wait) {
  q_t *q = h;
  TickType_t t0 = xTaskGetTickCount();
  if(!q) return pdFAIL;
  while(!q->count) {
    if(!in_task || (wait != portMAX_DELAY && (TickType_t)(xTaskGetTickCount() - t0) >= wait))
      return pdFAIL;
    task_yield();
  }
  memcpy(item, q->data + q->head * q->size, q->size);
  q->head = (q->head + 1) % q->len; q->count--;
  return pdPASS;
}

/* ---- main loop hook ---- */
void rtos_poll(void) {
  TickType_t now = xTaskGetTickCount();
  for(tmr_t *t = timers; t; t = t->next) {
    if(t->active && (int32_t)(now - t->due) >= 0) {
      if(t->reload) t->due = now + t->period; else t->active = 0;
      if(t->cb) t->cb(t);
    }
  }
  if(task_alive && !in_task) {
    in_task = 1;
    coop_switch(&main_sp, task_sp);
    in_task = 0;
  }
}
