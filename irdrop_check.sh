#!/bin/bash
# Static IR-drop check on a finished run with OpenROAD PSM.
# Usage: ./irdrop_check.sh [run_tag]   (default sram_full3), run from ihp_cmos5l/
# The Chip flow skips OpenROAD.IRDropReport, so this runs the same analysis
# by hand: typical-corner libs, nominal SPEF, every power and ground net.
set -e
cd "$(dirname "$0")"
RUN=runs/${1:-sram_full3}
OUT=$RUN/irdrop; mkdir -p $OUT
ODB=$(ls $RUN/final/odb/*.odb | head -1)
SDC=$(ls $RUN/final/sdc/*.sdc | head -1)
SPEF=$(ls $RUN/final/spef/*nom*/*.spef $RUN/final/spef/*/*.spef 2>/dev/null | head -1)
[ -f "$ODB" ] && [ -f "$SPEF" ] || { echo "missing odb or spef under $RUN/final"; exit 1; }

# every .lib the run resolved, typical corner only
python3 - "$RUN/resolved.json" > $OUT/libs.txt <<'PY'
import json, sys
seen = []
def walk(v):
    if isinstance(v, str):
        if v.endswith(".lib") and "slow" not in v and "fast" not in v and v not in seen: seen.append(v)
    elif isinstance(v, dict): [walk(x) for x in v.values()]
    elif isinstance(v, list): [walk(x) for x in v]
walk(json.load(open(sys.argv[1])))
print("\n".join(seen))
PY
echo "libs: $(wc -l < $OUT/libs.txt), spef: $SPEF"

cat > $OUT/irdrop.tcl <<TCL
foreach l [split [string trim [read [open $OUT/libs.txt]]] "\n"] { read_liberty \$l }
read_db $ODB
read_sdc $SDC
read_spef $SPEF
set_propagated_clock [all_clocks]
set_power_activity -input -activity 0.1
set_power_activity -input_port [get_ports rst_n_PAD] -activity 0
report_power
foreach {net v} {VPWR 1.2 VDD_SRAM 1.2 VGND 0.0} {
    puts "===== \$net"
    set_pdnsim_net_voltage -net \$net -voltage \$v
    analyze_power_grid -net \$net -voltage_file $OUT/\$net.csv -error_file $OUT/\$net.err
}
TCL
openroad -no_splash -exit $OUT/irdrop.tcl 2>&1 | tee $OUT/irdrop.log | grep -E "=====|Worstcase|Average|Total|PSM-0|ERROR" 
