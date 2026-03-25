# Fix: Debug через остановку pipeline

Текущая проблема: debug mux и pipeline конкурируют за bus, timing
кэша ломается. Решение: debug всегда работает через остановку CPU.

## Новый протокол

Любая debug команда:
1. CPU_PIPELINE_ADAPTER останавливается (stall)
2. Pipeline освобождает bus (triggers=0)
3. Debug выполняет операцию через bus
4. Pipeline возобновляется (если не HALT)
5. DEBUG_CONTROLLER шлёт ACK через UART

## Архитектура

```
DEBUG_CONTROLLER
  │
  ├── dbg_bus_request ──→ CPU_PIPELINE_ADAPTER.pause
  │                        (pipeline останавливается, bus свободен)
  │
  ├── dbg_bus_granted ←── CPU_PIPELINE_ADAPTER.paused
  │                        (pipeline остановлен, bus отдан)
  │
  └── mc_* (addr/rd/wr/data) ──→ bus mux ──→ PERIPHERAL_BUS
      (bus используется только когда paused=1)
```

## Задачи

### 1. CPU_PIPELINE_ADAPTER — добавить pause/paused
- [ ] 1.1 Добавить `input wire pause` — запрос остановки
- [ ] 1.2 Добавить `output wire paused` — pipeline остановлен и bus свободен
- [ ] 1.3 Логика: когда pause=1, дождаться завершения текущей фазы
      (FETCH_WAIT→готово или DATA_WAIT→готово), перейти в S_PAUSED
- [ ] 1.4 В S_PAUSED: все mc_* triggers = 0, instr_stall=1, mem_stall=1
- [ ] 1.5 Когда pause=0 → выйти из S_PAUSED в S_FETCH_TRIG

### 2. Bus mux в TOP.sv — упростить
- [ ] 2.1 Убрать DBG_MUX FSM
- [ ] 2.2 Простой mux: когда pipeline.paused=1, debug владеет bus
- [ ] 2.3 bus_addr/rd/wr/data = debug когда paused, pipeline когда !paused
- [ ] 2.4 mc_dbg_ready = bus_ready когда paused

### 3. DEBUG_CONTROLLER — новый flow
- [ ] 3.1 Для WRITE_MEM/READ_MEM:
      - Поднять dbg_bus_request
      - Ждать dbg_bus_granted (pipeline остановился)
      - Выставить mc_addr/trigger на 1 такт
      - Ждать mc_dbg_ready (bus завершил операцию)
      - Опустить dbg_bus_request (pipeline продолжает)
      - Отправить ACK
- [ ] 3.2 Для HALT:
      - Поднять dbg_bus_request + dbg_halt
      - Ждать granted
      - НЕ опускать dbg_bus_request (CPU остаётся)
      - Отправить ACK
- [ ] 3.3 Для RESUME:
      - Опустить dbg_halt + dbg_bus_request
      - Отправить ACK
- [ ] 3.4 Для STEP:
      - Опустить dbg_bus_request на 1 цикл pipeline
      - Pipeline делает 1 fetch+execute
      - Поднять dbg_bus_request обратно
      - Прочитать PC/INSTR, отправить
- [ ] 3.5 Для RESET_PC:
      - Поднять dbg_bus_request
      - Ждать granted
      - dbg_set_pc pulse
      - Flush pipeline
      - Опустить dbg_bus_request (если нет HALT)
      - Отправить ACK

### 4. Тесты
- [ ] 4.1 Прогнать 15 unit тестов
- [ ] 4.2 Прогнать PROGRAM_TEST с simple_test.hex
- [ ] 4.3 Прогнать все 8 program tests

### 5. riscv_tester.py — обновить
- [ ] 5.1 Добавить CMD_RESET_PC (0x06) с payload ADDR[31:0]
- [ ] 5.2 upload flow: HALT → WRITE_MEM × N → RESET_PC(0) → RESUME
- [ ] 5.3 Каждая команда ждёт ACK перед следующей
