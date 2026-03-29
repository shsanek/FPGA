# DOOM Benchmarks (E1M1, стоим на месте)

Все замеры: Arty A7-100T, 40 MHz CPU, OLED 96x64, стабильные кадры (после прогрева кэша).

## Конфигурации

| Код | Описание |
|-----|----------|
| **S** | Software rendering (без блиттера) |
| **B** | Hardware Blitter (column + span) |
| **B+S** | Blitter + Stream cache (bit29 в SRC_ADDR) |
| **B+I** | Blitter + I-cache 4 KB (direct-mapped, 256 линий) |

## Render breakdown (us)

| Метрика | Описание | S | B | B+S | B+I |
|---------|----------|---|---|-----|-----|
| setup | Камера, очистка буферов | 206 | 242 | 231 | 157 |
| bsp | BSP traversal + стены | 80,930 | 66,130 | 67,090 | 49,980 |
| planes | Полы/потолки (visplane+span) | 99,400 | 25,250 | 26,790 | 29,220 |
| masked | Спрайты, прозрачные текстуры | 7,800 | 6,020 | 6,150 | 3,980 |
| **RENDER** | **Итого рендер** | **188,350** | **97,640** | **100,260** | **83,340** |

## Full frame breakdown (us)

| Метрика | Описание | S | B | B+S | B+I |
|---------|----------|---|---|-----|-----|
| pre | Статус-бар, меню, wipe | 3,760 | 3,710 | 3,710 | 1,420 |
| render | Рендер (см. выше) | 188,350 | 97,640 | 100,260 | 83,340 |
| post | HUD-текст, рамка | 39 | 40 | 40 | 32 |
| oled | Downscale + SPI flush | 7,300 | 7,330 | 7,340 | 2,400 |
| tics | AI, физика, движение | 11,540 | 11,360 | 11,190 | 6,010 |
| input | Чтение UART | 0 | 0 | 1 | 0 |
| **LOOP** | **Полный кадр** | **226,000** | **135,000** | **137,600** | **107,900** |
| **FPS** | **Кадров в секунду** | **4.4** | **7.4** | **7.3** | **9.3** |

## Сравнение

| Переход | LOOP | Ускорение | FPS |
|---------|------|-----------|-----|
| S (baseline) | 226,000 us | — | 4.4 |
| S → B | 135,000 us | +67% | 7.4 |
| S → B+S | 137,600 us | +64% | 7.3 |
| S → B+I | 107,900 us | **+109%** | **9.3** |
| B → B+I | 135,000 → 107,900 | **+25%** | 7.4 → 9.3 |

## Анализ I-cache эффекта

I-cache (4 KB direct-mapped) ускоряет **всё**, не только рендер:

| Метрика | B | B+I | Ускорение | Причина |
|---------|---|-----|-----------|---------|
| bsp | 66,130 | 49,980 | **-24%** | BSP-цикл в I-cache, D-cache не вытесняется |
| planes | 25,250 | 29,220 | +16% (хуже) | Возможно conflict miss в I-cache |
| masked | 6,020 | 3,980 | **-34%** | Код спрайтов кэшируется |
| oled | 7,330 | 2,400 | **-67%** | Цикл downscale целиком в I-cache |
| tics | 11,360 | 6,010 | **-47%** | Игровая логика в I-cache |
| pre | 3,710 | 1,420 | **-62%** | Статус-бар код в I-cache |
| **LOOP** | **135,000** | **107,900** | **-20%** | |

Planes стали чуть медленнее — вероятно conflict miss: код span-рендерера конфликтует по индексу
с другим кодом в direct-mapped I-cache.

## Текущие узкие места (B+I)

```
LOOP 107,900 us (9.3 FPS)
├── bsp      49,980 us  46.3%  ← BSP traversal + стены (CPU-bound)
├── planes   29,220 us  27.1%  ← visplane + span (blitter, но setup на CPU)
├── tics      6,010 us   5.6%  ← AI, физика
├── masked    3,980 us   3.7%  ← спрайты (CPU)
├── oled      2,400 us   2.2%  ← downscale + SPI
├── pre       1,420 us   1.3%  ← статус-бар
└── прочее      ~890 us  0.8%
```

## Возможные следующие шаги

