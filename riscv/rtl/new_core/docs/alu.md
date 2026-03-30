# ALU Modules

Все ALU имеют единый valid/ready интерфейс:

```
input  prev_stage_valid   — EXECUTE_DISPATCHER подаёт инструкцию
output prev_stage_ready   — ALU свободен (= !blocked)
output next_stage_valid   — результат готов
input  next_stage_ready   — WRITEBACK_ARBITER принимает результат
```

`blocked = next_stage_valid && !next_stage_ready` — результат ждёт арбитра.

---

## ALU_COMPUTE — R-type / I-type (1 такт)

**Файл**: `alu/ALU_COMPUTE.sv`

### Операции

| funct3 | R-type (funct7=0x00) | R-type (funct7=0x20) | I-type |
|--------|---------------------|---------------------|--------|
| 000 | ADD | SUB | ADDI |
| 001 | SLL | — | SLLI |
| 010 | SLT | — | SLTI |
| 011 | SLTU | — | SLTIU |
| 100 | XOR | — | XORI |
| 101 | SRL | SRA | SRLI / SRAI |
| 110 | OR | — | ORI |
| 111 | AND | — | ANDI |

### Операнды

```
op_a = rs1_value
op_b = is_r_type ? rs2_value : sign_extend(imm_i)
imm_i = {{20{instr[31]}}, instr[31:20]}
```

### Gotcha: SRAI

iverilog теряет знак при `$signed(op_a) >>> op_b[4:0]`. Фикс:
```
$unsigned($signed(op_a) >>> op_b[4:0])
```

---

## ALU_BRANCH — Branch (1 такт)

**Файл**: `alu/ALU_BRANCH.sv`

Не пишет в регистр (`rd = 5'd0`). Выдаёт `out_flush` и `out_new_pc` если branch taken.

### Условия

| funct3 | Инструкция | Условие |
|--------|-----------|---------|
| 000 | BEQ | rs1 == rs2 |
| 001 | BNE | rs1 != rs2 |
| 100 | BLT | signed(rs1) < signed(rs2) |
| 101 | BGE | signed(rs1) >= signed(rs2) |
| 110 | BLTU | rs1 < rs2 (unsigned) |
| 111 | BGEU | rs1 >= rs2 (unsigned) |

### Immediate (B-type)

```
imm_b = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0}
new_pc = pc + imm_b  (если taken)
```

---

## ALU_JUMP — JAL / JALR (1 такт)

**Файл**: `alu/ALU_JUMP.sv`

Всегда выдаёт `out_flush = 1`. Пишет `rd = pc + 4` (return address).

### JAL (opcode 1101111)

```
imm_j = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0}
new_pc = pc + imm_j
```

### JALR (opcode 1100111)

```
imm_i = {{20{instr[31]}}, instr[31:20]}
new_pc = (rs1 + imm_i) & 0xFFFFFFFE
```

---

## ALU_UPPER — LUI / AUIPC (1 такт)

**Файл**: `alu/ALU_UPPER.sv`

### Операции

```
imm_u = {instr[31:12], 12'b0}

LUI:   rd = imm_u
AUIPC: rd = pc + imm_u
```

---

## ALU_MEMORY — LOAD / STORE (2-N тактов)

**Файл**: `alu/ALU_MEMORY.sv`

### FSM

```
S_IDLE → S_BUS_REQ → S_BUS_WAIT → S_IDLE
```

- **S_IDLE**: лatch addr, funct3, rd, is_load, rs2_value
- **S_BUS_REQ**: ждём bus_ready, выставляем bus_read/bus_write
- **S_BUS_WAIT**: LOAD — ждём bus_read_valid; STORE — готово

### Адрес

```
LOAD:  addr = rs1 + imm_i    (imm_i = {{20{instr[31]}}, instr[31:20]})
STORE: addr = rs1 + imm_s    (imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]})
```

### Store (byte-masked write)

128-bit шина с 16-bit mask. Позиционирование по `byte_off = addr[3:0]`:

| funct3 | Инструкция | Ширина | Mask |
|--------|-----------|--------|------|
| 00 | SB | 1 байт | 1 бит в mask |
| 01 | SH | 2 байта | 2 бита в mask |
| 10 | SW | 4 байта | 4 бита в mask |

### Load (sign/zero extension)

| funct3 | Инструкция | Ширина | Extension |
|--------|-----------|--------|-----------|
| 000 | LB | 1 байт | sign-extend |
| 001 | LH | 2 байта | sign-extend |
| 010 | LW | 4 байта | — |
| 100 | LBU | 1 байт | zero-extend |
| 101 | LHU | 2 байта | zero-extend |

### Тайминг

- **Store**: 2 такта (req + wait)
- **Load**: 2-3+ такта (req + wait for read_valid)

---

## ALU_MULDIV — RV32M Extension (32 такта)

**Файл**: `alu/ALU_MULDIV.sv`

### FSM

```
S_IDLE → S_COMPUTE (32 итерации) → S_DONE → S_IDLE
```

### Операции

| funct3 | Инструкция | Результат |
|--------|-----------|-----------|
| 000 | MUL | product[31:0] |
| 001 | MULH | product[63:32] (оба signed) |
| 010 | MULHSU | product[63:32] (rs1 signed, rs2 unsigned) |
| 011 | MULHU | product[63:32] (оба unsigned) |
| 100 | DIV | quotient (signed) |
| 101 | DIVU | quotient (unsigned) |
| 110 | REM | remainder (signed) |
| 111 | REMU | remainder (unsigned) |

### Алгоритмы

**Multiplication** (shift-add):
```
for i in 0..31:
  if operand_a[i]: accumulator += operand_b << i
```

**Division** (restoring):
```
for i in 0..31:
  shifted = {acc[62:0], 1'b0}
  if shifted[63:32] >= divisor:
    shifted[63:32] -= divisor
    shifted[0] = 1
  acc = shifted
quotient = acc[31:0], remainder = acc[63:32]
```

**Division by zero**: result = -1 (signed) или 0xFFFFFFFF (unsigned). Remainder = dividend.

### Знаковая обработка

Операнды приводятся к abs() на входе. Результат корректируется на выходе:
- MUL/DIV: negate если знаки rs1 и rs2 разные
- REM: знак = знак rs1

---

## ALU_SYSTEM — Catch-all (1 такт)

**Файл**: `alu/ALU_SYSTEM.sv`

Обрабатывает FENCE, ECALL, EBREAK и неизвестные opcodes.
Не пишет в регистр (`rd = 0, value = 0`). Просто пропускает инструкцию чтобы pipeline не зависал.
