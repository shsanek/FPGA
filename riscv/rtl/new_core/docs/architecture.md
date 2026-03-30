# Pipelined RISC-V Core — Architecture

## Overview

6-stage pipelined RV32IM processor.
- 1 instruction/cycle (IPC=1.0) in steady state при отсутствии hazard'ов и cache miss'ов
- 6 параллельных ALU: compute, branch, jump, upper, memory, muldiv
- Data hazard detection + writeback forwarding (bypass)
- Flush при branch/jump (no branch prediction — always flush)
- 128-bit bus interface (16 байт = 1 cache line)

## Block Diagram

```
                          ┌──────────────────────────────────────────────────────┐
                          │                     CORE                             │
                          │                                                      │
  ┌─────────┐   peek      │  ┌─────────┐  ┌────────┐  ┌──────────┐               │
  │ I_CACHE ├────────────►│  │INSTR    │─►│INSTR   │─►│REGISTER  │               │
  │ (MCV2)  │◄────────────│  │PROVIDER │  │DECODE  │  │DISPATCHER│               │
  │ RO=1    │  bus_read   │  │  (S1)   │  │ (S2)   │  │  (S3)    │               │
  └────┬────┘             │  └─────────┘  └────────┘  └────┬─────┘               │
       │                  │                                 │                    │
       │              ┌───┼─────────────────────────────────┼──────────┐         │
  ┌────┴────┐         │   │                                 ▼                    │
  │   BUS   │         │   │  ┌─────────────────────────────────────┐  │          │
  │ ARBITER │         │   │  │       EXECUTE_DISPATCHER (S4)       │  │          │
  │ p0>p1   │         │   │  │                                     │  │          │
  └────┬────┘         │   │  │  ┌────────┐ ┌──────┐ ┌──────┐       │  │          │
       │              │   │  │  │COMPUTE │ │BRANCH│ │ JUMP │       │  │          │
       │              │   │  │  │  1 clk │ │1 clk │ │1 clk │       │  │          │
       │              │   │  │  └────────┘ └──────┘ └──────┘       │  │          │
  ┌────┴────┐   data  │   │  │  ┌────────┐ ┌──────┐ ┌──────┐       │  │          │
  │ External│◄────────┤   │  │  │ UPPER  │ │MEMORY│ │MULDIV│       │  │          │
  │   Bus   │         │   │  │  │  1 clk │ │2-N   │ │ 32   │       │  │          │
  └─────────┘         │   │  │  └────────┘ └──────┘ └──────┘       │  │          │
                      │   │  │                                     │  │          │
                      │   │  │  ┌──────────────────────────┐       │  │          │
                      │   │  │  │  WRITEBACK_ARBITER (S5)  │       │  │          │
                      │   │  │  │  priority: 1-clk>mem>mul │       │  │          │
                      │   │  │  └────────────┬─────────────┘       │  │          │
                      │   │  └───────────────┼─────────────────────┘  │          │
                      │   │                  ▼                        │          │
                      │   │  ┌───────────────────────┐                │          │
                      │   │  │   WRITEBACK (S6)      │                │          │
                      │   │  │   rf_wr_en → regfile  ├──► regfile     │          │
                      │   │  │   wb_done → S3 notify │                │          │
                      │   │  └───────────────────────┘                │          │
                      │   │                                           │          │
                      │   │              PIPELINE                     │          │
                      └───┼───────────────────────────────────────────┘          │
                          └──────────────────────────────────────────────────────┘
```

## Valid/Ready Handshake Protocol

Все inter-stage соединения используют протокол:
- `prev_stage_valid` — upstream имеет данные
- `prev_stage_ready` — downstream может принять
- Transfer происходит когда `valid && ready` оба = 1 на одном posedge clk

```
         ┌───┐   ┌───┐   ┌───┐
  clk    │   │   │   │   │   │
    ─────┘   └───┘   └───┘   └──
         ___________
valid   /           \____________
        ─────────────
             _______
ready       /       \____________
        ─────────────
             ^ transfer happens here
```

## Flush

При branch taken или jump (JAL/JALR) pipeline сбрасывается:

```
out_flush = branch_flush || jump_flush    (из EXECUTE_DISPATCHER)
flush_pc  = ext_set_pc ? ext_new_pc : alu_new_pc

flush → S1 (INSTRUCTION_PROVIDER): новый PC, сброс буфера
flush → S2 (INSTRUCTION_DECODE):   сброс lat_valid
flush → S3 (REGISTER_DISPATCHER):  сброс lat_valid, busy[], next_stage_valid
```

S4 (EXECUTE_DISPATCHER) не получает flush — он сам генерирует его. Механизм `flush_locked` предотвращает диспатч новых инструкций пока branch/jump в полёте.

## flush_locked

```
Цикл N:   branch/jump диспатчится в ALU. flush_locked <= 1 (NBA).
           prev_stage_ready = 1 (flush_locked ещё 0). Handshake завершён.
Цикл N+1: flush_locked=1. prev_stage_ready=0. Никакие инструкции не проходят.
           ALU завершается: branch_done=1. flush fires (если taken).
           flush_locked <= 0 (NBA).
Цикл N+2: Pipeline чист. Возобновление работы.
```

## Data Hazard Detection

REGISTER_DISPATCHER (S3) ведёт таблицу `busy[0:31]`:
- **Set**: когда инструкция с `rd != x0` уходит на execute
- **Clear**: когда WRITEBACK сообщает `wb_done_valid` для этого регистра

Если `rs1` или `rs2` входящей инструкции busy — stall.

**Forwarding bypass**: если writeback пишет регистр на том же такте когда dispatcher его читает, используется значение из writeback напрямую (минуя regfile NBA).

## Memory Map (Bus)

```
addr[29] = 0: обычный доступ через cache
addr[29] = 1: stream bypass (без кэширования)
```

I_CACHE (MEMORY_CONTROLLER_V2, READ_ONLY=1) подключена через BUS_ARBITER port 1.
Data bus (ALU_MEMORY) подключен через BUS_ARBITER port 0 (приоритет).

## Performance

| Сценарий | IPC |
|----------|-----|
| Steady state (no hazards, hits) | ~1.0 |
| Branch/jump | 0 на 1-2 такта (flush penalty) |
| Data hazard | stall до writeback |
| Cache miss | stall до DDR response |
| MUL/DIV | 32 такта на операцию |

Тест fib(20): **549 тактов** (18 инструкций в hex).
