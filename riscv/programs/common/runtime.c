/*
 * Minimal runtime for RV32I bare-metal.
 * UART output → UART_IO_DEVICE TX_DATA (0x10000000)
 */

/* g_failed — используется check.h макросами для отслеживания ошибок */
int g_failed = 0;

#define UART_TX  ((volatile unsigned int *)0x40000000U)
#define UART_STS ((volatile unsigned int *)0x40000008U)

int putchar(int c) {
    /* Optional: wait for tx_ready (bit1) before writing */
    /* while (!(*UART_STS & 2)); */
    *UART_TX = (unsigned int)(unsigned char)c;
    return (unsigned char)c;
}

int puts(const char *s) {
    while (*s) putchar((unsigned char)*s++);
    putchar('\n');
    return 0;
}

void print_nl(void) {
    putchar('\n');
}

void print_uint(unsigned int n) {
    char buf[12];
    int  i = 0;
    if (n == 0) { putchar('0'); return; }
    while (n > 0) { buf[i++] = '0' + (n % 10); n /= 10; }
    while (i > 0) putchar(buf[--i]);
}

void print_int(int n) {
    if (n < 0) { putchar('-'); print_uint((unsigned int)-n); }
    else        print_uint((unsigned int)n);
}

void print_hex(unsigned int n) {
    const char *hex = "0123456789abcdef";
    for (int s = 28; s >= 0; s -= 4)
        putchar(hex[(n >> s) & 0xF]);
}

void _exit(int code) {
    (void)code;
    __asm__ volatile ("ebreak");
    while (1);
}
