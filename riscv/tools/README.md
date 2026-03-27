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

Подробное описание протокола — в `riscv/DEBUG.md`.

---

## Firmware: поддержка дампа регистров

Для команды `--regs` в firmware нужен обработчик триггера `0x06` (INPUT).
CPU получает байт через `UART_IO_DEVICE RX_DATA`, проверяет его, и при `0x06`
отправляет дамп всех 32 регистров через UART TX.

Подробности реализации — в исходниках `tests/runtime.c` и `tests/crt0.s`.

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
