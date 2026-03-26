# DEBUG_CONTROLLER

Отладочный контроллер RISC-V CPU. Принимает команды через байтовый интерфейс (UART),
управляет CPU (halt/resume/step), читает/пишет память, сбрасывает PC.

**Файл:** `riscv/CPU/DEBUG_CONTROLLER.sv`

---

## Протокол

Little-endian, фиксированные пакеты. Каждая команда → один ответ (ACK или данные).

| Код | Команда | Payload (→ FPGA) | Ответ (← FPGA) | Описание |
|-----|---------|-------------------|-----------------|----------|
| 0x01 | HALT | — | 0xFF | Остановить CPU |
| 0x02 | RESUME | — | 0xFF | Возобновить CPU |
| 0x03 | STEP | — | PC[31:0] + INSTR[31:0] (8 байт) | Один шаг, вернуть PC и инструкцию |
| 0x04 | READ_MEM | ADDR[31:0] | DATA[31:0] (4 байта) | Прочитать 32-бит слово |
| 0x05 | WRITE_MEM | ADDR[31:0] + DATA[31:0] | 0xFF | Записать 32-бит слово |
| 0x07 | RESET_PC | ADDR[31:0] | 0xFF | Установить PC на адрес |

**Код 0x06 зарезервирован** (не используется, пропускается как passthrough).

Байты вне диапазона 0x01–0x07 (и 0x06) проходят напрямую в CPU (passthrough).
Байты от CPU (UART_IO_DEVICE) отправляются обратно в тот же UART (passthrough обратно).

---

## Параметры

| Параметр | Default | Описание |
|----------|---------|----------|
| DEBUG_ENABLE | 1 | 1 = полная логика, 0 = заглушка (все выходы = 0) |
| ADDRESS_SIZE | 28 | Ширина адреса шины |
| DATA_SIZE | 32 | Ширина данных |
| MASK_SIZE | DATA_SIZE/8 | Ширина маски байт |

При `DEBUG_ENABLE=0` модуль синтезируется в заглушку без логики — `cpu_tx_ready=1`, все остальные выходы = 0.

---

## Интерфейс

### Байтовый RX/TX (от/к UART)

| Сигнал | Нап. | Ширина | Описание |
|--------|------|--------|----------|
| rx_byte | in | 8 | Принятый байт |
| rx_valid | in | 1 | 1-тактовый импульс: новый байт |
| tx_byte | out | 8 | Байт для отправки |
| tx_valid | out | 1 | 1-тактовый импульс: отправить |
| tx_ready | in | 1 | TX свободен |

### CPU debug-порты

| Сигнал | Нап. | Ширина | Описание |
|--------|------|--------|----------|
| dbg_halt | out | 1 | Удерживать CPU (уровень) |
| dbg_step | out | 1 | 1-тактовый импульс: один шаг |
| dbg_set_pc | out | 1 | 1-тактовый импульс: установить PC |
| dbg_new_pc | out | 32 | Новое значение PC (при dbg_set_pc) |
| dbg_is_halted | in | 1 | CPU остановлен |
| dbg_current_pc | in | 32 | Текущий PC |
| dbg_current_instr | in | 32 | Текущая инструкция |

### Bus debug-порты (память)

| Сигнал | Нап. | Ширина | Описание |
|--------|------|--------|----------|
| dbg_bus_request | out | 1 | Запрос остановки pipeline (уровень) |
| dbg_bus_granted | in | 1 | Pipeline остановлен, bus свободен |
| mc_dbg_address | out | ADDRESS_SIZE | Адрес на шине |
| mc_dbg_read_trigger | out | 1 | Триггер чтения (уровень, сбрасывается в S_MEM_WAIT) |
| mc_dbg_write_trigger | out | 1 | Триггер записи (уровень) |
| mc_dbg_write_data | out | DATA_SIZE | Данные для записи |
| mc_dbg_read_data | in | DATA_SIZE | Прочитанные данные |
| mc_dbg_ready | in | 1 | Bus завершил операцию |

### CPU passthrough

| Сигнал | Нап. | Ширина | Описание |
|--------|------|--------|----------|
| cpu_rx_byte | out | 8 | Байт от UART для CPU (не debug-команда) |
| cpu_rx_valid | out | 1 | 1-тактовый импульс |
| cpu_tx_byte | in | 8 | Байт от CPU для отправки через UART |
| cpu_tx_valid | in | 1 | CPU хочет отправить |
| cpu_tx_ready | out | 1 | DEBUG готов забрать байт (комбинационно) |

