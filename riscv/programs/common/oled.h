#ifndef OLED_API_H
#define OLED_API_H

/* OLED API — PmodOLEDrgb (SSD1331), 96×64 RGB565.
 *
 * Framebuffer в памяти: рисование → oled_flush() отправляет на экран.
 * Шрифт 8×10, даёт 12 колонок × 6 строк текста.
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

/* Init / shutdown */
void oled_init(void);                   /* power on + reset + SSD1331 init */
void oled_off(void);                    /* display off + power down */

/* Framebuffer drawing (не трогает экран до flush) */
void oled_clear(unsigned short color);
void oled_pixel(int x, int y, unsigned short color);
void oled_rect(int x0, int y0, int w, int h, unsigned short color);
void oled_char(int x, int y, char c, unsigned short fg, unsigned short bg);
void oled_print(int x, int y, const char *s, unsigned short fg, unsigned short bg);

/* Текст по строкам (row=0..5, col=0..11) — удобная обёртка */
void oled_text(int row, int col, const char *s, unsigned short fg, unsigned short bg);

/* Отправить фреймбуфер на экран */
void oled_flush(void);

/* Прямой доступ к фреймбуферу (для продвинутого использования) */
unsigned short *oled_framebuffer(void);

#endif
