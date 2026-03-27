/*
 * Stage 1 bootloader — загружает BOOT.BIN с SD карты (FAT32) в DDR.
 *
 * OLED: текстовые логи + прогресс-бар загрузки (font8x10, 12x6 символов)
 * UART: подробные логи каждого этапа
 */
#include "sd.h"
#include "fat32.h"
#include "../../programs/common/font8x10.h"

#define UART_TX   (*(volatile unsigned int *)0x10000000U)
#define SD_STATUS (*(volatile unsigned int *)0x10020008U)

/* OLED registers */
#define OLED_DATA    (*(volatile unsigned int *)0x10010000U)
#define OLED_CONTROL (*(volatile unsigned int *)0x10010004U)
#define OLED_STATUS  (*(volatile unsigned int *)0x10010008U)
#define OLED_DIVIDER (*(volatile unsigned int *)0x1001000CU)

/* Timer */
#define TIMER_MS     (*(volatile unsigned int *)0x10030008U)

#define CTL_CS     (1 << 0)
#define CTL_DC     (1 << 1)
#define CTL_RES    (1 << 2)
#define CTL_VCCEN  (1 << 3)
#define CTL_PMODEN (1 << 4)

#define LOAD_ADDR 0x00000000U

/* RGB565 */
#define COL_BLACK   0x0000
#define COL_WHITE   0xFFFF
#define COL_RED     0xF800
#define COL_GREEN   0x07E0
#define COL_BLUE    0x001F
#define COL_CYAN    0x07FF
#define COL_YELLOW  0xFFE0
#define COL_DARK    0x2104

/* ---- UART ---- */
static void boot_putc(int c) { UART_TX = (unsigned int)(unsigned char)c; }
static void boot_puts(const char *s) {
    while (*s) boot_putc(*s++);
    boot_putc('\n');
}
static void boot_print(const char *s) {
    while (*s) boot_putc(*s++);
}
static void boot_hex(unsigned int n) {
    const char *h = "0123456789abcdef";
    for (int s = 28; s >= 0; s -= 4) boot_putc(h[(n >> s) & 0xF]);
}

/* ---- OLED low-level ---- */
static void delay(volatile unsigned int n) {
    while (n--) __asm__ volatile("");
}
#define DELAY_1MS   81250
#define DELAY_20MS  (20 * DELAY_1MS)
#define DELAY_100MS (100 * DELAY_1MS)

static void spi_wait(void) { while (OLED_STATUS & 0x2); }
static void oled_cmd(unsigned char c) { spi_wait(); OLED_DATA = c; }
static void oled_data(unsigned char d) { spi_wait(); OLED_DATA = d; }

static void oled_set_cmd_mode(void) {
    unsigned int ctl = OLED_CONTROL;
    OLED_CONTROL = (ctl & ~CTL_DC) | CTL_CS;
}
static void oled_set_data_mode(void) {
    unsigned int ctl = OLED_CONTROL;
    OLED_CONTROL = ctl | CTL_DC | CTL_CS;
}

static void oled_init(void) {
    OLED_CONTROL = CTL_PMODEN;
    delay(DELAY_20MS);
    OLED_CONTROL = CTL_PMODEN | CTL_RES;
    delay(DELAY_1MS);
    OLED_CONTROL = CTL_PMODEN;
    delay(DELAY_1MS);
    OLED_CONTROL = CTL_PMODEN | CTL_CS;

    oled_cmd(0xAE); oled_cmd(0xA0); oled_cmd(0x72);
    oled_cmd(0xA1); oled_cmd(0x00); oled_cmd(0xA2); oled_cmd(0x00);
    oled_cmd(0xA4); oled_cmd(0xA8); oled_cmd(0x3F);
    oled_cmd(0xAD); oled_cmd(0x8E); oled_cmd(0xB0); oled_cmd(0x0B);
    oled_cmd(0xB1); oled_cmd(0x31); oled_cmd(0xB3); oled_cmd(0xF0);
    oled_cmd(0x8A); oled_cmd(0x64); oled_cmd(0x8B); oled_cmd(0x78);
    oled_cmd(0x8C); oled_cmd(0x64); oled_cmd(0xBB); oled_cmd(0x3A);
    oled_cmd(0xBE); oled_cmd(0x3E); oled_cmd(0x87); oled_cmd(0x06);
    oled_cmd(0x81); oled_cmd(0x91); oled_cmd(0x82); oled_cmd(0x50);
    oled_cmd(0x83); oled_cmd(0x7D);
    spi_wait();
    OLED_CONTROL = CTL_PMODEN | CTL_VCCEN | CTL_CS;
    delay(DELAY_100MS);
    oled_cmd(0xAF);
    spi_wait();
}

