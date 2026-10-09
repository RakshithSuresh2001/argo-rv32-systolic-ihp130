OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
  ISRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 4K
  DSRAM (rw)  : ORIGIN = 0x00010000, LENGTH = 4K
}
SECTIONS {
  .text : { *(.text.init) *(.text .text.*) *(.rodata .rodata.* .srodata .srodata.*) } > ISRAM
  .data : { *(.data .data.* .sdata .sdata.*) } > ISRAM
  .bss (NOLOAD) : { _bss_start = .; *(.bss .bss.* .sbss .sbss.* COMMON) . = ALIGN(4); _bss_end = .; } > DSRAM
  /DISCARD/ : { *(.eh_frame*) *(.comment) }
  _stack_top = ORIGIN(DSRAM) + LENGTH(DSRAM) - 16;
}
