/*
 * i_video.c — Video output for DOOM on Arty A7 (OLED 96×64).
 *
 * DOOM renders 320×200 8-bit indexed color.
 * We downscale to 96×64 and convert palette to RGB565 for OLED.
 */

#include <stdint.h>
#include <string.h>

#include "doomdef.h"
#include "i_system.h"
#include "v_video.h"
#include "i_video.h"
#include "config.h"

/* OLED hardware registers */
#define OLED_DATA_REG    (*(volatile unsigned int *)0x10010000U)
#define OLED_CONTROL_REG (*(volatile unsigned int *)0x10010004U)
#define OLED_STATUS_REG  (*(volatile unsigned int *)0x10010008U)
#define OLED_DIVIDER_REG (*(volatile unsigned int *)0x1001000CU)

#define CTL_CS     (1 << 0)
#define CTL_DC     (1 << 1)
#define CTL_RES    (1 << 2)
#define CTL_VCCEN  (1 << 3)
#define CTL_PMODEN (1 << 4)

#define OLED_W 96
#define OLED_H 64

static uint16_t palette565[256];
static uint16_t oled_fb[OLED_W * OLED_H];

/* ---- SPI helpers ---- */

static void spi_wait(void) {
    while (OLED_STATUS_REG & 0x2) ;
}

static void oled_cmd(unsigned char c) {
    OLED_CONTROL_REG = CTL_PMODEN | CTL_VCCEN | CTL_CS;
    spi_wait();
    OLED_DATA_REG = c;
    spi_wait();
}

static void oled_data(unsigned char d) {
    OLED_CONTROL_REG = CTL_PMODEN | CTL_VCCEN | CTL_CS | CTL_DC;
    spi_wait();
    OLED_DATA_REG = d;
    spi_wait();
}

static void delay(volatile unsigned int n) {
    while (n--) __asm__ volatile("");
}
#define DELAY_1MS   81250
#define DELAY_20MS  (20 * DELAY_1MS)
#define DELAY_100MS (100 * DELAY_1MS)

/* ---- Init ---- */

void I_InitGraphics(void)
{
    /* OLED already initialized by boot_oled_init() */
    memset(oled_fb, 0, sizeof(oled_fb));
    usegamma = 1;
}

void I_ShutdownGraphics(void)
{
    oled_cmd(0xAE);
    OLED_CONTROL_REG = CTL_PMODEN;
    delay(DELAY_100MS);
    OLED_CONTROL_REG = 0;
}

/* ---- Palette: DOOM RGB888 → RGB565 ---- */

void I_SetPalette(byte *palette)
{
    for (int i = 0; i < 256; i++) {
        uint8_t r = gammatable[usegamma][*palette++];
        uint8_t g = gammatable[usegamma][*palette++];
        uint8_t b = gammatable[usegamma][*palette++];
        palette565[i] = ((uint16_t)(r >> 3) << 11)
                      | ((uint16_t)(g >> 2) <<  5)
                      | ((uint16_t)(b >> 3));
    }
}

void I_UpdateNoBlit(void) {}

/* ---- Finish update: downscale 320×200 → 96×64, push to OLED ---- */

void I_FinishUpdate(void)
{
    byte *src = screens[0]; /* 320×200, 8-bit indexed */

    /* Nearest-neighbor downscale */
    for (int oy = 0; oy < OLED_H; oy++) {
        int sy = (oy * SCREENHEIGHT) / OLED_H;
        for (int ox = 0; ox < OLED_W; ox++) {
            int sx = (ox * SCREENWIDTH) / OLED_W;
            oled_fb[oy * OLED_W + ox] = palette565[src[sy * SCREENWIDTH + sx]];
        }
    }

    /* Set window */
    oled_cmd(0x15); oled_cmd(0x00); oled_cmd(0x5F);
    oled_cmd(0x75); oled_cmd(0x00); oled_cmd(0x3F);

    /* Stream pixels */
    for (int i = 0; i < OLED_W * OLED_H; i++) {
        oled_data((oled_fb[i] >> 8) & 0xFF);
        oled_data(oled_fb[i] & 0xFF);
    }
}

void I_WaitVBL(int count) { (void)count; }

void I_ReadScreen(byte *scr)
{
    memcpy(scr, screens[0], SCREENHEIGHT * SCREENWIDTH);
}

/* ---- Boot screen (called before DOOM init) ---- */

