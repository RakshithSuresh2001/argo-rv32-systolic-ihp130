.RECIPEPREFIX = >
CROSS  ?= riscv64-unknown-elf-
PROG   ?= hello
MARCH  ?= rv32im
CFLAGS  = -march=$(MARCH) -mabi=ilp32 -O2 -ffreestanding -fno-builtin -fno-asynchronous-unwind-tables -Wall
LDFLAGS = -T link.ld -nostdlib -Wl,--no-relax

all: $(PROG).hex
$(PROG).elf: start.S $(PROG).c soc.h link.ld
> $(CROSS)gcc $(CFLAGS) $(LDFLAGS) start.S $(PROG).c -o $@
$(PROG).bin: $(PROG).elf
> $(CROSS)objcopy -O binary $< $@
$(PROG).hex: $(PROG).bin
> python3 bin2hex.py $< > $@
> $(CROSS)size $(PROG).elf
> @echo "$@: $$(wc -l < $@) words"
clean:
> rm -f *.elf *.bin *.hex
