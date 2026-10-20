read_db [lindex [glob runs/sram_pdn/22-openroad-generatepdn/*.odb] 0]
set b [ord::get_db_block]; set m [$b findInst i_soc_top.u_stest_macro]; set bb [$m getBBox]
set x0 [expr [$bb xMin]+2000]; set x1 [expr [$bb xMax]-2000]; set y0 [expr [$bb yMin]+2000]; set y1 [expr [$bb yMax]-2000]
puts "macro [$bb xMin] [$bb yMin] [$bb xMax] [$bb yMax] (dbu)"
foreach n {VDD_SRAM VGND VPWR} {
  array unset c
  foreach sw [[$b findNet $n] getSWires] { foreach w [$sw getWires] {
    if {[$w isVia]} { set k "via:[[$w getBlockVia] getName]" } else { set k [[$w getTechLayer] getName] }
    if {[$w xMin] < $x1 && [$w xMax] > $x0 && [$w yMin] < $y1 && [$w yMax] > $y0} { incr c($k) } } }
  puts "$n strictly inside macro: [array get c]"
}
foreach t {vdd vss} { set mt [[$m getMaster] findMTerm $t]; set n 0; foreach p [$mt getMPins] { incr n [llength [$p getGeometry]] }; puts "master pin $t: $n shapes" }
