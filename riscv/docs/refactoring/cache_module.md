# Универсальный кэш-модуль (CACHE_CONTROLLER)

Единый модуль для I-cache и D-cache (будущий MEMORY_CONTROLLER).
Одинаковый интерфейс на каждом уровне иерархии — composable cache hierarchy.

## Цель

- Подготовка к 5-stage pipeline и 200 MHz (5ns signal path)
- Унификация I_CACHE и MEMORY_CONTROLLER в один модуль
- Подготовка к multi-core (MEMORY_MUX с N портами)

## Архитектура памяти (целевая)

```
              ┌──────────────────────────────────┐
              │           CPU CORE 0             │
              │                                  │
              │  ┌───────────┐  ┌───────────┐    │
              │  │  IF stage │  │ MEM stage │    │
              │  └─────┬─────┘  └─────┬─────┘    │
              │        │              │          │
              │   ┌────┴────┐         │          │
              │   │ I_CACHE │         │          │
              │   │ (0-clk  │         │          │
              │   │  hit)   │         │          │
              │   └──┬───┬──┘         │          │
              │  hit │   │ miss       │          │
              │   ↓  │   │            │          │
              │  CPU │   │            │          │
              └──────┼───┼────────────┼──────────┘
                     │   │            │
                     │   │      ┌─────┴──────────────┐
                     │   │      │  PERIPHERAL_BUS    │
                     │   │      │  addr[29:28]=01→IO │
                     │   │      │  addr[29:28]=00→↓  │
                     │   │      └─────┬──────────────┘
                     │   │            │
                     │   │  128-bit   │  32-bit (data r/w)
                     │   │  line fill │
                     │   │  +stream   │
                     │   │            │
                ┌────┴───┴────────────┴──────────┐
                │        MEMORY_MUX              │
                │  (арбитр, N портов)            │
                │                                │
                │  port0: PERIPHERAL_BUS (D, rw) │
                │  port1: I_CACHE miss (stream)  │
                │  port2: Core1 I_CACHE (future) │
                └───────────────┬────────────────┘
                                │
                                │  read_stream=1 для I-path
                                │  read_stream=0 для D-path
                                │
                ┌───────────────┴────────────────┐
                │      MEMORY_CONTROLLER         │
                │      (CACHE_CONTROLLER         │
                │       READ_ONLY=0)             │
                │                                │
                │  ┌────────────┐                │
                │  │  D_CACHE   │                │
                │  │ (256 lines)│                │
                │  └────────────┘                │
                │                                │
                │  read_stream=1 → bypass cache  │
                │  read_stream=0 → normal D-path │
                └───────────────┬────────────────┘
                                │
                ┌───────────────┴────────────────┐
                │       DDR_CONTROLLER           │
                │      (MIG / DDR3 PHY)          │
                └───────────────┬────────────────┘
                                │
                          ┌─────┴─────┐
                          │   DDR3    │
                          │  256 MB   │
                          └───────────┘
```

### MEMORY_CONTROLLER

Содержит D_CACHE (CACHE_CONTROLLER, READ_ONLY=0).

Два режима работы по `read_stream`:
- **read_stream=0** (D-path): обычный путь — проверка D_CACHE, miss → evict/fill
- **read_stream=1** (I-path): bypass D_CACHE — сразу в DDR_CONTROLLER, данные возвращаются
  без записи в кэш

---

## MEMORY_MUX

Арбитр с `NUM_PORTS` входами. Мультиплексирует несколько master-портов
(PERIPHERAL_BUS, I_CACHE miss, ...) в один slave-порт (MEMORY_CONTROLLER).

### Интерфейс

