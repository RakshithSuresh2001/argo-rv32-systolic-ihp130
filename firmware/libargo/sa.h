// 8x8 int8 weight-stationary systolic array.
// y[c] = sum over r of W[r][c] * x[r], 32-bit signed.
#pragma once
#include <stdint.h>

#define SA_WEIGHT_ROW   ARGO_REG(ARGO_SA_BASE + 0x00)
#define SA_WEIGHT_LO    ARGO_REG(ARGO_SA_BASE + 0x04)
#define SA_WEIGHT_HI    ARGO_REG(ARGO_SA_BASE + 0x08)
#define SA_WEIGHT_LOAD  ARGO_REG(ARGO_SA_BASE + 0x0C)
#define SA_ACT_LO       ARGO_REG(ARGO_SA_BASE + 0x10)
#define SA_ACT_HI       ARGO_REG(ARGO_SA_BASE + 0x14)
#define SA_PSUM_SEL     ARGO_REG(ARGO_SA_BASE + 0x18)
#define SA_PSUM_DATA    ARGO_REG(ARGO_SA_BASE + 0x1C)

#define SA_N 8
#define SA_SETTLE 0    // delay-loop iterations after writing activations

static inline uint32_t sa_pack4(const int8_t *p) {
    return (uint32_t)(uint8_t)p[0] | ((uint32_t)(uint8_t)p[1] << 8) |
           ((uint32_t)(uint8_t)p[2] << 16) | ((uint32_t)(uint8_t)p[3] << 24);
}

// Load all 8 weight rows. w[r][c] feeds output column c.
static inline void sa_load_weights(const int8_t w[SA_N][SA_N]) {
    for (int r = 0; r < SA_N; r++) {
        SA_WEIGHT_ROW  = (uint32_t)r;
        SA_WEIGHT_LO   = sa_pack4(&w[r][0]);
        SA_WEIGHT_HI   = sa_pack4(&w[r][4]);
        SA_WEIGHT_LOAD = 1;
    }
}

// One matrix-vector product with the weights already loaded.
static inline void sa_matvec(const int8_t x[SA_N], int32_t y[SA_N]) {
    SA_ACT_LO = sa_pack4(&x[0]);
    SA_ACT_HI = sa_pack4(&x[4]);
    for (volatile int d = 0; d < SA_SETTLE; d++) ;
    for (int c = 0; c < SA_N; c++) {
        SA_PSUM_SEL = (uint32_t)c;
        y[c] = (int32_t)SA_PSUM_DATA;
    }
}

// Same math on the CPU, for checking and for speed comparisons.
static inline void sa_matvec_ref(const int8_t w[SA_N][SA_N], const int8_t x[SA_N], int32_t y[SA_N]) {
    for (int c = 0; c < SA_N; c++) {
        int32_t s = 0;
        for (int r = 0; r < SA_N; r++) s += (int32_t)w[r][c] * (int32_t)x[r];
        y[c] = s;
    }
}
