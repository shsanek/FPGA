/*
 * Stage 1 bootloader — загружает BOOT.BIN с SD карты (FAT32) в DDR.
 *
 * OLED: boot анимация + прогресс-бар через OLED_FB_DEVICE (BRAM framebuffer).
 * UART: подробные логи каждого этапа.
 */
#include "sd.h"
#include "fat32.h"
#include "../../programs/common/font8x10.h"

#define UART_TX   (*(volatile unsigned int *)0x10000000U)
#define SD_STATUS (*(volatile unsigned int *)0x10020008U)
#define TIMER_MS  (*(volatile unsigned int *)0x10030008U)

/* ---- OLED_FB_DEVICE registers ---- */
#define OLED_CONTROL   (*(volatile unsigned int *)0x10010000U)
#define OLED_STATUS    (*(volatile unsigned int *)0x10010004U)
#define OLED_VP_WIDTH  (*(volatile unsigned int *)0x10010008U)
#define OLED_VP_HEIGHT (*(volatile unsigned int *)0x1001000CU)
#define OLED_FB        ((volatile unsigned int *)0x10014000U)

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

/* Viewport 96×64, stride=128 (shift=7) */
#define VP_W   96
#define VP_H   64
#define STRIDE_SHIFT 7

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

/* ---- Delay ---- */
static void delay(volatile unsigned int n) {
    while (n--) __asm__ volatile("");
}
#define DELAY_1MS   81250

/* ---- OLED framebuffer helpers ---- */
static void fb_wait(void) {
    while (OLED_STATUS & 1) ;
}

static void fb_flush(void) {
    OLED_CONTROL = 1;  /* mode=RGB565, flush */
    fb_wait();
}

static void fb_pixel(int x, int y, unsigned short color) {
    if ((unsigned)x >= VP_W || (unsigned)y >= VP_H) return;
    int hw = (y << STRIDE_SHIFT) + x;
    int wi = hw >> 1;
    if (x & 1)
        OLED_FB[wi] = (OLED_FB[wi] & 0x0000FFFF) | ((unsigned int)color << 16);
    else
        OLED_FB[wi] = (OLED_FB[wi] & 0xFFFF0000) | color;
}

static void fb_fill(unsigned short color) {
    unsigned int dword = ((unsigned int)color << 16) | color;
    for (int y = 0; y < VP_H; y++) {
        int base = (y << STRIDE_SHIFT) >> 1;
        for (int i = 0; i < VP_W / 2; i++)
            OLED_FB[base + i] = dword;
    }
}

static void fb_rect(int x0, int y0, int x1, int y1, unsigned short color) {
    unsigned int dword = ((unsigned int)color << 16) | color;
    for (int y = y0; y <= y1; y++) {
        int base = (y << STRIDE_SHIFT) >> 1;
        /* Заполняем парами пикселей */
        int xa = (x0 + 1) & ~1; /* первый чётный >= x0 */
        int xb = x1 & ~1;       /* последний чётный <= x1 */
        /* Одиночные пиксели на краях */
        if (x0 & 1) fb_pixel(x0, y, color);
        /* Пары */
        for (int x = xa; x < xb; x += 2)
            OLED_FB[base + (x >> 1)] = dword;
        /* Правый край */
        if (!(x1 & 1)) fb_pixel(x1, y, color);
        else if (xb <= x1) fb_pixel(x1, y, color);
    }
}

static void fb_hline(int y, unsigned short color) {
    fb_rect(0, y, VP_W - 1, y, color);
}

static void fb_char(int px, int py, char c, unsigned short fg, unsigned short bg) {
    if (c < FONT_FIRST || c > FONT_LAST) c = '?';
    const unsigned char *glyph = &font8x10[(c - FONT_FIRST) * FONT_H];
    for (int r = 0; r < FONT_H; r++) {
        unsigned char bits = glyph[r];
        for (int b = 7; b >= 0; b--) {
            fb_pixel(px + (7 - b), py + r, (bits >> b) & 1 ? fg : bg);
        }
    }
}

static void fb_text(int col, int row, const char *s, unsigned short fg, unsigned short bg) {
    int x = col * FONT_W;
    while (*s && x + FONT_W <= VP_W) {
        fb_char(x, row * FONT_H, *s, fg, bg);
        x += FONT_W;
        s++;
    }
}

