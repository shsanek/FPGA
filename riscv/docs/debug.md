# DEBUG_CONTROLLER

Отладочный контроллер RISC-V CPU. Принимает команды через байтовый интерфейс (UART),
управляет CPU (halt/resume/step), читает/пишет память, доставляет данные в CPU.

**Файл:** `riscv/CPU/DEBUG_CONTROLLER.sv`

---

## Протокол

### Команды (хост → FPGA)

Little-endian, фиксированные пакеты. Весь диапазон 0x01–0x07 — debug-команды.
Байты вне этого диапазона (кроме 0xFD) — passthrough в CPU.

| Код | Команда | Payload → FPGA | Размер | Описание |
|-----|---------|----------------|--------|----------|
| 0x01 | HALT | — | 0 | Остановить CPU |
| 0x02 | RESUME | — | 0 | Возобновить CPU |
| 0x03 | STEP | — | 0 | Один шаг CPU |
| 0x04 | READ_MEM | ADDR[4B] | 4 | Чтение 32-бит слова |
| 0x05 | WRITE_MEM | ADDR[4B] + DATA[4B] | 8 | Запись 32-бит слова |
| 0x06 | INPUT | DATA[1B] | 1 | Доставить байт в CPU |
| 0x07 | RESET_PC | ADDR[4B] | 4 | Установить PC на адрес |
| 0xFD | SYNC_RESET | — | 0 | Сброс FSM (см. ниже) |

Все payload — little-endian.

### Ответы (FPGA → хост)

Каждый ответ начинается с **1-байтового заголовка** — тип пакета:

| Заголовок | Значение | Формат пакета |
|-----------|----------|---------------|
| `0xAA` | Debug-ответ | `0xAA` CMD CMD [DATA...] |
| `0xBB` | CPU UART вывод | `0xBB` BYTE |

#### Debug-ответ (`0xAA`)

```
0xAA  CMD  CMD  [DATA...]
 │     │    │      └── 0, 4 или 8 байт данных (зависит от команды)
 │     └────┘── ACK: код команды × 2
 └── заголовок
```

| Команда | Данные после ACK |
|---------|-----------------|
| HALT (0x01) | — |
| RESUME (0x02) | — |
| STEP (0x03) | PC[7:0] PC[15:8] PC[23:16] PC[31:24] INSTR[7:0] INSTR[15:8] INSTR[23:16] INSTR[31:24] (8 байт) |
| READ_MEM (0x04) | DATA[7:0] DATA[15:8] DATA[23:16] DATA[31:24] (4 байта) |
| WRITE_MEM (0x05) | — |
| INPUT (0x06) | — |
| RESET_PC (0x07) | — |

#### CPU UART вывод (`0xBB`)

```
0xBB  BYTE
 │     └── байт от CPU (через UART_IO_DEVICE)
 └── заголовок
```

Хост читает первый байт: `0xAA` → debug-ответ, `0xBB` → данные от программы CPU.

### SYNC_RESET (0xFD)

Псевдо-команда вне основного pipeline. Принимается **параллельно** из любого состояния, кроме `S_RECV` (где 0xFD может быть частью payload). Сбрасывает FSM:

- `state → S_IDLE`
- `bus_request → 0` (CPU продолжает)
- `halt → 0`
- `mc_read/write → 0`

**Не шлёт ACK.** Используется при рассинхроне: хост шлёт `0xFD` и контроллер возвращается в чистое состояние.

**FIFO bypass:** TOP.sv подглядывает в голову RX FIFO (`rd_data` комбинационный). Если голова = `0xFD`, FIFO попается даже при `rx_ready=0`. Это гарантирует что SYNC_RESET дойдёт до DEBUG даже когда тот заблокирован.

---

## Параметры

| Параметр | Default | Описание |
|----------|---------|----------|
| DEBUG_ENABLE | 1 | 1 = полная логика, 0 = заглушка (все выходы = 0) |
| ADDRESS_SIZE | 28 | Ширина адреса шины |
| DATA_SIZE | 32 | Ширина данных |
| MASK_SIZE | DATA_SIZE/8 | Ширина маски байт |

При `DEBUG_ENABLE=0` модуль синтезируется в заглушку — `cpu_tx_ready=1`, все остальные выходы = 0.

---

