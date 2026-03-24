# RISC-V Processor TODO

## Фаза 1 — Базовые компоненты

### REGISTER_FILE
- [x] `REGISTER_32_BLOCK_32.sv` — 32×32-bit регистра, x0=0, dual read / single write
- [x] `REGISTER_32_BLOCK_32_TEST.sv`

### ALU
- [x] `OP_0110011.sv` — R-type: ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND
- [x] `OP_0110011_TEST.sv`
- [x] `OP_0010011.sv` — I-type ALU: ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI
- [x] `OP_0010011_TEST.sv`

### IMMEDIATE_GENERATOR
- [x] `IMMEDIATE_GENERATOR.sv` — декодирует immediate из форматов I/S/B/U/J
- [x] `IMMEDIATE_GENERATOR_TEST.sv`

### BRANCH_UNIT
- [x] `BRANCH_UNIT.sv` — BEQ/BNE/BLT/BGE/BLTU/BGEU → branch_taken + target_pc
- [x] `BRANCH_UNIT_TEST.sv`

### LOAD / STORE UNIT
- [x] `LOAD_UNIT.sv` — LB/LH/LW/LBU/LHU: выравнивание + sign extension
- [x] `LOAD_UNIT_TEST.sv`
- [x] `STORE_UNIT.sv` — SB/SH/SW: byte mask для MEMORY_CONTROLLER
- [x] `STORE_UNIT_TEST.sv`

---

## Фаза 2 — Однотактовый CPU

- [x] `CPU_ALU.sv` — комбинационный ALU (R-type + I-type + force_add)
- [x] `CPU_SINGLE_CYCLE.sv`
  - [x] Instruction fetch из ROM (массив в симуляции)
  - [x] Decode: opcode → control signals
  - [x] Execute: ALU / Branch / Load / Store / LUI / AUIPC / JAL / JALR
  - [x] Write back
  - [x] Debug: dbg_halt / dbg_step / DEBUG_ENABLE parameter
- [x] `CPU_SINGLE_CYCLE_TEST.sv`
  - [x] Тест: арифметика (ADDI, ADD, SUB)
  - [x] Тест: LUI, AUIPC
  - [x] Тест: память (SW, LW)
  - [x] Тест: ветвления (BEQ taken, BNE taken, skip-check)
  - [x] Тест: JAL (return addr + skip-check)
- [x] `CPU_SINGLE_CYCLE.sv` — FENCE (NOP), ECALL (NOP), EBREAK (debug halt)
- [x] `CPU_SINGLE_CYCLE_SYSTEM_TEST.sv` — ALL TESTS PASSED
  - [x] T1: FENCE → NOP, PC продвигается
  - [x] T2: ECALL → NOP, PC продвигается
  - [x] T3: EBREAK → CPU halted, dbg_step освобождает
  - [x] T4: EBREAK + HALT → RESUME освобождает

---

## Фаза 3 — Интеграция с памятью

- [x] Подключить `MEMORY_CONTROLLER` как data-память (инструкции — ROM)
  - [x] `CPU_DATA_ADAPTER.sv` — FSM-адаптер: CPU ↔ MEMORY_CONTROLLER со stall
- [x] `CPU_MEMORY_INTEGRATION_TEST.sv` — ALL TESTS PASSED
  - [x] SW/LW через MEMORY_CONTROLLER → RAM_CONTROLLER → MIG_MODEL

---

## Фаза 4 — Debugger v1  ✅

Протокол (UART, little-endian, фиксированные пакеты):

| CMD  | Название   | Payload               | Ответ                |
|------|------------|-----------------------|----------------------|
| 0x01 | HALT       | —                     | 0xFF                 |
| 0x02 | RESUME     | —                     | 0xFF                 |
| 0x03 | STEP       | —                     | PC[31:0]+INSTR[31:0] |
| 0x04 | READ_MEM   | ADDR[31:0]            | DATA[31:0]           |
| 0x05 | WRITE_MEM  | ADDR[31:0]+DATA[31:0] | 0xFF                 |

- [x] `DEBUG_CONTROLLER.sv` — FSM S_IDLE→S_RECV→S_EXEC→S_HALT_WAIT→S_SEND
  - [x] Байтовый интерфейс (UART подключается снаружи)
  - [x] DEBUG_ENABLE=0 → заглушка (нет ресурсов на FPGA)
