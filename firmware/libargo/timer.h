// Cycle counter (PicoRV32 ENABLE_COUNTERS=1). Low 32 bits wrap every
// 42.9 s at 100 MHz, so subtract two readings to time a block of code.
#pragma once
#include <stdint.h>

static inline uint32_t rdcycle(void) {
    uint32_t c;
    // csrrs c, cycle, x0. Written with .insn so the build needs no Zicsr flag.
    __asm__ volatile (".insn i 0x73, 2, %0, x0, -1024" : "=r"(c));
    return c;
}
