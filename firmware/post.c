// post.c: power-on self-test for bring-up. Tests every on-chip memory and the
// systolic array, then prints one summary line over the UART:
//   POST:I+D+A+S+   I=ISRAM (free space above the program)  D=DSRAM (between .bss
//                   and the stack)  A=systolic array  S=SRAM test block
//   '+' pass  '-' fail  '0' SRAM test block detached (sram_en strap low)
// On a failure, a detail line with the address and data goes out first.
#include "soc.h"

extern unsigned int _isram_end[], _bss_end[], _stack_top[];

static void fail(char blk, const char *what, unsigned int adr, unsigned int got, unsigned int exp) {
    putc_(blk); putc_(' '); puts_(what); puts_(" @"); puthex(adr);
    puts_(" got "); puthex(got); puts_(" exp "); puthex(exp); putc_('\n');
}

// March C- plus address-in-data over [p, p+n) words
static int memtest(char blk, volatile unsigned int *p, int n) {
    for (int k = 0; k < 2; k++) {
        unsigned int z = k ? 0x55555555u : 0u, o = ~z;
        for (int i = 0; i < n; i++) p[i] = z;
        for (int i = 0; i < n; i++) { if (p[i] != z) { fail(blk, "m1", (unsigned int)&p[i], p[i], z); return 1; } p[i] = o; }
        for (int i = 0; i < n; i++) { if (p[i] != o) { fail(blk, "m2", (unsigned int)&p[i], p[i], o); return 1; } p[i] = z; }
        for (int i = n - 1; i >= 0; i--) { if (p[i] != z) { fail(blk, "m3", (unsigned int)&p[i], p[i], z); return 1; } p[i] = o; }
        for (int i = n - 1; i >= 0; i--) { if (p[i] != o) { fail(blk, "m4", (unsigned int)&p[i], p[i], o); return 1; } p[i] = z; }
        for (int i = 0; i < n; i++) if (p[i] != z) { fail(blk, "m5", (unsigned int)&p[i], p[i], z); return 1; }
    }
    for (int i = 0; i < n; i++) p[i] = (unsigned int)&p[i] ^ 0xA5A50000u;
    for (int i = 0; i < n; i++) {
        unsigned int e = (unsigned int)&p[i] ^ 0xA5A50000u;
        if (p[i] != e) { fail(blk, "adr", (unsigned int)&p[i], p[i], e); return 1; }
    }
    return 0;
}

#define SA              0x10000000u
#define SA_WEIGHT_ROW   REG(SA + 0x00)
#define SA_WEIGHT_LO    REG(SA + 0x04)
#define SA_WEIGHT_HI    REG(SA + 0x08)
#define SA_WEIGHT_LOAD  REG(SA + 0x0C)
#define SA_ACT_LO       REG(SA + 0x10)
#define SA_ACT_HI       REG(SA + 0x14)
#define SA_PSUM_SEL     REG(SA + 0x18)
#define SA_PSUM_DATA    REG(SA + 0x1C)

static unsigned int pack4(const signed char *q) {
    return (unsigned char)q[0] | ((unsigned char)q[1] << 8) |
           ((unsigned char)q[2] << 16) | ((unsigned int)(unsigned char)q[3] << 24);
}

// one mixed-sign known-answer matrix-vector product
static int satest(void) {
    signed char w[8][8], a[8];
    for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) w[r][c] = (signed char)((r * 37 + c * 11 + 5) & 0xFF);
        a[r] = (signed char)((r * 53 + 17) & 0xFF);
        SA_WEIGHT_ROW = r; SA_WEIGHT_LO = pack4(&w[r][0]); SA_WEIGHT_HI = pack4(&w[r][4]); SA_WEIGHT_LOAD = 1;
    }
    SA_ACT_LO = pack4(&a[0]); SA_ACT_HI = pack4(&a[4]);
    for (volatile int d = 0; d < 64; d++);
    for (int c = 0; c < 8; c++) {
        int e = 0;
        for (int r = 0; r < 8; r++) e += (int)w[r][c] * (int)a[r];
        SA_PSUM_SEL = c;
        unsigned int g = SA_PSUM_DATA;
        if (g != (unsigned int)e) { fail('A', "col", (unsigned int)c, g, (unsigned int)e); return 1; }
    }
    return 0;
}

#define ST_BASE   0x30000000u
#define ST_STATUS REG(ST_BASE + 0x1000)

int main(void) {
    char r[4];
    volatile unsigned int *ib = (volatile unsigned int *)(((unsigned int)_isram_end + 63) & ~63u);
    volatile unsigned int *db = (volatile unsigned int *)(((unsigned int)_bss_end + 63) & ~63u);
    int in = (int)((0x1000u - ((unsigned int)ib & 0xFFFFu)) / 4);                 // up to end of ISRAM
    int dn = (int)(((unsigned int)_stack_top - 0x200u - (unsigned int)db) / 4);   // keep 512 B for the stack

    r[0] = memtest('I', ib, in) ? '-' : '+';
    r[1] = memtest('D', db, dn) ? '-' : '+';
    r[2] = satest() ? '-' : '+';
    unsigned int st = ST_STATUS;
    if ((st >> 8) != 0x5A4D00u)  { fail('S', "id", ST_BASE + 0x1000, st, 0x5A4D0000u); r[3] = '-'; }
    else if (!(st & 1))          r[3] = '0';
    else                         r[3] = memtest('S', (volatile unsigned int *)ST_BASE, 512) ? '-' : '+';

    puts_("POST:I"); putc_(r[0]); putc_('D'); putc_(r[1]); putc_('A'); putc_(r[2]); putc_('S'); putc_(r[3]); putc_('\n');
    return 0;
}
