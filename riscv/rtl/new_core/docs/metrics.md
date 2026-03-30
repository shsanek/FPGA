# Pipeline Performance Metrics

## Iteration 1 — baseline

Конфигурация: 6-stage pipeline, no branch prediction, flush_locked on branch/jump, 1-cycle bubble per branch/jump.

I-cache: ICACHE_DEPTH=16 (core tests), ICACHE_DEPTH=512 (program tests). Mock memory 1-cycle read latency.

| Тест | Cycles | Instrs | IPC | Группа |
|------|--------|--------|-----|--------|
| test_alu_basic | — | — | PASSED | pipeline |
| test_branch | — | — | PASSED | pipeline |
| test_jump | — | — | PASSED | pipeline |
| test_upper | — | — | PASSED | pipeline |
| test_hazard | — | — | PASSED | pipeline |
| test_shifts | — | — | PASSED | pipeline |
| test_loop | — | — | PASSED | pipeline |
| test_memory | — | — | PASSED | pipeline |
| core_test_alu | 203 | 31 | 0.15 | core |
| core_test_loop | 44 | 6 | 0.13 | core |
| core_test_mem | 76 | 17 | 0.22 | core |
| core_test_fib | 550 | 107 | 0.19 | core |
| test_alu | 2165 | 303 | 0.13 | program |
| test_branch | 5757 | 877 | 0.15 | program |
| test_jump | 4462 | 605 | 0.13 | program |
| test_upper | 905 | 125 | 0.13 | program |
| test_mem | 2083 | 419 | 0.20 | program |
| test_muldiv_hw | 7540 | 955 | 0.12 | program |

**Средний IPC (program tests): 0.14**

### Основные причины низкого IPC

- I-cache miss penalty (каждый miss = несколько тактов на bus arbitration + memory read)
- flush_locked: 1 bubble на каждый branch/jump (flush_locked ставится на 1 такт после dispatch)
- Data hazard stall: RAW зависимость блокирует dispatch до writeback
- ALU_MEMORY: 2-3 такта на каждый load/store
- ALU_MULDIV: 32 такта на MUL/DIV
- WRITEBACK: 1-cycle registered stage (добавляет латентность writeback → busy clear)
- Нет branch prediction (всегда flush, даже для not-taken)
- Нет forwarding из ALU result (только из writeback)
