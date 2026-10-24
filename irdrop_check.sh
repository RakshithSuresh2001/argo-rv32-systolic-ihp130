#!/bin/bash
# Static IR drop on a finished run with OpenROAD PSM, typical corner.
# usage: ./irdrop_check.sh [run_tag] [activity]   (defaults: sram_full6, 0.2)
#   activity = toggle rate per clock on every net (0.2 is a pessimistic default).
#   Each supply net is solved twice:
#   FULL = every top-metal node is an ideal source (optimistic bound)
#   PADS = sources only where the supply pads meet the core ring (what the chip sees)
cd "$(dirname "$0")"
RUN=runs/${1:-sram_full6}; ACT=${2:-0.2}
OUT=$RUN/irdrop; mkdir -p $OUT
ODB=$(ls $RUN/final/odb/*.odb | head -1)
SDC=$(ls $RUN/final/sdc/*.sdc | head -1)
SPEF=$(ls $RUN/final/spef/*nom*/*.spef $RUN/final/spef/*/*.spef 2>/dev/null | head -1)
[ -f "$ODB" ] && [ -f "$SPEF" ] || { echo "missing odb or spef under $RUN/final"; exit 1; }

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

cat > $OUT/irdrop.tcl <<TCL
foreach l [split [string trim [read [open $OUT/libs.txt]]] "\n"] { read_liberty \$l }
read_db $ODB
read_sdc $SDC
read_spef $SPEF
set_power_activity -global -activity $ACT -duty 0.5
set_power_activity -input -activity $ACT -duty 0.5
report_power

# One voltage source per supply pad: the point on the net's top-layer shapes
# closest to the pad's centre, i.e. where the pad feeds the core ring.
proc pad_vsrc {netname volt file pat} {
  set block [ord::get_db_block]
  set dbu [\$block getDbUnitsPerMicron]
  set net [\$block findNet \$netname]
  set top 0
  foreach sw [\$net getSWires] { foreach b [\$sw getWires] {
    if {[\$b isVia]} continue
    set lv [[\$b getTechLayer] getRoutingLevel]; if {\$lv > \$top} { set top \$lv } } }
  set fh [open \$file w]; set n 0
  foreach it [\$net getITerms] {
    set inst [\$it getInst]
    if {![string match \$pat [[\$inst getMaster] getName]]} continue
    set bb [\$inst getBBox]
    set cx [expr {([\$bb xMin] + [\$bb xMax]) / 2}]; set cy [expr {([\$bb yMin] + [\$bb yMax]) / 2}]
    set best 1e18; set px 0; set py 0
    foreach sw [\$net getSWires] { foreach b [\$sw getWires] {
      if {[\$b isVia] || [[\$b getTechLayer] getRoutingLevel] != \$top} continue
      set x [expr {min(max(\$cx, [\$b xMin]), [\$b xMax])}]; set y [expr {min(max(\$cy, [\$b yMin]), [\$b yMax])}]
      set d [expr {hypot(\$x - \$cx, \$y - \$cy)}]
      if {\$d < \$best} { set best \$d; set px \$x; set py \$y } } }
    puts \$fh "[expr {double(\$px)/\$dbu}],[expr {double(\$py)/\$dbu}],10,\$volt"
    puts "  source for \$netname at pad [\$inst getName]: ([expr {\$px/\$dbu}], [expr {\$py/\$dbu}]) um"
    incr n
  }
  close \$fh
  return \$n
}

foreach {net v pat} {VPWR 1.2 *IOPadVdd VDD_SRAM 1.2 *IOPadAnalog VGND 0.0 *IOPadVss} {
  set_pdnsim_net_voltage -net \$net -voltage \$v
  puts "===== \$net FULL"
  analyze_power_grid -net \$net -source_type FULL -voltage_file $OUT/\${net}_FULL.csv
  set n [pad_vsrc \$net \$v $OUT/\${net}.vsrc \$pat]
  puts "===== \$net PADS (\$n pads)"
  if {\$n > 0} { analyze_power_grid -net \$net -vsrc $OUT/\${net}.vsrc -voltage_file $OUT/\${net}_PADS.csv }
}
TCL
echo "run $RUN, activity $ACT, libs $(wc -l < $OUT/libs.txt)"
openroad -no_splash -exit $OUT/irdrop.tcl > $OUT/irdrop.log 2>&1
grep -E "^Total|=====|source for|Worstcase|Average|PSM-0|ERROR|Error" $OUT/irdrop.log
echo "full log: $OUT/irdrop.log"
