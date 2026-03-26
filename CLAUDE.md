# CLAUDE.md

## Project Overview

FPGA hardware design project implementing two subsystems in SystemVerilog:

1. **`first/`** — Brainfuck interpreter in hardware
2. **`riscv/`** — RISC-V processor components (ALU, register file, UART I/O, memory)

**License:** MIT (Copyright 2025 Alexandr Shipin)

---

## Technology Stack

- **Language:** SystemVerilog (IEEE 1800-2012)
- **Simulator:** `iverilog` + `vvp` → `/c/iverilog/bin/iverilog`, `/c/iverilog/bin/vvp`
- **Synthesis:** Vivado 2025.2 → `/c/AMDDesignTools/2025.2/Vivado/bin/vivado.bat`
- **RISC-V GCC:** xpack riscv-none-elf-gcc 14.2.0 → `/c/riscv-gcc/xpack-riscv-none-elf-gcc-14.2.0-3/bin/riscv-none-elf-gcc`
- **Waveforms:** VCD files (excluded from git)
- **Board:** Arty A7-100T, UART на COM4 (115200 baud)

---

## Build & Test

Each component has its own `make` or `script` file:

```bash
# Brainfuck interpreter
cd first/ && make

# RISC-V Register file
cd riscv/Register/ && make

# RISC-V ALU
cd riscv/ALU/OP_0110011/ && ./script

# I/O controllers
cd riscv/I_O/INPUT_CONTROLLER/ && ./script
cd riscv/I_O/OUTPUT_CONTROLLER/ && ./script
cd riscv/I_O/VALUE_STORAGE/ && ./script

# Memory subsystem
cd riscv/MEMORY/ && ./script                          # MEMORY_CONTROLLER
cd riscv/MEMORY/CHUNK_STORAGE/ && ./script
cd riscv/MEMORY/CHUNK_STORAGE_4_POOL/ && ./script
cd riscv/MEMORY/RAM_CONTROLLER/ && ./script
```

**Build flow:**
```bash
iverilog -g2012 -o [output] [source.sv] [test.sv]
vvp [output]
```

---

## Project Structure

```
FPGA/
├── first/                              # Brainfuck interpreter
│   ├── first.sv                        # Main implementation
│   └── first_test.sv                   # Test bench
│
└── riscv/                              # RISC-V processor
    ├── BASE_TYPE.sv                    # Shared type definitions
    ├── TOP.sv                          # System top (CPU + peripherals + DDR)
    ├── FPGA_TOP.sv                     # FPGA wrapper (clocking, MIG IP, pin assignments)
    ├── ALU/OP_0110011/                 # R-type ALU (ADD, SUB, SLL, SLT, XOR, OR, AND, SR*)
    ├── Register/                       # 32×32-bit register file
    ├── CPU/
    │   ├── CPU_SINGLE_CYCLE.sv         # Single-cycle RV32I core
    │   ├── CPU_PIPELINE_ADAPTER.sv     # Instruction fetch / data access FSM
    │   ├── CPU_ALU.sv                  # ALU wrapper
    │   ├── DEBUG_CONTROLLER.sv         # UART debug protocol (HALT/STEP/MEM)
    │   ├── PERIPHERAL_BUS.sv           # Address decoder (MC / UART / OLED / SD)
    │   ├── UART_IO_DEVICE.sv           # Memory-mapped UART TX/RX
    │   ├── SPI_MASTER.sv               # Full-duplex SPI (MOSI+MISO), configurable clock
    │   ├── OLED_IO_DEVICE.sv           # PmodOLEDrgb (SSD1331) controller
    │   └── SD_IO_DEVICE.sv             # PmodMicroSD (SPI mode) controller
    ├── I_O/
    │   ├── I_O_TIMER_GENERATOR.sv      # UART baud timer
    │   ├── INPUT_CONTROLLER/           # UART receiver
    │   ├── OUTPUT_CONTROLLER/          # UART transmitter
    │   └── VALUE_STORAGE/              # Button/LED buffer
    ├── MEMORY/
    │   ├── MEMORY_CONTROLLER.sv        # Cache controller (4-pool, write-back)
    │   ├── CHUNK_STORAGE/              # Single cache line storage
    │   ├── CHUNK_STORAGE_4_POOL/       # 4-entry cache pool (LRU eviction)
    │   └── RAM_CONTROLLER/             # MIG DDR controller + MIG_MODEL (sim)
    ├── tools/
    │   └── riscv_tester.py             # UART debug tester (upload/run/step/memdump)
    └── tests/
        ├── crt0.s, runtime.c, linker.ld, check.h  # Bare-metal runtime
        └── programs/                   # Test programs (C → hex)
            ├── hello/                  # UART hello world
            ├── fib/, sum/              # Algorithms
            ├── test_alu/branch/jump/mem/upper/  # CPU ISA tests
            ├── test_oled/              # SSD1331 RGB stripe test
            └── test_sd/               # SD card raw write/read test
```

