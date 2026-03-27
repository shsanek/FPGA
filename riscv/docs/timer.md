# TIMER_DEVICE

Счётчик тактов и времени с момента запуска (reset). Read-only, комбинационное чтение (controller_ready = 1 всегда).

**Файл:** `riscv/rtl/peripheral/TIMER_DEVICE.sv`

---

## Адресная карта

Базовый адрес: `0x1003_0000` (слот 11 в PERIPHERAL_BUS, `addr[28]=1, addr[17:16]=11`)

| Смещение | Регистр | Доступ | Описание |
|----------|---------|--------|----------|
| 0x0 | CYCLE_LO | R | Нижние 32 бита 64-бит счётчика тактов. При чтении защёлкивает CYCLE_HI |
| 0x4 | CYCLE_HI | R | Верхние 32 бита (snapshot, атомарно с CYCLE_LO) |
| 0x8 | TIME_MS | R | Миллисекунды с момента reset (32 бита, переполнение ~49 дней) |
| 0xC | TIME_US | R | Микросекунды с момента reset (32 бита, переполнение ~71 мин) |

---

## Параметры

| Параметр | Default | Описание |
|----------|---------|----------|
| CLOCK_FREQ | 81_250_000 | Частота clk в Гц (для вычисления ms/us) |

---

## Внутреннее устройство

### Счётчик тактов (64 бита)

Инкрементируется каждый такт. Сбрасывается при reset.

### Атомарное чтение 64-бит значения

При чтении `CYCLE_LO` (адрес 0x0) верхние 32 бита защёлкиваются в `cycle_hi_snapshot`. Последующее чтение `CYCLE_HI` (0x4) возвращает snapshot.

**Правильный порядок чтения:**
```c
uint32_t lo = TIMER_CYCLE_LO;  // ← защёлкивает HI
uint32_t hi = TIMER_CYCLE_HI;  // ← читает snapshot
uint64_t cycles = ((uint64_t)hi << 32) | lo;
```

### Миллисекунды

Делитель на `CLOCK_FREQ / 1000`. Инкрементирует `ms_counter` каждую миллисекунду.

- При 81.25 MHz: `CYCLES_PER_MS = 81250`
- Переполнение 32-бит: ~49.7 дней

### Микросекунды

Делитель на `CLOCK_FREQ / 1_000_000`. Инкрементирует `us_counter` каждую микросекунду.

- При 81.25 MHz: `CYCLES_PER_US = 81` (погрешность ~0.3%)
- Переполнение 32-бит: ~71.6 мин

---

## Использование в C

```c
#define TIMER_CYCLE_LO  (*(volatile unsigned int *)0x10030000U)
#define TIMER_CYCLE_HI  (*(volatile unsigned int *)0x10030004U)
#define TIMER_MS        (*(volatile unsigned int *)0x10030008U)
#define TIMER_US        (*(volatile unsigned int *)0x1003000CU)

// Замер времени выполнения
unsigned start = TIMER_MS;
do_something();
unsigned elapsed = TIMER_MS - start;  // миллисекунды
```

---

## Тестирование

**Unit-тест:** `test/peripheral/TIMER_DEVICE_TEST.sv`

| Тест | Проверка |
|------|----------|
| T1 | CYCLE_LO инкрементируется каждый такт |
| T2 | CYCLE_HI snapshot при чтении CYCLE_LO |
| T3 | TIME_MS инкрементируется через CYCLES_PER_MS тактов |
| T4 | TIME_US инкрементируется через CYCLES_PER_US тактов |

---

## Файлы

| Файл | Описание |
|------|----------|
| `rtl/peripheral/TIMER_DEVICE.sv` | Модуль (96 строк) |
| `test/peripheral/TIMER_DEVICE_TEST.sv` | Unit-тест |
