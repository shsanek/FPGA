# Системная шина и приоритеты доступа

## Общая схема

```
FLASH_LOADER ──┐
               │
DEBUG_CTRL ────┤   BUS MUX      PERIPHERAL_BUS       MEMORY_CONTROLLER
               ├──→ (TOP.sv) ──→ (addr decode) ──┬──→ (cache + DDR)
CPU_PIPELINE ──┘                                 │
                                                 ├──→ UART_IO_DEVICE
                                                 ├──→ OLED_IO_DEVICE
                                                 └──→ SD_IO_DEVICE
```

Три мастера конкурируют за одну шину. Арбитраж — комбинационный mux в TOP.sv.

---

## Приоритеты (BUS MUX)

```
1. FLASH_LOADER   (наивысший — только при загрузке)
2. DEBUG_CONTROLLER
3. CPU_PIPELINE_ADAPTER  (нормальная работа)
```

### Логика в TOP.sv

```systemverilog
// Pipeline останавливается если любой мастер выше по приоритету активен
pipeline.pause = flash_bus_request | dbg_bus_request;

// Кто владеет шиной
bus_addr = flash_active    ? flash_addr :
           pipeline_paused ? debug_addr :
                             pipeline_addr;

// Ready-сигналы маршрутизируются только к текущему владельцу
flash_ready = flash_active                       ? bus_ready : 0;
debug_ready = (!flash_active & pipeline_paused)  ? bus_ready : 0;
// pipeline видит bus_ready напрямую (когда не paused)
```

### Жизненный цикл приоритетов

```
Power-on
  │
  ▼
FLASH_LOADER active (bus_request=1)     ← CPU и debug ЗАБЛОКИРОВАНЫ
  │  ждёт DDR ready
  │  читает SPI flash
  │  пишет в DDR
  │  set_pc
  ▼
FLASH_LOADER done (bus_request=0)       ← debug и CPU разблокированы
  │
  ▼
Нормальная работа:
  CPU_PIPELINE владеет шиной
  DEBUG_CONTROLLER может захватить шину (dbg_bus_request=1 → pipeline paused)
```

---

## Адресное пространство (PERIPHERAL_BUS)

28-битный адрес. Бит `[27]` разделяет память и I/O.

```
addr[27] = 0  →  MEMORY_CONTROLLER (DDR через кэш)
addr[27] = 1  →  I/O, подразбивка по addr[17:16]:
```

| addr[17:16] | Базовый адрес | Устройство | Регистры |
|-------------|---------------|------------|----------|
| 00 | 0x800_0000 | UART_IO_DEVICE | TX, RX, STATUS |
| 01 | 0x801_0000 | OLED_IO_DEVICE | DATA, CONTROL, STATUS, DIVIDER |
| 10 | 0x802_0000 | SD_IO_DEVICE | DATA, CONTROL, STATUS, DIVIDER |
| 11 | 0x803_0000 | (свободно) | — |

### Декодирование (комбинационное)

```systemverilog
wire io_sel   = address[27];
wire uart_sel = io_sel & (io_dev == 2'b00);
wire oled_sel = io_sel & (io_dev == 2'b01);
wire sd_sel   = io_sel & (io_dev == 2'b10);

// Trigger проходит только к выбранному устройству
mc_read_trigger  = io_sel ? 0 : read_trigger;
uart_read_trigger = uart_sel ? read_trigger : 0;
// ...

// Ответ мультиплексируется обратно
read_value = sd_sel ? sd_read_value : oled_sel ? oled_read_value : ...
controller_ready = sd_sel ? sd_ready : oled_sel ? oled_ready : ...
```

---

## Путь данных CPU → DDR

```
CPU_SINGLE_CYCLE
  │  mem_addr, mem_write_en, mem_read_en
  ▼
CPU_PIPELINE_ADAPTER (FSM: FETCH → EXECUTE → DATA)
  │  mc_address, mc_read_trigger, mc_write_trigger
  ▼
BUS MUX (если не paused — pipeline владеет)
  │  bus_addr, bus_rd, bus_wr
  ▼
PERIPHERAL_BUS (addr[27]=0 → память)
  │  mc_address, mc_read/write_trigger
  ▼
MEMORY_CONTROLLER (4-entry write-back cache)
  │  cache hit → 1-2 такта
  │  cache miss → evict dirty + fetch from DDR
  ▼
RAM_CONTROLLER (CDC: clk ↔ mig_ui_clk)
  │
  ▼
MIG7 → DDR3 SDRAM
```

### Timing

| Операция | Такты |
|----------|-------|
| Cache hit (read/write) | 1-2 |
| Cache miss (clean) | ~10-20 (DDR fetch) |
| Cache miss (dirty) | ~20-40 (evict + fetch) |
| I/O register read/write | 1 (combinational ready) |
| SPI transfer (OLED/SD) | N (busy пока SPI не завершит) |

---

## Путь данных DEBUG → DDR

```
UART RX → RX FIFO → DEBUG_CONTROLLER
  │  dbg_bus_request=1
  │  pipeline paused
  ▼
BUS MUX (debug владеет)
  │  mc_dbg_address, mc_dbg_read/write_trigger
  ▼
PERIPHERAL_BUS → MEMORY_CONTROLLER → DDR
  │
  ▼
DEBUG_CONTROLLER ← mc_dbg_ready, mc_dbg_read_data
  │  отправляет ACK через UART TX
```

Debug может обращаться к любому адресу — и к DDR, и к I/O устройствам.

---

## Путь данных FLASH_LOADER → DDR

```
SPI_MASTER ← QSPI Flash (L13, K17, K18, L16)
  │  побайтное чтение
  ▼
FLASH_LOADER FSM
  │  собирает 4 байта → 32-bit word
  │  mc_flash_addr, mc_flash_wr
  ▼
BUS MUX (flash владеет, наивысший приоритет)
  │
  ▼
PERIPHERAL_BUS → MEMORY_CONTROLLER → DDR
```

FLASH_LOADER пишет только в DDR (addr[27]=0). Не обращается к I/O.

---

## Файлы

| Файл | Описание |
|------|----------|
| `rtl/TOP.sv` | Bus mux (строки 426-443), инстанцирование всех модулей |
| `rtl/peripheral/PERIPHERAL_BUS.sv` | Адресный декодер (105 строк) |
| `rtl/core/CPU_PIPELINE_ADAPTER.sv` | Pipeline FSM с pause/paused |
| `rtl/debug/DEBUG_CONTROLLER.sv` | Debug протокол, bus_request |
| `rtl/peripheral/FLASH_LOADER.sv` | Boot loader, bus_request |
| `rtl/memory/MEMORY_CONTROLLER.sv` | Write-back cache |
| `rtl/memory/RAM_CONTROLLER.sv` | MIG DDR controller |
