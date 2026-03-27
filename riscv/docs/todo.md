# RISC-V Processor TODO

## Отложено (v2)

- [ ] RV32M (MUL/DIV/REM)
- [ ] EXEC_INSTR (инъекция инструкции через отладчик)
- [ ] READ_REG по номеру через отладчик

- [ ] 5-стадийный pipeline (IF/ID/EX/MEM/WB)
- [ ] Hazard detection unit
- [ ] Data forwarding unit

- [ ] CSR регистры + прерывания
- [ ] Branch prediction

### Заметки по симуляции
- `I_O_INPUT_CONTROLLER` переворачивает биты (shift-left аккумуляция): чтобы
  DEBUG_CONTROLLER получил байт X, нужно отправить `rev8(X)` в стандартном UART.
  Пример: CMD_HALT=0x01 → uart_send(0x80).
- `tx_valid_r` — 1-тактовый импульс внутри uart_send; обнаруживать через `fork/join`
  с uart_send и expect_dbg_byte параллельно.
- ROM инициализируется через иерархический доступ в тестбенче: `dut.rom[i] = instr`.