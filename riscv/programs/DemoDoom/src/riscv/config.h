/*
 * config.h — Hardware config for DOOM on Arty A7.
 *
 * Address map (new):
 *   0x4000_xxxx  UART
 *   0x4001_xxxx  OLED
 *   0x4002_xxxx  SD
 *   0x4003_xxxx  TIMER
 *   0x4004_xxxx  SCRATCHPAD (128 KB)
 */

#pragma once

#include <stdint.h>
#include <string.h>

/* Timer device (cycle counter / milliseconds) */
#define TIMER_CYCLE_LO  (*(volatile uint32_t *)0x40030000U)
#define TIMER_CYCLE_HI  (*(volatile uint32_t *)0x40030004U)
#define TIMER_TIME_MS   (*(volatile uint32_t *)0x40030008U)
#define TIMER_TIME_US   (*(volatile uint32_t *)0x4003000CU)

/* Scratchpad — 128 KB BRAM, 1-тактовый доступ */
#define SCRATCH_BASE      0x40040000U
#define SCRATCH_SIZE      (128 * 1024)

/* Layout:
 * 0x00000  screen buffer 320×200 = 64000 bytes
 * 0x0FA00  colormaps 34×256      = 8704 bytes
 * 0x11C00  free                  = ~55 KB
 */
#define SCRATCH_SCREEN    ((uint8_t *)SCRATCH_BASE)
#define SCRATCH_COLORMAPS ((uint8_t *)(SCRATCH_BASE + 0x0FA00U))

/* Bus address flags */
#define BUS_STREAM        0x20000000U   /* bit29: bypass cache, use stream cache */

#define _memcpy(a, b, c) memcpy(a, b, c)
