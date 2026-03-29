# CLAUDE.md

## Project Overview

FPGA hardware design project implementing two subsystems in SystemVerilog:

1. **`first/`** — Brainfuck interpreter in hardware
2. **`riscv/`** — RISC-V processor components (ALU, register file, UART I/O, memory)

**License:** MIT (Copyright 2025 Alexandr Shipin)

---

## Technology Stack

- **Language:** SystemVerilog (IEEE 1800-2012)
- **Simulator:** `iverilog` + `vvp` (`C:\iverilog\bin\iverilog.exe`, version s20150603 — ограниченная поддержка SV)
- **Synthesis:** Vivado 2025.2 (`C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat`)
- **RISC-V GCC:** xpack riscv-none-elf-gcc 14.2.0 (`C:\riscv-gcc\xpack-riscv-none-elf-gcc-14.2.0-3\bin\`)
- **Waveforms:** VCD files (excluded from git)
- **Board:** Arty A7-100T, UART на COM4 (115200 baud)

---

## Build & Test

RTL modules are in `riscv/rtl/`, tests in `riscv/test/`. Each test compiles with iverilog:

```bash
# Example: compile and run a test
cd riscv/
iverilog -g2012 -o out rtl/peripheral/SPI_MASTER.sv test/peripheral/SPI_MASTER_TEST.sv
vvp out

# C programs
cd riscv/programs/ && make

# Boot loader
cd riscv/boot/tools/ && make stage1
```

---

## Project Structure

```
FPGA/
├── first/                              # Brainfuck interpreter
│   ├── first.sv                        # Main implementation
│   └── first_test.sv                   # Test bench
│
├── riscv/
│   ├── rtl/                            # SystemVerilog modules
│   │   ├── TOP.sv                      # System top (CPU + peripherals + DDR)
│   │   ├── FPGA_TOP.sv                 # FPGA wrapper (clocking, MIG, pins)
│   │   ├── BASE_TYPE.sv                # Shared type definitions
│   │   ├── core/                       # CPU ядро
│   │   │   ├── CPU_SINGLE_CYCLE.sv     # Single-cycle RV32I core
│   │   │   ├── CPU_PIPELINE_ADAPTER.sv # Instruction fetch / data access FSM
│   │   │   ├── CPU_ALU.sv              # ALU wrapper
│   │   │   ├── OP_0110011.sv           # R-type ALU operations
│   │   │   ├── OP_0010011.sv           # I-type ALU operations
│   │   │   ├── REGISTER_32_BLOCK_32.sv # 32×32-bit register file
│   │   │   ├── IMMEDIATE_GENERATOR.sv  # Immediate decoder
│   │   │   ├── BRANCH_UNIT.sv          # Branch comparator
│   │   │   ├── LOAD_UNIT.sv            # Load alignment + sign extension
│   │   │   └── STORE_UNIT.sv           # Store byte mask
│   │   ├── memory/                     # Cache + DDR
│   │   │   ├── MEMORY_CONTROLLER.sv    # Cache controller (D-cache + stream + I-cache)
│   │   │   ├── CHUNK_STORAGE.sv        # Single cache line
│   │   │   ├── CHUNK_STORAGE_4_POOL.sv # 4-entry D-cache pool (LRU)
│   │   │   ├── I_CACHE.sv             # Direct-mapped I-cache (256×16B = 4KB, read-only)
│   │   │   ├── RAM_CONTROLLER.sv       # MIG DDR controller
│   │   │   ├── MIG_MODEL.sv            # Simulation-only MIG mock
│   │   │   ├── SCRATCHPAD.sv           # 128 KB BRAM + Hardware Blitter
│   │   │   └── STREAM_CACHE.sv         # 1-entry read-only DDR bypass cache
│   │   ├── peripheral/                 # Периферия + шина
│   │   │   ├── PERIPHERAL_BUS.sv       # Address decoder
│   │   │   ├── UART_IO_DEVICE.sv       # Memory-mapped UART
│   │   │   ├── OLED_IO_DEVICE.sv       # PmodOLEDrgb raw SPI (legacy)
│   │   │   ├── OLED_FB_DEVICE.sv      # PmodOLEDrgb BRAM framebuffer + SPI renderer
│   │   │   ├── SD_IO_DEVICE.sv         # PmodMicroSD (SPI)
│   │   │   ├── SPI_MASTER.sv           # Full-duplex SPI
│   │   │   └── FLASH_LOADER.sv         # QSPI flash boot loader
│   │   ├── uart/                       # Физический UART стек
│   │   │   ├── SIMPLE_UART_RX.sv       # UART receiver
│   │   │   ├── I_O_OUTPUT_CONTROLLER.sv# UART transmitter
│   │   │   ├── I_O_TIMER_GENERATOR.sv  # Baud rate timer
│   │   │   ├── UART_FIFO.sv            # Sync FIFO
│   │   │   └── VALUE_STORAGE.sv        # Button/LED buffer
│   │   └── debug/
│   │       └── DEBUG_CONTROLLER.sv     # UART debug protocol
│   │
│   ├── test/                           # Все тестбенчи
│   │   ├── core/                       # CPU, ALU, register tests
│   │   ├── memory/                     # Cache, RAM controller tests
│   │   ├── peripheral/                 # Bus, SPI, OLED, SD, flash tests
│   │   ├── uart/                       # UART I/O tests
│   │   ├── debug/                      # Debug controller tests
│   │   └── integration/                # TOP_TEST, PROGRAM_TEST
│   │
│   ├── programs/                       # C тестовые программы
│   │   ├── common/                     # crt0.s, runtime.c/h, linker.ld, check.h
│   │   ├── hello/, fib/, sum/          # Базовые тесты
│   │   ├── test_alu/branch/jump/mem/upper/  # ISA unit тесты (симуляция)
│   │   ├── test_muldiv/               # Софтверное MUL/DIV (rv32i)
│   │   ├── test_muldiv_hw/            # Аппаратное MUL/DIV (rv32im M-extension)
│   │   ├── test_hw_full/              # Полный HW тест: ALU+MUL/DIV+MEM+BRANCH+JUMP+FIB
│   │   ├── test_boot_demo/            # Демо: бегущий текст на OLED
│   │   ├── test_oled/, test_sd/       # Программы для железа (не симуляция)
│   │   ├── test_blitter/             # Hardware blitter тесты (T1-T11)
│   │   ├── boot_tests/               # Объединённый BOOT.BIN (10 тестов)
│   │   └── DemoDoom/                 # Порт DOOM на RISC-V (320×200 → OLED 96×64)
│   │
│   ├── boot/                           # Загрузчик (QSPI flash → SD card)
│   │   ├── software/                   # Stage 1: sd.c, fat32.c, stage1.c
│   │   └── tools/                      # Makefile, linker, prepend_header.py
│   │
│   ├── tools/                          # UART тестер, скрипты
│   │   └── riscv_tester.py
│   │
│   └── docs/                           # Документация
│       ├── boot.md, debug.md, uart.md
│       ├── mig_setup.md, ram_controller.md
│       ├── blitter.md                 # Hardware blitter + бенчмарки
│       ├── benchmarks.md             # Сравнительные таблицы DOOM (S/B/B+S/B+I)
│       ├── tools.md, todo.md
│
└── vivado/                             # Vivado проект, TCL, XDC
```

---

## Key Components

### `riscv/BASE_TYPE.sv`
Defines shared types: `R_TYPE` instruction fields, `R_TYPE_ALU32_INPUT`, `PROCESSOR_STATE` enum (`READ_COMMAND`, `READ_REGISTER`, `RUN_COMMAND`, `WATING_MEMORY`, `SAVE_IN_REGISTER`, `ERROR`), and `BUS_MEM_TYPE` enum for memory bus routing (`BUS_BASE_MEM=00`, `BUS_STREAM=01`, `BUS_CODE_CACHE_CORE1=10`).

### `riscv/ALU/OP_0110011/OP_0110011.sv`
Implements all 8 RISC-V R-type operations. Dispatch is based on `funct3`; `funct7` distinguishes SUB from ADD and SRA from SRL.

### `riscv/Register/REGISTER_32_BLOCK_32.sv`
32×32-bit register file. Register 0 hardwired to 0. Asynchronous read (rs1, rs2), synchronous write (rd with `write_trigger`).

### `riscv/I_O/` (UART)
- **TIMER_GENERATOR** — generates periodic pulses for bit timing
- **INPUT_CONTROLLER** — serial UART receiver with debounce/accumulator
- **OUTPUT_CONTROLLER** — parallel-to-serial UART transmitter
- **VALUE_STORAGE** — 4-button / 4-LED state machine buffer

### `riscv/MEMORY/` (Memory subsystem)

Cache hierarchy between the processor and DDR RAM:

```
MEMORY_CONTROLLER (bus_type[1:0] selects cache path)
├── CHUNK_STORAGE_4_POOL   # D-cache: 4-entry write-back (128-bit chunks) ← bus_type=00
│   └── CHUNK_STORAGE ×4  # Individual cache line with mask-based writes
├── STREAM_CACHE           # 1-entry read-only bypass cache              ← bus_type=01
├── I_CACHE                # I-cache: 256-entry direct-mapped (4 KB)     ← bus_type=10
└── RAM_CONTROLLER         # MIG DDR controller with dual-clock sync (clk / mig_ui_clk)
```

**I_CACHE** (instruction cache):
- Direct-mapped, 256 lines × 16 bytes = 4 KB, read-only
- Address: `[tag 16b | index 8b | offset 4b]` (28-bit)
- Combinational hit check (distributed RAM for tags + data)
- CPU_PIPELINE_ADAPTER prefixes IF address with `2'b11` → routes through I-cache
- Eliminates instruction/data cache thrashing in DOOM BSP traversal

**MEMORY_CONTROLLER states:** `NORMAL` → `WATING` → `SAVE_DATA` → `WRITE_DATA` → `NORMAL`
- On cache miss: optionally evicts dirty line to RAM, then fetches new chunk
- Write path: buffers address/mask/data internally, applies after chunk load

**RAM_CONTROLLER:**
- Two-clock-domain design: `clk` (processor) and `mig_ui_clk` (MIG DDR)
- Synchronisation via `SYNC_CONTROLLER_STATE` handshake (4-state protocol)
- States: `INIT` → `WATING` → `READ` / `WRITE`
- `skip_write` flag handles simultaneous read+write (write first, then read)
- `mig_app_wdf_wren` asserted simultaneously with write command (MIG7 protocol)
- `read_value_ready` pulses 1 cycle when clk domain re-enters ACTIVE after a read
- `internal_error` auto-clears each ACTIVE cycle (controller recovers after error)

**MIG_MODEL** (`RAM_CONTROLLER/MIG_MODEL.sv`):
- Simulation-only MIG7 mock with 16-entry × 128-bit internal memory (indexed by `addr[7:4]`)
- Stores writes when `wdf_wren = 1`, returns reads with 1-cycle latency
- `mig_app_rdy` and `mig_app_wdf_rdy` always `1` (no back-pressure)

### Peripheral Bus — адресная карта (30-bit, addr[29:28] = bus type)

```
addr[29:28]=00: DDR D-cache (MEMORY_CONTROLLER, bus_type=00)
addr[29:28]=01: I/O устройства + SCRATCHPAD
addr[29:28]=10: DDR stream  (MEMORY_CONTROLLER, bus_type=01)
addr[29:28]=11: DDR I-cache (MEMORY_CONTROLLER, bus_type=10)

0x0000_0000 – 0x0FFF_FFFF  →  MEMORY_CONTROLLER (DDR3 256 MB, D-cache)
0x1000_0000 – 0x1000_FFFF  →  UART_IO_DEVICE
  0x1000_0000 : TX_DATA   (W/R)
  0x1000_0004 : RX_DATA   (R)
  0x1000_0008 : STATUS    (R) {tx_ready, rx_avail}
0x1001_0000 – 0x1001_FFFF  →  OLED_FB_DEVICE (PmodOLEDrgb SSD1331, JA)
  0x1001_0000 : CONTROL   (W)   — bit0: flush, bit1: mode (0=RGB565, 1=PAL256)
  0x1001_0004 : STATUS    (R)   — bit0: busy
  0x1001_0008 : VP_WIDTH  (W/R) — ширина viewport (96–256)
  0x1001_000C : VP_HEIGHT (W/R) — высота viewport (64–256)
  0x1001_0010 : PALETTE   (W/R) — 256×16 бит RGB565 (halfword, 512 байт)
  0x1001_4000 : FRAMEBUF  (W/R) — пиксели, stride=power-of-2
0x1002_0000 – 0x1002_FFFF  →  SD_IO_DEVICE (PmodMicroSD, JC)
  0x1002_0000 : DATA      (W/R) — SPI full-duplex TX/RX
  0x1002_0004 : CONTROL   (W/R) — {CS}
  0x1002_0008 : STATUS    (R)   — {card_detect, spi_busy}
  0x1002_000C : DIVIDER   (W/R) — SPI clock divider (init=101/~400kHz, fast=3/~10MHz)
0x1003_0000 – 0x1003_FFFF  →  TIMER_DEVICE (счётчик тактов и времени)
  0x1003_0000 : CYCLE_LO  (R)   — нижние 32 бита 64-bit счётчика тактов
  0x1003_0004 : CYCLE_HI  (R)   — верхние 32 бита (snapshot при чтении CYCLE_LO)
  0x1003_0008 : TIME_MS   (R)   — миллисекунды с момента reset (32-бит, ~49 дней)
  0x1003_000C : TIME_US   (R)   — микросекунды с момента reset (32-бит, ~71 мин)
0x1004_0000 – 0x1005_FFFF  →  SCRATCHPAD (BRAM 128 KB, 1-тактовый доступ)
0x1006_0000 – 0x1006_003F  →  BLITTER MMIO (внутри SCRATCHPAD)
  0x1006_0000 : CMD         (W)   — 1=column, 2=span
  0x1006_0004 : STATUS      (R)   — bit0: busy
  0x1006_0008 : SRC_ADDR    (W)   — адрес текстуры (30-bit bus addr)
  0x1006_0024 : CMAP_OFFSET (W)   — адрес colormap (полный bus addr)
  (см. docs/blitter.md для полного списка регистров)
```

Декодирование:
- `addr[29:28]=00` → DDR D-cache (MEMORY_CONTROLLER, `bus_type=00`)
- `addr[29:28]=01, addr[18]=0` → I/O, `addr[17:16]` → устройство (00=UART, 01=OLED, 10=SD, 11=TIMER)
- `addr[29:28]=01, addr[18]=1` → SCRATCHPAD (128 KB BRAM)
- `addr[29:28]=10` → DDR stream (MEMORY_CONTROLLER, `bus_type=01`)
- `addr[29:28]=11` → DDR I-cache (MEMORY_CONTROLLER, `bus_type=10`)

### `riscv/CPU/SPI_MASTER.sv`
Full-duplex SPI Mode 0 (CPOL=0, CPHA=0), MSB first. Настраиваемый делитель тактовой.
MOSI выход + MISO вход, `rx_data` содержит принятый байт после `done=1`.
Используется как OLED_IO_DEVICE, так и SD_IO_DEVICE.

### PMOD подключения

| PMOD | Устройство | Пины |
|------|-----------|------|
| JA | PmodOLEDrgb (SSD1331) | CS, MOSI, SCK, D/C, RES, VCCEN, PMODEN |
| JC | PmodMicroSD | CS, MOSI, MISO, SCK, Card Detect |

### Hardware Blitter (`riscv/rtl/memory/SCRATCHPAD.sv`)
Аппаратный ускоритель отрисовки текстур для DOOM, встроенный в SCRATCHPAD как bus master.
CMD=1 (column/стены) и CMD=2 (span/полы). CPU stall пока блиттер активен.
Даёт +68% FPS (4.4 → 7.4) на E1M1. Подробнее: `docs/blitter.md`.

### `first/first.sv`
Brainfuck interpreter state machine. Supports `+ - [ ] > <`. Uses a stack counter for nested loops.

---

## Testing Pattern

Simple modules use inline assertions:

```systemverilog
module XXX_TEST();
  XXX dut(...);
  initial forever #5 clk = ~clk;
  initial begin
    $dumpfile("XXX.vcd");
    $dumpvars(0, XXX_TEST);
    // stimulus + assertions
    assert(condition) else error++;
    $finish;
  end
endmodule
```

Complex modules (RAM_CONTROLLER) use tasks + a separate simulation model:

```systemverilog
// Tasks: do_write(addr, data), do_read(addr), wait_done
// wait_done: polls controller_ready with timeout, adds 1 extra cycle for NBA settle
// Simulation model instantiated alongside DUT and wired via shared buses
```

**RAM_CONTROLLER test coverage** (`RAM_CONTROLLER/RAM_CONTROLLER_TEST.sv`):

| Test | Scenario |
|------|----------|
| T1 | Basic write — verifies `wdf_wren` data reaches MIG |
| T2 | Basic read — read back data written in T1 |
| T3 | Multiple addresses — write/read 3 independent addresses |
| T4 | Simultaneous write+read — exercises `skip_write` path |

---

## Conventions

- Module names match file names (e.g., `OP_0110011` in `OP_0110011.sv`)
- Test benches are named `<MODULE>_TEST.sv`
- Clock period: `#5` half-period → 10 time-unit cycle (100 MHz equivalent)
- VCD files are gitignored; generate them locally via simulation
- UART default: 100 MHz clock, 115200 baud → ~868 cycles per bit

---

## TODO

- **DDR init wait:** После прошивки FPGA нужно ждать ~5 секунд пока MIG завершит калибровку DDR (`init_calib_complete`). Без этого bus-операции (READ_MEM, WRITE_MEM, STEP) зависают. Нужно добавить hardware-механизм: CPU/pipeline должен стоять в stall пока `init_calib_complete=0`, а не полагаться на таймаут в тестере.
