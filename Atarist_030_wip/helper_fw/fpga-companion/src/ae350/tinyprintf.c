/*
  tinyprintf.c - small printf family for the AE350 FPGA-Companion port.

  The companion's debug output (debug.h: debugf -> printf) goes to UART2.
  Using our own printf/sprintf keeps newlib's stdio (reentrancy structs,
  locks, buffered FILEs and their syscalls) out of the image. Supports
  %d %i %u %x %X %o %c %s %p %% with flags '-', '0', ' ', '+', width,
  precision for strings, and the h/hh/l/ll/z/j length modifiers.
*/
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "ae350_hw.h"

typedef struct { char *buf; size_t size, len; } out_t;

static void out_c(out_t *o, char c) {
  if(o->buf) { if(o->len + 1 < o->size) o->buf[o->len] = c; }
  else ae350_putc(c);
  o->len++;
}

static void out_num(out_t *o, unsigned long long v, int neg, unsigned base, int upper,
                    int width, int zero, int left, char sign) {
  char tmp[24]; int n = 0;
  const char *dig = upper ? "0123456789ABCDEF" : "0123456789abcdef";
  do { tmp[n++] = dig[v % base]; v /= base; } while(v);
  char s = neg ? '-' : sign;
  int len = n + (s ? 1 : 0);
  if(!left && !zero) while(width-- > len) out_c(o, ' ');
  if(s) out_c(o, s);
  if(!left && zero) while(width-- > len) out_c(o, '0');
  while(n) out_c(o, tmp[--n]);
  if(left) while(width-- > len) out_c(o, ' ');
}

static int do_fmt(out_t *o, const char *f, va_list ap) {
  for(; *f; f++) {
    if(*f != '%') { out_c(o, *f); continue; }
    f++;
    int left = 0, zero = 0, width = 0, prec = -1, lng = 0; char sign = 0;
    for(;; f++) {
      if(*f == '-') left = 1;
      else if(*f == '0') zero = 1;
      else if(*f == '+') sign = '+';
      else if(*f == ' ') { if(!sign) sign = ' '; }
      else break;
    }
    if(*f == '*') { width = va_arg(ap, int); f++; }
    else while(*f >= '0' && *f <= '9') width = width * 10 + (*f++ - '0');
    if(*f == '.') {
      f++; prec = 0;
      if(*f == '*') { prec = va_arg(ap, int); f++; }
      else while(*f >= '0' && *f <= '9') prec = prec * 10 + (*f++ - '0');
    }
    for(;; f++) {
      if(*f == 'l') lng++;
      else if(*f == 'z' || *f == 'j' || *f == 't') lng = (*f == 'j') ? 2 : 1;
      else if(*f == 'h') ;
      else break;
    }
    switch(*f) {
    case 'd': case 'i': {
      long long v = lng >= 2 ? va_arg(ap, long long) : lng ? va_arg(ap, long) : va_arg(ap, int);
      out_num(o, v < 0 ? -(unsigned long long)v : (unsigned long long)v, v < 0, 10, 0, width, zero, left, sign);
      break; }
    case 'u': case 'x': case 'X': case 'o': {
      unsigned long long v = lng >= 2 ? va_arg(ap, unsigned long long) : lng ? va_arg(ap, unsigned long) : va_arg(ap, unsigned);
      out_num(o, v, 0, *f == 'u' ? 10 : *f == 'o' ? 8 : 16, *f == 'X', width, zero, left, 0);
      break; }
    case 'p':
      out_c(o, '0'); out_c(o, 'x');
      out_num(o, (uintptr_t)va_arg(ap, void *), 0, 16, 0, 8, 1, 0, 0);
      break;
    case 'c': {
      char c = (char)va_arg(ap, int);
      if(!left) while(width-- > 1) out_c(o, ' ');
      out_c(o, c);
      if(left) while(width-- > 1) out_c(o, ' ');
      break; }
    case 's': {
      const char *s = va_arg(ap, const char *);
      if(!s) s = "(null)";
      int n = strlen(s); if(prec >= 0 && n > prec) n = prec;
      if(!left) while(width-- > n) out_c(o, ' ');
      for(int i = 0; i < n; i++) out_c(o, s[i]);
      if(left) while(width-- > n) out_c(o, ' ');
      break; }
    case '%': out_c(o, '%'); break;
    case 0: f--; break;
    default: out_c(o, '%'); out_c(o, *f); break;
    }
  }
  return (int)o->len;
}

int vsnprintf(char *buf, size_t size, const char *f, va_list ap) {
  out_t o = { buf, size, 0 };
  int n = do_fmt(&o, f, ap);
  if(buf && size) buf[o.len < size ? o.len : size - 1] = 0;
  return n;
}
int snprintf(char *buf, size_t size, const char *f, ...) {
  va_list ap; va_start(ap, f); int n = vsnprintf(buf, size, f, ap); va_end(ap); return n;
}
int vsprintf(char *buf, const char *f, va_list ap) { return vsnprintf(buf, (size_t)0x7fffffff, f, ap); }
int sprintf(char *buf, const char *f, ...) {
  va_list ap; va_start(ap, f); int n = vsprintf(buf, f, ap); va_end(ap); return n;
}
int vprintf(const char *f, va_list ap) { out_t o = { NULL, 0, 0 }; return do_fmt(&o, f, ap); }
int printf(const char *f, ...) {
  va_list ap; va_start(ap, f); int n = vprintf(f, ap); va_end(ap); return n;
}
#undef putchar
#undef puts
int putchar(int c) { ae350_putc((char)c); return c; }
int puts(const char *s) { ae350_puts(s); ae350_puts("\r\n"); return 1; }
