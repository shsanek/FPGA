# Boot — автозагрузка программы из QSPI flash + SD card

## Обзор

Трёхступенчатая загрузка при включении FPGA:

```
Stage 0 (hardware)  FLASH_LOADER → QSPI flash → DDR (0x07F00000)  | менять = шить битстрим
Stage 1 (software)  SD card FAT32 → DDR (0x00000000)               | менять = шить flash
Stage 2 (software)  исполняется с 0x00000000                       | менять = заменить BOOT.BIN на SD
```

Существующие программы (hello, fib, test_alu...) работают как BOOT.BIN без перелинковки.

---

## Карта памяти DDR (128 МБ)

```
0x00000000  BOOT.BIN (Stage 2) ← Stage 1 грузит с SD карты
0x00010000  BOOT.BIN .data/.bss/stack
   ...
0x07F00000  Stage 1 ← FLASH_LOADER грузит из QSPI flash
0x07F10000  Stage 1 .bss/stack
```

## QSPI flash layout

```
0x000000          Битстрим FPGA (~2.1 МБ для Arty A7-100T)
0xF00000          Header: [4B magic 0xB007C0DE] [4B size] [4B load_addr]
0x30000C          Stage 1 бинарник (~5.3 КБ)
```

---

## FLASH_LOADER — аппаратный модуль (Stage 0)

**Файл:** `riscv/CPU/FLASH_LOADER.sv`

Автономный FSM с собственным SPI_MASTER. Не занимает слот на PERIPHERAL_BUS.
Работает параллельно с DEBUG_CONTROLLER через общий bus mux.

### FSM

```
RESET → WAIT_DDR → CS_ON → SPI_XFER(cmd+addr) → READ_HEADER(12B) → VERIFY
  → LOAD_DATA(побайтно SPI → пословно DDR) → SET_PC(load_addr) → DONE
```

### Header формат (12 байт, little-endian)

| Поле | Размер | Описание |
|------|--------|----------|
| magic | 4B | 0xB007C0DE |
| size | 4B | Размер данных в байтах (кратно 4) |
| load_addr | 4B | Адрес загрузки в DDR |

Если magic не совпадает → DONE без загрузки (CPU стартует с PC=0, DDR пуста).

### Bus mux (3-way приоритет в TOP.sv)

```
flash_active    → flash владеет bus    (только при старте)
pipeline_paused → debug владеет bus    (UART отладка)
иначе           → pipeline владеет bus (нормальная работа)
```

### QSPI flash пины (Arty A7)

| Пин | Сигнал | Описание |
|-----|--------|----------|
| L13 | flash_cs_n | FCS_B, chip select |
| K17 | flash_mosi | DQ0, data to flash |
| K18 | flash_miso | DQ1, data from flash |
| L16 | flash_sck | Clock (не нужен STARTUPE2) |
| L14 | flash_wp_n | DQ2, = 1 (inactive) |
| M14 | flash_hold_n | DQ3, = 1 (inactive) |

Требуется `BITSTREAM.CONFIG.SPI_BUSWIDTH 1` для освобождения FCS_B после конфигурации.

### Параметры

| Параметр | Default | Описание |
|----------|---------|----------|
| FLASH_OFFSET | 24'h300000 | Адрес header в flash |
| SPI_DIVIDER | 7 | ~5 МГц при 81.25 МГц clock |

### Бонус: DDR init wait

FLASH_LOADER автоматически решает проблему ожидания DDR калибровки — CPU стоит в stall пока loader не завершит загрузку (включая ожидание `init_calib_complete`).

---

## Stage 1 — загрузчик SD FAT32

**Файлы:**
- `boot/software/stage1.c` — main: init SD → FAT32 → BOOT.BIN → jump
- `boot/software/sd.c/.h` — SPI SD driver (из test_sd.c, read-only)
- `boot/software/fat32.c/.h` — минимальный FAT32 reader

### Размер

- .text: **~10 КБ** (включая OLED анимацию и шрифт)
- .bss: 544 байт
- Загрузка из flash при 5 МГц: ~16 мс

### Что делает

1. **Boot-анимация** на OLED (PS1-style: чёрный → вспышка → расширение → лого RV32)
2. Проверяет наличие SD карты (card detect)
3. Инициализирует SD (CMD0 → CMD8 → ACMD41 → CMD58, SDHC/SDSC)
4. Читает MBR, находит FAT32 раздел
5. Парсит BPB, вычисляет геометрию FAT
6. Ищет `BOOT    BIN` в корневой директории (8.3 format)
7. Читает файл по цепочке кластеров в DDR (прогресс-бар на OLED)
8. Схлопывание анимации → прыжок на 0x00000000

OLED управляется через OLED_FB_DEVICE (BRAM framebuffer). SSD1331 init выполняется аппаратно при первом flush.

### UART вывод при загрузке

```
=== Stage1 Bootloader ===
[OLED] init OK
[SD]   OK
FAT32 OK
[LOAD] 00001a4c bytes, 000003e8 ms
[JUMP] 0x00000000
```

---

## Сборка

### Stage 1 (для QSPI flash)

```bash
cd riscv/boot/tools

# Собрать бинарник
make stage1 CROSS=riscv64-elf-

# Добавить header для FLASH_LOADER
python3 prepend_header.py stage1.bin stage1_with_header.bin
```

### BOOT.BIN (для SD карты)

Любая программа, скомпилированная со стандартным linker.ld (ORIGIN=0x0):

```bash
# Из существующего теста
make boot BOOT_SRC=../../tests/programs/hello/hello.c CROSS=riscv64-elf-

# Результат: BOOT.BIN → скопировать на SD карту (FAT32)
```

### MCS файл (битстрим + Stage 1)

```tcl
# В Vivado Tcl console:
write_cfgmem -format mcs -interface SPIx1 -size 16 \
  -loadbit "up 0x0 bitstream.bit" \
  -loaddata "up 0xF00000 stage1_with_header.bin" \
  -file boot.mcs
```

Прошить `boot.mcs` через Vivado Hardware Manager → Program Configuration Memory Device.

---

## Workflow обновления

| Что менять | Действия |
|-----------|----------|
| Stage 2 (программа) | Заменить BOOT.BIN на SD карте |
| Stage 1 (загрузчик) | Пересобрать stage1 → write_cfgmem → прошить flash |
| Stage 0 (hardware) | Пересинтезировать → write_cfgmem → прошить flash |

---

## Файлы

```
riscv/boot/
├── BOOT.md                  # Эта документация
├── software/
│   ├── stage1.c             # Main: SD init → FAT32 → load → jump
│   ├── sd.c / sd.h          # SD card SPI driver
│   └── fat32.c / fat32.h    # Minimal FAT32 reader
└── tools/
    ├── Makefile              # Сборка stage1.bin и BOOT.BIN
    ├── stage1.ld             # Linker: ORIGIN=0x07F00000
    └── prepend_header.py     # Добавляет header для FLASH_LOADER

riscv/CPU/
├── FLASH_LOADER.sv           # Hardware boot FSM
└── FLASH_LOADER_TEST.sv      # Unit-тест (ALL TESTS PASSED)
```

## Тестирование

### Unit-тест FLASH_LOADER

```bash
cd riscv/CPU
iverilog -g2012 -o FLASH_LOADER_TEST SPI_MASTER.sv FLASH_LOADER.sv FLASH_LOADER_TEST.sv
vvp FLASH_LOADER_TEST
# → ALL TESTS PASSED
```

Проверяет: header parsing (magic + size + load_addr), DDR write по правильным адресам, set_pc = load_addr, bad magic → abort.