`cpu_tx_ready = (state == S_IDLE) && tx_ready && !tx_valid_r` — CPU может слать только когда DEBUG в IDLE и TX свободен.

---

## Внутренние состояния (FSM)

```
              rx_valid (cmd)
                  │
     ┌────────────▼────────────┐
     │         S_IDLE           │ ◄──────────────────────────┐
     │  ожидание команды        │                             │
     │  passthrough CPU TX/RX   │                             │
     └──┬──────────┬───────────┘                             │
        │          │                                          │
  payload=0   payload>0                                       │
        │          │                                          │
        │  ┌───────▼──────────┐                              │
        │  │     S_RECV        │                              │
        │  │  приём payload    │                              │
        │  │  (4 или 8 байт)   │                              │
        │  └───────┬──────────┘                              │
        │          │                                          │
        ▼          ▼                                          │
  ┌─────────────────────────┐                                │
  │    S_PAUSE_WAIT          │                                │
  │  bus_request=1           │                                │
  │  ждём dbg_bus_granted    │                                │
  └──────────┬──────────────┘                                │
             │                                                │
  ┌──────────▼──────────────┐                                │
  │        S_EXEC            │                                │
  │  диспатч по cmd:         │                                │
  │  ├─ HALT → resp=0xFF ─────────────→ S_SEND ──────────→──┤
  │  ├─ RESUME → resp=0xFF ──────────→ S_SEND ──────────→──┤
  │  ├─ STEP → resp=PC+INSTR ────────→ S_SEND ──────────→──┤
  │  ├─ RESET_PC → resp=0xFF ────────→ S_SEND ──────────→──┤
  │  ├─ READ_MEM → mc_read_r=1 ──→ S_MEM_TRIG              │
  │  └─ WRITE_MEM → mc_write_r=1 → S_MEM_TRIG              │
  └─────────────────────────┘                                │
                                                              │
  ┌─────────────────────────┐                                │
  │     S_MEM_TRIG           │  trigger выставлен (1 такт)   │
  └──────────┬──────────────┘                                │
             │                                                │
  ┌──────────▼──────────────┐                                │
  │     S_MEM_WAIT           │  ждём mc_dbg_ready            │
  │  сбрасывает trigger      │                                │
  └──────────┬──────────────┘                                │
             │                                                │
  ┌──────────▼──────────────┐                                │
  │     S_MEM_DONE           │  формирует ответ:             │
  │  READ → resp=DATA[31:0] │  4 байта little-endian        │
  │  WRITE → resp=0xFF      │                                │
  │  !halt → bus_request=0  │                                │
  └──────────┬──────────────┘                                │
             │                                                │
  ┌──────────▼──────────────┐                                │
  │       S_SEND             │  побайтная отправка resp[]    │
  │  tx_byte = resp[idx]     │  по tx_ready                   │
  │  idx++ до resp_len       │                                │
  └──────────┴──────────────────────────────────────────────┘
```

### Описание состояний

| Состояние | Описание |
|-----------|----------|
| **S_IDLE** | Ждёт `rx_valid`. Распознаёт debug-команды (0x01–0x07, не 0x06). Остальные байты → CPU passthrough. Также перенаправляет CPU TX → UART TX. |
| **S_RECV** | Принимает payload побайтно: первые 4 байта → `payload_addr` (little-endian), следующие 4 → `payload_data`. |
| **S_PAUSE_WAIT** | `bus_request=1`. Ждёт `dbg_bus_granted` (pipeline остановлен, bus свободен). |
| **S_EXEC** | Диспатч по команде. Для HALT/RESUME/STEP/RESET_PC — сразу формирует ответ → S_SEND. Для READ_MEM/WRITE_MEM — выставляет триггер → S_MEM_TRIG. |
| **S_MEM_TRIG** | Триггер на bus уже выставлен (из S_EXEC). Промежуточное состояние (1 такт). → S_MEM_WAIT |
| **S_MEM_WAIT** | Ждёт `mc_dbg_ready`. Сбрасывает `mc_read_r` / `mc_write_r`. → S_MEM_DONE |
| **S_MEM_DONE** | Формирует ответ: для READ — 4 байта данных, для WRITE — 0xFF. Если CPU не в HALT — отпускает bus (`bus_request=0`). → S_SEND |
| **S_HALT_WAIT** | Не используется (legacy). → S_IDLE |
| **S_SEND** | Побайтная отправка `resp[0..resp_len-1]` через TX. Ждёт `tx_ready` перед каждым байтом. По завершении → S_IDLE |