/* Tiny 3x5 font for boot screen — digits, letters, punctuation */
static const uint8_t boot_font[][3] = {
    /* ' ' */ {0x00,0x00,0x00},
    /* '!' */ {0x00,0x17,0x00},
    /* '.' */ {0x00,0x10,0x00},
    /* '/' */ {0x08,0x04,0x02},
    /* '0' */ {0x1F,0x11,0x1F},
    /* '1' */ {0x12,0x1F,0x10},
    /* '2' */ {0x1D,0x15,0x17},
    /* '3' */ {0x15,0x15,0x1F},
    /* '4' */ {0x07,0x04,0x1F},
    /* '5' */ {0x17,0x15,0x1D},
    /* '6' */ {0x1F,0x15,0x1D},
    /* '7' */ {0x01,0x01,0x1F},
    /* '8' */ {0x1F,0x15,0x1F},
    /* '9' */ {0x17,0x15,0x1F},
    /* 'A' */ {0x1E,0x05,0x1E},
    /* 'B' */ {0x1F,0x15,0x0A},
    /* 'C' */ {0x0E,0x11,0x11},
    /* 'D' */ {0x1F,0x11,0x0E},
    /* 'E' */ {0x1F,0x15,0x11},
    /* 'F' */ {0x1F,0x05,0x01},
    /* 'G' */ {0x0E,0x11,0x1D},
    /* 'H' */ {0x1F,0x04,0x1F},
    /* 'I' */ {0x11,0x1F,0x11},
    /* 'J' */ {0x18,0x10,0x1F},
    /* 'K' */ {0x1F,0x04,0x1B},
    /* 'L' */ {0x1F,0x10,0x10},
    /* 'M' */ {0x1F,0x02,0x1F},
    /* 'N' */ {0x1F,0x01,0x1F},
    /* 'O' */ {0x0E,0x11,0x0E},
    /* 'P' */ {0x1F,0x05,0x02},
    /* 'Q' */ {0x0E,0x19,0x1E},
    /* 'R' */ {0x1F,0x05,0x1A},
    /* 'S' */ {0x12,0x15,0x09},
    /* 'T' */ {0x01,0x1F,0x01},
    /* 'U' */ {0x1F,0x10,0x1F},
    /* 'V' */ {0x0F,0x10,0x0F},
    /* 'W' */ {0x1F,0x08,0x1F},
    /* 'X' */ {0x1B,0x04,0x1B},
    /* 'Y' */ {0x03,0x1C,0x03},
    /* 'Z' */ {0x19,0x15,0x13},
};

static int boot_char_idx(char c) {
    if (c == ' ') return 0;
    if (c == '!') return 1;
    if (c == '.') return 2;
    if (c == '/') return 3;
    if (c >= '0' && c <= '9') return 4 + (c - '0');
    if (c >= 'A' && c <= 'Z') return 14 + (c - 'A');
    if (c >= 'a' && c <= 'z') return 14 + (c - 'a');
    return 0;
}

static void boot_putchar(int x, int y, char c, uint16_t fg, uint16_t bg) {
    int idx = boot_char_idx(c);
    for (int col = 0; col < 3; col++) {
        uint8_t bits = boot_font[idx][col];
        for (int row = 0; row < 5; row++) {
            if (x+col >= 0 && x+col < OLED_W && y+row >= 0 && y+row < OLED_H)
                oled_fb[(y+row)*OLED_W + x+col] = (bits & 1) ? fg : bg;
            bits >>= 1;
        }
    }
    /* 1px gap */
    for (int row = 0; row < 5; row++)
        if (x+3 >= 0 && x+3 < OLED_W && y+row >= 0 && y+row < OLED_H)
            oled_fb[(y+row)*OLED_W + x+3] = bg;
}

static void boot_print(int x, int y, const char *s, uint16_t fg, uint16_t bg) {
    while (*s) {
        boot_putchar(x, y, *s++, fg, bg);
        x += 4;
    }
}

static void boot_flush(void) {
    oled_cmd(0x15); oled_cmd(0x00); oled_cmd(0x5F);
    oled_cmd(0x75); oled_cmd(0x00); oled_cmd(0x3F);
    for (int i = 0; i < OLED_W * OLED_H; i++) {
        oled_data((oled_fb[i] >> 8) & 0xFF);
        oled_data(oled_fb[i] & 0xFF);
    }
}

