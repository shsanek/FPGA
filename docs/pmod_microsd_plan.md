# PmodMicroSD — план поддержки

## Устройство

PmodMicroSD — SPI ридер microSD карт. В SPI-режиме используются 4 сигнала + card detect.

## Распиновка (dual-row PMOD, подключаем к JC)

```
JC[0] = pin 1  = CS     (chip select, active low)
JC[1] = pin 2  = MOSI   (SPI data out → SD)
JC[2] = pin 3  = MISO   (SPI data in  ← SD)
JC[3] = pin 4  = SCK    (SPI clock, max 25 MHz при init, потом до 50 MHz)
JC[4] = pin 7  = DAT1   (не используется в SPI mode)
JC[5] = pin 8  = DAT2   (не используется в SPI mode)
JC[6] = pin 9  = CD     (card detect, input: 0=карта вставлена)
JC[7] = pin 10 = NC
```

DAT1/DAT2 в SPI mode не нужны — подтянуть к VCC или оставить.

## Адресная карта

Текущая:
- `0x0000000–0x7FFFFFF` → MEMORY_CONTROLLER
- `0x8000000` → UART_IO_DEVICE  (addr[27]=1, addr[16]=0)
- `0x8010000` → OLED_IO_DEVICE  (addr[27]=1, addr[16]=1)

Добавляем SD на `0x8020000` (addr[17]=1):

```
0x8020000  SD_DATA     (W) — отправить байт по SPI, прочитанный байт в read_value
                       (R) — последний принятый байт (MISO)
0x8020004  SD_CONTROL  (W/R) — bit 0 = CS (1=active/low)
0x8020008  SD_STATUS   (R) — {29'b0, card_detect, spi_busy, 0}
0x802000C  SD_DIVIDER  (W/R) — SPI clock делитель
```

## Ключевое отличие от OLED: нужен MISO

Текущий `SPI_MASTER` — transmit-only (нет MISO). SD карта требует full-duplex SPI:
- Отправляем байт (MOSI) и **одновременно** принимаем байт (MISO)
- Каждая SPI-транзакция 8 бит в обе стороны

### Решение: расширить SPI_MASTER

Добавить в `SPI_MASTER`:
- Вход `miso`
- Выход `rx_data [DATA_WIDTH-1:0]` — данные принятые по MISO
- В S_SHIFT на rising edge SCK: сдвигать `rx_shift_reg` и сэмплить `miso`
- По завершении `rx_data = rx_shift_reg`

Это **обратно совместимо** — OLED просто не подключает `miso`/`rx_data`.

## Протокол SD карты (SPI mode)

### Init sequence (CPU делает, не hardware)

1. Подождать >1ms после power-on
2. Отправить ≥74 тактов SCK с CS=high (отправить 10 байт 0xFF)
3. CS=low
4. CMD0 (GO_IDLE) → ожидать R1=0x01 (idle)
5. CMD8 (SEND_IF_COND, arg=0x1AA) → проверить voltage range
6. Цикл: ACMD41 (CMD55 + CMD41, arg=0x40000000) → ждать R1=0x00 (ready)
7. CMD58 (READ_OCR) → проверить CCS бит (SDHC/SDXC)
8. Опционально: CMD16 (SET_BLOCKLEN, 512) для SDSC

### Чтение блока

1. CMD17 (READ_SINGLE_BLOCK, addr) → R1=0x00
2. Ждать data token 0xFE (отправлять 0xFF, читать MISO)
3. Читать 512 байт данных
4. Читать 2 байта CRC (можно игнорировать)

### Запись блока

1. CMD24 (WRITE_BLOCK, addr) → R1=0x00
2. Отправить data token 0xFE
3. Отправить 512 байт данных
4. Отправить 2 байта CRC (0xFF 0xFF)
5. Читать data response (xxx00101 = accepted)
6. Ждать пока MISO != 0x00 (busy)

### SPI framing

```
CMD: 0x40|cmd_idx(6bit), arg[31:24], arg[23:16], arg[15:8], arg[7:0], crc|1
R1:  один байт, bit7=0 означает valid response
```

CRC обязателен только для CMD0 (0x95) и CMD8 (0x87). Остальные — 0xFF.

## Файлы для создания/изменения

### Новые:
1. **`riscv/CPU/SD_IO_DEVICE.sv`** — memory-mapped контроллер SD
   - 4 регистра (DATA, CONTROL, STATUS, DIVIDER)
   - Запись в DATA → SPI transfer, `rx_data` доступен через чтение DATA
   - CONTROL: CS pin
   - STATUS: card_detect, spi_busy
   - Делитель: init на 400 kHz (divider=101), рабочий на ~5 MHz (divider=7)
2. **`riscv/CPU/SD_IO_DEVICE_TEST.sv`** — тест с заглушкой MISO
3. **`riscv/tests/programs/test_sd/test_sd.c`** — C-тест: init SD, read block 0

### Изменения:
4. **`riscv/CPU/SPI_MASTER.sv`** — добавить `miso` вход, `rx_data` выход
5. **`riscv/CPU/SPI_MASTER_TEST.sv`** — тесты MISO
6. **`riscv/CPU/OLED_IO_DEVICE.sv`** — подключить `.miso(1'b1)` (не используется)
7. **`riscv/CPU/PERIPHERAL_BUS.sv`** — добавить SD порт (addr[17]=1)
8. **`riscv/TOP.sv`** — инстанциация SD_IO_DEVICE, порты наружу
9. **`riscv/FPGA_TOP.sv`** — JB пины
10. **`vivado/Arty-A7-100-Master.xdc`** — JB pin constraints

## Декодирование адресов в PERIPHERAL_BUS (расширение)

```
address[27] = 0  → MEMORY_CONTROLLER
address[27] = 1  → I/O:
  address[17:16]:
    00 → UART  (0x8000000)
    01 → OLED  (0x8010000)
    10 → SD    (0x8020000)
    11 → (free)
```

## SPI Clock для SD

- Init: ≤400 kHz → divider = 81250000 / (2 * 400000) ≈ 101
- Рабочий: ~5 MHz → divider = 7
- CPU переключает через SD_DIVIDER регистр после init

## Порядок реализации

1. Расширить `SPI_MASTER` (MISO) + тесты
2. Проверить что OLED тесты не сломались
3. `SD_IO_DEVICE` + тесты
4. `PERIPHERAL_BUS` — 4-device mux
5. `TOP.sv` + `FPGA_TOP.sv` + `.xdc`
6. Синтез
7. `test_sd.c` — init + read block 0 на железе

## Риски

- **SPI_MASTER изменения** — могут сломать OLED. Нужно прогнать все тесты после.
- **SD init timing** — init на 400 kHz медленный (~20 байт/мс). CMD/response циклы через UART upload будут ОК.
- **Card detect** — входной пин, может потребовать pull-up.
- **PERIPHERAL_BUS усложнение** — 4 устройства. Пока чисто комбинационный mux, не проблема.
