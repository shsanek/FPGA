# Pipeline Stages

## S1: INSTRUCTION_PROVIDER

**Файл**: `stages/INSTRUCTION_PROVIDER.sv`

Fetch-стадия с внутренним line buffer и prefetch.

### Порты

| Порт | Направление | Ширина | Описание |
|------|-------------|--------|----------|
| out_pc | out | 32 | Текущий PC |
| out_instruction | out | 32 | Декодированная инструкция |
| next_stage_valid | out | 1 | Есть инструкция для S2 |
| next_stage_ready | in | 1 | S2 готов принять |
| bus_address | out | 32 | Адрес запроса к I_CACHE |
| bus_read | out | 1 | Строб чтения |
| bus_ready | in | 1 | I_CACHE готов принять запрос |
| peek_line_address | in | 32 | Адрес линии в output buffer I_CACHE |
| peek_line_data | in | 128 | Данные линии (комбинационный) |
| peek_line_valid | in | 1 | Output buffer валиден |
| new_pc | in | 32 | Новый PC при flush |
| flush | in | 1 | Сброс pipeline |

### Внутренние регистры

- `pc [31:0]` — текущий instruction pointer
- `line_data [127:0]` — залатченная 128-bit cache line
- `line_tag` — tag адреса линии (pc[31:4])
- `line_valid` — буфер содержит валидные данные

### Логика

Два источника инструкций:
1. **line_hit** — инструкция в локальном буфере `line_data`
2. **peek_hit** — инструкция в output buffer I_CACHE (комбинационный доступ, 0 тактов)

```
line_hit = line_valid && (pc[31:4] == line_tag)
peek_hit = peek_line_valid && (pc[31:4] == peek_line_address[31:4])
have_current = line_hit || peek_hit
```

Выбор слова из 128-bit линии:
```
word_sel = pc[3:2]   // 4 инструкции в линии
instruction = line[word_sel * 32 +: 32]
```

Prefetch: если текущая линия есть, запрашиваем следующую.
Fetch: если текущей нет — запрашиваем текущую (приоритет).

### Тайминг

- **Hit (line или peek)**: 1 такт
- **Miss**: 1 + N тактов (ожидание I_CACHE fill)

---

## S2: INSTRUCTION_DECODE

**Файл**: `stages/INSTRUCTION_DECODE.sv`

Извлекает индексы регистров rs1, rs2, rd. Неиспользуемые индексы заменяет на 0 (x0).

### Порты

| Порт | Направление | Ширина | Описание |
|------|-------------|--------|----------|
| prev_pc | in | 32 | PC от S1 |
| prev_instruction | in | 32 | Инструкция от S1 |
| prev_stage_valid | in | 1 | S1 имеет данные |
| prev_stage_ready | out | 1 | S2 может принять |
| out_pc | out | 32 | PC для S3 |
| out_instruction | out | 32 | Инструкция для S3 |
| out_rs1_index | out | 5 | Индекс rs1 (0 если не используется) |
| out_rs2_index | out | 5 | Индекс rs2 (0 если не используется) |
| out_rd_index | out | 5 | Индекс rd (0 если не используется) |
| next_stage_valid | out | 1 | Есть данные для S3 |
| next_stage_ready | in | 1 | S3 готов |
| flush | in | 1 | Сброс |

### Декодирование

```
uses_rs1 = opcode in {R, I_ALU, LOAD, STORE, BRANCH, JALR}
uses_rs2 = opcode in {R, STORE, BRANCH}
uses_rd  = opcode in {R, I_ALU, LOAD, JAL, JALR, LUI, AUIPC}
```

Если регистр не используется — индекс = 5'd0. Это позволяет S3 не стопиться на ложных hazard'ах.

### Тайминг

1 такт (registered stage).

---

## S3: REGISTER_DISPATCHER

**Файл**: `stages/REGISTER_DISPATCHER.sv`

Hazard check + register read + forwarding bypass.

### Порты

| Порт | Направление | Ширина | Описание |
|------|-------------|--------|----------|
| prev_pc, prev_instruction | in | 32 | От S2 |
| prev_rs1_index, prev_rs2_index, prev_rd_index | in | 5 | От S2 |
| prev_stage_valid | in | 1 | S2 имеет данные |
| prev_stage_ready | out | 1 | Может принять от S2 |
| out_pc, out_instruction | out | 32 | Для S4 |
| out_rs1_value, out_rs2_value | out | 32 | Значения регистров для ALU |
| next_stage_valid | out | 1 | Есть данные для S4 |
| next_stage_ready | in | 1 | S4 готов |
| rf_rs1_addr, rf_rs2_addr | out | 5 | Адреса чтения regfile |
| rf_rs1_data, rf_rs2_data | in | 32 | Данные из regfile |
| wb_rd_index | in | 5 | Регистр, записываемый writeback |
| wb_rd_value | in | 32 | Значение из writeback (bypass) |
| wb_valid | in | 1 | Writeback активен |
| flush | in | 1 | Сброс |

### Hazard Detection