/* ---- OLED fill rect ---- */
static void oled_fill_rect(unsigned char x0, unsigned char y0,
                            unsigned char x1, unsigned char y1,
                            unsigned int color) {
    unsigned char hi = (color >> 8) & 0xFF;
    unsigned char lo = color & 0xFF;
    int count = (x1 - x0 + 1) * (y1 - y0 + 1);

    oled_set_cmd_mode();
    oled_cmd(0x15); oled_cmd(x0); oled_cmd(x1);
    oled_cmd(0x75); oled_cmd(y0); oled_cmd(y1);
    spi_wait();
    oled_set_data_mode();
    for (int i = 0; i < count; i++) {
        oled_data(hi);
        oled_data(lo);
    }
    spi_wait();
}

/* ---- OLED text (font8x10) ---- */
/* 96/8=12 символов в строке, 64/10=6 строк */

static void oled_draw_char(int col, int row, char c,
                            unsigned int fg, unsigned int bg) {
    if (c < FONT_FIRST || c > FONT_LAST) c = '?';
    int x = col * FONT_W;
    int y = row * FONT_H;
    if (x + FONT_W > 96 || y + FONT_H > 64) return;

    const unsigned char *glyph = &font8x10[(c - FONT_FIRST) * FONT_H];
    unsigned char fghi = (fg >> 8), fglo = fg & 0xFF;
    unsigned char bghi = (bg >> 8), bglo = bg & 0xFF;

    oled_set_cmd_mode();
    oled_cmd(0x15); oled_cmd(x); oled_cmd(x + FONT_W - 1);
    oled_cmd(0x75); oled_cmd(y); oled_cmd(y + FONT_H - 1);
    spi_wait();
    oled_set_data_mode();
    for (int r = 0; r < FONT_H; r++) {
        unsigned char bits = glyph[r];
        for (int b = 7; b >= 0; b--) {
            if ((bits >> b) & 1) {
                oled_data(fghi); oled_data(fglo);
            } else {
                oled_data(bghi); oled_data(bglo);
            }
        }
    }
    spi_wait();
}

/* Вывести строку на OLED, начиная с позиции (col, row) */
static void oled_text(int col, int row, const char *s,
                       unsigned int fg, unsigned int bg) {
    while (*s && col < 12) {
        oled_draw_char(col, row, *s, fg, bg);
        col++;
        s++;
    }
}

/* Строка + OK/FAIL справа */
static void oled_status(int row, const char *label, int ok) {
    oled_text(0, row, label, COL_WHITE, COL_BLACK);
    if (ok)
        oled_text(10, row, "OK", COL_GREEN, COL_BLACK);
    else
        oled_text(8, row, "FAIL", COL_RED, COL_BLACK);
}

/* ---- Прогресс-бар (строка 4, пиксельный) ---- */
#define BAR_Y0  40
#define BAR_Y1  43
#define BAR_X1  95
static int last_bar_px = -1;

static void draw_progress_bar(int px) {
    if (px > 96) px = 96;
    if (px == last_bar_px) return;
    if (px > 0)
        oled_fill_rect(0, BAR_Y0, px - 1, BAR_Y1, COL_GREEN);
    if (px < 96)
        oled_fill_rect(px, BAR_Y0, BAR_X1, BAR_Y1, COL_DARK);
    last_bar_px = px;
}

