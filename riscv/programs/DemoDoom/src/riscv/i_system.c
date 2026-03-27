/*
 * i_system.c — System support for DOOM on Arty A7.
 */

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "doomdef.h"
#include "doomstat.h"

#include "d_main.h"
#include "g_game.h"
#include "m_misc.h"
#include "i_sound.h"
#include "i_video.h"

#include "i_system.h"

#include "console.h"
#include "config.h"


/* Time tracking via TIMER_DEVICE (0x08030000) */
static uint32_t time_base_ms = 0;

void
I_Init(void)
{
    time_base_ms = TIMER_TIME_MS;
}

byte *
I_ZoneBase(int *size)
{
    /* Give 6M to DOOM */
    *size = 6 * 1024 * 1024;
    return (byte *) malloc(*size);
}

int
I_GetTime(void)
{
    /* DOOM expects tics at 35 Hz (TICRATE) */
    uint32_t now = TIMER_TIME_MS;
    uint32_t elapsed = now - time_base_ms;
    return (int)(elapsed * 35 / 1000);
}

static void
I_GetRemoteEvent(void)
{
    event_t event;

    int ch = console_getchar_nowait();
    if (ch == -1)
        return;

    event.type = ev_keydown;
    event.data1 = ch;
    D_PostEvent(&event);

    event.type = ev_keyup;
    event.data1 = ch;
    D_PostEvent(&event);
}

void
I_StartFrame(void)
{
}

void
I_StartTic(void)
{
    I_GetRemoteEvent();
}

ticcmd_t *
I_BaseTiccmd(void)
{
    static ticcmd_t emptycmd;
    return &emptycmd;
}

void
I_Quit(void)
{
    D_QuitNetGame();
    M_SaveDefaults();
    I_ShutdownGraphics();
    printf("[DOOM] Quit.\n");
    __asm__ volatile("ebreak");
    while (1) {}
}

byte *
I_AllocLow(int length)
{
    return (byte *)malloc(length);
}

void
I_Tactile(int on, int off, int total)
{
    (void)on; (void)off; (void)total;
}

void
I_Error(char *error, ...)
{
    va_list argptr;

    va_start(argptr, error);
    fprintf(stderr, "Error: ");
    vfprintf(stderr, error, argptr);
    fprintf(stderr, "\n");
    va_end(argptr);

    fflush(stderr);

    if (demorecording)
        G_CheckDemoStatus();

    D_QuitNetGame();
    I_ShutdownGraphics();

    printf("[DOOM] Fatal error, halting.\n");
    __asm__ volatile("ebreak");
    while (1) {}
}
