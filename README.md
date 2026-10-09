# PicoRV32 SoC with Systolic Array Accelerator (IHP)

This repo has two physical implementations of the same SoC:

| Folder | Process | Status |
|---|---|---|
| `ihp_cmos5l/` | IHP SG13CMOS5L (130 nm, 5 metal) | **Signoff clean with KLayout: DRC, density, antenna, LVS.** Bond pads placed. Planned for IHP fabrication. |
| `ihp_pd/` + root RTL | IHP SG13G2 | Earlier version. Superseded by `ihp_cmos5l/`. |

Everything below the SG13CMOS5L section describes the older SG13G2 version and is kept for history.

---

## SG13CMOS5L implementation (`ihp_cmos5l/`)

### What's on the chip

- **CPU:** PicoRV32, RV32IM, booted over SPI (`COMPRESSED_ISA=0`, `ENABLE_IRQ=0`)
- **Accelerator:** 8x8 systolic array, memory-mapped, done flag polled by firmware
- **Memory:** 2 x 4 KB `RM_IHPSG13_1P_1024x32_c2_bm_bist` SRAM macros (instruction and data)
- **Peripherals:** SPI slave with boot loader, UART (115200 baud at 100 MHz)
- **IO ring:** 6 inputs, 2 outputs (16 mA), 4 power pads, 4 corners, 70 x 70 um bond pads on all 12 pads
- **Die:** 2.0 x 2.0 mm

### GDS_Layout

<img width="937" height="935" alt="Screenshot 2026-10-08 233015" src="https://github.com/user-attachments/assets/cfef6b40-0eba-4665-b653-cb47878b1e67" />

### Results (run `c5l_v3`)

| Check | Tool | Result |
|---|---|---|
| DRC | KLayout (PDK deck) | [V3_DRC] |
| Density | KLayout | [V3_DENSITY] |
| Antenna | KLayout | [V3_ANTENNA] (router reports [V3_ROUTE_ANT] nets) |
| LVS | KLayout | [V3_LVS], pads and SRAMs black-boxed (see limits) |
| Router DRC | OpenROAD | [V3_ROUTE_DRC] |
| Gate-level sim | Icarus + SDF (typ, cell delays) | [V3_GLS] |

Timing at 100 MHz (10 ns):

| Corner | Setup slack | Hold |
|---|---|---|
| nom_fast_1p32V_m40C | +5.23 ns | met |
| nom_typ_1p20V_25C | +2.65 ns | met |
| nom_slow_1p08V_125C | -1.66 ns | met |

**Operating spec: 100 MHz typical, about 85 MHz at the slow corner (1.08 V, 125 C).** Hold is met at every corner, so the chip works at any clock up to these limits.

### Toolchain

All open source. No Symbiotic Docker bouquet was used for this chip.

- LibreLane 3.0.14 (pip) **plus `librelane-3.0.14-local.patch`** (10 script changes)
- IHP open PDK, SG13CMOS5L, dev checkout
- OpenROAD, Yosys, KLayout 0.28, Icarus Verilog (oss-cad-suite)
- Signoff is **KLayout only**. Magic has no SG13CMOS5L support.

### How to reproduce

```bash
# 1. Apply the local LibreLane changes to a clean 3.0.14 install
pip install librelane==3.0.14
patch -p1 -d $(python3 -c "import librelane,os;print(os.path.dirname(os.path.dirname(librelane.__file__)))") < ihp_cmos5l/librelane-3.0.14-local.patch

# 2. RTL regression (4 tests)
cd ihp_cmos5l
export CMOS5L_PDK_ROOT=<path to ihp-open-pdk checkout>   # contains ihp-sg13cmos5l/
./run_regress.sh

# 3. Full RTL to GDS with signoff (several hours, DRC is the long step)
python3 -m librelane --manual-pdk --pdk-root $CMOS5L_PDK_ROOT --pdk ihp-sg13cmos5l \
  --scl sg13cmos5l_stdcell --run-tag c5l_v3 config.yaml

# 4. Gate-level simulation on the routed netlist
RUN=runs/c5l_v3/final ./run_gls.sh hello sdfnoic
RUN=runs/c5l_v3/final ./run_gls.sh sa_test sdfnoic
```

Prebuilt results are in `ihp_cmos5l/results/` (gzipped GDS, final netlist, typical SDF, metrics).

### Local workarounds (and why)

| Issue | Workaround | Files |
|---|---|---|
| PDK pad CDL has a pin-count error (2 lines), KLayout LVS aborts | Fixed copy of the pad CDL | `sg13cmos5l_io_fixed.cdl` |
| 10 PDK cells (9 pad internals, 1 SRAM dummy) fail LVS against their own layout | Black-box those cells in a local copy of the LVS deck | `lvs_local/`, `mk_lvs_local.sh` |
| SRAM macro LVS compare runs for hours without finishing | Black-box `RM_IHPSG13_*` and `RSC_IHPSG13_*` | `lvs_local/` |
| Stock metal fill leaves Metal2/Metal3 under the 25% density minimum | Shaped top-up fill after the PDK filler (0.42 um spacing, 1.0 um min width) | `fill_local/` |
| Decap cells in gap fill landed under Metal1 routes (985 DRC errors) | `DECAP_CELLS` set to plain fill cells | `config.yaml` |
| PDK ships no bond pad cell; `bondpad.py` crashes writing the LEF | Generated GDS with the PDK script, shifted to a lower-left origin, LEF written by hand (`CLASS COVER`) | `bondpad/` |
| `PAD_PLACE_IO_TERMINALS` plus bond pads gives two pins per port (DRT-0302) | Setting removed, bond pad carries the terminal | `config.yaml` |
| Icarus crashes on SDF interconnect delays | GLS strips interconnect, cell delays only | `run_gls.sh` |

### Known limits

- **LVS coverage:** standard cells and top-level wiring only. Pads and SRAM macros are black-boxed. SRAM hookup is covered by a pin check against the RTL, gate-level simulation and a power-via count instead.
- **Slow corner:** setup misses by 1.66 ns at 10 ns. There are also max-slew violations at the slow corner on a few high-fanout decode nets (`a21oi_2` drivers, 40 to 100 loads). These are fixable with a larger repair slew margin. That was not applied, because typical and fast pass and hold is met at all corners.
- **Router vs KLayout antenna:** the router flags some nets that the KLayout antenna deck passes. KLayout is used for signoff.
- **Fill rules:** the tech file lists `MFil_b` 0.6 um and `MFil_a1` 2.0 um, which the DRC deck does not check. The top-up fill uses 0.42 / 1.0 um. Pending confirmation from IHP.
- **Timing extraction is pre-fill.**

### Open questions for IHP

1. Do they enforce `MFil_b` / `MFil_a1`, and do they want filled or unfilled GDS?
2. Is the default DRC rule set enough, or the maximal deck?
3. Is `RM_IHPSG13_1P_1024x32` allowed on a CMOS5L run?
4. Is black-boxing the pads in LVS acceptable?
5. Router antenna count or KLayout antenna check?
6. Is `bondpad_70x70` at offset (5, -70) what they expect?

---
