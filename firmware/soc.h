#pragma once
#define REG(a) (*(volatile unsigned int *)(a))
#define UART   REG(0x20000000)
static inline void putc_(char c) { while (!(UART & 1)); UART = (unsigned char)c; }
static inline void puts_(const char *s) { while (*s) putc_(*s++); }
static inline void puthex(unsigned int v) {
    for (int i = 28; i >= 0; i -= 4) putc_("0123456789abcdef"[(v >> i) & 0xf]);
}