static void fb_char_2x(int px, int py, char c, unsigned short fg, unsigned short bg) {
    if (c < FONT_FIRST || c > FONT_LAST) c = '?';
    const unsigned char *glyph = &font8x10[(c - FONT_FIRST) * FONT_H];
    for (int r = 0; r < FONT_H; r++) {
        unsigned char bits = glyph[r];
        for (int b = 7; b >= 0; b--) {
            unsigned short col = (bits >> b) & 1 ? fg : bg;
            int bx = px + (7 - b) * 2;
            int by = py + r * 2;
            fb_pixel(bx, by, col);
            fb_pixel(bx + 1, by, col);
            fb_pixel(bx, by + 1, col);
            fb_pixel(bx + 1, by + 1, col);
        }
    }
}

/* ---- Прогресс-бар (внизу экрана) ---- */
#define BAR_Y0  58
#define BAR_Y1  61
#define BAR_X0  8
#define BAR_X1  87
#define BAR_W   (BAR_X1 - BAR_X0 + 1)
static int last_bar_px = -1;

static void draw_progress_bar(int px) {
    if (px > BAR_W) px = BAR_W;
    if (px == last_bar_px) return;
    if (px > 0)
        fb_rect(BAR_X0, BAR_Y0, BAR_X0 + px - 1, BAR_Y1, COL_ACCENT);
    if (px < BAR_W)
        fb_rect(BAR_X0 + px, BAR_Y0, BAR_X1, BAR_Y1, COL_LGRAY);
    last_bar_px = px;
    fb_flush();
}

/* fat32 progress callback */
static void loading_progress(unsigned int loaded, unsigned int total) {
    int px = (total > 0) ? (int)((loaded * (unsigned long long)BAR_W) / total) : 0;
    draw_progress_bar(px);
}

/* ---- Boot animation (PS1-style) ---- */
static void boot_animation(void) {
    /* Настройка viewport */
    OLED_VP_WIDTH  = VP_W;
    OLED_VP_HEIGHT = VP_H;

    /* Phase 1: чёрный экран */
    fb_fill(COL_BLACK);
    fb_flush();
    delay(DELAY_1MS * 400);

    /* Phase 2: яркая точка в центре */
    fb_rect(45, 29, 50, 34, COL_WHITE);
    fb_flush();
    delay(DELAY_1MS * 250);

    /* Phase 3: горизонтальные линии расширяются от центра */
    for (int d = 0; d <= 31; d++) {
        fb_hline(31 - d, COL_WHITE);
        fb_hline(32 + d, COL_WHITE);
        fb_flush();
        delay(DELAY_1MS * 10);
    }

    /* Phase 4: лого "RV32" 2x по центру */
    fb_char_2x(16, 12, 'R', COL_DBLUE, COL_WHITE);
    fb_char_2x(32, 12, 'V', COL_DBLUE, COL_WHITE);
    fb_char_2x(48, 12, '3', COL_DBLUE, COL_WHITE);
    fb_char_2x(64, 12, '2', COL_DBLUE, COL_WHITE);

    /* Цветная полоска */
    fb_rect(16, 34, 79, 35, COL_ACCENT);

    /* "RISC-V" мелким шрифтом */
    fb_text(3, 5, "RISC-V", COL_DARK, COL_WHITE);

    fb_flush();
    delay(DELAY_1MS * 1200);
}

/* ---- Halt ---- */
static void halt_anim(const char *msg) {
    boot_puts(msg);
    fb_rect(BAR_X0, BAR_Y0, BAR_X1, BAR_Y1, COL_RED);
    fb_rect(0, 44, 95, 63, COL_WHITE);
    fb_text(0, 5, msg, COL_RED, COL_WHITE);
    fb_flush();
    while (1) __asm__ volatile("");
}

/* ---- Main ---- */
int main(void) {
    boot_puts("=== Stage1 Bootloader ===");

    /* Boot animation (SSD1331 init аппаратно при первом flush) */
    boot_animation();
    boot_puts("[OLED] init OK");

    /* Прогресс-бар */
    draw_progress_bar(0);

    /* SD card */
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

    /* UART log */
    boot_print("[LOAD] ");
    boot_hex((unsigned int)size);
    boot_print(" bytes, ");
    boot_hex(t1 - t0);
    boot_puts(" ms");

    /* Пауза + схлопывание */
    delay(DELAY_1MS * 300);
    for (int d = 0; d <= 31; d++) {
        fb_hline(d, COL_BLACK);
        fb_hline(63 - d, COL_BLACK);
        fb_flush();
        delay(DELAY_1MS * 4);
    }

    /* Jump */
    boot_print("[JUMP] 0x");
    boot_hex(LOAD_ADDR);
    boot_putc('\n');

    ((void (*)(void))LOAD_ADDR)();
    return 0;
}
