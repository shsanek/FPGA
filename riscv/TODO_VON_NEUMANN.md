# Von Neumann: инструкции из DDR

Переход от Harvard (ROM + DDR) к Von Neumann (только DDR).
CPU будет читать инструкции и данные через один MEMORY_CONTROLLER.

## Архитектура

```
CPU
 ├── instr_addr/instr_data/instr_stall  ──→  INSTR_FETCH_ADAPTER ──┐
 │                                                                   │
 └── mem_read/write/stall               ──→  CPU_DATA_ADAPTER    ──┤
                                                                    │
                                                          MEM_ARBITER
                                                              │
                                                     MEMORY_CONTROLLER
                                                              │
                                                     RAM_CONTROLLER → DDR
```

## Загрузка программы

DEBUG_CONTROLLER (HALT → WRITE_MEM × N → сброс PC → RESUME).
Программа грузится в DDR по адресу 0x00000000.
После RESUME CPU начинает fetch с PC=0.

## Задачи

### Фаза 1: CPU_SINGLE_CYCLE — поддержка instr_stall
- [ ] 1.1 Добавить `input wire instr_stall` в порты
- [ ] 1.2 Включить `instr_stall` в `cpu_stall` (рядом с `mem_stall`)
- [ ] 1.3 Обновить тест CPU_SINGLE_CYCLE_TEST (подключить instr_stall=0)
- [ ] 1.4 Проверить что все существующие тесты проходят

### Фаза 2: INSTR_FETCH_ADAPTER
- [ ] 2.1 Создать модуль INSTR_FETCH_ADAPTER:
  - Вход: `instr_addr` от CPU (32 бит)
  - Выход: `instr_data` (32 бит), `instr_stall` (1 бит)
  - Интерфейс к памяти: address/read_trigger/read_value/mask/controller_ready
  - Логика: если адрес попадает в кэшированный chunk — выдать сразу (stall=0)
  - Если промах — запросить чтение, поднять stall, ждать ответа
  - Простой кэш: 1 строка × 128 бит (4 слова по 32 бит, выровнено по 16 байт)
- [ ] 2.2 Написать тест INSTR_FETCH_ADAPTER_TEST
- [ ] 2.3 Проверить через xsim

### Фаза 3: MEM_ARBITER
- [ ] 3.1 Создать модуль MEM_ARBITER:
  - Два порта (instr + data) → один порт к MEMORY_CONTROLLER
  - Приоритет: data > instr (завершить текущую инструкцию важнее)
  - Каждый порт: address, read_trigger, write_trigger, write_value, mask,
                  read_value, controller_ready
  - Простая логика: если data хочет доступ — data идёт, instr ждёт.
                    Если только instr — instr идёт.
- [ ] 3.2 Написать тест MEM_ARBITER_TEST
- [ ] 3.3 Проверить через xsim

### Фаза 4: Интеграция в TOP.sv
- [ ] 4.1 Убрать ROM из TOP.sv
- [ ] 4.2 Подключить INSTR_FETCH_ADAPTER + MEM_ARBITER
- [ ] 4.3 CPU_DATA_ADAPTER → MEM_ARBITER порт data
- [ ] 4.4 INSTR_FETCH_ADAPTER → MEM_ARBITER порт instr
- [ ] 4.5 MEM_ARBITER → MEMORY_CONTROLLER (вместо прямого подключения)
- [ ] 4.6 Обновить FPGA_TOP (убрать ROM_DEPTH параметр)
- [ ] 4.7 Прогнать xsim тесты: TOP_TEST, CPU_MEMORY_INTEGRATION_TEST

### Фаза 5: DEBUG_CONTROLLER — сброс PC
- [ ] 5.1 Добавить команду RESET_PC (0x06) в DEBUG_CONTROLLER:
  - HALT → загрузка программы через WRITE_MEM → RESET_PC → RESUME
  - RESET_PC устанавливает PC=0 (или указанный адрес)
- [ ] 5.2 Добавить порт `dbg_set_pc` + `dbg_new_pc` в CPU_SINGLE_CYCLE
- [ ] 5.3 Обновить riscv_tester.py (команда RESET_PC)
- [ ] 5.4 Тест: загрузить hello.hex через UART, запустить, получить вывод

### Фаза 6: Синтез и проверка на железе
- [ ] 6.1 Полный lint (xvlog)
- [ ] 6.2 Синтез + implementation + bitstream
- [ ] 6.3 Прошить Arty A7-100T
- [ ] 6.4 Загрузить hello через riscv_tester.py --upload
- [ ] 6.5 Проверить вывод программы через UART

## Заметки

- INSTR_FETCH_ADAPTER кэширует 1 chunk (128 бит = 4 инструкции).
  При последовательном исполнении 3 из 4 fetch будут cache hit (0 stall).
  Только каждый 4-й fetch будет cache miss (стоимость: ~10-20 тактов DDR).
- Branch/jump сбрасывает кэш → miss на новом адресе.
- Data access приоритетнее instruction fetch в арбитре.
  Это предотвращает deadlock: CPU ждёт данные → data port должен быть обслужен.
- PC после reset = 0x00000000. Программа должна начинаться с этого адреса.