## Интерфейс

### Байтовый RX/TX (от/к UART FIFO)

| Сигнал | Нап. | Ширина | Описание |
|--------|------|--------|----------|
| rx_byte | in | 8 | Принятый байт |
| rx_valid | in | 1 | 1-тактовый импульс: новый байт |
| rx_ready | out | 1 | DEBUG готов принять (backpressure на FIFO) |
| tx_byte | out | 8 | Байт для отправки |
| tx_valid | out | 1 | 1-тактовый импульс: отправить |
| tx_ready | in | 1 | TX свободен |

`rx_ready = (state == S_IDLE) || (state == S_RECV)` — DEBUG принимает байты только в этих состояниях. Исключение: `0xFD` (SYNC_RESET) проходит через FIFO bypass даже при `rx_ready=0` (см. ниже).

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
| mc_dbg_read_trigger | out | 1 | Триггер чтения (уровень) |
| mc_dbg_write_trigger | out | 1 | Триггер записи (уровень) |
| mc_dbg_write_data | out | DATA_SIZE | Данные для записи |
| mc_dbg_read_data | in | DATA_SIZE | Прочитанные данные |
| mc_dbg_ready | in | 1 | Bus завершил операцию |

### CPU passthrough

| Сигнал | Нап. | Ширина | Описание |
|--------|------|--------|----------|
| cpu_rx_byte | out | 8 | Байт для CPU (из INPUT или passthrough) |
| cpu_rx_valid | out | 1 | 1-тактовый импульс |
| cpu_tx_byte | in | 8 | Байт от CPU для отправки |
| cpu_tx_valid | in | 1 | CPU хочет отправить |
| cpu_tx_ready | out | 1 | DEBUG готов забрать байт (комбинационно) |

`cpu_tx_ready = (state == S_IDLE) && tx_ready && !tx_valid_r`

---

## Внутренние состояния (FSM)

### Pipeline

```
S_IDLE → [S_RECV] → S_PAUSE_WAIT → S_EXEC → [S_MEM_WAIT]
                                                   │
                         ┌─────────────────────────┘
                         ▼
                    S_SEND_HDR → S_SEND_ACK1 → S_SEND_ACK2 → [S_SEND_DATA] → S_IDLE
```

CPU TX (параллельный путь):
```
S_IDLE → S_CPU_TX → S_IDLE
 (0xBB)   (byte)
```

### Описание состояний

| Состояние | Описание |
|-----------|----------|
| **S_IDLE** | `rx_ready=1`. Ждёт `rx_valid`. Debug-команды (0x01–0x07) → pipeline. Остальные → CPU passthrough. CPU TX → `0xBB` + байт (через S_CPU_TX). |
| **S_RECV** | `rx_ready=1`. Приём payload побайтно: первые 4 → `payload_addr`, следующие 4 → `payload_data` (little-endian). 0xFD здесь — данные, не сброс. |
| **S_PAUSE_WAIT** | `rx_ready=0`. `bus_request=1`. Ждёт `dbg_bus_granted`. |
| **S_EXEC** | Диспатч по cmd. Для READ/WRITE_MEM → `S_MEM_WAIT`. Для остальных → `S_SEND_HDR`. |
| **S_MEM_WAIT** | Ждёт `mc_dbg_ready`. Сбрасывает trigger. Для READ_MEM → сохраняет данные в resp. → `S_SEND_HDR` |
| **S_SEND_HDR** | Отправляет `0xAA` (заголовок debug-ответа). → `S_SEND_ACK1` |
| **S_SEND_ACK1** | Отправляет 1-й байт ACK (код команды). → `S_SEND_ACK2` |
| **S_SEND_ACK2** | Отправляет 2-й байт ACK (код команды). Если resp_len > 0 → `S_SEND_DATA`, иначе завершение. |
| **S_SEND_DATA** | Побайтная отправка `resp[0..resp_len-1]`. По завершении — если `cmd != HALT` → `bus_request=0`. → `S_IDLE` |
| **S_CPU_TX** | Отправляет сохранённый байт от CPU. → `S_IDLE` |

---

## Внутренние регистры

