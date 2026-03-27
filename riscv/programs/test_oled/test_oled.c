/*
 * test_oled.c — тест PmodOLEDrgb (SSD1331) через SPI.
 *
 * Последовательность:
 *   1. Power on (PMODEN)
 *   2. Reset pulse (RES)
 *   3. SSD1331 init commands
 *   4. VCCEN on
 *   5. Display ON
 *   6. Заливка экрана тремя цветами (R/G/B полосами)
 *   7. Вывод "OLED OK" через UART
 */
#include "../common/runtime.h"

/* ---- OLED регистры (memory-mapped) ---- */
#define OLED_DATA    (*(volatile unsigned int *)0x08010000U)
#define OLED_CONTROL (*(volatile unsigned int *)0x08010004U)
#define OLED_STATUS  (*(volatile unsigned int *)0x08010008U)
#define OLED_DIVIDER (*(volatile unsigned int *)0x0801000CU)

/*
 * CONTROL bits:
 *   [0] CS     — 1 = CS_N active (low)
 *   [1] DC     — 0 = command, 1 = data
 *   [2] RES    — 1 = reset active (RES_N low)
 *   [3] VCCEN  — 1 = OLED Vcc enable
 *   [4] PMODEN — 1 = module power enable
 */
#define CTL_CS     (1 << 0)
#define CTL_DC     (1 << 1)
#define CTL_RES    (1 << 2)
#define CTL_VCCEN  (1 << 3)
#define CTL_PMODEN (1 << 4)

/* ---- Busy-wait задержки (грубые, ~81 MHz) ---- */
static void delay(volatile unsigned int n) {
    while (n--) __asm__ volatile("");
}

#define DELAY_1MS   81250
#define DELAY_20MS  (20 * DELAY_1MS)
#define DELAY_100MS (100 * DELAY_1MS)

/* ---- SPI helpers ---- */
static void spi_wait(void) {
    while (OLED_STATUS & 0x2)  /* bit 1 = spi_busy */
        ;
}

static void oled_cmd(unsigned char c) {
    spi_wait();
    OLED_DATA = c;
}

static void oled_data(unsigned char d) {
    spi_wait();
    OLED_DATA = d;
}

static void set_cmd_mode(void) {
    /* DC=0 (command), CS=1 (active), PMODEN, VCCEN keep current */
    unsigned int ctl = OLED_CONTROL;
    OLED_CONTROL = (ctl & ~CTL_DC) | CTL_CS;
}

static void set_data_mode(void) {
    /* DC=1 (data), CS=1 (active) */
    unsigned int ctl = OLED_CONTROL;
    OLED_CONTROL = ctl | CTL_DC | CTL_CS;
}

/* ---- SSD1331 init ---- */
static void oled_init(void) {
    /* 1. Power on module */
    OLED_CONTROL = CTL_PMODEN;
    delay(DELAY_20MS);

    /* 2. Assert reset */
    OLED_CONTROL = CTL_PMODEN | CTL_RES;
    delay(DELAY_1MS);
    /* Deassert reset */
    OLED_CONTROL = CTL_PMODEN;
    delay(DELAY_1MS);

    /* 3. Send init commands (DC=0, CS active) */
    OLED_CONTROL = CTL_PMODEN | CTL_CS;  /* cmd mode */

    oled_cmd(0xAE);  /* Display OFF */
    oled_cmd(0xA0);  /* Set remap */
    oled_cmd(0x72);  /* 16-bit RGB565, COM split, scan direction */
    oled_cmd(0xA1);  /* Start line = 0 */
    oled_cmd(0x00);
    oled_cmd(0xA2);  /* Display offset = 0 */
    oled_cmd(0x00);
    oled_cmd(0xA4);  /* Normal display */
    oled_cmd(0xA8);  /* Multiplex ratio */
    oled_cmd(0x3F);  /* 64 lines */
    oled_cmd(0xAD);  /* Master config */
    oled_cmd(0x8E);
    oled_cmd(0xB0);  /* Power save disable */
    oled_cmd(0x0B);
    oled_cmd(0xB1);  /* Phase period */
    oled_cmd(0x31);
    oled_cmd(0xB3);  /* Clock divider / oscillator freq */
    oled_cmd(0xF0);
    oled_cmd(0x8A);  /* Precharge A */
    oled_cmd(0x64);
    oled_cmd(0x8B);  /* Precharge B */
    oled_cmd(0x78);
    oled_cmd(0x8C);  /* Precharge C */
    oled_cmd(0x64);
    oled_cmd(0xBB);  /* Precharge voltage */
    oled_cmd(0x3A);
    oled_cmd(0xBE);  /* VCOMH deselect level */
    oled_cmd(0x3E);
    oled_cmd(0x87);  /* Master current */
    oled_cmd(0x06);
    oled_cmd(0x81);  /* Contrast A (red) */
    oled_cmd(0x91);
    oled_cmd(0x82);  /* Contrast B (green) */
    oled_cmd(0x50);
    oled_cmd(0x83);  /* Contrast C (blue) */
    oled_cmd(0x7D);

    spi_wait();

    /* 4. VCCEN on */
    OLED_CONTROL = CTL_PMODEN | CTL_VCCEN | CTL_CS;
    delay(DELAY_100MS);

    /* 5. Display ON */
    oled_cmd(0xAF);
    spi_wait();
}

/* ---- Рисование ---- */

/* Установить окно рисования */
static void oled_set_window(unsigned char x0, unsigned char y0,
                             unsigned char x1, unsigned char y1) {
    set_cmd_mode();
    oled_cmd(0x15);  /* Set column address */
    oled_cmd(x0);
    oled_cmd(x1);
    oled_cmd(0x75);  /* Set row address */
    oled_cmd(y0);
    oled_cmd(y1);
    spi_wait();
}

/* Залить прямоугольник цветом (RGB565, big-endian: high byte first) */
static void oled_fill_rect(unsigned char x0, unsigned char y0,
                            unsigned char x1, unsigned char y1,
                            unsigned int color16) {
    unsigned char hi = (color16 >> 8) & 0xFF;
    unsigned char lo = color16 & 0xFF;
    int count = (x1 - x0 + 1) * (y1 - y0 + 1);

    oled_set_window(x0, y0, x1, y1);
    set_data_mode();

    for (int i = 0; i < count; i++) {
        oled_data(hi);
        oled_data(lo);
    }
    spi_wait();
}

/* RGB565 color macros */
#define RGB565_RED   0xF800
#define RGB565_GREEN 0x07E0
#define RGB565_BLUE  0x001F
#define RGB565_WHITE 0xFFFF
#define RGB565_BLACK 0x0000

int main(void) {
    puts("OLED init...");

    oled_init();
    puts("OLED init done");

    /* Три горизонтальные полосы: R / G / B */
    oled_fill_rect(0,  0, 95, 20, RGB565_RED);
    puts("Red stripe");

    oled_fill_rect(0, 21, 95, 42, RGB565_GREEN);
    puts("Green stripe");

    oled_fill_rect(0, 43, 95, 63, RGB565_BLUE);
    puts("Blue stripe");

    puts("OLED OK");
    return 0;
}
