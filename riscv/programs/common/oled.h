#ifndef OLED_API_H
#define OLED_API_H

/* OLED API — PmodOLEDrgb (SSD1331), 96×64 RGB565.
 *
 * OLED_FB_DEVICE: BRAM framebuffer на FPGA, аппаратный рендерер.
 * CPU пишет пиксели через MMIO, flush отправляет кадр аппаратно.
 * Шрифт 8×10, даёт 12 колонок × 6 строк текста.
 *
 * Два режима:
 *   RGB565 — 16 бит на пиксель, прямой цвет
 *   PAL256 — 8 бит на пиксель, 256-цветная палитра (16 бит на запись)
 */

#define OLED_W  96
#define OLED_H  64

/* Цвета RGB565 */
#define OLED_BLACK   0x0000
#define OLED_RED     0xF800
#define OLED_GREEN   0x07E0
#define OLED_BLUE    0x001F
#define OLED_YELLOW  0xFFE0
#define OLED_CYAN    0x07FF
#define OLED_MAGENTA 0xF81F
#define OLED_WHITE   0xFFFF
#define OLED_RGB(r5,g6,b5)  ((unsigned short)(((r5)<<11)|((g6)<<5)|(b5)))

/* Режимы цвета */
#define OLED_MODE_RGB565  0
#define OLED_MODE_PAL256  1

/* Init: устанавливает viewport 96×64, mode RGB565.
 * SSD1331 init выполняется аппаратно при первом flush. */
void oled_init(void);

/* Viewport: задать рабочую область (96–256 каждая сторона).
 * Аппаратный скейлинг вписывает в 96×64. */
void oled_set_viewport(int w, int h);

/* Режим цвета: OLED_MODE_RGB565 или OLED_MODE_PAL256 */
void oled_set_mode(int mode);

/* Палитра (только для PAL256): задать цвет для индекса 0–255 */
void oled_set_palette(int idx, unsigned short color);

/* Framebuffer drawing (пишет в BRAM на FPGA через MMIO) */
void oled_clear(unsigned short color);
void oled_pixel(int x, int y, unsigned short color);
void oled_rect(int x0, int y0, int w, int h, unsigned short color);
void oled_char(int x, int y, char c, unsigned short fg, unsigned short bg);
void oled_print(int x, int y, const char *s, unsigned short fg, unsigned short bg);

/* PAL256 drawing */
void oled_clear_pal(unsigned char idx);
void oled_pixel_pal(int x, int y, unsigned char idx);

/* Текст по строкам (row=0..5, col=0..11) — удобная обёртка */
void oled_text(int row, int col, const char *s, unsigned short fg, unsigned short bg);

/* Запустить отрисовку (неблокирующий — CPU может работать дальше).
 * Запись в FB во время рендера → CPU stall аппаратно. */
void oled_flush(void);

/* Ждёт завершения текущего рендера (блокирующий) */
void oled_sync(void);

/* Busy? (неблокирующая проверка) */
int oled_busy(void);

#endif