| Регистр | Ширина | Описание |
|---------|--------|----------|
| state | 4 | Текущее состояние FSM |
| cmd | 8 | Код текущей команды |
| payload_addr | 32 | Адрес из payload (little-endian) |
| payload_data | 32 | Данные из payload (little-endian) |
| byte_idx | 3 | Счётчик принятых байт payload |
| resp[0:7] | 8×8 | Буфер данных ответа (до 8 байт) |
| resp_len | 4 | Длина данных (0 = нет) |
| resp_idx | 4 | Индекс текущего отправляемого байта |
| halt_r | 1 | Halt (уровень) |
| step_r | 1 | Step (импульс, auto-clear) |
| set_pc_r | 1 | Set PC (импульс, auto-clear) |
| new_pc_r | 32 | Новый PC |
| bus_request_r | 1 | Bus request (уровень) |
| mc_addr_r | ADDRESS_SIZE | Адрес для bus |
| mc_data_r | DATA_SIZE | Данные для записи |
| mc_read_r | 1 | Триггер чтения (уровень) |
| mc_write_r | 1 | Триггер записи (уровень) |
| tx_byte_r | 8 | TX байт |
| tx_valid_r | 1 | TX valid (импульс, auto-clear) |
| cpu_rx_byte_r | 8 | Байт для CPU |
| cpu_rx_valid_r | 1 | CPU RX valid (импульс, auto-clear) |
| cpu_tx_saved | 8 | Сохранённый CPU TX байт (для S_CPU_TX) |

**Auto-clear:** `tx_valid_r`, `step_r`, `set_pc_r`, `cpu_rx_valid_r`.

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
- `pipeline_paused=1` → debug владеет bus
- `pipeline_paused=0` → pipeline владеет bus
- `mc_dbg_ready = pipeline_paused ? bus_ready : 0`

---

## Протокол каждой команды

### HALT (0x01)
1. `bus_request=1` → ждём `granted`
2. `halt_r=1`, `bus_request` остаётся 1
3. Ответ: `0xAA 0x01 0x01`

### RESUME (0x02)
1. `bus_request=1` → ждём `granted`
2. `halt_r=0`
3. Ответ: `0xAA 0x02 0x02`
4. `bus_request=0` — CPU продолжает

### STEP (0x03)
1. `bus_request=1` → ждём `granted`
2. `step_r=1` (импульс), захват PC и INSTR
3. Ответ: `0xAA 0x03 0x03` + PC[4B] + INSTR[4B]

### READ_MEM (0x04)
1. Приём ADDR[4B]
2. `bus_request=1` → ждём `granted`
3. `mc_read_r=1` → ждём `mc_dbg_ready`
4. Ответ: `0xAA 0x04 0x04` + DATA[4B]
5. Если `!halt` → `bus_request=0`

### WRITE_MEM (0x05)
1. Приём ADDR[4B] + DATA[4B]
2. `bus_request=1` → ждём `granted`
3. `mc_write_r=1` → ждём `mc_dbg_ready`
4. Ответ: `0xAA 0x05 0x05`
5. Если `!halt` → `bus_request=0`

### INPUT (0x06)
1. Приём DATA[1B]
2. `bus_request=1` → ждём `granted`
3. `cpu_rx_byte=DATA`, `cpu_rx_valid=1` — байт доставлен в UART_IO_DEVICE
4. Ответ: `0xAA 0x06 0x06`
5. `bus_request=0` — CPU продолжает

### RESET_PC (0x07)
1. Приём ADDR[4B]
2. `bus_request=1` → ждём `granted`
3. `set_pc_r=1`, `new_pc_r=ADDR`
4. Ответ: `0xAA 0x07 0x07`
5. Если `!halt` → `bus_request=0`

### SYNC_RESET (0xFD)
1. Принимается из любого состояния кроме S_RECV
2. FSM → S_IDLE, `bus_request=0`, `halt=0`, triggers=0
3. Без ACK

### CPU UART вывод
1. CPU пишет в UART_IO_DEVICE TX_DATA (0x800_0000)
2. UART_IO_DEVICE: `controller_ready=0`, `cpu_tx_valid=1` (уровень TX_WAIT_ACCEPT)
3. CPU pipeline стоит в S_DATA_WAIT (bus blocked)
4. DEBUG_CONTROLLER (в S_IDLE): принимает байт, шлёт `0xBB` + байт через S_CPU_TX
5. UART_IO_DEVICE: ждёт возврата DEBUG в S_IDLE (TX_WAIT_DONE)
6. `controller_ready=1` — CPU pipeline продолжает