/* fat32 progress callback */
static void loading_progress(unsigned int loaded, unsigned int total) {
    int px = (total > 0) ? (int)((loaded * 96ULL) / total) : 0;
    draw_progress_bar(px);
}

/* ---- Halt ---- */
static void halt_red(const char *msg, int row) {
    boot_puts(msg);
    oled_text(0, row, msg, COL_RED, COL_BLACK);
    oled_fill_rect(0, 54, 95, 63, COL_RED);
    while (1) __asm__ volatile("");
}

/* ---- Main ---- */
int main(void) {
    boot_puts("=== Stage1 Bootloader ===");

    /* OLED init */
    oled_init();
    oled_fill_rect(0, 0, 95, 63, COL_BLACK);
    oled_text(0, 0, "RV32 Boot v1", COL_CYAN, COL_BLACK);
    boot_puts("[OLED] init OK");

    /* SD card */
    oled_text(0, 1, "SD:     ", COL_WHITE, COL_BLACK);
    if (!(SD_STATUS & 0x04))
        halt_red("NO CARD", 1);

    if (sd_init() != 0)
        halt_red("SD FAIL", 1);

    oled_status(1, "SD:", 1);
    boot_puts("[SD]   OK");

    /* FAT32 */
    oled_text(0, 2, "FAT32:  ", COL_WHITE, COL_BLACK);
    if (fat32_init() != 0)
        halt_red("FAT FAIL", 2);

    oled_status(2, "FAT32:", 1);
    boot_puts("[FAT]  OK");

    /* Load BOOT.BIN */
    oled_text(0, 3, "Loading...", COL_YELLOW, COL_BLACK);
    draw_progress_bar(0);
    fat32_set_progress(loading_progress);

    unsigned int t0 = TIMER_MS;
    int size = fat32_load("BOOT    BIN", (unsigned char *)LOAD_ADDR);
    unsigned int t1 = TIMER_MS;

    if (size <= 0)
        halt_red("NOT FOUND", 3);

    draw_progress_bar(96);
    oled_status(3, "Loaded:", 1);

    /* Показать размер на OLED строка 4 (под прогресс-баром) */
    /* Простой вывод размера в KB */
    {
        unsigned int kb = (unsigned int)size / 1024;
        char buf[12];
        int pos = 0;
        /* uint to string */
        if (kb == 0) {
            buf[pos++] = '0';
        } else {
            char tmp[10];
            int n = 0;
            unsigned int v = kb;
            while (v) { tmp[n++] = '0' + (v % 10); v /= 10; }
            while (n > 0) buf[pos++] = tmp[--n];
        }
        buf[pos++] = 'K'; buf[pos++] = 'B'; buf[pos] = 0;
        oled_text(0, 5, buf, COL_WHITE, COL_BLACK);

        /* Время загрузки */
        unsigned int dt = t1 - t0;
        pos = 0;
        if (dt == 0) {
            buf[pos++] = '0';
        } else {
            char tmp[10];
            int n = 0;
            unsigned int v = dt;
            while (v) { tmp[n++] = '0' + (v % 10); v /= 10; }
            while (n > 0) buf[pos++] = tmp[--n];
        }
        buf[pos++] = 'm'; buf[pos++] = 's'; buf[pos] = 0;
        oled_text(6, 5, buf, COL_DARK, COL_BLACK);
    }

    /* UART */
    boot_print("[LOAD] ");
    boot_hex((unsigned int)size);
    boot_print(" bytes, ");
    boot_hex(t1 - t0);
    boot_puts(" ms");

    /* Jump */
    boot_print("[JUMP] 0x");
    boot_hex(LOAD_ADDR);
    boot_putc('\n');
    boot_puts("=========================");

    ((void (*)(void))LOAD_ADDR)();
    return 0;
}