| # | Оптимизация | Цель | Ожидание |
|---|-------------|------|----------|
| 1 | I-cache 8-16 KB | planes regression, bsp | Устранить conflict miss, bsp ещё -10-20% |
| 2 | 2-way set-associative I-cache | planes regression | Меньше conflict miss при том же размере |
| 3 | Dual-port BRAM (pixel write + cmap read) | bsp, planes | -4 такта/пиксель в блиттере |
| 4 | Masked спрайты через блиттер | masked | 4ms → ~1.5ms |
| 5 | OLED scale аппаратно | oled | 2.4ms → ~0ms CPU |

## Сырые логи

<details>
<summary>S — Software</summary>

```
[RENDER F15] setup=206 bsp=80929 planes=99406 masked=7808 total=188349 us
[DISP F279] pre=3758(1%) render=188288(94%) post=39(0%) oled=7305(3%) total=199390 us
[LOOP 279] total=226001 input=0(0%) tics=11516(5%) display=214485(94%) us
[RENDER F29] setup=206 bsp=80931 planes=99406 masked=7808 total=188351 us
[DISP F293] pre=3757(1%) render=188292(94%) post=39(0%) oled=7305(3%) total=199393 us
[LOOP 293] total=226016 input=0(0%) tics=11532(5%) display=214484(94%) us
[RENDER F43] setup=206 bsp=80937 planes=99403 masked=7803 total=188349 us
[DISP F307] pre=4522(2%) render=188283(94%) post=39(0%) oled=7305(3%) total=200149 us
[LOOP 307] total=226802 input=0(0%) tics=11559(5%) display=215243(94%) us
```

</details>

<details>
<summary>B — Blitter</summary>

```
[RENDER F26] setup=243 bsp=66132 planes=25222 masked=6074 total=97671 us
[DISP F127] pre=3711(3%) render=97684(89%) post=40(0%) oled=7335(6%) total=108770 us
[LOOP 127] total=135715 input=0(0%) tics=12097(8%) display=123618(91%) us
[RENDER F51] setup=242 bsp=66132 planes=25222 masked=6074 total=97670 us
[DISP F152] pre=3710(3%) render=97695(89%) post=41(0%) oled=7334(6%) total=108780 us
[LOOP 152] total=134571 input=0(0%) tics=10943(8%) display=123628(91%) us
[RENDER F76] setup=242 bsp=66122 planes=25299 masked=5906 total=97569 us
[DISP F177] pre=3713(3%) render=97688(89%) post=39(0%) oled=7334(6%) total=108774 us
[LOOP 177] total=134667 input=0(0%) tics=11042(8%) display=123625(91%) us
```

</details>

<details>
<summary>B+S — Blitter + Stream</summary>

```
[RENDER F25] setup=232 bsp=66972 planes=26845 masked=6145 total=100194 us
[DISP F556] pre=3713(3%) render=100311(90%) post=40(0%) oled=7336(6%) total=111400 us
[LOOP 556] total=137311 input=1(0%) tics=10810(7%) display=126500(92%) us
[RENDER F50] setup=231 bsp=67147 planes=26761 masked=6149 total=100288 us
[DISP F581] pre=3708(3%) render=100135(90%) post=39(0%) oled=7336(6%) total=111218 us
[LOOP 581] total=138308 input=1(0%) tics=11992(8%) display=126315(91%) us
[RENDER F75] setup=231 bsp=67139 planes=26763 masked=6150 total=100283 us
[DISP F606] pre=3710(3%) render=100141(90%) post=40(0%) oled=7336(6%) total=111227 us
[LOOP 606] total=137079 input=1(0%) tics=10756(7%) display=126322(92%) us
```

</details>

<details>
<summary>B+I — Blitter + I-cache 4KB</summary>

```
[RENDER F33] setup=156 bsp=49980 planes=29218 masked=3986 total=83340 us
[DISP F1799] pre=1417(1%) render=83353(95%) post=32(0%) oled=2402(2%) total=87204 us
[LOOP 1799] total=108774 input=0(0%) tics=6941(6%) display=101833(93%) us
[RENDER F66] setup=157 bsp=49977 planes=29216 masked=3983 total=83333 us
[DISP F1832] pre=1416(1%) render=83358(95%) post=32(0%) oled=2401(2%) total=87207 us
[LOOP 1832] total=106925 input=0(0%) tics=5088(4%) display=101837(95%) us
```

</details>