```
module MEMORY_MUX #(
    parameter NUM_PORTS = 2,
    parameter ADDRESS_SIZE = 28,
    parameter LINE_SIZE = 128,
    parameter MASK_SIZE = 16
)(
    input wire clk,
    input wire reset,

    // === Upstream: N master-портов (от шины, от I_CACHE, ...) ===

    // port[i] → MUX
    input  wire [NUM_PORTS-1:0]                  port_command_read,   // пульс: read request
    input  wire [NUM_PORTS-1:0]                  port_command_write,  // пульс: write request
    input  wire [NUM_PORTS*ADDRESS_SIZE-1:0]     port_address,        // packed array
    input  wire [NUM_PORTS*MASK_SIZE-1:0]        port_write_mask,
    input  wire [NUM_PORTS*LINE_SIZE-1:0]        port_write_value,
    input  wire [NUM_PORTS-1:0]                  port_read_stream,    // 1 = bypass cache

    // MUX → port[i]
    output wire [NUM_PORTS-1:0]                  port_ready,          // 1 = порт может слать
    output wire [NUM_PORTS*LINE_SIZE-1:0]        port_read_value,     // данные ответа
    output wire [NUM_PORTS-1:0]                  port_read_valid,     // пульс: read done
    output wire [NUM_PORTS-1:0]                  port_write_done,     // пульс: write done

    // === Downstream: 1 slave-порт (к MEMORY_CONTROLLER) ===

    // MUX → MEMORY_CONTROLLER
    output wire [ADDRESS_SIZE-1:0]               mem_address,
    output wire [1:0]                            mem_command,         // 00/01/10
    output wire                                  mem_read_stream,
    output wire [MASK_SIZE-1:0]                  mem_write_mask,
    output wire [LINE_SIZE-1:0]                  mem_write_value,

    // MEMORY_CONTROLLER → MUX
    input  wire                                  mem_ready,
    input  wire [LINE_SIZE-1:0]                  mem_read_value,
    input  wire                                  mem_read_valid,
    input  wire                                  mem_write_done
);
```

### Snoop-порт к I_CACHE

При записи от PERIPHERAL_BUS (port0 write) MEMORY_MUX параллельно отправляет
snoop в I_CACHE — «обнови если есть, игнорируй если нет».

```
    // === Snoop: MEMORY_MUX → I_CACHE (параллельно с основным потоком) ===

    // Для каждого I-порта (port1, port2, ...):
    output wire                                  icache_snoop_valid,  // пульс 1 такт
    output wire [ADDRESS_SIZE-1:0]               icache_snoop_address,
    output wire [MASK_SIZE-1:0]                  icache_snoop_mask,
    output wire [LINE_SIZE-1:0]                  icache_snoop_value
```

Snoop — **fire-and-forget**: MUX не ждёт ответа, I_CACHE обрабатывает за 1 такт.

I_CACHE при получении snoop:
- **Hit:** byte-masked update линии (та же логика что WRITE_CACHE, но без FSM)
- **Miss:** игнорирует (нет такой инструкции в кэше — нечего обновлять)

Snoop срабатывает **одновременно** с пробросом write в MEMORY_CONTROLLER —
не добавляет тактов, не блокирует основной поток.

### Конфигурация портов

| Порт | Источник | read_stream | Snoop target | Описание |
|------|----------|-------------|--------------|----------|
| 0 | PERIPHERAL_BUS | 0 (hardwired) | — | Data read/write → D_CACHE |
| 1 | Core0 I_CACHE miss | 1 (hardwired) | Core0 I_CACHE | Instruction line fill |
| 2+ | Core1+ I_CACHE miss | 1 (hardwired) | Core1+ I_CACHE | Future multi-core |

### Внутренние регистры

```
active_port[$clog2(NUM_PORTS)-1:0]  // какой порт сейчас обслуживается
busy                                 // 1 = ждём ответ от MEMORY_CONTROLLER
```

### FSM

```
         ┌─────────┐
    ┌───►│  IDLE   │◄──────────────────────────────┐
    │    │         │                                │
    │    │ scan    │  busy=0                        │
    │    │ ports   │  port_ready[all]=mem_ready     │
    │    │ by pri  │                                │
    │    └────┬────┘                                │
    │         │ port[i] has command                  │
    │         │ && mem_ready                         │
    │         ▼                                     │
    │    ┌─────────┐                                │
    │    │  ACTIVE │                                │
    │    │         │  busy=1                        │
    │    │ forward │  port_ready[all]=0             │
    │    │ cmd to  │  active_port=i                 │
    │    │ mem_*   │                                │
    │    └────┬────┘                                │
    │         │                                     │
    │         │ mem_read_valid || mem_write_done     │
    │         ▼                                     │
    │    ┌─────────┐                                │
    │    │  DONE   │                                │
    │    │         │  route response to port[i]     │
    │    │ forward │  port_read_valid[i]=1          │
    │    │ resp to │  or port_write_done[i]=1       │
    └────┤ port[i] │                                │
         └─────────┘  → IDLE (next cycle)           │
                                                    │
         0-cycle path (mem responds same cycle):    │
         ACTIVE can go directly to DONE ────────────┘
```

### IDLE — арбитрация

