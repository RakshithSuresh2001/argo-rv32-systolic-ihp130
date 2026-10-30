// UART transmit. 8N1, 868 clocks per bit (115200 baud at 100 MHz).
#pragma once
#include <stdint.h>

#define ARGO_UART ARGO_REG(ARGO_UART_BASE)

static inline void uart_putc(char c) {
    while (!(ARGO_UART & 1)) ;          // bit 0 = transmitter ready
    ARGO_UART = (uint8_t)c;
}

static inline void uart_puts(const char *s) { while (*s) uart_putc(*s++); }

static inline void uart_puthex(uint32_t v) {
    for (int i = 28; i >= 0; i -= 4) uart_putc("0123456789abcdef"[(v >> i) & 0xf]);
}

// Decimal without division: the core has no divider (ENABLE_DIV=0) and the
// build links no libgcc, so subtract powers of ten instead.
static inline void uart_putdec(int32_t v) {
    static const uint32_t p10[] = {1000000000u, 100000000u, 10000000u, 1000000u,
                                   100000u, 10000u, 1000u, 100u, 10u, 1u};
    uint32_t u = (uint32_t)v;
    if (v < 0) { uart_putc('-'); u = 0u - u; }
    int started = 0;
    for (int i = 0; i < 10; i++) {
        char d = '0';
        while (u >= p10[i]) { u -= p10[i]; d++; }
        if (d != '0' || started || i == 9) { uart_putc(d); started = 1; }
    }
}
