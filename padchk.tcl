read_db runs/sram_pdn/22-openroad-generatepdn/soc_padframe.odb
set b [ord::get_db_block]; set n [$b findNet VDD_SRAM]
foreach it [$n getITerms] { puts "VDD_SRAM iterm: [[$it getInst] getName]/[[$it getMTerm] getName]" }
set p [$b findInst vdd_sram_pad]; set bb [$p getBBox]; set c 0
foreach sw [$n getSWires] { foreach w [$sw getWires] { if {[$w xMin] < [$bb xMax] && [$w xMax] > [$bb xMin] && [$w yMin] < [$bb yMax] && [$w yMax] > [$bb yMin]} { incr c } } }
puts "VDD_SRAM special wires touching vdd_sram_pad: $c  (pad bbox [$bb xMin] [$bb yMin] [$bb xMax] [$bb yMax])"
