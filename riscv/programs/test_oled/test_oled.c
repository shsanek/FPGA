/*
 * test_oled.c — тест PmodOLEDrgb (SSD1331) через OLED API.
 *
 * Рисует RGB полосы + текст через framebuffer → oled_flush().
 */
#include "../common/runtime.h"
#include "../common/oled.h"

int test_oled_run(void);
#ifndef NO_MAIN
int main(void) { return test_oled_run(); }
#endif
int test_oled_run(void) {
    puts("OLED init...");
    oled_init();
    puts("OLED init done");

    /* Три горизонтальные полосы: R / G / B */
    oled_rect(0,  0, 96, 21, OLED_RED);
    oled_rect(0, 21, 96, 22, OLED_GREEN);
    oled_rect(0, 43, 96, 21, OLED_BLUE);

    /* Текст поверх полос */
    oled_text(1, 2, "RISC-V", OLED_WHITE, OLED_RED);
    oled_text(3, 3, "OLED", OLED_BLACK, OLED_GREEN);
    oled_text(5, 3, "TEST", OLED_WHITE, OLED_BLUE);

    oled_flush();

    puts("OLED OK");
    return 0;
}