- [x] `DEBUG_CONTROLLER_TEST.sv` — ALL TESTS PASSED
- [x] `CPU_SINGLE_CYCLE.sv` — debug-порты dbg_halt/step/is_halted/pc/instr
- [x] `MEMORY_CONTROLLER.sv` — debug-порт с приоритетом над CPU

---

## Фаза 4.5 — Периферийная шина + Memory-Mapped UART  ✅

Физический UART разделён между отладчиком и CPU:
- Байты 0x01–0x05 → DEBUG_CONTROLLER (дебаг-команды)
- Остальные байты → CPU RX буфер (через cpu_rx_valid)
- CPU TX → физический UART когда DEBUG в S_IDLE

Адресное пространство (28-bit mc_address):
- bit 27 = 0: MEMORY_CONTROLLER (ОЗУ, кэш)
- bit 27 = 1: I/O устройства (UART_IO_DEVICE)

UART_IO_DEVICE регистры (base = 0x0800_0000):
| Смещение | Регистр  | Доступ | Описание                        |
|----------|----------|--------|---------------------------------|
| +0x00    | TX_DATA  | W/R    | Запись → отправить байт в UART  |
| +0x04    | RX_DATA  | R      | Принятый байт (сброс после чтения)|
| +0x08    | STATUS   | R      | bit1=tx_ready, bit0=rx_available|

- [x] `UART_IO_DEVICE.sv` — memory-mapped UART регистры
- [x] `PERIPHERAL_BUS.sv` — маршрутизатор по биту 27 адреса
- [x] `PERIPHERAL_BUS_TEST.sv` — ALL TESTS PASSED

---

## Фаза 5 — Полная интеграция и симуляция  ✅

- [x] `TOP.sv` — верхний модуль: CPU + MEMORY_CONTROLLER + RAM_CONTROLLER + I_O + DEBUG_CONTROLLER + PERIPHERAL_BUS + UART_IO_DEVICE
- [x] `TOP_TEST.sv` — симуляция полной системы (ALL TESTS PASSED)
  - [x] T1: CPU выполняет программу SW/LW (x1=42, x2=42, x3=52, x4=52)
  - [x] T2: HALT через физический UART → cpu останавливается
  - [x] T3: RESUME через физический UART → cpu возобновляет работу
  - [x] T4: CPU пишет в UART_IO_DEVICE TX_DATA через память (0x0800_0000)
- [x] C-программный тест-фреймворк (`tests/` + `PROGRAM_TEST.sv` + `run_tests.sh`)
  - [x] `tests/linker.ld`, `tests/crt0.s`, `tests/runtime.c` — bare-metal RV32I runtime
  - [x] `tests/programs/hello/` — "Hello, RISC-V!" (77 cycles)
  - [x] `tests/programs/fib/` — Фибоначчи 0..9 (5169 cycles)
  - [x] `tests/programs/sum/` — Сумма 1..100=5050 (700 cycles)
  - [x] Toolchain: riscv64-elf-gcc -march=rv32i -mabi=ilp32
  - [x] Bug fix: UART_IO_DEVICE cpu_tx_byte = write_value (не tx_data_r)
- [ ] Синтез под Xilinx (constraints, pin mapping)
- [ ] Тест на железе: загрузить программу через UART, выполнить, прочитать результат

### Заметки по симуляции
- `I_O_INPUT_CONTROLLER` переворачивает биты (shift-left аккумуляция): чтобы
  DEBUG_CONTROLLER получил байт X, нужно отправить `rev8(X)` в стандартном UART.
  Пример: CMD_HALT=0x01 → uart_send(0x80).
- `tx_valid_r` — 1-тактовый импульс внутри uart_send; обнаруживать через `fork/join`
  с uart_send и expect_dbg_byte параллельно.
- ROM инициализируется через иерархический доступ в тестбенче: `dut.rom[i] = instr`.

---

## Отложено (v2)

- [ ] 5-стадийный pipeline (IF/ID/EX/MEM/WB)
- [ ] Hazard detection unit
- [ ] Data forwarding unit
- [ ] EXEC_INSTR (инъекция инструкции через отладчик)
- [ ] READ_REG по номеру через отладчик
- [ ] RV32M (MUL/DIV/REM)
- [ ] CSR регистры + прерывания
- [ ] Branch prediction
