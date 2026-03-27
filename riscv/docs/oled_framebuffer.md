# OLED Framebuffer Device — план реализации

Замена OLED_IO_DEVICE (прямой SPI) на OLED_FB_DEVICE (BRAM framebuffer + аппаратный рендерер).

---

## Что меняем

- `rtl/peripheral/OLED_IO_DEVICE.sv` — **не удаляем**, но убираем с шины PERIPHERAL_BUS
- OLED_FB_DEVICE.sv — новый модуль, занимает слот 01 на шине (0x1001_0000)
- OLED_FB_DEVICE внутри себя содержит SPI_MASTER и логику SSD1331 init (использует их напрямую, не через шину)
- TOP.sv — заменить инстанс OLED_IO_DEVICE на OLED_FB_DEVICE в подключении к PERIPHERAL_BUS
- `test/peripheral/PERIPHERAL_BUS_OLED_TEST.sv` — обновить под новый модуль

---

## Архитектура

```
CPU → PERIPHERAL_BUS → OLED_FB_DEVICE
                            ├── Регистры (CONTROL, STATUS, VP_WIDTH, VP_HEIGHT)
                            ├── Палитра (256 × 16 бит, distributed RAM)
                            ├── BRAM (dual-port, 48 KB, 12 BRAM36)
                            │     Port A: CPU read/write (32-бит, через шину)
                            │     Port B: Renderer read (32-бит, только чтение)
                            └── OLED_RENDERER (FSM → SPI_MASTER → OLED пины)
                                  ├── Скейлинг viewport → 96×64 (сдвиги)
                                  ├── Палитра lookup (PAL256 режим)
                                  └── SPI init + pixel stream
```

---

## Адресное пространство (слот 0x1001_0000, 64 KB)

| Смещение | Регистр | Доступ | Описание |
|----------|---------|--------|----------|
| 0x0000 | CONTROL | W | bit 0: flush (запуск отрисовки) |
|        |         |   | bit 1: mode (0=RGB565, 1=PAL256) |
| 0x0004 | STATUS | R | bit 0: busy (1=flush, запись заблокирована) |
| 0x0008 | VP_WIDTH | W/R | Ширина рабочей области (96–256) |
| 0x000C | VP_HEIGHT | W/R | Высота рабочей области (64–256) |
| 0x0010–0x020F | PALETTE | W/R | 256 записей × 16 бит RGB565 (512 байт) |
| 0x4000–0xFFFF | FRAMEBUFFER | W/R | Пиксели, stride = power-of-2 |

### Framebuffer layout

Stride = ближайшая степень двойки >= VP_WIDTH:
- VP_WIDTH ≤ 128 → stride = 128
- VP_WIDTH ≤ 256 → stride = 256

Адрес пикселя (x, y):
```
// RGB565: 2 байта на пиксель
addr = 0x4000 + (y << (stride_shift + 1)) + (x << 1)

// PAL256: 1 байт на пиксель
addr = 0x4000 + (y << stride_shift) + x
```

### Запись пикселей с CPU

Шина 32-бит. Один `sw` записывает несколько пикселей в BRAM.

**RGB565 (mode=0)** — 2 пикселя в слове, little-endian:

```
sw 0x1234ABCD, addr    →  pixel[0] = 0xABCD, pixel[1] = 0x1234
                           [15:0]              [31:16]

Адрес пикселя (x, y):
  word_addr = 0x4000 + (y << (stride_shift + 1)) + (x & ~1) * 2
  Пиксель с чётным x → биты [15:0], нечётным x → биты [31:16]
```

Пример — записать один пиксель (x=5, y=3, color=0x07E0, stride=128):
```c
// stride_shift = 7, байтовый stride = 256 (128 пикселей × 2 байта)
volatile unsigned int *fb = (volatile unsigned int *)0x10014000;
// word index: (3 << 7) + (5 >> 1) = 384 + 2 = 386
// x=5 нечётный → старшие 16 бит
unsigned int old = fb[386];
fb[386] = (old & 0x0000FFFF) | (0x07E0 << 16);
```

