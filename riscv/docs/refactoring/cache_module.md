# Рефакторинг памяти: шина + кэш

## Цель

- Подготовка к 5-stage pipeline и 200 MHz (5ns signal path)
- Стандартная 128-bit шина с единым интерфейсом для всех устройств
- Подготовка к multi-core

## Шина

128 бит данных, 16 бит маска, 32 бит адрес.

### Стандартный slave-интерфейс (9 линий)

```systemverilog
// Request (master → slave)
input  wire [31:0]  bus_address,
input  wire         bus_read,          // пульс 1 такт
input  wire         bus_write,         // пульс 1 такт
input  wire [127:0] bus_write_data,
input  wire [15:0]  bus_write_mask,

// Response (slave → master)
output wire         bus_ready,         // 1 = могу принять команду
output wire [127:0] bus_read_data,
output wire         bus_read_valid,    // пульс 1 такт — данные готовы
```

Протокол:
1. Master проверяет `bus_ready=1`
2. Master поднимает `bus_read` или `bus_write` на 1 такт
3. Write: slave обрабатывает, `bus_ready` вернётся в 1 когда готов
4. Read: slave ставит `bus_read_valid=1` + `bus_read_data` когда данные готовы


## Архитектура (целевая)

```
     ┌──────────────────────────────────────────┐
     │              CPU CORE 0                  │
     │                                          │
     │  ┌──────────┐        ┌──────────┐        │
     │  │ IF stage │        │MEM stage │        │
     │  └────┬─────┘        └────┬─────┘        │
     │       │                   │              │
     │  ┌────┴────┐              │              │
     │  │ I_CACHE │              │              │
     │  │ (MCV2   │              │              │
     │  │  RO=1)  │              │              │
     │  └──────┬──┘              │              │
     │         │ miss            │              │
     │         │ (bus master)    │ (bus master) │
     │         │                 │              │
     │         │  ┌──────────────┴───────────┐  │
     │         └──┤    CORE_BUS_ARBITER      │  │
     │            │  (I_CACHE miss vs MEM)   │  │
     │            │  priority: MEM > I_CACHE │  │
     │            └────────────┬─────────────┘  │
     │                         │ standard bus   │
     └─────────────────────────┼────────────────┘
                               │
                       ┌───────┴──────────┐
                       │  MULTICORE_MUX   │
                       │  (1 core = pass- │
                       │   through,       │
                       │   N cores later) │
                       └───────┬──────────┘
                               │ standard bus (128b data, 32b addr)
                               │
      ┌────────────────────────┴──────────────┐
      │             BUS_DECODER               │
      │         (address decoder)             │
      │                                       │
      │  addr[31:28]=0x0 → MEMORY_CONTROLLER  │
      │  addr[31:28]=0x1 → I/O devices        │
      │  addr[31:28]=0x2 → SCRATCHPAD         │
      │  ...                                  │
      └──┬──────────────┬─────────────────┬───┘
         │              │                 │
         ▼              ▼                 ▼
    ┌──────────┐  ┌──────────┐    ┌──────────────┐
    │  MCV2    │  │ I/O devs │    │  SCRATCHPAD  │
    │ D$+DDR   │  │UART,OLED │    │              │
    │          │  │SD,TIMER  │    │              │
    └────┬─────┘  └──────────┘    └──────────────┘
         │
    ┌────┴─────┐
    │  DDR3    │
    └──────────┘
```

  CPU Core:
    I_CACHE miss ──┐
                   ├── CORE_BUS_ARBITER ── MULTICORE_MUX ── BUS_DECODER
    MEM stage ─────┘                                          ├── MEMORY_CONTROLLER (D$ + DDR)
                                                              ├── UART, OLED, SD, TIMER
                                                              └── SCRATCHPAD

### CORE_BUS_ARBITER (внутри ядра)

Два bus master → один bus port:
- **MEM stage** (load/store) — приоритет (CPU stall на data хуже чем IF stall)
- **I_CACHE miss** (line fill) — ниже приоритет

Использует стандартный bus interface на обоих входах и выходе.

### MULTICORE_MUX

N core bus ports → один bus. Для single-core = pass-through.

### BUS_DECODER

Один master port → N slave ports. Address decoder. Всё на стандартном интерфейсе.

## Устройства на шине (все slave, стандартный интерфейс)

| Устройство | Addr prefix | Описание |
|------------|-------------|----------|
| MEMORY_CONTROLLER (MCV2) | 0x0_______ | D-cache + DDR3 |
| UART | 0x1000____ | Serial I/O |
| OLED | 0x1001____ | PmodOLEDrgb |
| SD | 0x1002____ | PmodMicroSD |
| TIMER | 0x1003____ | Cycle/time counters |
| SCRATCHPAD | 0x1004____ | 128 KB BRAM + Blitter |

Каждое устройство принимает 128-bit bus, но может использовать только нужные байты через mask.
I/O устройства (UART и т.д.) используют только нижние 32 бита — остальное игнорируется.

## MEMORY_CONTROLLER_V2 (slave на шине)

Принимает стандартный bus interface. Содержит D_CACHE (WAYS=1 или 2).

- `bus_read` → проверка D_CACHE → hit: ответ / miss: DDR fetch → fill → ответ
- `bus_write` → проверка D_CACHE → hit: byte-masked write / miss: DDR fetch → fill → write
- `read_stream` убран — I_CACHE miss теперь идёт через ту же шину как обычный read,
  MEMORY_CONTROLLER обрабатывает его через D_CACHE (может быть hit!)

### read_stream больше не нужен

Раньше: I_CACHE miss шёл напрямую в DDR мимо D_CACHE (stream bypass).
Теперь: I_CACHE miss → шина → MEMORY_CONTROLLER → D_CACHE → DDR.

Если D_CACHE содержит нужную линию (data и code в одном адресе) — hit, без DDR.
Если нет — miss, DDR fetch, fill D_CACHE. Инструкции тоже кэшируются в D_CACHE.

Это проще и правильнее: один путь к данным, D_CACHE как unified L2.

## I_CACHE — snoop

При записи через шину в адрес, который есть в I_CACHE, нужна когерентность.
BUS_DECODER при `bus_write` параллельно шлёт snoop в I_CACHE:

```
// BUS_DECODER → I_CACHE (fire-and-forget)
snoop_valid, snoop_address, snoop_mask, snoop_data
```

I_CACHE: hit → update линию, miss → игнорировать.

## MEMORY_CONTROLLER_V2 — текущая реализация

- Параметры: `DEPTH`, `WAYS` (1 или 2), `READ_ONLY`
- 6 состояний FSM: WAIT_REQUEST, READ_CACHE, WRITE_CACHE, MISS_READ_REQ, MISS_READ_WAIT, MISS_SAVE
- Output buffer (1-entry fast path)
- Fire-and-forget evict в MISS_SAVE
- 22 теста проходят (D-cache WAYS=1, I-cache READ_ONLY=1, D-cache WAYS=2)

## Что реализовано

- [x] MEMORY_CONTROLLER_V2 с READ_ONLY, WAYS, output buffer
- [x] 22 теста (D-cache, I-cache, 2-way)

## Следующие шаги

- [ ] Привести upstream MCV2 к стандартному bus interface (bus_read/bus_write вместо command)
- [ ] CORE_BUS_ARBITER
- [ ] BUS_DECODER
- [ ] Адаптеры для I/O устройств (128b bus → 32b device)
- [ ] Интеграция в TOP
