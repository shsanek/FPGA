/*
 * config.h — Hardware config for DOOM on Arty A7.
 */

#pragma once

#include <stdint.h>
#include <string.h>

/* Timer device (cycle counter / milliseconds) */
#define TIMER_CYCLE_LO  (*(volatile uint32_t *)0x10030000U)
#define TIMER_CYCLE_HI  (*(volatile uint32_t *)0x10030004U)
#define TIMER_TIME_MS   (*(volatile uint32_t *)0x10030008U)
#define TIMER_TIME_US   (*(volatile uint32_t *)0x1003000CU)

/* Scratchpad — 128 KB BRAM, 1-тактовый доступ */
#define SCRATCH_BASE      0x10040000U
#define SCRATCH_SIZE      (128 * 1024)

/* Layout:
 * 0x00000  screen buffer 320×200 = 64000 bytes
 * 0x0FA00  colormaps 34×256      = 8704 bytes
 * 0x11C00  free                  = ~55 KB
 */
#define SCRATCH_SCREEN    ((uint8_t *)SCRATCH_BASE)
#define SCRATCH_COLORMAPS ((uint8_t *)(SCRATCH_BASE + 0x0FA00U))

/* Hardware Blitter (inside SCRATCHPAD, offset 0x20000) */
#define BLIT_BASE        (SCRATCH_BASE + 0x20000U)
#define BLIT_CMD         (*(volatile uint32_t *)(BLIT_BASE + 0x00))
#define BLIT_STATUS      (*(volatile uint32_t *)(BLIT_BASE + 0x04))
#define BLIT_SRC_ADDR    (*(volatile uint32_t *)(BLIT_BASE + 0x08))
#define BLIT_SRC_FRAC    (*(volatile uint32_t *)(BLIT_BASE + 0x0C))
#define BLIT_SRC_STEP    (*(volatile uint32_t *)(BLIT_BASE + 0x10))
#define BLIT_SRC_MASK    (*(volatile uint32_t *)(BLIT_BASE + 0x14))
#define BLIT_DST_OFFSET  (*(volatile uint32_t *)(BLIT_BASE + 0x18))
#define BLIT_DST_STEP    (*(volatile uint32_t *)(BLIT_BASE + 0x1C))
#define BLIT_COUNT       (*(volatile uint32_t *)(BLIT_BASE + 0x20))
#define BLIT_CMAP_OFFSET (*(volatile uint32_t *)(BLIT_BASE + 0x24))
#define BLIT_SRC_YFRAC   (*(volatile uint32_t *)(BLIT_BASE + 0x28))
#define BLIT_SRC_YSTEP   (*(volatile uint32_t *)(BLIT_BASE + 0x2C))
#define BLIT_SRC_SHIFT   (*(volatile uint32_t *)(BLIT_BASE + 0x30))

#define _memcpy(a, b, c) memcpy(a, b, c)
