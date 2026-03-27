/* UART console — memory-mapped UART_IO_DEVICE (0x10000000). */
#include "uart.h"

#define UART_TX_DATA  (*(volatile unsigned int *)0x10000000U)
#define UART_RX_DATA  (*(volatile unsigned int *)0x10000004U)
#define UART_STATUS   (*(volatile unsigned int *)0x10000008U)

/* STATUS bits: bit1=tx_ready, bit0=rx_available */

int uart_putc(int c) {
    UART_TX_DATA = (unsigned int)(unsigned char)c;
    return (unsigned char)c;
}

int uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
    uart_putc('\n');
    return 0;
}

int uart_write(const char *s) {
    while (*s) uart_putc(*s++);
    return 0;
}

int uart_getc(void) {
    while (!(UART_STATUS & 1)) ;  /* wait rx_available */
    return (int)(UART_RX_DATA & 0xFF);
}

int uart_available(void) {
    return (UART_STATUS & 1) ? 1 : 0;
}

void uart_print_uint(unsigned int n) {
    char buf[12];
    int i = 0;
    if (n == 0) { uart_putc('0'); return; }
    while (n > 0) { buf[i++] = '0' + (n % 10); n /= 10; }
    while (i > 0) uart_putc(buf[--i]);
}

void uart_print_int(int n) {
    if (n < 0) { uart_putc('-'); uart_print_uint((unsigned int)-n); }
    else uart_print_uint((unsigned int)n);
}

void uart_print_hex(unsigned int n) {
    const char *h = "0123456789abcdef";
    for (int s = 28; s >= 0; s -= 4)
        uart_putc(h[(n >> s) & 0xF]);
}