static void boot_rect(int x0, int y0, int w, int h, uint16_t color) {
    for (int y = y0; y < y0+h && y < OLED_H; y++)
        for (int x = x0; x < x0+w && x < OLED_W; x++)
            oled_fb[y*OLED_W + x] = color;
}

/* RGB565 helpers */
#define RGB565(r,g,b) ((uint16_t)(((r)<<11)|((g)<<5)|(b)))
#define C_BLACK   0x0000
#define C_RED     RGB565(31,0,0)
#define C_DKRED   RGB565(16,0,0)
#define C_GREEN   RGB565(0,50,0)
#define C_GREY    RGB565(10,20,10)
#define C_WHITE   RGB565(31,63,31)
#define C_YELLOW  RGB565(31,63,0)

void boot_oled_init(void)
{
    OLED_DIVIDER_REG = 7;

    OLED_CONTROL_REG = CTL_PMODEN;
    delay(DELAY_20MS);
    OLED_CONTROL_REG = CTL_PMODEN | CTL_RES;
    delay(DELAY_1MS);
    OLED_CONTROL_REG = CTL_PMODEN;
    delay(DELAY_1MS);

    oled_cmd(0xAE);
    oled_cmd(0xA0); oled_cmd(0x72);
    oled_cmd(0xA1); oled_cmd(0x00);
    oled_cmd(0xA2); oled_cmd(0x00);
    oled_cmd(0xA4);
    oled_cmd(0xA8); oled_cmd(0x3F);
    oled_cmd(0xAD); oled_cmd(0x8E);
    oled_cmd(0xB0); oled_cmd(0x0B);
    oled_cmd(0xB1); oled_cmd(0x31);
    oled_cmd(0xB3); oled_cmd(0xF0);
    oled_cmd(0xBB); oled_cmd(0x3A);
    oled_cmd(0xBE); oled_cmd(0x3E);
    oled_cmd(0x87); oled_cmd(0x06);
    oled_cmd(0x81); oled_cmd(0x91);
    oled_cmd(0x82); oled_cmd(0x50);
    oled_cmd(0x83); oled_cmd(0x7D);

    OLED_CONTROL_REG = CTL_PMODEN | CTL_VCCEN | CTL_CS;
    delay(DELAY_100MS);
    oled_cmd(0xAF);
    delay(DELAY_20MS);

    /* Black screen */
    memset(oled_fb, 0, sizeof(oled_fb));

    /* === DOOM boot screen === */

    /* Red border frame */
    boot_rect(0, 0, OLED_W, 1, C_DKRED);
    boot_rect(0, OLED_H-1, OLED_W, 1, C_DKRED);
    boot_rect(0, 0, 1, OLED_H, C_DKRED);
    boot_rect(OLED_W-1, 0, 1, OLED_H, C_DKRED);

    /* Title */
    boot_print(22, 4, "DOOM", C_RED, C_BLACK);
    boot_print(10, 12, "ARTY A7", C_YELLOW, C_BLACK);

    /* Separator */
    boot_rect(4, 20, OLED_W-8, 1, C_GREY);

    /* Status lines */
    boot_print(4, 24, "RISC V  RV32IM", C_GREEN, C_BLACK);
    boot_print(4, 32, "OLED 96X64", C_GREEN, C_BLACK);

    /* Progress bar outline */
    boot_rect(4, 50, OLED_W-8, 7, C_GREY);
    boot_rect(5, 51, OLED_W-10, 5, C_BLACK);

    boot_print(4, 42, "LOADING...", C_WHITE, C_BLACK);

    boot_flush();
}

void boot_oled_progress(int percent)
{
    if (percent > 100) percent = 100;
    int bar_w = (OLED_W - 12) * percent / 100;

    /* Fill progress bar */
    boot_rect(6, 52, bar_w, 3, C_RED);

    /* Percent text */
    char buf[8];
    buf[0] = '0' + (percent / 100) % 10;
    buf[1] = '0' + (percent / 10) % 10;
    buf[2] = '0' + percent % 10;
    buf[3] = 0;
    /* Skip leading zeros */
    char *p = buf;
    if (*p == '0') p++;
    if (*p == '0' && percent >= 10) p++;

    boot_print(OLED_W - 20, 42, p, C_WHITE, C_BLACK);

    boot_flush();
}

void boot_oled_status(const char *msg)
{
    /* Clear status area */
    boot_rect(4, 42, OLED_W-8, 5, C_BLACK);
    boot_print(4, 42, msg, C_WHITE, C_BLACK);
    boot_flush();
}
