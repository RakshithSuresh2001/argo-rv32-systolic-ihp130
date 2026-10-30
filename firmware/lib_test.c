// lib_test.c: first libargo program. Checks the UART helpers and runs one
// 8x8 matrix-vector product on the array and on the CPU, then compares the
// results and the cycle counts. Last line is PASS or FAIL.
#include "libargo/argo.h"

static int8_t W[SA_N][SA_N], X[SA_N];

int main(void) {
    uart_puts("libargo dec "); uart_putdec(-1234567); uart_putc(' '); uart_putdec(0);
    uart_puts(" hex "); uart_puthex(0xA5A5u); uart_putc('\n');

    for (int r = 0; r < SA_N; r++) {
        for (int c = 0; c < SA_N; c++) W[r][c] = (int8_t)(r * 37 + c * 11 + 5);
        X[r] = (int8_t)(r * 53 + 17);
    }
    int32_t ys[SA_N], yc[SA_N];

    uint32_t t0 = rdcycle();
    sa_load_weights(W);
    uint32_t t1 = rdcycle();
    sa_matvec(X, ys);
    uint32_t t2 = rdcycle();
    sa_matvec_ref(W, X, yc);
    uint32_t t3 = rdcycle();

    int ok = 1;
    for (int c = 0; c < SA_N; c++) if (ys[c] != yc[c]) ok = 0;

    uart_puts("y0 "); uart_putdec(ys[0]); uart_puts(" y7 "); uart_putdec(ys[7]);
    uart_puts(" load "); uart_putdec((int32_t)(t1 - t0));
    uart_puts(" sa "); uart_putdec((int32_t)(t2 - t1));
    uart_puts(" cpu "); uart_putdec((int32_t)(t3 - t2)); uart_putc('\n');
    uart_puts(ok ? "PASS\n" : "FAIL\n");
    return 0;
}
