/*
 * console.c — UART консоль через нашу шину (0x08000000).
 */
#include <stdint.h>
#include <stdarg.h>

#include "mini-printf.h"
#include "console.h"

/* UART registers */
#define UART_TX_DATA  (*(volatile unsigned int *)0x08000000U)
#define UART_RX_DATA  (*(volatile unsigned int *)0x08000004U)
#define UART_STATUS   (*(volatile unsigned int *)0x08000008U)

void console_init(void) { }

void console_putchar(char c) {
    UART_TX_DATA = (unsigned int)(unsigned char)c;
}

void console_puts(const char *p) {
    while (*p) console_putchar(*p++);
}

char console_getchar(void) {
    if (!(UART_STATUS & 1)) return -1;
    return (char)(UART_RX_DATA & 0xFF);
}

int console_getchar_nowait(void) {
    return console_getchar();
}

int console_printf(const char *fmt, ...) {
    static char _printf_buf[128];
    va_list va;
    va_start(va, fmt);
    int l = mini_vsnprintf(_printf_buf, 128, fmt, va);
    va_end(va);
    console_puts(_printf_buf);
    return l;
}