---

## Типичный flow загрузки программы

```
Хост → FPGA                         FPGA → Хост

0x01                                 0xAA 0x01 0x01        (HALT ACK)

0x05 ADDR[4B] DATA[4B]              0xAA 0x05 0x05        (WRITE_MEM ACK)
0x05 ADDR[4B] DATA[4B]              0xAA 0x05 0x05
...повторить N раз...

0x07 0x00 0x00 0x00 0x00             0xAA 0x07 0x07        (RESET_PC ACK)

0x02                                 0xAA 0x02 0x02        (RESUME ACK)

                                     0xBB 'H'              (CPU output)
                                     0xBB 'e'
                                     0xBB 'l'
                                     0xBB 'l'
                                     0xBB 'o'
```

---

## Тестирование

### Unit-тест: `DEBUG_CONTROLLER_TEST.sv`

| Тест | Команда | Проверка |
|------|---------|----------|
| T1 | HALT | ACK `0xAA 0x01 0x01`, cpu_halted=1 |
| T2 | RESUME | ACK `0xAA 0x02 0x02`, cpu_halted=0 |
| T3 | STEP | ACK + 8 байт: PC + INSTR |
| T4 | READ_MEM addr=0x10 | ACK + 4 байта: 0xCAFEBABE |
| T5 | WRITE_MEM addr=0x20 | ACK, mc_addr=0x20 |
| T6 | RESET_PC addr=0x100 | ACK |
| T7 | INPUT 0xAB | ACK, байт доставлен в CPU |
| T7b | INPUT 0x01 | ACK, CPU не halted (0x01 = данные, не HALT) |
| T8 | SYNC_RESET | FSM → S_IDLE, halt=0, bus_request=0 |
| T9 | 0xFD в S_RECV | Не сбрасывает (принят как payload) |

Стубы:
- **CPU stub:** `cpu_halted` следует за `dbg_halt`
- **MC stub:** `mc_ready` через 3 такта после фронта trigger, `mc_rdata = 0xCAFEBABE`
- **Bus granted:** захардкожен в `1` (pipeline bypass)

---

## Известные особенности

1. **STEP возвращает PC/INSTR до шага.** Значения захватываются в тот же такт, что `step_r=1`.

2. **CPU TX блокирующий.** Запись в TX_DATA блокирует CPU pipeline (`controller_ready=0`) до тех пор, пока DEBUG_CONTROLLER не заберёт байт и не вернётся в S_IDLE. UART_IO_DEVICE FSM: `TX_IDLE → TX_WAIT_ACCEPT → TX_WAIT_DONE → TX_IDLE`.

3. **CPU RX fire-and-forget.** Доставка байта в CPU (`cpu_rx_valid`) — 1-тактовый импульс без backpressure. Если `rx_avail_r=1` (CPU не прочитал предыдущий), новый байт перезапишет старый.

4. **RX backpressure на FIFO.** DEBUG выставляет `rx_ready` только в S_IDLE и S_RECV. RX FIFO не попается пока DEBUG занят. Исключение: байт `0xFD` попается всегда (FIFO head peek bypass).

5. **INPUT останавливает pipeline.** Доставка байта в CPU идёт через стандартный pipeline (pause → exec → ACK).

6. **0xFD в payload.** Если команда ожидает payload, байт 0xFD воспринимается как данные, не как SYNC_RESET. FIFO bypass НЕ активируется в S_RECV (rx_ready=1, попается нормально).

---

## Файлы

| Файл | Описание |
|------|----------|
| `riscv/CPU/DEBUG_CONTROLLER.sv` | Основной модуль |
| `riscv/CPU/DEBUG_CONTROLLER_TEST.sv` | Unit-тест (T1–T9) |
| `riscv/PROGRAM_TEST.sv` | Интеграционный тест (UART bit-bang) |
| `riscv/tools/riscv_tester.py` | Python UART тестер |
| `riscv/TOP.sv` | Интеграция: bus mux, FIFO, passthrough |
| `riscv/CPU/CPU_PIPELINE_ADAPTER.sv` | Pipeline с pause/paused для debug |
