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
│   │   ├── TOP_V2.sv                   # System top (128-bit bus, I_CACHE + D_CACHE)
│   │   ├── FPGA_TOP.sv                 # FPGA wrapper (clocking, MIG, pins)
│   │   ├── BASE_TYPE.sv                # Shared type definitions
│   │   ├── core/                       # CPU ядро
│   │   │   ├── CPU_SINGLE_CYCLE.sv     # Single-cycle RV32I core
│   │   │   ├── CPU_IF_ADAPTER.sv       # Instruction fetch → bus read pulses
│   │   │   ├── CPU_DATA_ADAPTER_V2.sv  # Data access (load/store) → bus
│   │   │   ├── CPU_ALU.sv              # ALU wrapper
│   │   │   ├── OP_0110011.sv           # R-type ALU operations
│   │   │   ├── OP_0010011.sv           # I-type ALU operations
│   │   │   ├── REGISTER_32_BLOCK_32.sv # 32×32-bit register file
│   │   │   ├── IMMEDIATE_GENERATOR.sv  # Immediate decoder
│   │   │   ├── BRANCH_UNIT.sv          # Branch comparator
│   │   │   ├── LOAD_UNIT.sv            # Load alignment + sign extension
│   │   │   └── STORE_UNIT.sv           # Store byte mask
│   │   ├── memory/                     # Cache + DDR
│   │   │   ├── MEMORY_CONTROLLER_V2.sv # Unified cache (D/I, WAYS=1/2, READ_ONLY)
│   │   │   ├── BUS_ARBITER.sv          # 2-port priority arbiter (MEM > I_CACHE)
│   │   │   ├── RAM_CONTROLLER.sv       # MIG DDR controller
│   │   │   ├── MIG_MODEL.sv            # Simulation-only MIG mock
│   │   │   └── SCRATCHPAD.sv           # 128 KB BRAM + Hardware Blitter
│   │   ├── peripheral/                 # Периферия + шина
│   │   │   ├── PERIPHERAL_BUS_V2.sv    # 128-bit address decoder
│   │   │   ├── BUS_128_TO_32.sv        # Bus bridge: 128-bit → 32-bit device
│   │   │   ├── BUS_32_TO_128.sv        # Bus bridge: 32-bit CPU → 128-bit bus
│   │   │   ├── UART_IO_DEVICE.sv       # Memory-mapped UART
│   │   │   ├── OLED_FB_DEVICE.sv       # PmodOLEDrgb BRAM framebuffer + SPI renderer
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

### Memory subsystem (128-bit bus)

```
CPU IF → CPU_IF_ADAPTER → BUS_32_TO_128 → I_CACHE (MCV2, RO=1) ──miss──→ BUS_ARBITER p1
CPU MEM → CPU_DATA_ADAPTER_V2 → mux → BUS_32_TO_128 ──────────────────→ BUS_ARBITER p0
                                                                              ↓
                                                                        PERIPHERAL_BUS_V2
                                                                        ├── MEMORY_CONTROLLER_V2 (D$+DDR)
                                                                        ├── UART, OLED, SD, TIMER (via BUS_128_TO_32)
                                                                        └── SCRATCHPAD (via BUS_128_TO_32)
```

**MEMORY_CONTROLLER_V2** (unified cache):
- Parameters: `DEPTH` (lines), `WAYS` (1=direct-mapped, 2=2-way LRU), `READ_ONLY` (0=D$, 1=I$)
- 128-bit standard bus interface (upstream slave + downstream master to DDR)
- 6-state FSM: WAIT_REQUEST → READ_CACHE → WRITE_CACHE → MISS_READ_REQ → MISS_READ_WAIT → MISS_SAVE
- Output buffer (1-entry line buffer for sequential access fast path)
- Stream: `bus_address[29]=1` → bypass cache (don't save to D_CACHE)
- Fire-and-forget dirty eviction in MISS_SAVE (NBA semantics)
- I_CACHE instance: MCV2 with READ_ONLY=1, miss → BUS_ARBITER → shared bus → D_CACHE → DDR

**BUS_ARBITER:**
- 2-port priority arbiter (port0=MEM data > port1=I_CACHE miss)
- 5 explicit states: IDLE, WAIT_P0, WAIT_P1, WAIT_P0_QUEUE_P1, QUEUE_P0_WAIT_P1
- Per-port latched read_data registers
- Handles simultaneous sends without data loss

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

### Peripheral Bus V2 — адресная карта (32-bit, 128-bit data bus)

```
bit30=0 (0x0000_0000 – 0x3FFF_FFFF) → MEMORY_CONTROLLER_V2 (D-cache + DDR)
  bit29=0: normal D-cache path
  bit29=1: stream (bypass D-cache, don't save)

bit30=1 (0x4000_0000+) → I/O devices (decoded by addr[19:16]):

0x4000_0000 – 0x4000_FFFF  →  UART_IO_DEVICE
  0x4000_0000 : TX_DATA   (W/R)
  0x4000_0004 : RX_DATA   (R)
  0x4000_0008 : STATUS    (R) {tx_ready, rx_avail}
0x4001_0000 – 0x4001_FFFF  →  OLED_FB_DEVICE (PmodOLEDrgb SSD1331, JA)
  0x4001_0000 : CONTROL   (W)   — bit0: flush, bit1: mode (0=RGB565, 1=PAL256)
  0x4001_0004 : STATUS    (R)   — bit0: busy
  0x4001_0008 : VP_WIDTH  (W/R)
  0x4001_000C : VP_HEIGHT (W/R)
  0x4001_0010 : PALETTE   (W/R) — 256×16 бит RGB565
  0x4001_4000 : FRAMEBUF  (W/R)
0x4002_0000 – 0x4002_FFFF  →  SD_IO_DEVICE (PmodMicroSD, JC)
  0x4002_0000 : DATA      (W/R)
  0x4002_0004 : CONTROL   (W/R) — {CS}
  0x4002_0008 : STATUS    (R)   — {card_detect, spi_busy}
  0x4002_000C : DIVIDER   (W/R)
0x4003_0000 – 0x4003_FFFF  →  TIMER_DEVICE
  0x4003_0000 : CYCLE_LO  (R)
  0x4003_0004 : CYCLE_HI  (R)
  0x4003_0008 : TIME_MS   (R)
  0x4003_000C : TIME_US   (R)
0x4004_0000 – 0x4005_FFFF  →  SCRATCHPAD (BRAM 128 KB)
0x4006_0000 – 0x4006_003F  →  BLITTER MMIO (внутри SCRATCHPAD)
  (см. docs/blitter.md для полного списка регистров)
```

Декодирование (PERIPHERAL_BUS_V2):
- `addr[30]=0` → MEMORY_CONTROLLER_V2 (DDR, addr[29]=stream flag)
- `addr[30]=1, addr[19:16]=0` → UART (via BUS_128_TO_32)
- `addr[30]=1, addr[19:16]=1` → OLED (via BUS_128_TO_32)
- `addr[30]=1, addr[19:16]=2` → SD (via BUS_128_TO_32)
- `addr[30]=1, addr[19:16]=3` → TIMER (via BUS_128_TO_32)
- `addr[30]=1, addr[19:16]>=4` → SCRATCHPAD (via BUS_128_TO_32)

### `riscv/rtl/peripheral/SPI_MASTER.sv`
Full-duplex SPI Mode 0 (CPOL=0, CPHA=0), MSB first. Настраиваемый делитель тактовой.
MOSI выход + MISO вход, `rx_data` содержит принятый байт после `done=1`.
Используется OLED_FB_DEVICE, SD_IO_DEVICE и FLASH_LOADER.

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
