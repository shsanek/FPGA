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

#define _memcpy(a, b, c) memcpy(a, b, c)
