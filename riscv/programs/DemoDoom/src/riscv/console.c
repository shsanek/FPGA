/*
 * console.c — UART-based console for DOOM on Arty A7.
 * Input: 2-byte protocol from riscv_tester.py --keyboard
 *   byte 0: Windows VK code
 *   byte 1: flags (bit7=release, bit0=shift, bit1=ctrl, bit2=alt)
 */

#include <stdint.h>
#include "mini-printf.h"
#include "../doomdef.h"

/* UART hardware */
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
}

/* --- Input: read 2-byte packets [VK] [FLAGS] --- */

static int uart_rx_available(void)
{
    return (UART_STATUS & 1) ? 1 : 0;
}

static unsigned char uart_rx_read(void)
{
    return (unsigned char)(UART_RX_DATA & 0xFF);
}

/* Windows Virtual Key codes → DOOM key codes */
static int vk_to_doom(unsigned char vk, unsigned char flags)
{
    /* VK codes (Windows) */
    switch (vk) {
        case 0x1B: return KEY_ESCAPE;      /* VK_ESCAPE */
        case 0x0D: return KEY_ENTER;       /* VK_RETURN */
        case 0x09: return KEY_TAB;         /* VK_TAB */
        case 0x08: return KEY_BACKSPACE;   /* VK_BACK */
        case 0x20: return ' ';             /* VK_SPACE */

        /* Arrow keys */
        case 0x25: return KEY_LEFTARROW;   /* VK_LEFT */
        case 0x26: return KEY_UPARROW;     /* VK_UP */
        case 0x27: return KEY_RIGHTARROW;  /* VK_RIGHT */
        case 0x28: return KEY_DOWNARROW;   /* VK_DOWN */

        /* Modifiers */
        case 0x10: return KEY_RSHIFT;      /* VK_SHIFT */
        case 0xA0: return KEY_RSHIFT;      /* VK_LSHIFT */
        case 0xA1: return KEY_RSHIFT;      /* VK_RSHIFT */
        case 0x11: return KEY_RCTRL;       /* VK_CONTROL */
        case 0xA2: return KEY_RCTRL;       /* VK_LCONTROL */
        case 0xA3: return KEY_RCTRL;       /* VK_RCONTROL */
        case 0x12: return KEY_RALT;        /* VK_MENU (Alt) */
        case 0xA4: return KEY_RALT;        /* VK_LMENU */
        case 0xA5: return KEY_RALT;        /* VK_RMENU */

        /* F-keys */
        case 0x70: return KEY_F1;          /* VK_F1 */
        case 0x71: return KEY_F2;
        case 0x72: return KEY_F3;
        case 0x73: return KEY_F4;
        case 0x74: return KEY_F5;
        case 0x75: return KEY_F6;
        case 0x76: return KEY_F7;
        case 0x77: return KEY_F8;
        case 0x78: return KEY_F9;
        case 0x79: return KEY_F10;
        case 0x7A: return KEY_F11;
        case 0x7B: return KEY_F12;

        case 0x13: return KEY_PAUSE;       /* VK_PAUSE */
        case 0xBB: return KEY_EQUALS;      /* VK_OEM_PLUS (=) */
        case 0xBD: return KEY_MINUS;       /* VK_OEM_MINUS (-) */
    }

    /* Letters A-Z: VK 0x41-0x5A → lowercase ASCII */
    if (vk >= 0x41 && vk <= 0x5A)
        return vk + 32;  /* 'a'-'z' */

    /* Digits 0-9: VK 0x30-0x39 = ASCII */
    if (vk >= 0x30 && vk <= 0x39)
        return vk;

    return 0;  /* unknown */
}

/*
 * Read one input event from UART (2-byte protocol).
 * Returns: DOOM key code, or -1 if no input.
 * Sets *is_press = 1 for keydown, 0 for keyup.
 */
int console_read_event(int *is_press)
{
    if (!uart_rx_available())
        return -1;

    unsigned char vk = uart_rx_read();
    if (vk == 0) return -1;

    /* Wait for flags byte — debug protocol ACK adds latency */
    int timeout = 100000;
    while (!uart_rx_available() && --timeout > 0) ;
    unsigned char flags = uart_rx_available() ? uart_rx_read() : 0;

    *is_press = (flags & 0x80) ? 0 : 1;

    int key = vk_to_doom(vk, flags);
    return key;
}

/* Legacy API (unused now but kept for console_printf) */
char console_getchar(void) { return -1; }
int console_getchar_nowait(void) { return -1; }

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
