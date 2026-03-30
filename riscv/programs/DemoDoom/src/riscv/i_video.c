/*
 * i_video.c — Video output for DOOM on Arty A7.
 *
 * Uses OLED_FB_DEVICE PAL256 mode:
 *   - CPU writes 8-bit palette indices to MMIO framebuffer
 *   - Hardware does palette lookup → RGB565 → SPI → SSD1331
 *   - Hardware downscales viewport to 96×64
 *
 * DOOM renders 320×200, but viewport limited to 256×200 max (BRAM size).
 * We use 160×100 viewport → hardware 2:1 downscale → good fit for 96×64.
 */

#include <stdint.h>
#include <string.h>

#include "doomdef.h"
#include "i_system.h"
#include "v_video.h"
#include "i_video.h"
#include "config.h"

/* OLED FB DEVICE registers */
#define OLED_CONTROL   (*(volatile unsigned int *)0x40010000U)
#define OLED_STATUS    (*(volatile unsigned int *)0x40010004U)
#define OLED_VP_WIDTH  (*(volatile unsigned int *)0x40010008U)
#define OLED_VP_HEIGHT (*(volatile unsigned int *)0x4001000CU)
#define OLED_PALETTE   ((volatile unsigned short *)0x40010010U)
#define OLED_FB_BASE   0x40014000U
#define OLED_FB        ((volatile unsigned int *)OLED_FB_BASE)

/* Viewport for DOOM — downscaled from 320×200 */
#define VP_W  96
#define VP_H  64
#define VP_STRIDE_SHIFT 7  /* log2(128), stride for BRAM addressing */

static void oled_sync(void) {
    while (OLED_STATUS & 1) ;
}

void I_InitGraphics(void)
{
    oled_sync();

    /* Switch to PAL256 mode for DOOM */
    OLED_VP_WIDTH  = VP_W;
    OLED_VP_HEIGHT = VP_H;

    /* Clear framebuffer (old RGB565 boot screen data) */
    int total_words = (VP_H << VP_STRIDE_SHIFT) >> 2;
    for (int i = 0; i < total_words; i++)
        OLED_FB[i] = 0;

    /* Init palette to black so first frame doesn't flash garbage */
    for (int i = 0; i < 256; i++)
        OLED_PALETTE[i] = 0;

    usegamma = 0;
}

void I_ShutdownGraphics(void)
{
}

/* ---- Palette: load DOOM palette into hardware LUT ---- */

void I_SetPalette(byte *palette)
{
    for (int i = 0; i < 256; i++) {
        uint8_t r = gammatable[usegamma][*palette++];
        uint8_t g = gammatable[usegamma][*palette++];
        uint8_t b = gammatable[usegamma][*palette++];
        uint16_t c = ((uint16_t)(r >> 3) << 11)
                   | ((uint16_t)(g >> 2) <<  5)
                   | ((uint16_t)(b >> 3));
        OLED_PALETTE[i] = c;
    }
}

void I_UpdateNoBlit(void) {}

/* ---- Finish update: downscale 320×200 → VP_W×VP_H, write to MMIO FB ---- */

void I_FinishUpdate(void)
{
    static int frame_num = 0;
    byte *src = screens[0]; /* 320×200, 8-bit indexed */

    uint32_t t0 = TIMER_TIME_US;

    /* Wait for previous render before writing to FB */
    oled_sync();
    uint32_t t1 = TIMER_TIME_US;

    /* Write palette indices directly — hardware does the rest */
    for (int oy = 0; oy < VP_H; oy++) {
        int sy = (oy * SCREENHEIGHT) / VP_H;
        int fb_row_base = (oy << VP_STRIDE_SHIFT) >> 2; /* word offset for row */

        for (int ox = 0; ox < VP_W; ox += 4) {
            int sx0 = ((ox + 0) * SCREENWIDTH) / VP_W;
            int sx1 = ((ox + 1) * SCREENWIDTH) / VP_W;
            int sx2 = ((ox + 2) * SCREENWIDTH) / VP_W;
            int sx3 = ((ox + 3) * SCREENWIDTH) / VP_W;

            /* Pack 4 palette indices into one 32-bit write */
            uint32_t word = (uint32_t)src[sy * SCREENWIDTH + sx0]
                         | ((uint32_t)src[sy * SCREENWIDTH + sx1] << 8)
                         | ((uint32_t)src[sy * SCREENWIDTH + sx2] << 16)
                         | ((uint32_t)src[sy * SCREENWIDTH + sx3] << 24);

            OLED_FB[fb_row_base + (ox >> 2)] = word;
        }
    }

    uint32_t t2 = TIMER_TIME_US;

    /* Kick hardware render (non-blocking): mode=PAL256 (bit1), flush (bit0) */
    OLED_CONTROL = 0x03;

    uint32_t t3 = TIMER_TIME_US;

    frame_num++;
    {
        static uint32_t last_oled_log_ms = 0;
        uint32_t now_ms = TIMER_TIME_MS;
        if (frame_num <= 3 || (now_ms - last_oled_log_ms) >= 3000) {
            printf("[OLED F%d] sync=%d scale=%d flush=%d us\n",
                   frame_num, t1 - t0, t2 - t1, t3 - t2);
            last_oled_log_ms = now_ms;
        }
    }
}