---

## Внутренние регистры

| Регистр | Ширина | Описание |
|---------|--------|----------|
| state | 4 | Текущее состояние FSM |
| cmd | 8 | Код текущей команды |
| payload_addr | 32 | Адрес из payload (little-endian) |
| payload_data | 32 | Данные из payload (little-endian) |
| byte_idx | 3 | Счётчик принятых байт payload |
| resp[0:7] | 8×8 | Буфер ответа (до 8 байт) |
| resp_len | 4 | Длина ответа (сколько байт слать) |
| resp_idx | 4 | Индекс текущего отправляемого байта |
| halt_r | 1 | Регистр halt (уровень) |
| step_r | 1 | Регистр step (импульс, auto-clear) |
| set_pc_r | 1 | Регистр set_pc (импульс, auto-clear) |
| new_pc_r | 32 | Новый PC (при set_pc) |
| bus_request_r | 1 | Регистр bus request (уровень) |
| mc_addr_r | ADDRESS_SIZE | Адрес для bus |
| mc_data_r | DATA_SIZE | Данные для записи |
| mc_read_r | 1 | Триггер чтения (уровень) |
| mc_write_r | 1 | Триггер записи (уровень) |
| tx_byte_r | 8 | TX байт |
| tx_valid_r | 1 | TX valid (импульс, auto-clear) |
| cpu_rx_byte_r | 8 | Passthrough RX байт |
| cpu_rx_valid_r | 1 | Passthrough RX valid (импульс, auto-clear) |

**Auto-clear** (сбрасывается в 0 каждый такт, если не выставлен заново): `tx_valid_r`, `step_r`, `set_pc_r`, `cpu_rx_valid_r`.

---

## Интеграция с pipeline (bus arbitration)

```
DEBUG_CONTROLLER                    CPU_PIPELINE_ADAPTER
     │                                        │
     ├─ dbg_bus_request ──────────→ pause      │
     │                                         │
     ├─ dbg_bus_granted ◄────────── paused     │
     │                                         │
     └─ mc_dbg_* ──┐                          │
                    │                          │
              ┌─────▼───────────────────┐      │
              │     BUS MUX (TOP.sv)    │      │
              │  paused ? debug : pipe  │ ◄────┘ pipe_*
              └─────────┬───────────────┘
                        │
                  PERIPHERAL_BUS
                   ├── MEMORY_CONTROLLER
                   └── UART_IO_DEVICE
```

**Bus mux** (комбинационный, в TOP.sv):
- `pipeline_paused=1` → debug владеет bus (addr/rd/wr/data от DEBUG_CONTROLLER)
- `pipeline_paused=0` → pipeline владеет bus
- `mc_dbg_ready = pipeline_paused ? bus_ready : 0`
- `mc_dbg_rd_data = bus_rd_data` (всегда подключен)

---

## Протокол bus request / granted

### HALT
1. `bus_request=1` → pipeline stalls → `granted=1`
2. `halt_r=1`, `bus_request` остаётся 1
3. CPU и pipeline остановлены до RESUME
4. Ответ 0xFF

### RESUME
1. `halt_r=0`, `bus_request=0`
2. Pipeline выходит из S_PAUSED → S_FETCH_TRIG
3. CPU продолжает выполнение
4. Ответ 0xFF

### READ_MEM / WRITE_MEM
1. `bus_request=1` → ждём `granted=1`
2. Выставляем `mc_addr_r` + `mc_read_r` (или `mc_write_r` + `mc_data_r`)
3. S_MEM_TRIG → S_MEM_WAIT (ждём `mc_dbg_ready`)
4. Сбрасываем trigger
5. S_MEM_DONE: формируем ответ, если `!halt_r` → `bus_request=0`
6. S_SEND: отправляем ответ

### STEP
1. Уже в HALT (bus_request=1, granted=1)
2. `step_r=1` (1-тактовый импульс) — CPU делает один шаг
3. Захватываем `dbg_current_pc` и `dbg_current_instr` **в этот же такт** (значения до шага)
4. Ответ: 8 байт (PC + INSTR, little-endian)

