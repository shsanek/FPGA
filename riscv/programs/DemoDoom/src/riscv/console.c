/*
 * console.c — UART-based console for DOOM on Arty A7.
 * Replaces original memory-mapped text console (0x40000000).
 */

#include <stdint.h>
#include "mini-printf.h"
#include "../doomdef.h"

/* UART hardware (from common/uart.c addresses) */
#define UART_TX_DATA  (*(volatile unsigned int *)0x10000000U)
#define UART_RX_DATA  (*(volatile unsigned int *)0x10000004U)
#define UART_STATUS   (*(volatile unsigned int *)0x10000008U)

void console_putchar(char c)
{
    if (c == '\0') return;
    while (!(UART_STATUS & 2)) ;  /* wait tx_ready */
    UART_TX_DATA = (unsigned int)(unsigned char)c;
}

void console_puts(const char *p)
{
    while (*p) console_putchar(*p++);
}

void console_init(void)
{
    /* UART doesn't need software init */
}

char console_getchar(void)
{
    /* Non-blocking: check UART RX available (bit 0 of STATUS) */
    if (!(UART_STATUS & 1))
        return -1;

    unsigned char value = (unsigned char)(UART_RX_DATA & 0xFF);

    if (value == 0)
        return -1;

    /* Map UART bytes to DOOM keys */
    switch (value) {
        case 0x1B: return KEY_ESCAPE;
        case '\r':
        case '\n': return KEY_ENTER;
        case '\t': return KEY_TAB;
        case 0x7F:
        case '\b': return KEY_BACKSPACE;
        /* Arrow keys: ANSI escape sequences would need state machine.
         * For now, use simple WASD mapping: */
        case 'w':  return KEY_UPARROW;
        case 's':  return KEY_DOWNARROW;
        case 'a':  return KEY_LEFTARROW;
        case 'd':  return KEY_RIGHTARROW;
        case ' ':  return KEY_RCTRL;   /* fire */
        case 'e':  return KEY_RSHIFT;  /* use/open */
        case 'q':  return KEY_RALT;    /* strafe */
        case '=':  return KEY_EQUALS;
        case '-':  return KEY_MINUS;
    }

    /* F-keys: digits 1-0 map to F1-F10 */
    if (value >= '1' && value <= '9')
        return KEY_F1 + (value - '1');
    if (value == '0')
        return KEY_F10;

    return (char)value;
}

int console_getchar_nowait(void)
{
    return console_getchar();
}

int console_printf(const char *fmt, ...)
{
    static char _printf_buf[128];
    va_list va;
    int l;

    va_start(va, fmt);
    l = mini_vsnprintf(_printf_buf, 128, fmt, va);
    va_end(va);

    console_puts(_printf_buf);

    return l;
}
