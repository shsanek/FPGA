# UART подсистема

Полный UART-стек проекта: от физических сигналов до интеграции в CPU.

---

## Архитектура

```
                      ┌─────────────────────────────────┐
    uart_rx (A9) ───→ │ SIMPLE_UART_RX                  │
                      │   2-FF sync + mid-bit sampling   │
                      │   rx_data[7:0], rx_valid (pulse) │
                      └──────────┬──────────────────────┘
                                 │
                      ┌──────────▼──────────────────────┐
                      │ RX FIFO (UART_FIFO, DEPTH=4)    │
                      │   При переполнении байт теряется │
                      └──────────┬──────────────────────┘
                                 │
                      ┌──────────▼──────────────────────┐
                      │ DEBUG_CONTROLLER                 │
                      │   cmd 0x01–0x07 → debug FSM      │
                      │   остальное → CPU passthrough     │
                      └──┬───────────────────────┬──────┘
                         │ tx_byte/tx_valid       │ cpu_rx_byte
                         │                        │ cpu_rx_valid
                      ┌──▼──────────────────────┐ │
                      │ TX FIFO (UART_FIFO, D=4)│ │
                      │   При переполнении пропуск│ │
                      └──┬──────────────────────┘ │
                         │                        ▼
                      ┌──▼──────────────────────┐ UART_IO_DEVICE
                      │ I_O_OUTPUT_CONTROLLER    │ (memory-mapped)
                      │   LSB-first, 8N1         │
                      └──┬──────────────────────┘
                         │
    uart_tx (D10) ◀──────┘
```

---

## Модули

### SIMPLE_UART_RX

**Файл:** `riscv/SIMPLE_UART_RX.sv`

Надёжный UART-приёмник с 2-FF синхронизатором.

**Параметры:**

| Параметр | Default | Описание |
|----------|---------|----------|
| CLOCK_FREQ | 81_250_000 | Частота тактового сигнала (Гц) |
| BAUD_RATE | 115_200 | Скорость UART (бод) |

**Интерфейс:**

| Сигнал | Нап. | Описание |
|--------|------|----------|
| clk | in | Тактовый сигнал |
| reset | in | Синхронный сброс |
| rx | in | Физическая UART линия |
| rx_data[7:0] | out | Принятый байт |
| rx_valid | out | 1-тактовый импульс: байт готов |

**Внутренние состояния:**

| Состояние | Описание |
|-----------|----------|
| S_IDLE | Ожидание start-бита (LOW) |
| S_START | Ждёт HALF_BIT тактов, проверяет что start-бит ещё LOW |
| S_DATA | Сэмплирует 8 бит через BIT_PERIOD тактов, LSB first |
| S_STOP | Ждёт stop-бит (HIGH). Если HIGH → rx_valid=1 |

**Особенности:**
- Mid-bit sampling: отсчитывает HALF_BIT от start-бита, потом BIT_PERIOD между битами
- Защита от ложного срабатывания: если start-бит исчез к середине → S_IDLE
- Биты записываются по индексу `shift[bit_idx]` (не сдвиговый регистр), порядок гарантирован

---

### I_O_OUTPUT_CONTROLLER

**Файл:** `riscv/I_O/OUTPUT_CONTROLLER/I_O_OUTPUT_CONTROLLER.sv`

UART-передатчик. Формат: 1 start + 8 data (LSB first) + 1 stop.

**Параметры:**

| Параметр | Default | Описание |
|----------|---------|----------|
| CLOCK_FREQ | 100_000_000 | Частота тактового сигнала |
| BAUD_RATE | 115_200 | Скорость UART |
| BIT_PERIOD | CLOCK_FREQ/BAUD_RATE | Тактов на бит |

**Интерфейс:**

| Сигнал | Нап. | Описание |
|--------|------|----------|
| clk, reset | in | Такт и сброс |
| io_output_value[7:0] | in | Байт для отправки |
| io_output_trigger | in | Импульс: начать передачу |
| io_output_ready_trigger | out | TX свободен (можно слать) |
| RXD | out | Физическая UART линия (выход) |

**Внутренние состояния:**

| Состояние | Описание |
|-----------|----------|
| OUT_WATING_VALUE | Ожидание trigger. ready=1, линия HIGH |
| OUT_START_SIGNAL | Выставляет LOW (start-бит) по `active` от таймера |
| OUT_VALUE | 8 бит LSB-first, каждый по `active`. Сдвиг вправо |
| OUT_END_SIGNAL | Выставляет HIGH (stop-бит), ready=1 |

**Зависимость:** использует `I_O_TIMER_GENERATOR` для генерации тактов BIT_PERIOD.

---

### I_O_TIMER_GENERATOR

**Файл:** `riscv/I_O/I_O_TIMER_GENERATOR.sv`

Делитель частоты. Считает от 0 до BIT_PERIOD-1, выдаёт 1-тактовый импульс `active`.

При 81.25 МГц / 115200 бод = 705 тактов на бит.

---

### UART_FIFO

**Файл:** `riscv/UART_FIFO.sv`

Синхронный FIFO с параметрической глубиной (степень 2).

**Параметры:**

| Параметр | Default | Описание |
|----------|---------|----------|
| DEPTH | 16 | Глубина (степень 2) |
| WIDTH | 8 | Ширина данных |

**Интерфейс:**

