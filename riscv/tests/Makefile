# -----------------------------------------------------------------------
# RV32I bare-metal test programs
# -----------------------------------------------------------------------
# Requires riscv32-unknown-elf-gcc (or riscv64-unknown-elf-gcc with -march=rv32i)
# Install on macOS:
#   brew tap riscv-software-src/riscv
#   brew install riscv-gnu-toolchain --HEAD
# -----------------------------------------------------------------------

CC       := riscv64-elf-gcc
OBJCOPY  := riscv64-elf-objcopy
CFLAGS   := -march=rv32i -mabi=ilp32 -O2 -Wall \
            -ffreestanding -nostdlib -nostartfiles \
            -I$(CURDIR)
LDFLAGS  := -T$(CURDIR)/linker.ld -Wl,--gc-sections
LDLIBS   := -lgcc

RUNTIME  := $(CURDIR)/crt0.s $(CURDIR)/runtime.c

PROGRAMS := $(sort $(dir $(wildcard programs/*/)))
HEXFILES := $(patsubst programs/%/,programs/%/program.hex,$(PROGRAMS))

.PHONY: all clean

all: $(HEXFILES)
	@echo "Built: $(HEXFILES)"

# Generic rule: programs/<name>/program.hex from programs/<name>/<name>.c
PYTHON   := $(shell which python3 2>/dev/null || echo /usr/bin/python3)

programs/%/program.hex: programs/%/program.elf
	$(OBJCOPY) -O binary $< $(patsubst %.hex,%.bin,$@)
	$(PYTHON) $(CURDIR)/bin2hex.py $(patsubst %.hex,%.bin,$@) $@

programs/%/program.elf: programs/%/*.c $(RUNTIME) linker.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(RUNTIME) $< $(LDLIBS)

clean:
	rm -f programs/*/program.elf programs/*/program.bin programs/*/program.hex
