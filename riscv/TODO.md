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

## Фаза 5 — Полная интеграция и синтез

- [ ] `TOP.sv` — верхний модуль: CPU + MEMORY_CONTROLLER + RAM_CONTROLLER + I_O + DEBUG_CONTROLLER
- [ ] `TOP_TEST.sv` — симуляция полной системы
- [ ] Синтез под Xilinx (constraints, pin mapping)
- [ ] Тест на железе: загрузить программу через UART, выполнить, прочитать результат

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