```
Приоритет: port0 > port1 > port2 > ...

if mem_ready:
    port_ready[all] = 1     // все порты видят ready
                             // (только один должен слать command)

    // Сканируем по приоритету
    for i = 0 to NUM_PORTS-1:
        if port_command_read[i] || port_command_write[i]:
            active_port <= i
            busy <= 1

            // Пробрасываем в MEMORY_CONTROLLER
            mem_address     <= port_address[i]
            mem_command     <= {port_command_write[i], port_command_read[i]}
            mem_read_stream <= port_read_stream[i]
            mem_write_mask  <= port_write_mask[i]
            mem_write_value <= port_write_value[i]

            // === SNOOP: write от port0 → уведомляем все I_CACHE ===
            if port_command_write[i] && (i == 0):
                icache_snoop_valid   <= 1
                icache_snoop_address <= port_address[0]
                icache_snoop_mask    <= port_write_mask[0]
                icache_snoop_value   <= port_write_value[0]

            // Блокируем все порты
            port_ready[all] <= 0

            state <= ACTIVE
            break
else:
    port_ready[all] = 0     // MEMORY_CONTROLLER занят
```

### ACTIVE — ожидание ответа

```
// Command уже отправлен, ждём ответ
mem_command <= 2'b00        // снимаем command (был пульс 1 такт)

if mem_read_valid:
    port_read_value[active_port] <= mem_read_value
    port_read_valid[active_port] <= 1
    state <= IDLE
    busy <= 0

if mem_write_done:
    port_write_done[active_port] <= 1
    state <= IDLE
    busy <= 0
```

### Timing

| Операция | Overhead MUX | Примечание |
|----------|-------------|------------|
| Проброс command | **0 тактов** | Комбинационный в IDLE (same cycle forward) |
| Проброс response | **0 тактов** | Комбинационный routing ответа в порт |
| Арбитрация | **0 тактов** | Priority encoder — комбинационный |
| **Итого MUX overhead** | **0 тактов** | Прозрачный pass-through |

MUX не добавляет тактов — только удлиняет комбинационный путь (gate delay).
При необходимости можно добавить pipeline register (1 такт), но для 200 MHz
priority encoder + mux на 2-3 порта укладывается в 5ns.

### Гарантии

- **Один запрос за раз:** пока `busy=1`, все `port_ready=0` — никто не шлёт новый command
- **Ответ маршрутизируется:** `port_read_valid` / `port_write_done` поднимается только
  для `active_port`
- **Приоритет D-cache:** port0 (data) обслуживается первым — write-back eviction
  не должен ждать I-cache fill
- **Fairness:** для 2 портов приоритет достаточен; для N>2 можно добавить round-robin

## Внешний интерфейс

Единый интерфейс CACHE_CONTROLLER ↔ следующий уровень:

```
// Адрес (общий для read/write)
ram_address[27:0]           →   // line-aligned ([3:0] = 0000)

// Управление
controller_ready            ←   // 1 = можно слать command
command[1:0]                →   // 00=nop, 01=read, 10=write (пульс 1 такт)
read_stream                 →   // 1 = bypass cache (не сохранять в кэш)

// Read response
ram_read_value[127:0]       ←   // 128-bit линия
ram_read_value_ready        ←   // пульс 1 такт — данные готовы

// Write request
ram_write_mask[15:0]        →   // byte mask (16 байт = 128 бит)
ram_write_value[127:0]      →   // данные для записи
ram_write_done              ←   // пульс 1 такт — запись завершена
```

## Внутренние регистры

```
output_valid                    // 1 = output buffer содержит валидные данные
output_address[27:0]            // адрес линии в output buffer
output_value[127:0]             // данные линии (= ram_read_value)
current_command[1:0]            // защёлкнутая команда
current_stream                  // защёлкнутый read_stream
```

`output_valid/address/value` — 1-entry line buffer (fast path для повторного доступа к той же линии).

## FSM

