#!/bin/bash
# Switch the SRAM test block from the dev_SRAM example (SP6TBlock_512x32we4)
# to Staf's arra-mem output (SP6TSRAM_512x32_4we). Run from ihp_cmos5l/.
set -e
OLD=SP6TBlock_512x32we4
NEW=SP6TSRAM_512x32_4we
SRC=${MEMGEN_OUT:-$HOME/c4m/memgen/out}
cd "$(dirname "$0")"
chmod -R u+w .

# 1. views: GDS shifted to (0,0), LEF with Staf's pins + our OBS/power rails, placeholder lib
python3 sram_test/sram_views.py "$SRC/gds/$NEW.gds" $NEW sram_test "$SRC/lef/$NEW.lef"
cp "$SRC/lef/$NEW.lef"         sram_test/${NEW}_staf.lef     # keep his original for reference
cp "$SRC/ngspice/$NEW.spi"     sram_test/$NEW.spi            # transistor netlist, for real LVS later
cp "$SRC/verilog/$NEW.v"       sram_test/$NEW.v              # behavioral model for simulation

# 2. ports-only stub for the flow, CDL stub for blackbox LVS
python3 - "$NEW" <<'EOF'
import re, sys
n = sys.argv[1]
pins = re.findall(r"^\s*PIN (\S+)", open(f"sram_test/{n}.lef").read(), re.M)
open(f"sram_test/{n}.cdl", "w").write(f".SUBCKT {n} " + " ".join(pins) + "\n.ENDS\n")
open(f"sram_test/{n}_stub.v", "w").write(f"""/// sta-blackbox
// Ports-only blackbox for the flow. Simulation model: {n}.v (Chips4Makers arra-mem).
(* blackbox *)
module {n} (a, d, we, clk, q);
  input  [8:0]  a;
  input  [31:0] d;
  input  [3:0]  we;
  input         clk;
  output [31:0] q;
endmodule
""")
print(len(pins), "pins")
EOF

# 3. rename everywhere it is referenced
sed -i "s/$OLD/$NEW/g" soc_top.sv config.yaml run_regress.sh
sed -i 's/,SP6TBlock_\*,/,SP6T*,/' config.yaml

echo "--- check"
grep -n "$NEW" soc_top.sv config.yaml run_regress.sh | head -20
grep -c "$OLD" soc_top.sv config.yaml run_regress.sh || true
