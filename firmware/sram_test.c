// sram_test.c: self-test for the detachable C4M SRAM test block at 0x3000_0000.
// Prints "PASS" (enabled and good), "OFF" (strap low, isolation verified)
// or "FAIL ..." over the UART.
#include "soc.h"

#define ST_BASE    0x30000000u
#define ST_WORDS   512
#define ST_STATUS  REG(ST_BASE + 0x1000)
#define ST_ID      0x5A4D00u

static volatile unsigned int *const M = (volatile unsigned int *)ST_BASE;

static int fail(const char *what, int i, unsigned int got, unsigned int exp) {
    puts_("FAIL "); puts_(what); puts_(" @"); puthex((unsigned int)i);
    puts_(" got "); puthex(got); puts_(" exp "); puthex(exp); putc_('\n');
    return 1;
}

// March C-: up(w0) up(r0,w1) up(r1,w0) down(r0,w1) down(r1,w0) up(r0)
static int march(unsigned int z) {
    unsigned int o = ~z;
    for (int i = 0; i < ST_WORDS; i++) M[i] = z;
    for (int i = 0; i < ST_WORDS; i++) { if (M[i] != z) return fail("m1", i, M[i], z); M[i] = o; }
    for (int i = 0; i < ST_WORDS; i++) { if (M[i] != o) return fail("m2", i, M[i], o); M[i] = z; }
    for (int i = ST_WORDS - 1; i >= 0; i--) { if (M[i] != z) return fail("m3", i, M[i], z); M[i] = o; }
    for (int i = ST_WORDS - 1; i >= 0; i--) { if (M[i] != o) return fail("m4", i, M[i], o); M[i] = z; }
    for (int i = 0; i < ST_WORDS; i++) if (M[i] != z) return fail("m5", i, M[i], z);
    return 0;
}

int main(void) {
    unsigned int st = ST_STATUS;
    if ((st >> 8) != ST_ID) { fail("id", 0, st, ST_ID << 8); return 0; }

    if (!(st & 1)) {
        // detached: writes must be dropped and reads must come back as 0
        M[0] = 0xDEADBEEF; M[ST_WORDS - 1] = 0x12345678;
        if (M[0] != 0 || M[ST_WORDS - 1] != 0) { fail("iso", 0, M[0], 0); return 0; }
        puts_("OFF\n");
        return 0;
    }

    if (march(0x00000000u) || march(0x55555555u)) return 0;

    // address-in-data: catches decoder shorts and aliasing
    for (int i = 0; i < ST_WORDS; i++) M[i] = ((unsigned int)i << 16) | (unsigned int)(~i & 0xFFFF);
    for (int i = 0; i < ST_WORDS; i++) {
        unsigned int e = ((unsigned int)i << 16) | (unsigned int)(~i & 0xFFFF);
        if (M[i] != e) return fail("adr", i, M[i], e);
    }

    // byte and halfword lanes
    volatile unsigned char  *b = (volatile unsigned char *)ST_BASE;
    volatile unsigned short *h = (volatile unsigned short *)ST_BASE;
    M[7] = 0;
    b[28] = 0x11; b[29] = 0x22; b[30] = 0x33; b[31] = 0x44;
    if (M[7] != 0x44332211u) return fail("byte", 7, M[7], 0x44332211u);
    h[14] = 0xBEEF;
    if (M[7] != 0x4433BEEFu) return fail("half", 7, M[7], 0x4433BEEFu);
    if (b[30] != 0x33) return fail("rdb", 7, b[30], 0x33);

    puts_("PASS\n");
    return 0;
}
