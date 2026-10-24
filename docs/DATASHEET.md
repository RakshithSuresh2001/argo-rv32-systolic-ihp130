# Argo datasheet

Argo is a RISC-V test chip with an 8x8 systolic array accelerator, built on IHP SG13CMOS5L (130 nm, 1.2 V core) with an open-source flow and KLayout-only signoff.

Revision: v2 (October 2026), signoff tag `argo-v2-sram-signoff`.

## Features

- PicoRV32 CPU, RV32IM (hardware multiply, no divide, no compressed ISA, no interrupts), cycle and instret counters
- 8x8 weight-stationary systolic array, signed int8 inputs, 32-bit accumulators, 64 MACs per cycle
- 4 KB instruction SRAM and 4 KB data SRAM (IHP `RM_IHPSG13_1P_1024x32` macros)
- 2 KB SRAM test block (512x32, byte write enables) from an open-source SRAM compiler, on its own supply and detachable by a strap pin
- SPI slave: boot loader for the instruction SRAM, CPU run and halt, direct systolic array access
- UART transmitter, 8N1, 115200 baud at 100 MHz
- 16 pads, 70 x 70 um bond pads, 2.2 x 2.2 mm die

## Pinout

| Pad | Side | Type | Function |
|---|---|---|---|
| `clk` | North | Input | System clock, 100 MHz nominal |
| `rst_n` | North | Input | Asynchronous active-low reset |
| `VDD` | North | Power | Core supply, 1.2 V |
| `VSS` | North | Ground | Core ground |
| `uart_rx` | West | Input | Not used in this revision, tie high |
| `uart_tx` | West | Output, 16 mA | UART transmit |
| `sram_en` | West | Input | SRAM test block enable. Low: detached. High: enabled. Pull down on the board |
| `VDD` (2) | West | Power | Second core supply pad, 1.2 V. Connect to the same rail as the north `VDD` |
| `VSS` (2) | West | Ground | Second core ground pad |
| `spi_clk` | East | Input | SPI clock, mode 0 |
| `spi_cs_n` | East | Input | SPI chip select, active low |
| `spi_mosi` | East | Input | SPI data in |
| `spi_miso` | East | Output, 16 mA | SPI data out |
| `IOVDD` | South | Power | IO supply (3.3 V nominal, confirm against the IHP IO cell spec) |
| `IOVSS` | South | Ground | IO ground |
| `VDD_SRAM` | South | Power, analog pad | SRAM test block supply, 1.2 V. Can be left off when `sram_en` is low |


## Memory map

| Address | Size | Block |
|---|---|---|
| `0x0000_0000` | 4 KB | Instruction SRAM. Code, read-only data and `.data`. CPU reset vector |
| `0x0001_0000` | 4 KB | Data SRAM. `.bss` and stack (stack top `0x0001_0FF0`) |
| `0x1000_0000` | 32 B | Systolic array registers |
| `0x2000_0000` | 4 B | UART |
| `0x3000_0000` | 2 KB | SRAM test block data |
| `0x3000_1000` | 4 B | SRAM test block status |
| `0x4000_0000` | | Reserved |

Accesses to unmapped addresses stall the CPU (no ready is returned). Instruction fetches are only served from the instruction SRAM.

## Registers

### Systolic array (base `0x1000_0000`)

| Offset | Name | Access | Description |
|---|---|---|---|
| `0x00` | WEIGHT_ROW | W | Row index, bits [2:0] |
| `0x04` | WEIGHT_DATA_LO | W | Weights 0 to 3 of the row, int8, byte 0 = column 0 |
| `0x08` | WEIGHT_DATA_HI | W | Weights 4 to 7 of the row |
| `0x0C` | WEIGHT_LOAD | W | Any write loads the row into the array |
| `0x10` | ACT_LO | W | Activations 0 to 3, int8 |
| `0x14` | ACT_HI | W | Activations 4 to 7 |
| `0x18` | PSUM_SEL | W | Output column to read, bits [2:0] |
| `0x1C` | PSUM_DATA | R | 32-bit signed sum for the selected column |

Give the array a few dozen cycles after writing the activations before reading (`firmware/sa_test.c` waits 64 loop iterations). Column c returns the sum over r of `W[r][c] * A[r]`.

### UART (`0x2000_0000`)

| Access | Description |
|---|---|
| Write | Bits [7:0] are sent as one 8N1 character |
| Read | Bit 0 = transmitter ready. Poll it before each write |

The baud rate is fixed at 868 clocks per bit, so it scales with the clock: 115200 baud at 100 MHz, 11520 baud at 10 MHz.

### SRAM test block status (`0x3000_1000`, read-only)

| Bits | Value |
|---|---|
| [31:8] | `0x5A4D00`, block ID |
| [0] | 1 when the `sram_en` strap is high |