```
┌──────────────┐
│ WAIT_REQUEST │◄─────────────────────────────────────────────────┐
│              │                                                  │
│ cmd=00: idle │  controller_ready=1                              │
│              │                                                  │
│ cmd=01: read │                                                  │
│  stream=0:   │                                                  │
│   output_buf │──hit──→ ram_read_value_ready=1 ─────────────────►│
│   hit?       │                                                  │
│              │──miss─→┌─────────────┐                           │
│  stream=1:   │        │ READ_CACHE  │                           │
│   skip cache─────────→│ search tags │                           │
│              │  ▲     │             │──hit──→ update             │
│ cmd=10: write│  │     │             │  output buf ─────────────►│
│   invalidate │  │     │             │  ready=1                  │
│   output_buf │  │     │             │──miss──┐                  │
└──────────────┘  │     └─────────────┘        │                  │
                  │                            ▼                  │
                  │  ┌──────────────────────────────────────┐     │
                  │  │              MISS                     │     │
                  │  │                                       │     │
                  │  │  stream=1:  (short path)              │     │
                  │  │  ┌────────────────┐ ┌──────────────┐ │     │
                  │  │  │ MISS_READ_REQ  │→│MISS_READ_WAIT│─┼────►│
                  │  │  └────────────────┘ └──────────────┘ │ ready=1
                  │  │   (no evict, no save)                 │     │
                  │  │                                       │     │
                  │  │  stream=0:  (full path)               │     │
                  │  │  ┌────────────────┐ ┌──────────────┐ │     │
                  │  │  │MISS_EVICT_REQ  │→│MISS_EVICT_WAIT│ │     │
                  │  │  │(dirty line?)   │ │(ждём done)   │ │     │
                  │  │  └────────────────┘ └──────┬───────┘ │     │
                  │  │   (skip if clean)          │         │     │
                  │  │                            ▼         │     │
                  │  │  ┌────────────────┐ ┌──────────────┐ │     │
                  │  │  │ MISS_READ_REQ  │→│MISS_READ_WAIT│ │     │
                  │  │  └────────────────┘ └──────┬───────┘ │     │
                  │  │                            │         │     │
                  │  │                   ┌────────┴───────┐ │     │
                  │  │                   │  MISS_SAVE     │─┼────►│
                  │  │                   │  save to cache  │ │(→READ_CACHE
                  │  │                   │                 │ │ или
                  │  │                   │                 │ │ WRITE_CACHE)
                  │  │                   └────────────────┘ │
                  │  └──────────────────────────────────────┘
                  │
                  └── WRITE_CACHE: hit→done, miss→MISS (stream=0 always)
```

### WAIT_REQUEST

```
if command == 2'b00:
    controller_ready <= 1
    ram_write_done <= 0
    ram_read_value_ready <= 0

if command == 2'b01 (read):
    controller_ready <= 0
    current_command <= 2'b01
    current_stream <= read_stream

    if read_stream == 1:
        // Stream: bypass cache, сразу в DDR
        state <= MISS_READ_REQ

    else if output_valid && (output_address == ram_address):
        // Output buffer hit (0-cycle)
        ram_read_value_ready <= 1
        controller_ready <= 1
    else:
        ram_read_value_ready <= 0
        state <= READ_CACHE

if command == 2'b10 (write):
    controller_ready <= 0
    current_command <= 2'b10
    current_stream <= 0                 // write всегда через кэш
    if output_valid && (output_address == ram_address):
        output_valid <= 0               // инвалидируем (будем менять)
    state <= WRITE_CACHE
```

### READ_CACHE

Поиск в кэше (tags + valid):
- **Hit:** обновить output buffer, `ram_read_value_ready <= 1` → WAIT_REQUEST
- **Miss:** → MISS_EVICT_REQ (или MISS_READ_REQ если clean)

### WRITE_CACHE

Поиск в кэше:
- **Hit:** byte-masked запись, `ram_write_done <= 1` → WAIT_REQUEST
- **Miss:** → MISS_EVICT_REQ (или MISS_READ_REQ если clean)

### MISS substates

```
// === Stream path (read_stream=1): short ===

MISS_READ_REQ:      // выставляем read request к DDR
MISS_READ_WAIT:     // ждём ram_read_value_ready
    if current_stream:
        // Данные сразу в output — НЕ сохраняем в кэш
        ram_read_value_ready <= 1 → WAIT_REQUEST

// === Normal path (read_stream=0): full ===

MISS_EVICT_REQ:     // выставляем write request к DDR (dirty line)
    если линия clean → пропускаем, сразу MISS_READ_REQ
MISS_EVICT_WAIT:    // ждём ram_write_done от нижнего уровня

MISS_READ_REQ:      // выставляем read request к DDR
MISS_READ_WAIT:     // ждём ram_read_value_ready от нижнего уровня

MISS_SAVE:          // сохраняем новую линию в кэш
    if current_command == 2'b01 → READ_CACHE  (теперь будет hit)
    if current_command == 2'b10 → WRITE_CACHE (теперь будет hit)
```

## Latency (в тактах)

