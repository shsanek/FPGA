/* OLED API — PmodOLEDrgb (SSD1331), framebuffer + flush. */
#include "oled.h"
#include "font8x10.h"

/* ---- Hardware registers ---- */
#define OLED_DATA_REG    (*(volatile unsigned int *)0x08010000U)
#define OLED_CONTROL_REG (*(volatile unsigned int *)0x08010004U)
#define OLED_STATUS_REG  (*(volatile unsigned int *)0x08010008U)
#define OLED_DIVIDER_REG (*(volatile unsigned int *)0x0801000CU)

#define CTL_CS     (1 << 0)
#define CTL_DC     (1 << 1)
#define CTL_RES    (1 << 2)
#define CTL_VCCEN  (1 << 3)
#define CTL_PMODEN (1 << 4)

/* ---- Framebuffer (12 KB) ---- */
static unsigned short fb[OLED_W * OLED_H];

unsigned short *oled_framebuffer(void) { return fb; }

/* ---- Delay ---- */
static void delay(volatile unsigned int n) {
    while (n--) __asm__ volatile("");
}
#define DELAY_1MS   81250
#define DELAY_20MS  (20 * DELAY_1MS)
#define DELAY_100MS (100 * DELAY_1MS)

/* ---- SPI helpers ---- */
static void spi_wait(void) {
    while (OLED_STATUS_REG & 0x2) ;
}

static void oled_cmd(unsigned char c) {
    OLED_CONTROL_REG = CTL_PMODEN | CTL_VCCEN | CTL_CS;  /* DC=0 (cmd) */
    spi_wait();
    OLED_DATA_REG = c;
    spi_wait();
}

static void oled_data(unsigned char d) {
    OLED_CONTROL_REG = CTL_PMODEN | CTL_VCCEN | CTL_CS | CTL_DC;  /* DC=1 */
    spi_wait();
    OLED_DATA_REG = d;
    spi_wait();
}

/* ---- Init / shutdown ---- */
void oled_init(void) {
    OLED_DIVIDER_REG = 7;  /* ~5 MHz */

    /* Power on */
    OLED_CONTROL_REG = CTL_PMODEN;
    delay(DELAY_20MS);

    /* Reset pulse */
    OLED_CONTROL_REG = CTL_PMODEN | CTL_RES;
    delay(DELAY_1MS);
    OLED_CONTROL_REG = CTL_PMODEN;
    delay(DELAY_1MS);

    /* SSD1331 init sequence */
    oled_cmd(0xAE);        /* Display OFF */
    oled_cmd(0xA0);        /* Remap & color depth */
    oled_cmd(0x72);        /* RGB, 65k colors */
    oled_cmd(0xA1);        /* Start line = 0 */
    oled_cmd(0x00);
    oled_cmd(0xA2);        /* Display offset = 0 */
    oled_cmd(0x00);
    oled_cmd(0xA4);        /* Normal display */
    oled_cmd(0xA8);        /* Multiplex ratio */
    oled_cmd(0x3F);        /* 64 lines */
    oled_cmd(0xAD);        /* Master config */
    oled_cmd(0x8E);
    oled_cmd(0xB0);        /* Power save OFF */
    oled_cmd(0x0B);
    oled_cmd(0xB1);        /* Phase period */
    oled_cmd(0x31);
    oled_cmd(0xB3);        /* Clock divider */
    oled_cmd(0xF0);
    oled_cmd(0xBB);        /* Precharge voltage */
    oled_cmd(0x3A);
    oled_cmd(0xBE);        /* VCOMH deselect */
    oled_cmd(0x3E);
    oled_cmd(0x87);        /* Master current */
    oled_cmd(0x06);
    oled_cmd(0x81);        /* Contrast A (blue) */
    oled_cmd(0x91);
    oled_cmd(0x82);        /* Contrast B (green) */
    oled_cmd(0x50);
    oled_cmd(0x83);        /* Contrast C (red) */
    oled_cmd(0x7D);

    /* Vcc enable */
    OLED_CONTROL_REG = CTL_PMODEN | CTL_VCCEN | CTL_CS;
    delay(DELAY_100MS);

    /* Display ON */
    oled_cmd(0xAF);
    delay(DELAY_20MS);

    /* Clear framebuffer */
    oled_clear(OLED_BLACK);
    oled_flush();
}

void oled_off(void) {
    oled_cmd(0xAE);        /* Display OFF */
    OLED_CONTROL_REG = CTL_PMODEN;
    delay(DELAY_100MS);
    OLED_CONTROL_REG = 0;
}

/* ---- Framebuffer drawing ---- */

void oled_clear(unsigned short color) {
    for (int i = 0; i < OLED_W * OLED_H; i++)
        fb[i] = color;
}

void oled_pixel(int x, int y, unsigned short color) {
    if ((unsigned)x < OLED_W && (unsigned)y < OLED_H)
        fb[y * OLED_W + x] = color;
}

void oled_rect(int x0, int y0, int w, int h, unsigned short color) {
    for (int y = y0; y < y0 + h; y++)
        for (int x = x0; x < x0 + w; x++)
            oled_pixel(x, y, color);
}

void oled_char(int x, int y, char c, unsigned short fg, unsigned short bg) {
    if (c < FONT_FIRST || c > FONT_LAST) c = ' ';
    const unsigned char *glyph = &font8x10[(c - FONT_FIRST) * FONT_H];

    for (int row = 0; row < FONT_H; row++) {
        unsigned char bits = glyph[row];
        for (int col = 0; col < FONT_W; col++) {
            unsigned short color = (bits & 0x80) ? fg : bg;
            oled_pixel(x + col, y + row, color);
            bits <<= 1;
        }
    }
}

void oled_print(int x, int y, const char *s, unsigned short fg, unsigned short bg) {
    while (*s) {
        oled_char(x, y, *s++, fg, bg);
        x += FONT_W;
        if (x + FONT_W > OLED_W) break;
    }
}

void oled_text(int row, int col, const char *s, unsigned short fg, unsigned short bg) {
    oled_print(col * FONT_W, row * FONT_H, s, fg, bg);
}

/* ---- Flush framebuffer to OLED ---- */

void oled_flush(void) {
    /* Set column address 0..95 */
    oled_cmd(0x15);
    oled_cmd(0x00);
    oled_cmd(0x5F);

    /* Set row address 0..63 */
    oled_cmd(0x75);
    oled_cmd(0x00);
    oled_cmd(0x3F);

    /* Stream pixel data (RGB565, 2 bytes per pixel, MSB first) */
    for (int i = 0; i < OLED_W * OLED_H; i++) {
        oled_data((fb[i] >> 8) & 0xFF);
        oled_data(fb[i] & 0xFF);
    }
}