```
busy[0:31]  — per-register "в полёте" флаги

rs1_busy = (lat_rs1_index != 0) && busy[lat_rs1_index]
rs2_busy = (lat_rs2_index != 0) && busy[lat_rs2_index]
has_hazard = lat_valid && (rs1_busy || rs2_busy)
```

**Set**: `busy[rd] <= 1` когда инструкция диспатчится в S4 (rd != 0)
**Clear**: `busy[wb_rd_index] <= 0` когда приходит `wb_valid` (независимо от flush)

### Forwarding Bypass

Если writeback пишет регистр на том же такте — используем значение напрямую:
```
out_rs1_value <= (wb_valid && wb_rd_index == lat_rs1_index) ? wb_rd_value : rf_rs1_data
```

### Тайминг

- Без hazard'а: 1 такт
- С hazard'ом: stall до wb_valid для нужного регистра

---

## S4: EXECUTE_DISPATCHER

**Файл**: `stages/EXECUTE_DISPATCHER.sv`

Роутинг инструкций по ALU. Содержит все 6 ALU + WRITEBACK_ARBITER.

### Порты

| Порт | Направление | Ширина | Описание |
|------|-------------|--------|----------|
| prev_pc, prev_instruction | in | 32 | От S3 |
| prev_rs1_value, prev_rs2_value | in | 32 | Значения регистров |
| prev_stage_valid | in | 1 | S3 имеет данные |
| prev_stage_ready | out | 1 | Может принять |
| out_rd_index | out | 5 | Результат: индекс rd |
| out_rd_value | out | 32 | Результат: значение rd |
| next_stage_valid | out | 1 | Есть результат |
| next_stage_ready | in | 1 | S6 готов |
| out_flush | out | 1 | Branch/jump flush |
| out_new_pc | out | 32 | Новый PC |
| mem_bus_* | in/out | — | Шина памяти для ALU_MEMORY |

### Opcode Routing

| Selector | Opcodes | ALU |
|----------|---------|-----|
| sel_compute | 0110011 (R), 0010011 (I) | ALU_COMPUTE |
| sel_branch | 1100011 (B) | ALU_BRANCH |
| sel_jump | 1101111 (JAL), 1100111 (JALR) | ALU_JUMP |
| sel_upper | 0110111 (LUI), 0010111 (AUIPC) | ALU_UPPER |
| sel_memory | 0000011 (LOAD), 0100011 (STORE) | ALU_MEMORY |
| sel_muldiv | 0110011 + funct7[0]=1 | ALU_MULDIV |
| sel_system | всё остальное | ALU_SYSTEM |

M-extension override: если `sel_muldiv`, то `sel_compute_final = 0`.

### flush_locked

```
prev_stage_ready = target_ready && !flush_locked

xxx_valid = prev_stage_valid && sel_xxx && xxx_ready && !flush_locked
```

Блокирует диспатч новых инструкций пока branch/jump в ALU.
Устанавливается когда `branch_valid || jump_valid`. Снимается когда `branch_done || jump_done`.

### WRITEBACK_ARBITER (внутри S4)

Комбинационный арбитр. Приоритет:
1. Single-cycle ALU (compute, branch, jump, upper, system) — макс. один за такт
2. ALU_MEMORY
3. ALU_MULDIV

---

## S5: WRITEBACK_ARBITER

**Файл**: `stages/WRITEBACK_ARBITER.sv`

Комбинационный мультиплексор. Принимает результаты от всех ALU, выбирает один по приоритету.

### Логика

```
single_valid = compute_valid || branch_valid || jump_valid || upper_valid || system_valid
pick_single  = single_valid && wb_ready
pick_memory  = !single_valid && memory_valid && wb_ready
pick_muldiv  = !single_valid && !memory_valid && muldiv_valid && wb_ready
```

Ready для single-cycle ALU: `pick_single || !xxx_valid` (ready если выиграл арбитраж или нет результата).
Ready для memory/muldiv: только если выиграл (`pick_memory` / `pick_muldiv`).

### Тайминг

0 тактов (комбинационная логика).

---

## S6: WRITEBACK

**Файл**: `stages/WRITEBACK.sv`

Финальная registered стадия. Пишет результат в register file, нотифицирует S3.

### Порты

| Порт | Направление | Ширина | Описание |
|------|-------------|--------|----------|
| prev_rd_index | in | 5 | Индекс rd от арбитра |
| prev_rd_value | in | 32 | Значение rd |
| prev_stage_valid | in | 1 | Арбитр имеет результат |
| prev_stage_ready | out | 1 | Может принять (= !rf_wr_en) |
| rf_wr_addr | out | 5 | Адрес записи в regfile |
| rf_wr_data | out | 32 | Данные записи |
| rf_wr_en | out | 1 | Строб записи |
| wb_done_index | out | 5 | Нотификация S3: какой регистр записан |
| wb_done_value | out | 32 | Нотификация S3: значение (для bypass) |
| wb_done_valid | out | 1 | Нотификация S3: валидно |

### Тайминг

1 такт. Запись x0 игнорируется (`rf_wr_en = prev_rd_index != 5'd0`).
