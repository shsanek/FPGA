# OLED Framebuffer Device

OLED_FB_DEVICE — BRAM framebuffer 48 KB + аппаратный SPI рендерер для SSD1331 (PmodOLEDrgb, 96×64 RGB565).

**Файл:** `rtl/peripheral/OLED_FB_DEVICE.sv`

---

## Архитектура

```
CPU → PERIPHERAL_BUS → OLED_FB_DEVICE
                            ├── Регистры (CONTROL, STATUS, VP_WIDTH, VP_HEIGHT)
                            ├── Палитра (256 × 16 бит, distributed RAM)
                            ├── BRAM (dual-port, 48 KB, 12 BRAM36)
                            │     Port A: CPU read/write (32-бит, через шину)
                            │     Port B: Renderer read (комбинаторный адрес от pixel_addr_r)
                            └── Renderer FSM → SPI_MASTER → OLED пины
                                  ├── SSD1331 init (power, reset, 36 SPI команд)
                                  ├── Скейлинг viewport → 96×64 (сдвиги)
                                  ├── Палитра lookup (PAL256 режим)
                                  └── SPI pixel stream (~5 MHz)
```

---

## Адресное пространство (слот 0x1001_0000, 64 KB)

| Смещение | Регистр | Доступ | Описание |
|----------|---------|--------|----------|
| 0x0000 | CONTROL | W | bit 0: flush (запуск отрисовки), bit 1: mode (0=RGB565, 1=PAL256) |
| 0x0004 | STATUS | R | bit 0: busy (рендер идёт) |
| 0x0008 | VP_WIDTH | W/R | Ширина viewport (96–256) |
| 0x000C | VP_HEIGHT | W/R | Высота viewport (64–256) |
| 0x0010–0x020F | PALETTE | W/R | 256 записей × 16 бит RGB565 (halfword доступ через sh/lhu) |
| 0x4000–0xFFFF | FRAMEBUFFER | W/R | Пиксели, stride = power-of-2 |

### Блокировки

- `controller_ready = 1` всегда — CPU не блокируется на шине
- Запись в регистры и палитру заблокирована во время рендера (`!rend_busy`)
- CPU может писать в FRAMEBUFFER во время рендера (dual-port BRAM, tearing возможен)
- `oled_flush()` должен ждать `!busy` перед записью CONTROL (иначе flush теряется)

### Framebuffer layout

Stride = ближайшая степень двойки >= VP_WIDTH:
- VP_WIDTH ≤ 128 → stride = 128 (stride_shift = 7)
- VP_WIDTH ≤ 256 → stride = 256 (stride_shift = 8)

Адрес пикселя (x, y) в RGB565:
```
halfword_addr = (y << stride_shift) + x
word_addr = halfword_addr >> 1
Чётный x → [15:0], нечётный x → [31:16]
```

Адрес пикселя (x, y) в PAL256:
```
byte_addr = (y << stride_shift) + x
word_addr = byte_addr >> 2
Позиция: byte_addr & 3 → [7:0], [15:8], [23:16], [31:24]
```

---

## Координатное преобразование (аппаратный скейлинг)

Рендерер масштабирует viewport → 96×64 экран.

```
scale_shift = наименьший N где:
    (VP_WIDTH  >> N) <= 96  И
    (VP_HEIGHT >> N) <= 64

disp_w = VP_WIDTH  >> scale_shift
disp_h = VP_HEIGHT >> scale_shift

offset_x = (96 - disp_w) >> 1    // центрирование
offset_y = (64 - disp_h) >> 1
```

При отрисовке пикселя экрана (sx, sy):
```
if (sx < offset_x || sx >= offset_x + disp_w ||
    sy < offset_y || sy >= offset_y + disp_h):
    pixel = 0x0000  // чёрный бордюр
else:
    bx = (sx - offset_x) << scale_shift
    by = (sy - offset_y) << scale_shift
    pixel = BRAM[(by << stride_shift) + bx]
```

---

## Renderer FSM

