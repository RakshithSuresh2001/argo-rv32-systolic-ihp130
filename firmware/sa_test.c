#include "soc.h"

#define SA              0x10000000u
#define SA_WEIGHT_ROW   REG(SA + 0x00)
#define SA_WEIGHT_LO    REG(SA + 0x04)
#define SA_WEIGHT_HI    REG(SA + 0x08)
#define SA_WEIGHT_LOAD  REG(SA + 0x0C)
#define SA_ACT_LO       REG(SA + 0x10)
#define SA_ACT_HI       REG(SA + 0x14)
#define SA_PSUM_SEL     REG(SA + 0x18)
#define SA_PSUM_DATA    REG(SA + 0x1C)

static signed char W[8][8], A[8];

static unsigned int pack4(const signed char *p) {
    return (unsigned char)p[0] | ((unsigned char)p[1] << 8) |
           ((unsigned char)p[2] << 16) | ((unsigned int)(unsigned char)p[3] << 24);
}

static void load_weights(void) {
    for (int r = 0; r < 8; r++) {
        SA_WEIGHT_ROW  = r;
        SA_WEIGHT_LO   = pack4(&W[r][0]);
        SA_WEIGHT_HI   = pack4(&W[r][4]);
        SA_WEIGHT_LOAD = 1;
    }
}

static int run_and_check(int tag) {
    SA_ACT_LO = pack4(&A[0]);
    SA_ACT_HI = pack4(&A[4]);
    for (volatile int d = 0; d < 64; d++);
    for (int c = 0; c < 8; c++) {
        int exp = 0;
        for (int r = 0; r < 8; r++) exp += (int)W[r][c] * (int)A[r];
        SA_PSUM_SEL = c;
        unsigned int got = SA_PSUM_DATA;
        if (got != (unsigned int)exp) {
            puts_("FAIL t"); putc_('0' + tag); puts_(" c"); putc_('0' + c);
            puts_(" got "); puthex(got); puts_(" exp "); puthex((unsigned int)exp); putc_('\n');
            return 1;
        }
    }
    return 0;
}

int main(void) {
    // Set 1: mixed signs (values >= 128 wrap negative)
    for (int r = 0; r < 8; r++)
        for (int c = 0; c < 8; c++) W[r][c] = (signed char)((r * 37 + c * 11 + 5) & 0xFF);
    load_weights();
    for (int r = 0; r < 8; r++) A[r] = (signed char)((r * 53 + 17) & 0xFF);
    if (run_and_check(1)) return 0;
    for (int r = 0; r < 8; r++) A[r] = (r == 3) ? -1 : 0;       // one-hot -1: psum = -W[3][c]
    if (run_and_check(2)) return 0;

    // Set 2: corner values
    for (int r = 0; r < 8; r++)
        for (int c = 0; c < 8; c++) W[r][c] = -128;
    load_weights();
    for (int r = 0; r < 8; r++) A[r] = -128;                    // max positive: 8 * 16384
    if (run_and_check(3)) return 0;
    for (int r = 0; r < 8; r++) A[r] = 127;                     // large negative sum
    if (run_and_check(4)) return 0;

    // Set 3: reload all rows with a different mixed pattern
    for (int r = 0; r < 8; r++)
        for (int c = 0; c < 8; c++) W[r][c] = (signed char)(((7 - r) * 29 + (7 - c) * 13 + 200) & 0xFF);
    load_weights();
    for (int r = 0; r < 8; r++) A[r] = (signed char)((r * 91 + 3) & 0xFF);
    if (run_and_check(5)) return 0;

    puts_("PASS\n");
    return 0;
}
