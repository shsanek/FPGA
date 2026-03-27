/* OLED API — OLED_FB_DEVICE (BRAM framebuffer + аппаратный рендерер).
 *
 * CPU пишет пиксели через MMIO в BRAM на FPGA.
 * oled_flush() запускает аппаратный рендерер (SPI → SSD1331).
 */
#include "oled.h"
#include "font8x10.h"

/* ---- Hardware registers (OLED_FB_DEVICE, слот 0x1001_0000) ---- */
#define OLED_CONTROL   (*(volatile unsigned int *)0x10010000U)
#define OLED_STATUS    (*(volatile unsigned int *)0x10010004U)
#define OLED_VP_WIDTH  (*(volatile unsigned int *)0x10010008U)
#define OLED_VP_HEIGHT (*(volatile unsigned int *)0x1001000CU)

/* Палитра: 256 × 16 бит, base 0x10010010 */
#define OLED_PALETTE   ((volatile unsigned short *)0x10010010U)

/* Framebuffer: base 0x10014000, 32-бит доступ */
#define OLED_FB_BASE   0x10014000U
#define OLED_FB        ((volatile unsigned int *)OLED_FB_BASE)

/* ---- State ---- */
static int vp_w = OLED_W;
static int vp_h = OLED_H;
static int stride_shift = 7;  /* log2(128) for vp_w <= 128 */
static int cur_mode = OLED_MODE_RGB565;

static void update_stride(void) {
    stride_shift = (vp_w <= 128) ? 7 : 8;
}

/* ---- Init ---- */
void oled_init(void) {
    vp_w = OLED_W;
    vp_h = OLED_H;
    cur_mode = OLED_MODE_RGB565;
    update_stride();

    OLED_VP_WIDTH  = vp_w;
    OLED_VP_HEIGHT = vp_h;
    OLED_CONTROL   = 0;  /* mode=RGB565, no flush */

    oled_clear(OLED_BLACK);
    oled_flush();
}

/* ---- Viewport ---- */
void oled_set_viewport(int w, int h) {
    vp_w = w;
    vp_h = h;
    update_stride();
    OLED_VP_WIDTH  = w;
    OLED_VP_HEIGHT = h;
}

/* ---- Mode ---- */
void oled_set_mode(int mode) {
    cur_mode = mode;
    /* Mode is sent with next flush via CONTROL register */
}

/* ---- Palette ---- */
void oled_set_palette(int idx, unsigned short color) {
    if ((unsigned)idx < 256)
        OLED_PALETTE[idx] = color;
}

/* ---- Flush ---- */
void oled_flush(void) {
    /* Trigger flush with current mode */
    OLED_CONTROL = (cur_mode ? 2 : 0) | 1;  /* bit1=mode, bit0=flush */
    /* CPU stalls automatically on next OLED access while busy.
     * But we wait explicitly so caller knows flush is done. */
    while (OLED_STATUS & 1) ;
}

void oled_wait(void) {
    while (OLED_STATUS & 1) ;
}

int oled_busy(void) {
    return OLED_STATUS & 1;
}

/* ---- RGB565 pixel write ---- */
void oled_pixel(int x, int y, unsigned short color) {
    if ((unsigned)x >= (unsigned)vp_w || (unsigned)y >= (unsigned)vp_h) return;

    /* Адрес в framebuffer:
     * halfword_addr = (y << stride_shift) + x
     * word_addr = halfword_addr >> 1
     * Пиксель с чётным x → [15:0], нечётным → [31:16] */
    int hw_addr = (y << stride_shift) + x;
    int word_idx = hw_addr >> 1;
    volatile unsigned int *p = &OLED_FB[word_idx];

    if (x & 1)
        *p = (*p & 0x0000FFFF) | ((unsigned int)color << 16);
    else
        *p = (*p & 0xFFFF0000) | color;
}

void oled_clear(unsigned short color) {
    unsigned int dword = ((unsigned int)color << 16) | color;
    int stride = 1 << stride_shift;
    /* Заполняем построчно (stride может быть > vp_w) */
    for (int y = 0; y < vp_h; y++) {
        int base = (y << stride_shift) >> 1; /* word offset for row */
        int words = vp_w >> 1; /* 2 pixels per word */
        for (int i = 0; i < words; i++)
            OLED_FB[base + i] = dword;
        /* Нечётная ширина — последний пиксель */
        if (vp_w & 1) {
            int hw_addr = (y << stride_shift) + vp_w - 1;
            int wi = hw_addr >> 1;
            OLED_FB[wi] = (OLED_FB[wi] & 0xFFFF0000) | color;
        }
    }
}

void oled_rect(int x0, int y0, int w, int h, unsigned short color) {
    for (int y = y0; y < y0 + h; y++)
        for (int x = x0; x < x0 + w; x++)
            oled_pixel(x, y, color);
}

/* ---- PAL256 pixel write ---- */
void oled_pixel_pal(int x, int y, unsigned char idx) {
    if ((unsigned)x >= (unsigned)vp_w || (unsigned)y >= (unsigned)vp_h) return;

    /* Адрес в framebuffer:
     * byte_addr = (y << stride_shift) + x
     * word_addr = byte_addr >> 2
     * Байт position: byte_addr & 3 */
    int byte_addr = (y << stride_shift) + x;
    int word_idx = byte_addr >> 2;
    int shift = (byte_addr & 3) << 3;
    volatile unsigned int *p = &OLED_FB[word_idx];
    *p = (*p & ~(0xFF << shift)) | ((unsigned int)idx << shift);
}

void oled_clear_pal(unsigned char idx) {
    unsigned int dword = (unsigned int)idx | ((unsigned int)idx << 8) |
                         ((unsigned int)idx << 16) | ((unsigned int)idx << 24);
    int stride = 1 << stride_shift;
    for (int y = 0; y < vp_h; y++) {
        int base = (y << stride_shift) >> 2; /* word offset for row */
        int words = vp_w >> 2;
        for (int i = 0; i < words; i++)
            OLED_FB[base + i] = dword;
    }
}

/* ---- Text (RGB565 mode) ---- */
void oled_char(int x, int y, char c, unsigned short fg, unsigned short bg) {
    if (c < FONT_FIRST || c > FONT_LAST) c = ' ';
    const unsigned char *glyph = &font8x10[(c - FONT_FIRST) * FONT_H];

    for (int row = 0; row < FONT_H; row++) {
        unsigned char bits = glyph[row];
        for (int col = 0; col < FONT_W; col++) {
            oled_pixel(x + col, y + row, (bits & 0x80) ? fg : bg);
            bits <<= 1;
        }
    }
}

void oled_print(int x, int y, const char *s, unsigned short fg, unsigned short bg) {
    while (*s) {
        oled_char(x, y, *s++, fg, bg);
        x += FONT_W;
        if (x + FONT_W > vp_w) break;
    }
}

void oled_text(int row, int col, const char *s, unsigned short fg, unsigned short bg) {
    oled_print(col * FONT_W, row * FONT_H, s, fg, bg);
}