With the strap low, the macro clock is gated, its inputs are held at 0, writes are dropped and reads return 0, so the block can't hang or corrupt the rest of the chip even when `VDD_SRAM` is off.

## Boot and SPI protocol

After reset the CPU is held in reset. The host loads the program into the instruction SRAM over SPI and then releases the CPU.

SPI mode 0 (CPOL 0, CPHA 0), MSB first, one command per chip-select frame, except that `0x02` and `0x03` must share one frame: the SPI path only drives the array while chip select is low. The SPI inputs are synchronized to `clk`, so keep `spi_clk` well below the system clock. Simulation uses 10 MHz SPI at a 100 MHz system clock, and `clk` / 10 is a safe ratio.

| Command | Frame | Action |
|---|---|---|
| `0x01` | `01 row w0..w7` | Load one weight row into the array |
| `0x02` | `02 a0..a7` | Load activations. Follow with `0x03` in the same frame |
| `0x03` | `03` then 32 dummy bytes | Read the 8 column sums: column 7 first, 4 bytes each, MSB first |
| `0x04` | `04` | Reset the array |
| `0x05` | `05 addr_hi addr_lo d3 d2 d1 d0` | Write one word to the instruction SRAM. Word address, 10 bits. Ignored while the CPU runs |
| `0x06` | `06` | Release the CPU from reset (starts at `0x0000_0000`) |
| `0x07` | `07` | Hold the CPU in reset, for reloading |

`tools/spi_load.py` loads a `.hex` file produced by `firmware/Makefile`, and `--array-test` runs a known-answer check on the systolic array over SPI alone, without the CPU.

## Clock, reset and timing

| Parameter | Value |
|---|---|
| Clock target | 100 MHz (10 ns) |
| Typical corner (1.20 V, 25 C) | Setup slack +2.82 ns at 10 ns |
| Slow corner (1.08 V, 125 C) | Setup WNS -1.38 ns, so about 88 MHz worst case |
| Hold | Met at all corners |
| Reset | `rst_n` asynchronous assert, synchronized release |

## Physical

| | |
|---|---|
| Process | IHP SG13CMOS5L, 130 nm, Metal1 to Metal4 plus TopMetal1 |
| Die | 2.2 x 2.2 mm, core 1.5 x 1.5 mm |
| Standard cells | about 72,000 |
| Macros | 2 x IHP 4 KB SRAM, 1 x 2 KB test SRAM |
| Bond pads | 70 x 70 um on TopMetal1 |
| Signoff | KLayout DRC, density, antenna and LVS clean |

## Package pinout (QFN32, 5 x 5 mm, draft)

Draft bond plan, pending the assembler's bonding rules. It assumes the die sits in the package
with its north edge toward package pins 25 to 32 (no rotation) and standard JEDEC numbering,
counterclockwise from pin 1 at the top of the left side, top view. Each die pad goes to the
nearest lead on the same side, in order, so no bond wires cross. The die is 2.2 x 2.2 mm, so
radial wire length is about 1 mm, and the largest sideways offset is about 0.7 mm.

| Pin | Signal | Die pad | Pin | Signal | Die pad |
|---|---|---|---|---|---|
| 1 | NC | | 17 | NC | |
| 2 | `sram_en` | West | 18 | NC | |
| 3 | VSS | West (`vss_pad2`) | 19 | `spi_clk` | East |
| 4 | VDD | West (`vdd_pad2`) | 20 | `spi_cs_n` | East |
| 5 | `uart_tx` | West | 21 | `spi_mosi` | East |
| 6 | `uart_rx` | West | 22 | `spi_miso` | East |
| 7 | NC | | 23 | NC | |
| 8 | NC | | 24 | NC | |
| 9 | NC | | 25 | NC | |
| 10 | NC | | 26 | NC | |
| 11 | NC | | 27 | VSS | North (`vss_pad`) |
| 12 | IOVDD | South | 28 | VDD | North (`vdd_pad`) |
| 13 | IOVSS | South | 29 | `rst_n` | North |
| 14 | VDD_SRAM | South | 30 | `clk` | North |
| 15 | NC | | 31 | NC | |
| 16 | NC | | 32 | NC | |
| EP | Exposed pad | Not bonded. Connect to ground on the PCB for heat and mechanical support | | | |

Board notes:
- Pins 3 and 27 (VSS) and pins 4 and 28 (VDD) are the same nets on the die. Connect both pairs
  on the PCB, with a 100 nF capacitor close to each pair.
- VDD_SRAM (pin 14) feeds only the SRAM test block. Leave it on its own supply, or tie it to VDD
  if the SRAM block isn't being tested. Strap `sram_en` (pin 2) low when VDD_SRAM is off.
- NC pins have no bond wire. Leave them unconnected or ground them.
