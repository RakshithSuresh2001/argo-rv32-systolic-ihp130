// libargo: small header-only support library for Argo firmware.
// Include this one file. Everything is static inline, so no extra build step.
#pragma once
#include <stdint.h>

#define ARGO_REG(a)      (*(volatile uint32_t *)(a))

// Memory map (docs/DATASHEET.md)
#define ARGO_ISRAM_BASE  0x00000000u   // 4 KB, code + rodata + .data
#define ARGO_DSRAM_BASE  0x00010000u   // 4 KB, .bss + stack
#define ARGO_SA_BASE     0x10000000u   // systolic array registers
#define ARGO_UART_BASE   0x20000000u   // UART TX
#define ARGO_STEST_BASE  0x30000000u   // 2 KB SRAM test block

#include "uart.h"
#include "timer.h"
#include "sa.h"
