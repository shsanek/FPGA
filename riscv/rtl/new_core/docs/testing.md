# Testing

## Test Harnesses

### PIPELINE_TB.sv

Testbench для pipeline без CORE обвязки. Inline `include` — каждый тест оборачивает его в свой module.

Содержит:
- Register file (32x32, x0=0)
- I_CACHE mock (peek-based, 1-cycle fill на bus_read)
- Data memory mock (128KB byte-addressable, 2-cycle read latency, instant write)
- Helper tasks: `load_program()`, `init()`, `check_reg()`, `check_mem_byte()`

### CORE_TB.sv

Testbench для полного CORE (pipeline + I_CACHE + BUS_ARBITER + regfile).

Содержит:
- Unified mock memory (64K words = 256KB, 1-cycle read latency)
- CORE instance с параметрами `ICACHE_DEPTH=16, ICACHE_WAYS=1`
- Helper tasks: `load_program()`, `run_program()`, `check_reg()`
- Детекция EBREAK: мониторинг `s3_valid && s3_ready && s3_instruction == 0x00100073`

## Компиляция

```bash
cd riscv/

# Pipeline test (file list в /tmp/iverilog_pipeline.txt):
iverilog -g2012 -Itest/new_core -o /tmp/test_xxx \
  -f /tmp/iverilog_pipeline.txt test/new_core/test_xxx.sv
vvp /tmp/test_xxx

# Core test:
iverilog -g2012 -Itest/new_core -o /tmp/core_test_xxx \
  -f /tmp/iverilog_core.txt test/new_core/core_test_xxx.sv
vvp /tmp/core_test_xxx
```

**Важно**: `-o` должен быть ПЕРЕД `-f`, иначе iverilog 13.0 падает с "No such file or directory".

## Pipeline Tests (8 тестов)

| Тест | Что проверяет | Результат |
|------|--------------|-----------|
| test_alu_basic | ADD, SUB, AND, OR, XOR, SLT, ADDI | PASSED |
| test_branch | BEQ, BNE, BLT, BGE, BLTU, BGEU | PASSED |
| test_jump | JAL, JALR (wrong-path не выполняется) | PASSED |
| test_upper | LUI, AUIPC | PASSED |
| test_hazard | RAW data dependency stalling | PASSED |
| test_shifts | SLL, SRL, SRA, SLLI, SRLI, SRAI | PASSED |
| test_loop | Цикл с branch (sum 1..10) | PASSED |
| test_memory | SB, SH, SW, LB, LH, LW, LBU, LHU | PASSED |

## Core Tests (4 теста с C-программами)

| Тест | Программа | Cycles | Результат |
|------|----------|--------|-----------|
| core_test_alu | 37 инструкций: все ALU ops | 203 | PASSED |
| core_test_loop | sum(1..100) = 5050 | 42 | PASSED |
| core_test_mem | store/load array | 76 | PASSED |
| core_test_fib | fib(20) = 6765 | 549 | PASSED |

## Hex файлы

Core тесты загружают hex из `/tmp/core_test_xxx.hex`. Формат: 1 слово (32-bit) на строку, little-endian hex.

Генерация из C:
```bash
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib \
  -T programs/common/linker.ld -o /tmp/prog.elf src/*.c src/*.s
riscv64-unknown-elf-objcopy -O binary /tmp/prog.elf /tmp/prog.bin
python3 -c "
import sys; data=open(sys.argv[1],'rb').read()
[print(f'{int.from_bytes(data[i:i+4],\"little\"):08x}') for i in range(0,len(data),4)]
" /tmp/prog.bin > /tmp/prog.hex
```

## Известные предупреждения

iverilog 13.0 выдаёт `sorry: constant selects in always_* processes` для ALU_COMPUTE и ALU_MEMORY. Это cosmetic — результат корректный, процесс просто sensitive ко всем битам вместо выбранных.
