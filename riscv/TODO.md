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
- [ ] `BRANCH_UNIT.sv` — BEQ/BNE/BLT/BGE/BLTU/BGEU → branch_taken + target_pc
- [ ] `BRANCH_UNIT_TEST.sv`

### LOAD / STORE UNIT
- [ ] `LOAD_UNIT.sv` — LB/LH/LW/LBU/LHU: выравнивание + sign extension
- [ ] `LOAD_UNIT_TEST.sv`
- [ ] `STORE_UNIT.sv` — SB/SH/SW: byte mask для MEMORY_CONTROLLER
- [ ] `STORE_UNIT_TEST.sv`

---

## Фаза 2 — Однотактовый CPU

- [ ] `CPU_SINGLE_CYCLE.sv`
  - [ ] Instruction fetch из ROM (массив в симуляции)
  - [ ] Decode: opcode → control signals
  - [ ] Execute: ALU / Branch / Load / Store / LUI / AUIPC / JAL / JALR
  - [ ] Write back
- [ ] `CPU_ROM.sv` — инструкционная память для тестов (параметрический массив)
- [ ] `CPU_SINGLE_CYCLE_TEST.sv`
  - [ ] Тест: арифметика (ADD, ADDI, LUI, AUIPC)
  - [ ] Тест: переходы (BEQ, BNE, JAL, JALR)
  - [ ] Тест: память (LW/SW, LB/SB, LH/SH)
  - [ ] Тест: простая программа (цикл, сумма массива)

---

## Фаза 3 — Интеграция с памятью

- [ ] Подключить `MEMORY_CONTROLLER` как инструкционную и data-память
  - [ ] Разделить instruction fetch и data access (два порта или арбитраж)
- [ ] `CPU_MEMORY_INTEGRATION_TEST.sv`
  - [ ] Загрузить программу через write-порт, запустить, проверить результат

---

## Фаза 4 — Debugger v1

> **Требование:** весь debug-код должен легко отключаться.
> Все debug-порты и `DEBUG_CONTROLLER` оборачиваются в параметр:
> ```systemverilog
> parameter DEBUG_ENABLE = 1
> ```
> При `DEBUG_ENABLE=0` — debug-порты CPU/MEM не подключаются, `DEBUG_CONTROLLER` не инстанциируется, на FPGA ресурсы не тратятся.

### Протокол (UART, little-endian, фиксированные пакеты)

| CMD  | Название   | Payload         | Ответ              |
|------|------------|-----------------|--------------------|
| 0x01 | HALT       | —               | 0xFF               |
| 0x02 | RESUME     | —               | 0xFF               |
| 0x03 | STEP       | —               | PC[31:0]+INSTR[31:0] |
| 0x04 | READ_MEM   | ADDR[31:0]      | DATA[31:0]         |
| 0x05 | WRITE_MEM  | ADDR[31:0]+DATA[31:0] | 0xFF          |

### Модули

- [ ] `DEBUG_CONTROLLER.sv` — главный FSM: приём команды → управление CPU/MEM → отправка ответа
- [ ] `DEBUG_CONTROLLER_TEST.sv`

### Изменения в CPU

- [ ] Добавить debug-порты в `CPU_SINGLE_CYCLE.sv`:
  ```
  input  dbg_halt
  input  dbg_step
  output dbg_is_halted
  output dbg_current_pc[31:0]
  output dbg_current_instr[31:0]
  ```

### Изменения в MEMORY_CONTROLLER

- [ ] Добавить debug-порт (приоритет выше CPU):
  ```
  input  dbg_read_trigger
  input  dbg_write_trigger
  input  dbg_address[27:0]
  input  dbg_write_data[31:0]
  output dbg_read_data[31:0]
  output dbg_ready
  ```

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
