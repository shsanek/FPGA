# Von Neumann: инструкции из DDR

Переход от Harvard (ROM + DDR) к Von Neumann (только DDR).
CPU читает инструкции и данные через один MEMORY_CONTROLLER.
Кэш (CHUNK_STORAGE_4_POOL) уже есть — используем его.

## Архитектура

CPU становится двухфазным:
```
FETCH_INSTR → EXECUTE (→ если load/store: WAIT_MEM) → FETCH_INSTR
```

Один порт MEMORY_CONTROLLER, time-multiplexed:
```
CPU_PIPELINE_ADAPTER
 ├── фаза FETCH: читает инструкцию по PC из MEMORY_CONTROLLER
 ├── фаза EXECUTE: CPU исполняет, если нужен load/store → data access
 └── мультиплексирует адрес/триггеры на MEMORY_CONTROLLER
         │
    MEMORY_CONTROLLER (с кэшем 4×128 бит)
         │
    RAM_CONTROLLER → DDR
```

Арбитр не нужен — fetch и data access никогда не одновременны.

## Задачи

### Фаза 1: CPU_SINGLE_CYCLE — instr_stall ✅
- [x] 1.1 Добавить `input wire instr_stall` в порты CPU
- [x] 1.2 Включить `instr_stall` в `cpu_stall`
- [x] 1.3 Обновить тесты (подключить instr_stall=0)
- [x] 1.4 Прогнать все тесты — 15/15 pass

### Фаза 2: CPU_PIPELINE_ADAPTER ✅
- [x] 2.1 Создать модуль CPU_PIPELINE_ADAPTER:
  - Входы от CPU: instr_addr, mem_read_en, mem_write_en, mem_addr,
                   mem_write_data, mem_byte_mask
  - Выходы к CPU: instr_data, instr_stall, mem_read_data, mem_stall
  - Порт к MEMORY_CONTROLLER: address, read_trigger, write_trigger,
                                write_value, mask, read_value, controller_ready
  - Состояния:
    - FETCH_REQUEST: отправить read по адресу PC (выровненному по 4)
    - FETCH_WAIT: ждать controller_ready, защёлкнуть инструкцию
    - EXECUTE: снять instr_stall, CPU исполняет за 1 такт
      - если mem_read_en или mem_write_en → перейти в DATA_REQUEST
      - иначе → FETCH_REQUEST (следующая инструкция)
    - DATA_REQUEST: отправить read/write по mem_addr
    - DATA_WAIT: ждать controller_ready, защёлкнуть данные
    - DATA_DONE: снять mem_stall → FETCH_REQUEST
- [x] 2.2 Lint пройден
- [ ] 2.3 Тест CPU_PIPELINE_ADAPTER_TEST (отложен — проверяется через интеграцию)

### Фаза 3: Интеграция в TOP.sv ✅
- [x] 3.1 Убрать ROM из TOP.sv
- [x] 3.2 Заменить CPU_DATA_ADAPTER на CPU_PIPELINE_ADAPTER
- [x] 3.3 CPU_PIPELINE_ADAPTER подключается напрямую к PERIPHERAL_BUS
- [x] 3.4 Убрать ROM_DEPTH параметр из TOP и FPGA_TOP
- [x] 3.5 Lint + 15/15 unit тестов pass

### Фаза 4: DEBUG_CONTROLLER — сброс PC ✅
- [x] 4.1 Добавить команду RESET_PC (0x06, payload=ADDR[31:0], ответ=0xFF)
- [x] 4.2 Добавить порты `dbg_set_pc` + `dbg_new_pc` в CPU_SINGLE_CYCLE
- [ ] 4.3 Обновить riscv_tester.py (Фаза 5)
- [x] 4.4 15/15 unit тестов pass

### Фаза 5: Программные тесты (iverilog)
- [ ] 5.1 Установить iverilog (winget install IcarusVerilog.IcarusVerilog)
- [ ] 5.2 Прогнать все 8 program tests через PROGRAM_TEST.sv + iverilog:
        hello, fib, sum, test_alu, test_branch, test_jump, test_mem, test_upper
- [ ] 5.3 Сравнить вывод с expected.txt для каждого теста
- [ ] 5.4 Все 8 тестов должны пройти

### Фаза 6: Синтез и проверка на железе
- [ ] 6.1 Lint (xvlog) + xsim unit тесты (15 тестов)
- [ ] 6.2 Синтез + implementation + bitstream
- [ ] 6.3 Прошить Arty A7-100T
- [ ] 6.4 riscv_tester.py --upload hello.hex → проверить вывод
- [ ] 6.5 Прогнать все 8 программ через UART

## Заметки

- MEMORY_CONTROLLER кэш (4 строки × 128 бит) покрывает 64 байта = 16 инструкций.
  При последовательном исполнении большинство fetch — cache hit (1-2 такта).
- Branch/jump → cache miss → ~10-20 тактов на DDR read.
- Нет арбитра: fetch и data access строго последовательны.
- PC после reset = 0x00000000.
