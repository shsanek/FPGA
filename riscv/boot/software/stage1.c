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
#define COL_DBLUE   0x1926
#define COL_ACCENT  0x049F
#define COL_LGRAY   0xDEFB

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

/* ---- Прогресс-бар (внизу экрана, поверх анимации) ---- */
#define BAR_Y0  58
#define BAR_Y1  61
#define BAR_X0  8
#define BAR_X1  87
#define BAR_W   (BAR_X1 - BAR_X0 + 1)  /* 80px */
static int last_bar_px = -1;

static void draw_progress_bar(int px) {
    if (px > BAR_W) px = BAR_W;
    if (px == last_bar_px) return;
    if (px > 0)
        oled_fill_rect(BAR_X0, BAR_Y0, BAR_X0 + px - 1, BAR_Y1, COL_ACCENT);
    if (px < BAR_W)
        oled_fill_rect(BAR_X0 + px, BAR_Y0, BAR_X1, BAR_Y1, COL_LGRAY);
    last_bar_px = px;
}

/* fat32 progress callback */
static void loading_progress(unsigned int loaded, unsigned int total) {
    int px = (total > 0) ? (int)((loaded * (unsigned long long)BAR_W) / total) : 0;
    draw_progress_bar(px);
}


/* ---- Boot animation (PS1-style) ---- */

static void oled_draw_char_2x(int px, int py, char c,
                                unsigned int fg, unsigned int bg) {
    if (c < FONT_FIRST || c > FONT_LAST) c = '?';
    const unsigned char *glyph = &font8x10[(c - FONT_FIRST) * FONT_H];
    unsigned char fghi = (fg >> 8), fglo = fg & 0xFF;
    unsigned char bghi = (bg >> 8), bglo = bg & 0xFF;
    int w2 = FONT_W * 2, h2 = FONT_H * 2;
    if (px + w2 > 96 || py + h2 > 64) return;

    oled_set_cmd_mode();
    oled_cmd(0x15); oled_cmd(px); oled_cmd(px + w2 - 1);
    oled_cmd(0x75); oled_cmd(py); oled_cmd(py + h2 - 1);
    spi_wait();
    oled_set_data_mode();
    for (int r = 0; r < FONT_H; r++) {
        unsigned char bits = glyph[r];
        /* Каждая строка рисуется дважды (2x по Y) */
        for (int rep = 0; rep < 2; rep++) {
            for (int b = 7; b >= 0; b--) {
                int on = (bits >> b) & 1;
                unsigned char hi = on ? fghi : bghi;
                unsigned char lo = on ? fglo : bglo;
                /* 2x по X */
                oled_data(hi); oled_data(lo);
                oled_data(hi); oled_data(lo);
            }
        }
    }
    spi_wait();
}

static void boot_animation(void) {
    /* Phase 1: чёрный экран, пауза */
    oled_fill_rect(0, 0, 95, 63, COL_BLACK);
    delay(DELAY_1MS * 400);

    /* Phase 2: яркая точка в центре */
    oled_fill_rect(45, 29, 50, 34, COL_WHITE);
    delay(DELAY_1MS * 250);

    /* Phase 3: горизонтальные линии расширяются от центра */
    for (int d = 0; d <= 31; d++) {
        oled_fill_rect(0, 31 - d, 95, 31 - d, COL_WHITE);
        oled_fill_rect(0, 32 + d, 95, 32 + d, COL_WHITE);
        delay(DELAY_1MS * 10);
    }

    /* Phase 4: лого "RV32" 2x по центру на белом фоне */
    /* 4 символа * 16px = 64px, центр: (96-64)/2 = 16 */
    oled_draw_char_2x(16, 12, 'R', COL_DBLUE, COL_WHITE);
    oled_draw_char_2x(32, 12, 'V', COL_DBLUE, COL_WHITE);
    oled_draw_char_2x(48, 12, '3', COL_DBLUE, COL_WHITE);
    oled_draw_char_2x(64, 12, '2', COL_DBLUE, COL_WHITE);

    /* Цветная полоска-акцент под лого */
    oled_fill_rect(16, 34, 79, 35, COL_ACCENT);

    /* "RISC-V" мелким шрифтом снизу */
    oled_text(3, 5, "RISC-V", COL_DARK, COL_WHITE);

    delay(DELAY_1MS * 1200);
    /* Экран остаётся — загрузка поверх */
}

/* ---- Halt (на экране анимации, с информацией) ---- */
static void halt_anim(const char *msg) {
    boot_puts(msg);
    /* Красная полоска вместо прогресс-бара */
    oled_fill_rect(BAR_X0, BAR_Y0, BAR_X1, BAR_Y1, COL_RED);
    /* Затемняем нижнюю часть и пишем ошибку */
    oled_fill_rect(0, 44, 95, 63, COL_WHITE);
    oled_text(0, 5, msg, COL_RED, COL_WHITE);
    while (1) __asm__ volatile("");
}

/* ---- Main ---- */
int main(void) {
    boot_puts("=== Stage1 Bootloader ===");

    /* OLED init + boot animation (экран остаётся белый с лого) */
    oled_init();
    boot_animation();
    boot_puts("[OLED] init OK");

    /* Рисуем пустой прогресс-бар */
    draw_progress_bar(0);

    /* SD card (статус только в UART) */
    if (!(SD_STATUS & 0x04))
        halt_anim("NO CARD");
    if (sd_init() != 0)
        halt_anim("SD FAIL");
    boot_puts("[SD]   OK");

    /* FAT32 */
    if (fat32_init() != 0)
        halt_anim("FAT FAIL");
    boot_puts("FAT32 OK");

    /* Load BOOT.BIN */
    fat32_set_progress(loading_progress);
    unsigned int t0 = TIMER_MS;
    int size = fat32_load("BOOT    BIN", (unsigned char *)LOAD_ADDR);
    unsigned int t1 = TIMER_MS;

    if (size <= 0)
        halt_anim("NOT FOUND");

    draw_progress_bar(BAR_W);
    boot_puts("[SD]   OK");

    /* UART log */
    boot_print("[LOAD] ");
    boot_hex((unsigned int)size);
    boot_print(" bytes, ");
    boot_hex(t1 - t0);
    boot_puts(" ms");

    /* Короткая пауза с полным прогресс-баром */
    delay(DELAY_1MS * 300);

    /* Схлопывание экрана к центру → чёрный */
    for (int d = 0; d <= 31; d++) {
        oled_fill_rect(0, d, 95, d, COL_BLACK);
        oled_fill_rect(0, 63 - d, 95, 63 - d, COL_BLACK);
        delay(DELAY_1MS * 4);
    }

    /* Jump */
    boot_print("[JUMP] 0x");
    boot_hex(LOAD_ADDR);
    boot_putc('\n');

    ((void (*)(void))LOAD_ADDR)();
    return 0;
}