### RESET_PC
1. `bus_request=1` → ждём `granted=1`
2. `set_pc_r=1`, `new_pc_r=payload_addr` (1-тактовый импульс)
3. Pipeline получает flush
4. Если `!halt_r` → `bus_request=0`
5. Ответ 0xFF

---

## Типичный flow загрузки программы

```
Python (riscv_tester.py)              DEBUG_CONTROLLER
         │                                    │
    HALT (0x01) ─────────────────────────→    │
         │  ◄──────────── 0xFF ──────────     │
         │                                    │
    WRITE_MEM (0x05)                          │
      addr=0x00, data=instr[0] ──────────→    │
         │  ◄──────────── 0xFF ──────────     │
    WRITE_MEM addr=0x04, data=instr[1] ──→    │
         │  ◄──────────── 0xFF ──────────     │
         │     ...повторить N раз...          │
         │                                    │
    RESET_PC (0x07) addr=0x00 ───────────→    │
         │  ◄──────────── 0xFF ──────────     │
         │                                    │
    RESUME (0x02) ───────────────────────→    │
         │  ◄──────────── 0xFF ──────────     │
         │                                    │
         │  ◄──── CPU output (passthrough) ── │
```

---

## Тестирование

### Unit-тест: `DEBUG_CONTROLLER_TEST.sv`

| Тест | Команда | Проверка |
|------|---------|----------|
| T1 | HALT | Ответ 0xFF, cpu_halted=1 |
| T2 | RESUME | Ответ 0xFF, cpu_halted=0 |
| T3 | STEP | Ответ 8 байт: PC + INSTR (little-endian) |
| T4 | READ_MEM addr=0x10 | Ответ 4 байта: 0xCAFEBABE (stub) |
| T5 | WRITE_MEM addr=0x20 data=0x12345678 | Ответ 0xFF |

Стубы:
- **CPU stub:** `cpu_halted` следует за `dbg_halt`
- **MC stub:** `mc_ready` через 3 такта после фронта trigger, `mc_rdata = 0xCAFEBABE`
- **Bus granted:** захардкожен в `1` (pipeline bypass)

### Интеграционный тест: `PROGRAM_TEST.sv`

Загружает программу через полный UART debug-протокол (bit-bang → FIFO → DEBUG_CONTROLLER → memory). Проверяет:
- HALT/RESUME работает
- WRITE_MEM записывает данные в DDR (через кэш)
- READ_MEM возвращает записанные данные
- RESET_PC(0) корректно сбрасывает PC
- CPU выполняет загруженную программу до EBREAK

### Аппаратный тест: `riscv_tester.py`

Python-скрипт для тестирования через реальный UART (COM порт):
- Загрузка hex-файлов
- HALT/RESUME/STEP
- Readback памяти

---

## Известные особенности

1. **STEP возвращает PC/INSTR до шага.** Значения захватываются в тот же такт, что `step_r=1`. CPU увидит step на следующем фронте.

2. **Trigger на bus — уровень, не импульс.** `mc_read_r`/`mc_write_r` выставляются в S_EXEC и сбрасываются только в S_MEM_WAIT при `mc_dbg_ready`. Trigger держится 2+ такта (S_EXEC → S_MEM_TRIG → S_MEM_WAIT).

3. **Passthrough ограничен S_IDLE.** CPU может отправлять UART-байты только когда DEBUG_CONTROLLER в S_IDLE. Если контроллер обрабатывает debug-команду, CPU TX буферизируется.

4. **Код 0x06 — дыра.** Байт 0x06 не является debug-командой (пропущен между 0x05 и 0x07), проходит как passthrough в CPU. Зарезервирован для будущего использования.

---

## Файлы

| Файл | Описание |
|------|----------|
| `riscv/CPU/DEBUG_CONTROLLER.sv` | Основной модуль |
| `riscv/CPU/DEBUG_CONTROLLER_TEST.sv` | Unit-тест (T1–T5) |
| `riscv/PROGRAM_TEST.sv` | Интеграционный тест (UART bit-bang) |
| `riscv/TODO_DEBUG_FIX.md` | История: переход на pause/paused протокол |
| `riscv/tools/riscv_tester.py` | Python UART тестер |
| `riscv/TOP.sv` | Интеграция: bus mux, FIFO, passthrough |
| `riscv/CPU/CPU_PIPELINE_ADAPTER.sv` | Pipeline с pause/paused для debug |