void I_WaitVBL(int count) { (void)count; }

void I_ReadScreen(byte *scr)
{
    memcpy(scr, screens[0], SCREENHEIGHT * SCREENWIDTH);
}

/* ==== Boot screen (RGB565 mode, before DOOM starts) ==== */

/* Tiny 3x5 font for boot screen */
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

/* Boot screen uses RGB565 mode with 96×64 viewport */
static void boot_pixel(int x, int y, uint16_t color) {
    if ((unsigned)x >= 96 || (unsigned)y >= 64) return;
    int hw_addr = (y << 7) + x;  /* stride=128 */
    int word_idx = hw_addr >> 1;
    if (x & 1)
        OLED_FB[word_idx] = (OLED_FB[word_idx] & 0x0000FFFF) | ((unsigned int)color << 16);
    else
        OLED_FB[word_idx] = (OLED_FB[word_idx] & 0xFFFF0000) | color;
}

static void boot_rect(int x0, int y0, int w, int h, uint16_t color) {
    for (int y = y0; y < y0+h && y < 64; y++)
        for (int x = x0; x < x0+w && x < 96; x++)
            boot_pixel(x, y, color);
}

static void boot_putchar(int x, int y, char c, uint16_t fg, uint16_t bg) {
    int idx = boot_char_idx(c);
    for (int col = 0; col < 3; col++) {
        uint8_t bits = boot_font[idx][col];
        for (int row = 0; row < 5; row++) {
            boot_pixel(x+col, y+row, (bits & 1) ? fg : bg);
            bits >>= 1;
        }
    }
    for (int row = 0; row < 5; row++)
        boot_pixel(x+3, y+row, bg);
}

static void boot_print(int x, int y, const char *s, uint16_t fg, uint16_t bg) {
    while (*s) {
        boot_putchar(x, y, *s++, fg, bg);
        x += 4;
    }
}

static void boot_flush(void) {
    /* RGB565 mode, flush */
    OLED_CONTROL = 0x01;
}

#define C_BLACK   0x0000
#define C_RED     0xF800
#define C_DKRED   0x8000
#define C_GREEN   0x0560
#define C_GREY    0x4A49
#define C_WHITE   0xFFFF
#define C_YELLOW  0xFFE0

void boot_oled_init(void)
{
    /* Init OLED_FB_DEVICE: 96×64 RGB565 */
    oled_sync();
    OLED_VP_WIDTH  = 96;
    OLED_VP_HEIGHT = 64;

    /* Clear framebuffer */
    for (int i = 0; i < (64 * 128) / 2; i++)
        OLED_FB[i] = 0;

    /* Red border */
    boot_rect(0, 0, 96, 1, C_DKRED);
    boot_rect(0, 63, 96, 1, C_DKRED);
    boot_rect(0, 0, 1, 64, C_DKRED);
    boot_rect(95, 0, 1, 64, C_DKRED);

    /* Title */
    boot_print(22, 4, "DOOM", C_RED, C_BLACK);
    boot_print(10, 12, "ARTY A7", C_YELLOW, C_BLACK);

    /* Separator */
    boot_rect(4, 20, 88, 1, C_GREY);

    /* Info */
    boot_print(4, 24, "RISC V  RV32IM", C_GREEN, C_BLACK);
    boot_print(4, 32, "OLED 96X64", C_GREEN, C_BLACK);

    /* Progress bar outline */
    boot_rect(4, 50, 88, 7, C_GREY);
    boot_rect(5, 51, 86, 5, C_BLACK);

    boot_print(4, 42, "LOADING...", C_WHITE, C_BLACK);

    boot_flush();
}

void boot_oled_progress(int percent)
{
    if (percent > 100) percent = 100;
    int bar_w = 84 * percent / 100;
    oled_sync();
    boot_rect(6, 52, bar_w, 3, C_RED);
    boot_flush();
}

void boot_oled_status(const char *msg)
{
    oled_sync();
    boot_rect(4, 42, 88, 5, C_BLACK);
    boot_print(4, 42, msg, C_WHITE, C_BLACK);
    boot_flush();
}