| Сигнал | Нап. | Описание |
|--------|------|----------|
| wr_data[WIDTH-1:0] | in | Данные для записи |
| wr_en | in | Запись (если !full) |
| full | out | Буфер полон |
| rd_data[WIDTH-1:0] | out | Данные для чтения (комбинационный) |
| rd_en | in | Подтверждение чтения |
| empty | out | Буфер пуст |

**Поведение при переполнении:** если `wr_en && full` — байт пропускается (не записывается).

**Реализация:** кольцевой буфер с указателями wr_ptr и rd_ptr шириной ADDR_BITS+1 (MSB для детекции full/empty).

---

## Интеграция в TOP.sv

### RX-путь (UART → CPU)

```
uart_rx pin
  → SIMPLE_UART_RX (raw_rx_byte, raw_rx_valid)
  → RX FIFO (DEPTH=4): буферизация, при переполнении байт теряется
  → Логика чтения с backpressure: pop только если rx_ready || head==0xFD
  → DEBUG_CONTROLLER (uart_rx_byte, uart_rx_valid, rx_ready)
```

**Логика чтения из RX FIFO (valid/ready handshake):**
1. FIFO не пуст И DEBUG готов (`rx_ready`) ИЛИ голова = `0xFD` → `rd_en=1`
2. На том же фронте `rd_en=1` — данные захватываются в регистр `rx_fifo_captured`
3. Следующий такт — `rx_fifo_valid_r=1` с корректными данными
4. `0xFD` bypass: голова FIFO (`rd_data`, комбинационный) сравнивается с `0xFD` — попается даже при `rx_ready=0`

### TX-путь (CPU → UART)

```
UART_IO_DEVICE (cpu_tx_byte, cpu_tx_valid — уровень, cpu_tx_ready)
  → DEBUG_CONTROLLER: добавляет заголовок 0xBB (S_IDLE → S_CPU_TX)
  → TX FIFO (DEPTH=4): буферизация, при переполнении байт теряется
  → Логика чтения: rd_en → захват в регистр → trigger на след. такт
  → I_O_OUTPUT_CONTROLLER (raw_tx_byte, raw_tx_valid)
  → uart_tx pin
```

**TX ready:** DEBUG_CONTROLLER видит `uart_tx_ready = !tx_fifo_full`.

**Блокирующий TX в UART_IO_DEVICE:** запись в TX_DATA опускает `controller_ready=0`. CPU pipeline стоит пока байт не будет принят DEBUG_CONTROLLER'ом и отправлен. FSM: `TX_IDLE → TX_WAIT_ACCEPT → TX_WAIT_DONE → TX_IDLE`.

### Интерфейсы (сводка)

| Граница | Направление | valid | ready | Тип |
|---------|------------|-------|-------|-----|
| RX FIFO → DEBUG | RX | импульс | `rx_ready` + FD bypass | valid/ready |
| DEBUG → UART_IO | RX (CPU input) | импульс | нет (fire-and-forget) | push |
| UART_IO → DEBUG | TX (CPU output) | уровень | `cpu_tx_ready` | valid/ready |
| DEBUG → TX FIFO | TX | импульс | `!tx_fifo_full` | valid/ready |

---

## Параметры для Arty A7-100

| Параметр | Значение |
|----------|----------|
| Частота CPU | 81.25 МГц |
| Baud rate | 115200 |
| BIT_PERIOD | 705 тактов |
| Формат | 8N1 (8 бит, без чётности, 1 стоп-бит) |
| UART TX пин | D10 (LVCMOS33) |
| UART RX пин | A9 (LVCMOS33) |
| Интерфейс к PC | FTDI USB-Serial |
| RX FIFO глубина | 4 байта |
| TX FIFO глубина | 4 байта |

---

## Файлы

| Файл | Описание |
|------|----------|
| `riscv/SIMPLE_UART_RX.sv` | UART приёмник (2-FF sync, mid-bit sampling) |
| `riscv/I_O/OUTPUT_CONTROLLER/I_O_OUTPUT_CONTROLLER.sv` | UART передатчик |
| `riscv/I_O/I_O_TIMER_GENERATOR.sv` | Таймер бит-периода |
| `riscv/UART_FIFO.sv` | Параметрический синхронный FIFO |
| `riscv/I_O/INPUT_CONTROLLER/I_O_INPUT_CONTROLLER.sv` | Старый UART RX (с аккумулятором, не используется в TOP) |
| `riscv/UART_ECHO_TOP.sv` | Тестовый echo-модуль (без CPU/DDR) |
| `riscv/TOP.sv` | Интеграция: RX/TX FIFO + DEBUG_CONTROLLER |
| `test_uart_echo.py` | Python-тест: базовый echo |
| `test_uart_buffer.py` | Python-тест: стресс-тест буфера |

---

## Тестирование

### Симуляция (xsim)

UART тестируется в составе PROGRAM_TEST — debug-протокол отправляет байты через UART bit-bang, загружает программу в память, запускает CPU.

### Аппаратное (на Arty A7)

1. **Echo-тест** (`test_uart_echo.py`): прошить `UART_ECHO_TOP`, отправить байты, проверить что возвращаются.
2. **Buffer stress-тест** (`test_uart_buffer.py`): burst-пакеты, переполнение, полный диапазон 0x00–0xFF.

```bash
# Собрать и прошить echo
vivado -mode batch -source vivado/build_echo.tcl

# Запустить тесты
python test_uart_echo.py
python test_uart_buffer.py
```
