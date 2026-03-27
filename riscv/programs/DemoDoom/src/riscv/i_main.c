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

/* Boot screen */
extern void boot_oled_init(void);
extern void boot_oled_progress(int percent);
extern void boot_oled_status(const char *msg);

int main(void)
{
    console_init();

    /* Init OLED and show boot screen */
    boot_oled_init();

    console_printf("DOOM on Arty A7\n");

    boot_oled_status("SD INIT");
    console_printf("SD card init... ");
    int r = sd_init();
    if (r != 0) {
        boot_oled_status("SD FAIL!");
        console_printf("FAILED (%d)\n", r);
        while (1) {}
    }
    console_printf("OK\n");
    boot_oled_progress(5);

    boot_oled_status("FAT32");
    console_printf("FAT32 init... ");
    r = fat32_init();
    if (r != 0) {
        boot_oled_status("FAT FAIL!");
        console_printf("FAILED (%d)\n", r);
        while (1) {}
    }
    console_printf("OK\n");
    boot_oled_progress(10);

    boot_oled_status("LOADING WAD");
    doom_load_wad("doomu.wad");
    boot_oled_progress(80);

    boot_oled_status("INIT ENGINE");
    D_DoomMain();
    return 0;
}