Или записать два пикселя сразу (x=4,5):
```c
fb[386] = (color1) | (color0 << 16);  // pixel[4]=color0, pixel[5]=color1
```

**PAL256 (mode=1)** — 4 пикселя в слове, little-endian:

```
sw 0xAABBCCDD, addr    →  pixel[0] = 0xDD (индекс палитры)
                           pixel[1] = 0xCC
                           pixel[2] = 0xBB
                           pixel[3] = 0xAA
                           [7:0]  [15:8]  [23:16]  [31:24]

Адрес пикселя (x, y):
  word_addr = 0x4000 + (y << (stride_shift - 2)) + (x >> 2)
  Пиксель x%4==0 → [7:0], x%4==1 → [15:8], x%4==2 → [23:16], x%4==3 → [31:24]
```

Пример — залить строку y=0 индексом 5 (stride=128):
```c
volatile unsigned int *fb = (volatile unsigned int *)0x10014000;
unsigned int fill = 0x05050505;  // 4 пикселя с индексом 5
for (int i = 0; i < 128/4; i++)
    fb[i] = fill;
```

**Палитра** — запись одного цвета:
```c
// PALETTE[idx] = RGB565 color
volatile unsigned short *pal = (volatile unsigned short *)0x10010010;
pal[0]   = 0x0000;  // индекс 0 = чёрный
pal[1]   = 0xFFFF;  // индекс 1 = белый
pal[255] = 0xF800;  // индекс 255 = красный
```

### controller_ready (блокировка)

```
controller_ready = !busy
```

Когда busy=1 (flush в процессе), ЛЮБОЕ обращение к OLED_FB_DEVICE (чтение/запись регистров или FB) блокирует CPU pipeline до окончания flush. CPU подвисает в S_DATA_WAIT автоматически.

---

## Режимы цвета

| Режим | Бит в CONTROL | Пиксель | Палитра |
|-------|---------------|---------|---------|
| RGB565 | mode=0 | 16 бит прямой цвет | не используется |
| PAL256 | mode=1 | 8 бит индекс | 256 × 16 бит RGB565 |

### Максимальные размеры viewport (48 KB BRAM)

| Viewport | RGB565 | PAL256 |
|----------|--------|--------|
| 96×64 | 12 KB ✓ | 6 KB ✓ |
| 128×128 | 32 KB ✓ | 16 KB ✓ |
| 192×128 | 48 KB ✓ (макс) | 24 KB ✓ |
| 256×192 | — | 48 KB ✓ (макс) |

---

## Аппаратный скейлинг (без умножений/делений)

Рендерер масштабирует viewport → 96×64 экран.

```
scale_shift = наименьший N где:
    (VP_WIDTH  >> N) <= 96  И
    (VP_HEIGHT >> N) <= 64

// Отображаемый размер на экране
disp_w = VP_WIDTH  >> scale_shift
disp_h = VP_HEIGHT >> scale_shift

// Центрирование
offset_x = (96 - disp_w) >> 1
offset_y = (64 - disp_h) >> 1
```

При отрисовке пикселя экрана (sx, sy):
```
bx = (sx - offset_x) << scale_shift
by = (sy - offset_y) << scale_shift

if (sx < offset_x || sx >= offset_x + disp_w ||
    sy < offset_y || sy >= offset_y + disp_h):
    pixel = 0x0000  // чёрный (бордюр)
else:
    if mode == PAL256:
        addr = (by << stride_shift) + bx
        idx = BRAM_byte[addr]
        pixel = PALETTE[idx]
    else:
        addr = (by << stride_shift) + bx
        pixel = BRAM_halfword[addr]

SPI_send(pixel_hi, pixel_lo)
```

Все вычисления — сдвиги и сложения. Ноль умножений/делений.

---

## OLED_RENDERER FSM

