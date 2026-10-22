# Argo bring-up plan

How to take a packaged Argo from first power-up to a full self-test. Each step only needs what the previous one proved, so a failure points at one block.

## Board

- Three supplies, each with a current readout: `VDD` 1.2 V, `IOVDD` (IO voltage, 3.3 V nominal), `VDD_SRAM` 1.2 V. Keep `VDD_SRAM` separate so it can be switched off and measured on its own.
- Clock: a function generator or oscillator into `clk`. Start at 10 MHz.
- `rst_n`: pull-up plus a button to ground.
- `sram_en`: pull-down plus a jumper to IOVDD.
- `uart_rx`: tie high (unused in this revision).
- SPI host: a Raspberry Pi (`/dev/spidev0.0`) or any SPI adapter, at IO voltage levels.
- UART: a USB-serial adapter on `uart_tx`.

## UART baud rate

The UART divider is fixed at 868 clocks per bit, so the baud rate scales with the clock:

| `clk` | Baud |
|---|---|
| 10 MHz | 11520 |
| 50 MHz | 57600 |
| 100 MHz | 115200 |

Set the host terminal to `clk / 868`.

## Steps

1. **Power, no clock.** Current-limit every supply (about 50 mA on VDD to start). Bring up IOVDD and VDD with `VDD_SRAM` off and `sram_en` low. Record the idle current on each rail. A short or a supply far above the others stops here.
2. **Clock and reset.** Apply a 10 MHz clock, pulse `rst_n`. The CPU stays in reset until the SPI run command, so the current should rise only by clock-tree switching.
3. **Systolic array over SPI, no CPU.** `python3 tools/spi_load.py --array-test --hz 1000000` should print `ARRAY PASS`. This proves the clock, reset, SPI pads, the SPI slave and the array, before any firmware runs.
4. **First firmware.** `python3 tools/spi_load.py firmware/hello.hex`. The terminal at 11520 baud should show `HI`. This proves the boot loader, instruction SRAM, CPU and UART.
5. **Power-on self-test, SRAM block detached.** Load `firmware/post.hex`. Expect `POST:I+D+A+S0`: instruction SRAM, data SRAM and array pass, and the SRAM test block reports detached.
6. **SRAM test block.** Turn on `VDD_SRAM`, set `sram_en` high, pulse reset and reload `post.hex`. Expect `POST:I+D+A+S+`. Record the `VDD_SRAM` current before and during the test. `firmware/sram_test.hex` runs a longer test on that block alone.
7. **Frequency sweep.** Raise `clk` in steps (25, 50, 75, 100 MHz and up), changing the terminal baud to `clk / 868` each time, and rerun `post.hex`. Record the highest passing frequency per chip, and per supply voltage if the VDD supply can be stepped (1.08, 1.20, 1.32 V).
8. **Power.** At 100 MHz, record the VDD current with the CPU halted (SPI command `0x07`), running `hello`, and running `sa_test` in a loop.

## Reading a POST line

`POST:I<r>D<r>A<r>S<r>`, where `<r>` is `+` pass, `-` fail, or `0` (SRAM test block detached).

| Letter | Block | Range tested |
|---|---|---|
| I | Instruction SRAM | Free space above the program, up to `0x0000_0FFF` |
| D | Data SRAM | Between `.bss` and the stack, keeping 512 B for the stack |
| A | Systolic array | One mixed-sign 8x8 known-answer product |
| S | SRAM test block | All 512 words |

The memory tests are March C- with two background patterns plus an address-in-data pass. On a failure a detail line comes first, for example `D m3 @00010440 got ffffffff exp 55555555`: block, march element, word address, read value, expected value.

## If something fails

| Symptom | Check |
|---|---|
| No `ARRAY PASS` | Clock present at the pad, reset released, SPI mode 0, SPI clock at or below `clk` / 10, IOVDD level |
| `ARRAY PASS` but no `HI` | Terminal baud matches `clk / 868`, `uart_tx` wiring, reload with a slower SPI clock |
| `HI` but POST `I-` or `D-` | Note the failing address. Repeat at a lower clock and higher VDD to separate timing from a hard fault |
| `S-` | Check `VDD_SRAM` is on. If it still fails, set `sram_en` low and the rest of the chip keeps working |
| Works slowly, fails fast | Expected near the timing limit. Signoff predicts about 83 MHz worst case and 100 MHz or more on typical parts |

To reload after a run, send SPI `0x07` (halt) before loading; `spi_load.py` does this.
