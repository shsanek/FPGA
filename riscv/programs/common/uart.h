#ifndef UART_H
#define UART_H

/* UART console API.
 * Hardware blocking: запись в TX_DATA блокирует CPU пока байт не отправлен.
 */

int  uart_putc(int c);
int  uart_puts(const char *s);           /* строка + \n */
int  uart_write(const char *s);          /* строка без \n */
int  uart_getc(void);                    /* блокирующее чтение */
int  uart_available(void);               /* есть байт в RX? */
void uart_print_int(int n);
void uart_print_uint(unsigned int n);
void uart_print_hex(unsigned int n);     /* 8 hex digits */

#endif
