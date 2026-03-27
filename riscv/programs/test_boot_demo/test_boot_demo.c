/*
 * test_boot_demo.c — демо для проверки загрузчика.
 *
 * Бесконечный цикл: OLED показывает бегущий текст "Hello World!",
 * UART печатает счётчик кадров.
 */
#include "../common/oled.h"
#include "../common/uart.h"

static void delay(volatile unsigned int n) {
    while (n--) __asm__ volatile("");
}

int main(void) {
    uart_puts("Boot demo start");
    oled_init();

    const char *msg = "Hello World! ";
    int msg_len = 0;
    while (msg[msg_len]) msg_len++;

    int frame = 0;
    int offset = 0;

    while (1) {
        /* Фон — тёмно-синий */
        oled_clear(0x0008);

        /* Бегущая строка по центру экрана */
        int y = 27;  /* центр по вертикали (64/2 - 10/2) */
        for (int i = 0; i < 13; i++) {  /* 12 символов + запас */
            int char_idx = (offset + i) % msg_len;
            int x = i * 8 - (frame % 8);
            if (x >= -8 && x < 96)
                oled_char(x, y, msg[char_idx], OLED_GREEN, 0x0008);
        }

        /* Рамка */
        for (int x = 0; x < 96; x++) {
            oled_pixel(x, 0, OLED_WHITE);
            oled_pixel(x, 63, OLED_WHITE);
        }
        for (int y = 0; y < 64; y++) {
            oled_pixel(0, y, OLED_WHITE);
            oled_pixel(95, y, OLED_WHITE);
        }

        /* Счётчик кадров внизу */
        char buf[12];
        int n = frame;
        int i = 0;
        if (n == 0) buf[i++] = '0';
        else { while (n > 0) { buf[i++] = '0' + (n % 10); n /= 10; } }
        /* reverse */
        for (int a = 0, b = i - 1; a < b; a++, b--) {
            char t = buf[a]; buf[a] = buf[b]; buf[b] = t;
        }
        buf[i] = 0;
        oled_text(5, 0, "FRM:", OLED_YELLOW, 0x0008);
        oled_text(5, 4, buf, OLED_YELLOW, 0x0008);

        oled_flush();

        /* UART каждые 10 кадров */
        if (frame % 10 == 0) {
            uart_write("frame ");
            uart_print_uint(frame);
            uart_putc('\n');
        }

        frame++;
        /* Сдвиг текста каждые 2 кадра */
        if (frame % 2 == 0) offset = (offset + 1) % msg_len;

        delay(50000);  /* ~небольшая пауза */
    }
}
