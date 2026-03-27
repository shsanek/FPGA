/*
 * i_video.c — DOOM видео → OLED 96×64 RGB565.
 *
 * DOOM рендерит 320×200, палитра 256 цветов (screens[0]).
 * Nearest-neighbor масштабирование → 96×64, конвертация палитры → RGB565,
 * отправка через SPI на PmodOLEDrgb (SSD1331).
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

/* Палитра в RGB565 */
static uint16_t pal565[256];

/* OLED framebuffer */
static uint16_t oled_fb[OLED_W * OLED_H];

static void delay(volatile unsigned int n) {
    while (n--) __asm__ volatile("");
}
#define DELAY_1MS   81250
#define DELAY_20MS  (20 * DELAY_1MS)
#define DELAY_100MS (100 * DELAY_1MS)

static void spi_wait(void) { while (OLED_STATUS_REG & 0x2); }

static void oled_cmd(uint8_t c) {
    OLED_CONTROL_REG = CTL_PMODEN | CTL_VCCEN | CTL_CS;
    spi_wait(); OLED_DATA_REG = c; spi_wait();
}

static void oled_dat(uint8_t d) {
    OLED_CONTROL_REG = CTL_PMODEN | CTL_VCCEN | CTL_CS | CTL_DC;
    spi_wait(); OLED_DATA_REG = d; spi_wait();
}

static void oled_hw_init(void) {
    OLED_DIVIDER_REG = 7;
    OLED_CONTROL_REG = CTL_PMODEN;           delay(DELAY_20MS);
    OLED_CONTROL_REG = CTL_PMODEN | CTL_RES; delay(DELAY_1MS);
    OLED_CONTROL_REG = CTL_PMODEN;           delay(DELAY_1MS);

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
}

static void oled_flush(void) {
    oled_cmd(0x15); oled_cmd(0x00); oled_cmd(0x5F);
    oled_cmd(0x75); oled_cmd(0x00); oled_cmd(0x3F);
    for (int i = 0; i < OLED_W * OLED_H; i++) {
        oled_dat((oled_fb[i] >> 8) & 0xFF);
        oled_dat(oled_fb[i] & 0xFF);
    }
}

/* ---- DOOM interface ---- */

void I_InitGraphics(void) {
    usegamma = 1;
    oled_hw_init();
}

void I_ShutdownGraphics(void) {
    oled_cmd(0xAE);
    OLED_CONTROL_REG = CTL_PMODEN;
    delay(DELAY_100MS);
    OLED_CONTROL_REG = 0;
}

void I_SetPalette(byte *palette) {
    for (int i = 0; i < 256; i++) {
        uint8_t r = gammatable[usegamma][*palette++];
        uint8_t g = gammatable[usegamma][*palette++];
        uint8_t b = gammatable[usegamma][*palette++];
        pal565[i] = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
    }
}

void I_UpdateNoBlit(void) { }

void I_FinishUpdate(void) {
    /* Scale 320×200 → 96×64 nearest-neighbor + palette → RGB565 */
    byte *src = screens[0];
    for (int oy = 0; oy < OLED_H; oy++) {
        int sy = oy * SCREENHEIGHT / OLED_H;
        for (int ox = 0; ox < OLED_W; ox++) {
            int sx = ox * SCREENWIDTH / OLED_W;
            oled_fb[oy * OLED_W + ox] = pal565[src[sy * SCREENWIDTH + sx]];
        }
    }
    oled_flush();
}

void I_WaitVBL(int count) { }

void I_ReadScreen(byte *scr) {
    _memcpy(scr, screens[0], SCREENHEIGHT * SCREENWIDTH);
}
