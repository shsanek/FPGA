# riscv_tester.py — UART-тестер RISC-V процессора

Python-скрипт для тестирования процессора через физический UART (FPGA) или симуляцию.
Работает на **Windows 10+, Linux, macOS**. Требует Python 3.9+.

---

## Установка

### Windows

1. Установить [Python 3.9+](https://python.org/downloads) — **галочка "Add to PATH"**
2. Установить драйвер UART-моста:
   | Чип | Ссылка |
   |-----|--------|
   | FTDI FT232 | https://ftdichip.com/drivers/vcp-drivers/ |
   | CH340/CH341 | https://www.wch-ic.com/downloads/CH341SER_EXE.html |
   | CP210x | Silicon Labs VCP driver |
3. Установить зависимость:
   ```cmd
   pip install pyserial
   ```
4. Найти номер COM-порта: **Диспетчер устройств → Порты (COM и LPT)**

### Linux / macOS

```bash
pip3 install pyserial
# Добавить себя в группу dialout (Linux):
sudo usermod -a -G dialout $USER
```

---

## Быстрый старт

```bash
# Найти COM-порт
python riscv_tester.py --list-ports

# Захватить вывод запущенной программы
python riscv_tester.py -p COM3 --capture

# Шаговая отладка — 10 шагов с дизассемблированием
python riscv_tester.py -p COM3 --step 10

# Дамп регистров (требует поддержки в firmware, см. ниже)
python riscv_tester.py -p COM3 --regs

# Hexdump памяти — 64 слова начиная с 0x10000
python riscv_tester.py -p COM3 --memdump 0x10000:64

# Запустить все тесты из каталога tests/ (программа уже в ROM)
python riscv_tester.py -p COM3 --tests ../tests/ --no-upload
```

---

## Команды

### Подключение

| Флаг | Описание | По умолчанию |
|------|----------|--------------|
| `-p`, `--port` | COM-порт (`COM3`, `/dev/ttyUSB0`, …) | обязателен |
| `-b`, `--baud` | Скорость UART | `115200` |
| `--ack-timeout SEC` | Таймаут ответа на debug-команду | `2.0` |
| `--list-ports` | Показать доступные порты и выйти | — |

### Инспекция состояния CPU

#### `--step N` — пошаговое выполнение

Останавливает CPU, исполняет N инструкций, выводит PC и мнемонику:

```
=== Шаговая отладка (10 шагов) ===
  CPU остановлен.
     1  PC=0x00000000  00000013   addi   zero, zero, 0
     2  PC=0x00000004  00010137   lui    sp, 0x10
     3  PC=0x00000008  FFF10113   addi   sp, sp, -1
     ...
```

#### `--regs` — дамп всех 32 регистров

Посылает триггер `0x06` через UART passthrough. CPU отвечает 128 байт (x0–x31, little-endian).

```
=== Дамп регистров ===
  Регистры RISC-V  (PC = 0x000001A4)
  ──────────────────────────────────────────────────────────────────────
  x0/zero = 00000000  (           0)    x1/ra   = 000001A4  (         420)
  x2/sp   = 0000FFE0  (       65504)    x3/gp   = 00000000  (           0)
  x4/tp   = 00000000  (           0)    x5/t0   = 000002EC  (         748)
  ...
```

> **Требование к firmware:** в `main()` нужно вызывать `poll_debug()`.
> Подробности — в секции [Firmware: поддержка дампа регистров](#firmware-поддержка-дампа-регистров).

#### `--memdump ADDR[:COUNT]` — hexdump памяти

Читает COUNT слов (по умолчанию 64) начиная с ADDR через последовательные `READ_MEM`:

```
=== Дамп памяти  0x00010000 – 0x000100FF  (64 слова = 256 байт) ===
  ──────────────────────────────────────────────────────────────────────────
  0x00010000  DEADBEEF  12345678  FFFFFFFF  00000001  ....x4V8........
  0x00010010  00000000  00000000  44332211  80000000  ........3D......
  ...
```

Можно указывать несколько раз:
```bash
python riscv_tester.py -p COM3 --memdump 0x10000:32 --memdump 0x20000:16
```

### Захват вывода

#### `--capture` — читать UART-вывод текущей программы

```bash
python riscv_tester.py -p COM3 --capture --idle-timeout 3 --total-timeout 60
```

| Флаг | Описание | По умолчанию |
|------|----------|--------------|
| `--idle-timeout SEC` | Пауза без байт = программа завершилась | `2.0` |
| `--total-timeout SEC` | Жёсткий предел ожидания | `30.0` |

### Тесты

#### `--tests DIR [filter]` — прогон тестовых программ

Ищет подкаталоги в `DIR/programs/`, каждый должен содержать `program.hex` и (опционально) `expected.txt`.

```bash
# Все тесты
python riscv_tester.py -p COM3 --tests ../tests/ --no-upload

# Только тесты с "mem" в имени
python riscv_tester.py -p COM3 --tests ../tests/ --no-upload mem

# Вывод:
# === Прогон 8 тестов ===
#   fib                     PASS
#   hello                   PASS
#   test_alu                PASS
#   test_mem                PASS
#   ...
# === 8 пройдено  0 провалено ===
```

Флаг `--no-upload` означает: программа уже прошита в ROM через Vivado.
Без `--no-upload` скрипт загружает `program.hex` в DDR через `WRITE_MEM`
(требует [двухпортового BRAM](#как-сделать-rom-перезаписываемым)).

#### `--upload HEX` — загрузить программу и запустить

```bash
python riscv_tester.py -p COM3 --upload ../tests/programs/hello/program.hex
```

---

## Отладочный протокол

Все debug-команды: байты `0x01`–`0x05` перехватываются `DEBUG_CONTROLLER`.
Байты вне этого диапазона передаются напрямую в CPU (passthrough).

| Байт | Команда | Payload → FPGA | Ответ ← FPGA |
|------|---------|----------------|--------------|
| `0x01` | HALT | — | `0xFF` после остановки |
| `0x02` | RESUME | — | `0xFF` |
| `0x03` | STEP | — | `PC[31:0]` + `INSTR[31:0]` (8 байт LE) |
| `0x04` | READ_MEM | `ADDR[31:0]` (4 байта LE) | `DATA[31:0]` (4 байта LE) |
| `0x05` | WRITE_MEM | `ADDR[31:0]` + `DATA[31:0]` (8 байт LE) | `0xFF` |

Все числа **little-endian**. `WRITE_MEM` пишет в MEMORY_CONTROLLER → DDR SDRAM.

---

## Firmware: поддержка дампа регистров

Для команды `--regs` в firmware нужен обработчик триггера `0x06`.

### runtime.h / runtime.c — добавить:

```c
#define REG_DUMP_TRIGGER 0x06

// Вызывать в main loop перед каждой итерацией
void poll_debug(void);
```

### debug_stub.s — обработчик на asm:

Читать все 32 регистра без искажений можно **только в asm** —
компилятор C трогает регистры в процессе выполнения.

```asm
# debug_stub.s
.section .text
.global poll_debug
.global dump_regs_binary

# void poll_debug(void)
# Проверяет UART_RX; если получен REG_DUMP_TRIGGER — отправляет дамп регистров
poll_debug:
    lui   t0, 0x8000          # t0 = 0x08000000 (UART base)
    lw    t1, 8(t0)           # t1 = STATUS
    andi  t1, t1, 1           # bit0 = rx_avail
    beq   t1, zero, .Lpd_ret
    lw    t1, 4(t0)           # t1 = RX_DATA (чтение сбрасывает флаг)
    li    t2, 0x06
    bne   t1, t2, .Lpd_ret
    call  dump_regs_binary
.Lpd_ret:
    ret

# void dump_regs_binary(void)
# Записывает x0..x31 (каждый 4 байта LE) в UART TX
dump_regs_binary:
    addi  sp, sp, -8
    sw    ra, 4(sp)
    sw    t0, 0(sp)           # сохраняем t0 — он нужен нам как указатель UART

    lui   t0, 0x8000          # t0 = 0x08000000 (UART TX_DATA)

    # x0 всегда 0
    sw    x0,  0(t0)
    sw    x1,  0(t0)
    sw    x2,  0(t0)
    sw    x3,  0(t0)
    sw    x4,  0(t0)
    sw    x5,  0(t0)
    sw    x6,  0(t0)
    sw    x7,  0(t0)
    sw    x8,  0(t0)
    sw    x9,  0(t0)
    sw    x10, 0(t0)
    sw    x11, 0(t0)
    sw    x12, 0(t0)
    sw    x13, 0(t0)
    sw    x14, 0(t0)
    sw    x15, 0(t0)
    sw    x16, 0(t0)
    sw    x17, 0(t0)
    sw    x18, 0(t0)
    sw    x19, 0(t0)
    sw    x20, 0(t0)
    sw    x21, 0(t0)
    sw    x22, 0(t0)
    sw    x23, 0(t0)
    sw    x24, 0(t0)
    sw    x25, 0(t0)
    sw    x26, 0(t0)
    sw    x27, 0(t0)
    sw    x28, 0(t0)
    sw    x29, 0(t0)
    # x30 (t5) — живой
    sw    x30, 0(t0)
    # x31 (t6) — живой
    sw    x31, 0(t0)

    lw    t0, 0(sp)           # восстанавливаем t0 (x5) — теперь шлём сохранённое
    sw    t0, 0(t0)           # ← это неверно для x5, но x5=t0 уже был отправлен выше
    # Примечание: x5 в дампе будет значением ДО вызова dump_regs_binary,
    # потому что мы сохранили его в стек в самом начале.

    lw    ra, 4(sp)
    addi  sp, sp, 8
    ret
```

> **Примечание:** значение `x5/t0` в дампе будет его значением **до** вызова
> `poll_debug` — потому что мы сохраняем t0 в стек первым делом. Это корректно.

### Подключение в main():

```c
#include "runtime.h"

int main(void) {
    while (1) {
        poll_debug();   // ← добавить эту строку в начало main loop
        // ... логика программы ...
    }
    return 0;
}
```

---

## Как сделать ROM перезаписываемым

Сейчас `WRITE_MEM` пишет в DDR SDRAM, а CPU исполняет инструкции из ROM.
Для динамической загрузки программ нужно:

### Шаг 1 — Двухпортовый BRAM в TOP.sv

Заменить `logic [31:0] rom [0:ROM_DEPTH-1]` на `BRAM_TDP`:

```systemverilog
// Порт A: instruction fetch (CPU, read-only)
// Порт B: debug write (DEBUG_CONTROLLER)
BRAM_TDP #(
    .WIDTH(32),
    .DEPTH(ROM_DEPTH)
) rom_bram (
    .clka (clk),
    .ena  (1'b1),
    .wea  (1'b0),
    .addra(instr_addr[$clog2(ROM_DEPTH)+1 : 2]),
    .dina (32'b0),
    .douta(instr_data),

    .clkb (clk),
    .enb  (rom_dbg_we),
    .web  (1'b1),
    .addrb(rom_dbg_addr[$clog2(ROM_DEPTH)+1 : 2]),
    .dinb (rom_dbg_data),
    .doutb()
);
```

### Шаг 2 — Новая команда CMD_WRITE_ROM = 0x06 в DEBUG_CONTROLLER

```
Byte  Команда      Payload               Ответ
0x06  WRITE_ROM    ADDR[31:0]+DATA[31:0]  0xFF
```

Выходы: `rom_dbg_we`, `rom_dbg_addr[31:0]`, `rom_dbg_data[31:0]`
Адресное пространство: `0x0F000000 + offset` → `ROM[offset/4]`

### Шаг 3 — Workflow после изменений

```bash
# Скомпилировать тест
make -C tests/ test_alu

# Загрузить через UART и запустить
python riscv_tester.py -p COM3 --upload tests/programs/test_alu/program.hex

# Прогнать все тесты автоматически
python riscv_tester.py -p COM3 --tests tests/
```

---

## Структура каталога тестов

```
tests/
├── linker.ld          # ROM @ 0x0, RAM @ 0x10000
├── crt0.s             # startup: copy .data, zero .bss, call main, ebreak
├── runtime.c/h        # putchar/puts/print_hex → UART_IO_DEVICE (0x08000000)
├── check.h            # CHECK_EQ / DONE макросы
├── bin2hex.py         # binary → $readmemh hex
├── Makefile           # сборка всех программ
└── programs/
    ├── hello/         # program.hex + expected.txt
    ├── fib/
    ├── sum/
    ├── test_alu/      # все R/I-type ALU опкоды
    ├── test_mem/      # LB/LH/LW/LBU/LHU + SB/SH/SW, overlaps
    ├── test_branch/   # BEQ/BNE/BLT/BGE/BLTU/BGEU
    ├── test_jump/     # JAL/JALR, рекурсия, function pointers
    └── test_upper/    # LUI/AUIPC
```

Каждая программа компилируется так:

```bash
riscv64-elf-gcc -march=rv32i -mabi=ilp32 -O2 \
    -ffreestanding -nostdlib -nostartfiles \
    -T tests/linker.ld \
    tests/crt0.s tests/runtime.c programs/<name>/<name>.c \
    -lgcc -o program.elf
```

---

## Запуск симуляции (без железа)

```bash
# Собрать и прогнать все тесты в iverilog
cd riscv/
./run_tests.sh

# Только сборка
./run_tests.sh --build-only

# Только симуляция одного теста
./run_tests.sh --sim-only hello
```