```
S_IDLE          — ждёт flush trigger
      ↓
S_INIT_CMD      — SSD1331: set column 0..95, set row 0..63 (6 SPI команд)
      ↓
S_PIXEL_READ    — вычислить адрес BRAM, прочитать слово
      ↓
S_PIXEL_LOOKUP  — (PAL256) lookup палитры; (RGB565) passthrough
      ↓
S_PIXEL_SEND_HI — SPI отправить старший байт пикселя
      ↓
S_PIXEL_SEND_LO — SPI отправить младший байт пикселя
      ↓
S_PIXEL_NEXT    — sx++; если sx==96 → sy++; если sy==64 → S_DONE
      ↓             иначе → S_PIXEL_READ
S_DONE          — busy=0, вернуться в S_IDLE
```

Общее время flush при 10 MHz SPI:
- 96 × 64 × 2 байта = 12,288 байт
- 12,288 × 8 бит / 10 MHz ≈ **10 мс** на кадр (~100 FPS макс)

---

## Ресурсы FPGA (Arty A7-100T)

| Ресурс | Использование | Из доступных | % |
|--------|--------------|-------------|---|
| BRAM36 | 12 | 135 | 8.9% |
| LUT (палитра) | ~200 | 63,400 | 0.3% |
| LUT (логика рендерера) | ~400 | 63,400 | 0.6% |
| Registers | ~200 | 126,800 | 0.2% |
| **Итого** | | | **~10%** |

---

## Этапы реализации

### Этап 1: OLED_FB_DEVICE.sv
- Регистры CONTROL, STATUS, VP_WIDTH, VP_HEIGHT
- BRAM instantiation (dual-port, 48 KB)
- CPU port: read/write через шину (Port A)
- controller_ready = !busy
- Палитра (distributed RAM, 256×16)

### Этап 2: OLED_RENDERER.sv
- FSM (S_IDLE → S_INIT_CMD → pixel loop → S_DONE)
- SSD1331 init sequence (column/row address set)
- BRAM read (Port B) с адресацией через сдвиги
- Скейлинг + центрирование
- Палитра lookup
- SPI_MASTER интерфейс

### Этап 3: Интеграция
- Удалить OLED_IO_DEVICE.sv
- Удалить OLED_IO_DEVICE_TEST.sv
- Подключить OLED_FB_DEVICE в TOP.sv (SPI пины + PERIPHERAL_BUS)
- Обновить PERIPHERAL_BUS (если нужно — порты те же)

### Этап 4: C API
- Обновить oled.h/oled.c — убрать софтверный framebuffer, писать в MMIO
- `oled_pixel(x,y,c)` → запись в 0x1001_4000+offset
- `oled_flush()` → запись 1 в CONTROL, busy-wait STATUS
- `oled_set_palette(idx, color)` → запись в PALETTE
- `oled_set_viewport(w, h)` → запись VP_WIDTH, VP_HEIGHT
- `oled_set_mode(mode)` → запись CONTROL bit 1

### Этап 5: Тесты
- Unit: OLED_FB_DEVICE_TEST.sv (запись в FB, чтение, flush FSM)
- Unit: OLED_RENDERER_TEST.sv (проверка SPI output, скейлинг)
- Обновить PERIPHERAL_BUS_OLED_TEST.sv
- Интеграция: визуальный тест на железе

### Этап 6: Обновить stage1 bootloader
- Переписать анимацию: вместо прямого SPI → запись в MMIO framebuffer + flush
- OLED init не нужен в stage1 — аппаратный рендерер делает сам при первом flush
- Убрать весь SPI код из stage1.c (oled_cmd, oled_data, spi_wait и т.д.)

---

## Решения

1. **SSD1331 init** — аппаратно в OLED_RENDERER. При первом flush (или по CONTROL.init) рендерер сам выполняет power on, reset pulse, SSD1331 config sequence через встроенный SPI_MASTER. CPU не занимается SPI напрямую.

2. **Stage1 bootloader** — stage1 пишет в framebuffer нового девайса (он доступен на шине как MMIO). Анимация через запись пикселей + flush. Никакого прямого SPI.

3. **Double buffering** — не нужен на первом этапе. Можно добавить позже.
