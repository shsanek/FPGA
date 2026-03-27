# Makefile for Stage 1 bootloader
#
# Targets:
#   make stage1      — build stage1.bin (raw binary)
#   make stage1_hdr  — build stage1_with_header.bin (for write_cfgmem)
#   make boot        — build BOOT.BIN from a test program (set BOOT_SRC)
#   make clean

CROSS    ?= riscv-none-elf-
CC        = $(CROSS)gcc
OBJCOPY   = $(CROSS)objcopy
SIZE      = $(CROSS)size

CFLAGS    = -march=rv32i -mabi=ilp32 -O2 -ffreestanding -nostdlib -nostartfiles -Wall
TESTS_DIR = ../../tests

SW_DIR    = ../software
SRC       = $(SW_DIR)/stage1.c $(SW_DIR)/sd.c $(SW_DIR)/fat32.c
CRT0      = $(TESTS_DIR)/crt0.s
RUNTIME   = $(TESTS_DIR)/runtime.c

.PHONY: stage1 stage1_hdr boot clean

# ---- Stage 1 (for QSPI flash, loads at 0x07F00000) ----

stage1: stage1.bin
	$(SIZE) stage1.elf

stage1.elf: $(CRT0) $(RUNTIME) $(SRC) stage1.ld
	$(CC) $(CFLAGS) -T stage1.ld $(CRT0) $(RUNTIME) $(SRC) -lgcc -o $@

stage1.bin: stage1.elf
	$(OBJCOPY) -O binary $< $@

stage1_hdr: stage1.bin
	python3 prepend_header.py stage1.bin stage1_with_header.bin

# ---- BOOT.BIN (for SD card, loads at 0x00000000 — standard linker.ld) ----
# Usage: make boot BOOT_SRC=../../tests/programs/hello/hello.c

BOOT_SRC ?= ../../tests/programs/hello/hello.c

boot: BOOT.BIN

boot.elf: $(CRT0) $(RUNTIME) $(BOOT_SRC) $(TESTS_DIR)/linker.ld
	$(CC) $(CFLAGS) -T $(TESTS_DIR)/linker.ld $(CRT0) $(RUNTIME) $(BOOT_SRC) -lgcc -o $@

BOOT.BIN: boot.elf
	$(OBJCOPY) -O binary $< $@
	$(SIZE) boot.elf

# ---- Clean ----

clean:
	rm -f *.elf *.bin *.o