---

## Key Components

### `riscv/BASE_TYPE.sv`
Defines shared types: `R_TYPE` instruction fields, `R_TYPE_ALU32_INPUT`, and `PROCESSOR_STATE` enum (`READ_COMMAND`, `READ_REGISTER`, `RUN_COMMAND`, `WATING_MEMORY`, `SAVE_IN_REGISTER`, `ERROR`).

### `riscv/ALU/OP_0110011/OP_0110011.sv`
Implements all 8 RISC-V R-type operations. Dispatch is based on `funct3`; `funct7` distinguishes SUB from ADD and SRA from SRL.

### `riscv/Register/REGISTER_32_BLOCK_32.sv`
32×32-bit register file. Register 0 hardwired to 0. Asynchronous read (rs1, rs2), synchronous write (rd with `write_trigger`).

### `riscv/I_O/` (UART)
- **TIMER_GENERATOR** — generates periodic pulses for bit timing
- **INPUT_CONTROLLER** — serial UART receiver with debounce/accumulator
- **OUTPUT_CONTROLLER** — parallel-to-serial UART transmitter
- **VALUE_STORAGE** — 4-button / 4-LED state machine buffer

### `riscv/MEMORY/` (Memory subsystem — branch `f/cash`)

Cache hierarchy between the processor and DDR RAM:

```
MEMORY_CONTROLLER
├── CHUNK_STORAGE_4_POOL   # 4-entry write-back cache (128-bit chunks, 16-byte aligned)
│   └── CHUNK_STORAGE ×4  # Individual cache line with mask-based writes
└── RAM_CONTROLLER         # MIG DDR controller with dual-clock sync (clk / mig_ui_clk)
```

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

### Peripheral Bus — адресная карта (28-bit)

```
0x000_0000 – 0x7FF_FFFF  →  MEMORY_CONTROLLER (DDR3 через кеш)
0x800_0000 – 0x800_FFFF  →  UART_IO_DEVICE
  0x800_0000 : TX_DATA   (W/R)
  0x800_0004 : RX_DATA   (R)
  0x800_0008 : STATUS    (R) {tx_ready, rx_avail}
0x801_0000 – 0x801_FFFF  →  OLED_IO_DEVICE (PmodOLEDrgb SSD1331, JA)
  0x801_0000 : DATA      (W)   — SPI byte
  0x801_0004 : CONTROL   (W/R) — {PMODEN, VCCEN, RES, DC, CS}
  0x801_0008 : STATUS    (R)   — {spi_busy}
  0x801_000C : DIVIDER   (W/R) — SPI clock divider
0x802_0000 – 0x802_FFFF  →  SD_IO_DEVICE (PmodMicroSD, JC)
  0x802_0000 : DATA      (W/R) — SPI full-duplex TX/RX
  0x802_0004 : CONTROL   (W/R) — {CS}
  0x802_0008 : STATUS    (R)   — {card_detect, spi_busy}
  0x802_000C : DIVIDER   (W/R) — SPI clock divider (init=101/~400kHz, fast=7/~5MHz)
```

Декодирование: `addr[27]=1` → I/O, `addr[17:16]` → устройство (00=UART, 01=OLED, 10=SD, 11=free).

### `riscv/CPU/SPI_MASTER.sv`
Full-duplex SPI Mode 0 (CPOL=0, CPHA=0), MSB first. Настраиваемый делитель тактовой.
MOSI выход + MISO вход, `rx_data` содержит принятый байт после `done=1`.
Используется как OLED_IO_DEVICE, так и SD_IO_DEVICE.

### PMOD подключения

| PMOD | Устройство | Пины |
|------|-----------|------|
| JA | PmodOLEDrgb (SSD1331) | CS, MOSI, SCK, D/C, RES, VCCEN, PMODEN |
| JC | PmodMicroSD | CS, MOSI, MISO, SCK, Card Detect |

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
