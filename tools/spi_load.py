#!/usr/bin/env python3
"""Load firmware into Argo's instruction SRAM over SPI and start the CPU.

Uses Linux spidev (for example a Raspberry Pi: /dev/spidev0.0). The hex file is
the one firmware/Makefile writes: one 32-bit word per line.

  python3 spi_load.py firmware/hello.hex             # halt, load, verify count, run
  python3 spi_load.py firmware/post.hex --hz 1000000
  python3 spi_load.py firmware/hello.hex --dry-run   # print the SPI frames only
  python3 spi_load.py --array-test                    # systolic array over SPI only, no CPU needed
"""
import argparse, sys

def frames(words):
    yield [0x07]                                        # hold CPU in reset
    for a, w in enumerate(words):
        yield [0x05, (a >> 8) & 0x3, a & 0xFF, (w >> 24) & 0xFF, (w >> 16) & 0xFF, (w >> 8) & 0xFF, w & 0xFF]
    yield [0x06]                                        # release CPU reset

def s8(v):
    return v - 256 if v & 0x80 else v

def array_test(spi):
    """Same known-answer case as tb/tb_spi.sv test 1."""
    W = [[(r * 37 + c * 11 + 5) & 0xFF for c in range(8)] for r in range(8)]
    A = [(r * 53 + 17) & 0xFF for r in range(8)]
    for r in range(8):
        spi.xfer2([0x01, r] + W[r])
    rx = spi.xfer2([0x02] + A + [0x03] + [0x00] * 32)   # activations and readback in ONE frame
    got = rx[10:]                                        # 32 bytes: column 7 first, MSB first
    errs = 0
    for c in range(8):
        b = got[(7 - c) * 4:(7 - c) * 4 + 4]
        g = int.from_bytes(bytes(b), "big", signed=True)
        e = sum(s8(W[r][c]) * s8(A[r]) for r in range(8))
        if g != e:
            errs += 1
            print(f"col {c}: got {g} exp {e}")
    print("ARRAY PASS" if errs == 0 else f"ARRAY FAIL ({errs} columns)")
    return errs

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hex", nargs="?")
    ap.add_argument("--array-test", action="store_true")
    ap.add_argument("--bus", type=int, default=0)
    ap.add_argument("--dev", type=int, default=0)
    ap.add_argument("--hz", type=int, default=1_000_000, help="SPI clock, keep it at or below clk/10")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if a.array_test:
        import spidev
        spi = spidev.SpiDev(); spi.open(a.bus, a.dev); spi.mode = 0; spi.max_speed_hz = a.hz
        rc = array_test(spi); spi.close(); sys.exit(1 if rc else 0)
    if not a.hex:
        ap.error("give a .hex file or --array-test")

    words = [int(l, 16) for l in open(a.hex) if l.strip()]
    if len(words) > 1024:
        sys.exit(f"{len(words)} words do not fit the 4 KB instruction SRAM")

    if a.dry_run:
        for f in frames(words):
            print(" ".join(f"{b:02x}" for b in f))
        return

    import spidev
    spi = spidev.SpiDev()
    spi.open(a.bus, a.dev)
    spi.mode = 0
    spi.max_speed_hz = a.hz
    for f in frames(words):
        spi.xfer2(f)                                    # one command per chip-select frame
    spi.close()
    print(f"loaded {len(words)} words from {a.hex}, CPU running")

if __name__ == "__main__":
    main()