```
R_IDLE
  │ flush && !initialized
  ▼
R_INIT_POWER ─20ms─► R_INIT_RESET_HI ─1ms─► R_INIT_RESET_LO ─1ms─►
  │                    RES=0                    RES=1
  ▼
R_INIT_CMD ─36 SPI─► R_INIT_VCCEN ─100ms─► R_INIT_DISPLAY_ON
                       VCCEN=1                SPI: 0xAF, initialized=1
  │
  │ flush && initialized
  ▼
R_SET_WINDOW ─6 SPI─► (column 0–95, row 0–63)
  │
  ▼
R_PIXEL_ADDR ◄─────────────────────────┐
  вычислить pixel_addr_r               │
  bram_addr_b = f(pixel_addr_r) (комб.)│
  │                                     │
R_PIXEL_READ                            │
  1 такт BRAM latency                  │
  │                                     │
R_PIXEL_LOOKUP                          │
  извлечь пиксель из bram_dout_b       │
  PAL256: palette lookup                │
  │                                     │
R_PIXEL_SEND_HI ─ SPI hi byte          │
R_PIXEL_SEND_LO ─ SPI lo byte          │
  │                                     │
R_PIXEL_NEXT                            │
  sx++, sy++ → 96×64                    │
  done? ──► R_DONE ──► R_IDLE          │
  else  ────────────────────────────────┘
```

### Критичный момент: BRAM адресация

`bram_addr_b` — **комбинаторный** (не регистровый!) от `pixel_addr_r`:
```systemverilog
assign bram_addr_b = mode_r ? pixel_addr_r[BRAM_ADDR_W+1:2]   // PAL256
                             : pixel_addr_r[BRAM_ADDR_W:1];     // RGB565
```

Это убирает двойную регистровую задержку (pixel_addr_r registered + bram_addr_b registered = 2 такта), оставляя ровно 1 такт BRAM latency.

### Тайминг

| Этап | При 81.25 MHz |
|------|---------------|
| SSD1331 init (первый flush) | ~123 мс |
| Window setup (6 SPI) | ~9 мкс |
| 1 пиксель | ~1.4 мкс |
| Полный кадр 96×64 | ~8.6 мс (~116 FPS) |

SPI: ~5 MHz (делитель 7, SSD1331 max 6.67 MHz).

---

## Режимы цвета

| Режим | CONTROL bit 1 | Пиксель | Палитра |
|-------|---------------|---------|---------|
| RGB565 | 0 | 16 бит прямой цвет | не используется |
| PAL256 | 1 | 8 бит индекс | 256 × 16 бит RGB565 |

### Максимальные viewport (48 KB BRAM)

| Viewport | RGB565 | PAL256 |
|----------|--------|--------|
| 96×64 | 12 KB | 6 KB |
| 128×128 | 32 KB | 16 KB |
| 192×128 | 48 KB (макс) | 24 KB |
| 256×192 | — | 48 KB (макс) |

---

## C API

```c
#include "oled.h"

oled_init();                          // viewport 96×64, RGB565
oled_pixel(x, y, OLED_RED);          // один пиксель
oled_rect(10, 10, 20, 15, OLED_BLUE);// прямоугольник
oled_clear(OLED_BLACK);              // залить всё
oled_print(0, 0, "Hello", OLED_WHITE, OLED_BLACK);
oled_flush();                        // запуск рендера
oled_sync();                         // ждать завершения
```

Палитра:
```c
oled_set_mode(OLED_MODE_PAL256);
oled_set_palette(0, OLED_BLACK);
oled_set_palette(1, OLED_WHITE);
oled_pixel_pal(x, y, 1);            // палитровый индекс
```

Viewport:
```c
oled_set_viewport(192, 128);         // аппаратный 2:1 downscale
```

---

## Пины SSD1331 (PmodOLEDrgb, JA)

| Пин | Направление | Описание |
|-----|-------------|----------|
| oled_cs_n | out | Chip select (active low) |
| oled_mosi | out | SPI data |
| oled_sck | out | SPI clock (~5 MHz) |
| oled_dc | out | 0=command, 1=data |
| oled_res_n | out | Reset (active low) |
| oled_vccen | out | VCC enable |
| oled_pmoden | out | Power module enable |

SPI Mode 0 (CPOL=0, CPHA=0), MSB first.

---

## Файлы

| Файл | Описание |
|------|----------|
| `rtl/peripheral/OLED_FB_DEVICE.sv` | Основной модуль (557 строк) |
| `rtl/peripheral/SPI_MASTER.sv` | SPI Mode 0 (используется внутри) |
| `programs/common/oled.h` | C API заголовок |
| `programs/common/oled.c` | C API реализация |
| `programs/common/font8x10.h` | Шрифт 8×10 (ASCII 32–126) |
