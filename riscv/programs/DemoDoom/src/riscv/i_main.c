/*
 * i_main.c — Main entry point for DOOM on Arty A7.
 */

#include "doomdef.h"
#include "d_main.h"
#include "console.h"

/* SD + FAT32 */
extern int sd_init(void);
extern int fat32_init(void);
extern void doom_load_wad(const char *filename);

int main(void)
{
    console_init();
    console_printf("DOOM on Arty A7\n");

    console_printf("SD card init... ");
    int r = sd_init();
    if (r != 0) {
        console_printf("FAILED (%d)\n", r);
        while (1) {}
    }
    console_printf("OK\n");

    console_printf("FAT32 init... ");
    r = fat32_init();
    if (r != 0) {
        console_printf("FAILED (%d)\n", r);
        while (1) {}
    }
    console_printf("OK\n");

    doom_load_wad("doomu.wad");

    D_DoomMain();
    return 0;
}
