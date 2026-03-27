#ifndef FAT32_H
#define FAT32_H

/* Minimal FAT32 reader for bootloader.
 * Reads a file by 8.3 name from the first FAT32 partition on SD card.
 *
 * Usage:
 *   fat32_init()                     — read MBR + BPB, cache geometry
 *   fat32_load("BOOT    BIN", dst)   — find file, load to dst, return size
 */

/* Initialize FAT32: read MBR, find partition, parse BPB.
 * Returns 0 on success. */
int fat32_init(void);

/* Load file by 8.3 name (11 chars, space-padded, no dot).
 * dst: destination address in memory.
 * Returns file size in bytes, or negative on error. */
int fat32_load(const char *name83, unsigned char *dst);

#endif
