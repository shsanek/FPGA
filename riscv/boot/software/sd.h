#ifndef SD_H
#define SD_H

/* SD card SPI driver for RISC-V bare-metal.
 * Uses SD_IO_DEVICE at 0x10020000.
 */

/* Returns 0 on success, negative on error.
 * Sets internal SDHC flag for correct block addressing. */
int sd_init(void);

/* Read 512-byte block from SD card.
 * block_addr: sector number (SDHC) or byte address (SDSC).
 * For SDHC, automatically uses sector addressing.
 * buf must be at least 512 bytes. */
int sd_read_block(unsigned int block_addr, unsigned char *buf);

#endif