| Сценарий | Такты | Примечание |
|----------|-------|------------|
| Output buffer hit (read) | **0** | Комбинационный, тот же такт |
| Cache hit (read) | **2** | WAIT→READ_CACHE→WAIT |
| Cache hit (write) | **2** | WAIT→WRITE_CACHE→WAIT |
| **Stream read (I-cache miss)** | **N+2** | **WAIT→READ_REQ→READ_WAIT(N)→WAIT** |
| Miss (clean, D-cache) | **N+4** | READ_REQ→READ_WAIT(N)→SAVE→R/W_CACHE→WAIT |
| Miss (dirty evict, D-cache) | **2N+6** | EVICT_REQ→EVICT_WAIT(N)→READ_REQ→READ_WAIT(N)→SAVE→R/W_CACHE |

N = latency нижнего уровня (DDR_CONTROLLER → MIG).

### Stream vs Normal miss

| | Normal miss (D-path) | Stream miss (I-path) |
|-|---------------------|---------------------|
| Проверка кэша | Да (READ_CACHE) | Нет (skip) |
| Evict dirty | Да (если dirty) | Нет |
| Сохранение в кэш | Да (MISS_SAVE) | Нет |
| Повторный поиск | Да (R/W_CACHE) | Нет |
| **Состояний** | **5-7** | **2** |

## Для IF (sequential fetch)

4 слова в линии → 3 из 4 = output buffer hit (0 clk), 1 из 4 = cache hit (2 clk).
Среднее: **(3×0 + 1×2) / 4 = 0.5 clk/IF**.

При 200 MHz: 0.5 × 5ns = **2.5ns average** (vs текущие 0 × 25ns = 0ns при 40 MHz).

## Параметры модуля

```systemverilog
module CACHE_CONTROLLER #(
    parameter DEPTH = 256,          // кол-во линий кэша
    parameter READ_ONLY = 0,        // 1 = I-cache (no dirty/evict)
    parameter ADDRESS_SIZE = 28,
    parameter LINE_SIZE = 128       // 128-bit линия = 16 байт
)(
    // ... unified interface (включая read_stream)
);
```

## Отличия I-cache vs D-cache (через параметр)

| | I-cache (READ_ONLY=1) | D-cache (READ_ONLY=0) |
|-|----------------------|----------------------|
| Write command | Игнорируется | Byte-masked запись |
| Dirty tracking | Нет | Да |
| MISS_EVICT | Пропускается всегда | Только если dirty |
| Snoop порт | Да (от MEMORY_MUX) | Нет (сам обрабатывает write) |
| Типичный DEPTH | 1024 (16 KB) | 256 (4 KB) |

## I_CACHE — snoop-порт

I_CACHE (на ядре) имеет дополнительный входной порт для snoop от MEMORY_MUX:

```
// Snoop input (от MEMORY_MUX, параллельно основному потоку)
input  wire                      snoop_valid,
input  wire [ADDRESS_SIZE-1:0]   snoop_address,
input  wire [MASK_SIZE-1:0]      snoop_mask,
input  wire [LINE_SIZE-1:0]      snoop_value
```

### Обработка (1 такт, параллельно с основной FSM)

```
always_ff @(posedge clk) begin
    if (snoop_valid) begin
        snoop_idx = snoop_address[INDEX_W+3 : 4];
        snoop_tag = snoop_address[ADDRESS_SIZE-1 : INDEX_W+4];

        if (valid[snoop_idx] && tags[snoop_idx] == snoop_tag) begin
            // HIT: byte-masked update (та же логика что write)
            lines[snoop_idx] <= apply_mask(lines[snoop_idx], snoop_value, snoop_mask, snoop_address[3:2]);
        end
        // MISS: ничего не делаем — нет такой инструкции в кэше
    end
end
```

### Почему это безопасно

- **Нет гонок:** snoop пишет в I_CACHE, основная FSM только читает (read-only cache).
  Единственный другой писатель — fill при miss, но fill и snoop не могут быть одновременно
  на одном index (fill блокирует CPU → нет новых store → нет snoop).
- **Fire-and-forget:** MUX не ждёт ответа. Если snoop miss — ничего страшного,
  данных в I_CACHE не было, когерентность не нарушена.
- **Self-modifying code:** если программа пишет в область кода, I_CACHE обновляется
  автоматически через snoop. Без snoop пришлось бы делать fence.i.

## Использование read_stream

| Источник запроса | read_stream | Поведение в MEMORY_CONTROLLER |
|-----------------|-------------|-------------------------------|
| PERIPHERAL_BUS (data) | 0 | Обычный D-cache path |
| I_CACHE miss (Core0) | 1 | Bypass D_CACHE → DDR → ответ (не pollution) |
| I_CACHE miss (Core1) | 1 | То же (future) |

MEMORY_MUX автоматически выставляет `read_stream=1` для I-портов.
