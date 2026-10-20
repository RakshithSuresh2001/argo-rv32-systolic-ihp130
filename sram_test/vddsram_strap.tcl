# vddsram_strap.tcl
# Runs right after pdngen (see the pdngen wrapper in pdn_cfg_cmos5l.tcl).
# Connects the analog VDD_SRAM pad's core-side Metal3 pin to the VDD_SRAM
# core ring: Metal3 strap pad -> ring, Metal4 landing under the ring segment,
# Via3 + Via4 cut arrays. Everything is derived from the database.

proc _vs_log {msg} { puts "\[VDD_SRAM strap\] $msg" }

set _vs_block [ord::get_db_block]
set _vs_tech  [ord::get_db_tech]
set _vs_dbu   [$_vs_tech getDbUnitsPerMicron]
set _vs_net   [$_vs_block findNet VDD_SRAM]
set _vs_pad   [$_vs_block findInst vdd_sram_pad]
set _vs_m3    [$_vs_tech findLayer Metal3]
set _vs_m4    [$_vs_tech findLayer Metal4]
set _vs_tm1   [$_vs_tech findLayer TopMetal1]

if {$_vs_net eq "NULL" || $_vs_pad eq "NULL"} {
    _vs_log "VDD_SRAM net or vdd_sram_pad not found, skipping"
    return
}

# --- 1. core-side Metal3 pin of the pad, in die coordinates -------------------
set _vs_master [$_vs_pad getMaster]
set _vs_W [$_vs_master getWidth]
set _vs_H [$_vs_master getHeight]
set _vs_bb [$_vs_pad getBBox]
set _vs_x0 [$_vs_bb xMin]; set _vs_y0 [$_vs_bb yMin]
set _vs_x1 [$_vs_bb xMax]; set _vs_y1 [$_vs_bb yMax]
set _vs_or [$_vs_pad getOrient]

proc _vs_xform {lx0 ly0 lx1 ly1} {
    upvar _vs_or o _vs_x0 x0 _vs_y0 y0 _vs_x1 x1 _vs_y1 y1
    switch -- $o {
        R0   { return [list [expr {$x0+$lx0}] [expr {$y0+$ly0}] [expr {$x0+$lx1}] [expr {$y0+$ly1}]] }
        MY   { return [list [expr {$x1-$lx1}] [expr {$y0+$ly0}] [expr {$x1-$lx0}] [expr {$y0+$ly1}]] }
        MX   { return [list [expr {$x0+$lx0}] [expr {$y1-$ly1}] [expr {$x0+$lx1}] [expr {$y1-$ly0}]] }
        R180 { return [list [expr {$x1-$lx1}] [expr {$y1-$ly1}] [expr {$x1-$lx0}] [expr {$y1-$ly0}]] }
        default { error "unsupported pad orientation $o" }
    }
}

# pick the Metal3 pin shape nearest the core (largest distance from die edge = nearest die center)
set _vs_core_cy [expr {([[$_vs_block getDieArea] yMin] + [[$_vs_block getDieArea] yMax]) / 2}]
set _vs_pin {}
set _vs_bestd -1
foreach mp [[$_vs_master findMTerm pad] getMPins] {
    foreach g [$mp getGeometry] {
        if {[$g getTechLayer] eq "NULL"} continue
        if {[[$g getTechLayer] getName] ne "Metal3"} continue
        set r [_vs_xform [$g xMin] [$g yMin] [$g xMax] [$g yMax]]
        set cy [expr {([lindex $r 1] + [lindex $r 3]) / 2}]
        set d [expr {-abs($cy - $_vs_core_cy)}]
        if {$_vs_bestd == -1 || $d > $_vs_bestd} { set _vs_bestd $d; set _vs_pin $r }
    }
}
if {$_vs_pin eq ""} { _vs_log "no Metal3 pin shape on vdd_sram_pad/pad"; return }
lassign $_vs_pin px0 py0 px1 py1
_vs_log "pad orient $_vs_or, core-side Metal3 pin: [expr {$px0/double($_vs_dbu)}] [expr {$py0/double($_vs_dbu)}] [expr {$px1/double($_vs_dbu)}] [expr {$py1/double($_vs_dbu)}]"

# pad on the south edge: core is above the pin (ring y > pin y)
set _vs_up [expr {$py1 < $_vs_core_cy}]

# --- 2. VDD_SRAM ring segment on TopMetal1 right above/below the pin -------------
set _vs_ring {}
set _vs_bestgap -1
foreach sw [$_vs_net getSWires] {
    foreach w [$sw getWires] {
        if {[$w isVia]} continue
        if {[[$w getTechLayer] getName] ne "TopMetal1"} continue
        if {[$w xMin] > $px0 || [$w xMax] < $px1} continue
        if {$_vs_up} { set gap [expr {[$w yMin] - $py1}] } else { set gap [expr {$py0 - [$w yMax]}] }
        if {$gap < 0} continue
        if {$_vs_bestgap == -1 || $gap < $_vs_bestgap} {
            set _vs_bestgap $gap
            set _vs_ring [list [$w xMin] [$w yMin] [$w xMax] [$w yMax]]
        }
    }
}
if {$_vs_ring eq ""} { _vs_log "no VDD_SRAM TopMetal1 ring segment spans the pad pin"; return }
lassign $_vs_ring rx0 ry0 rx1 ry1
_vs_log "VDD_SRAM ring segment y [expr {$ry0/double($_vs_dbu)}]..[expr {$ry1/double($_vs_dbu)}] (gap [expr {$_vs_bestgap/double($_vs_dbu)}] um)"

# --- 3. free x window: avoid other nets' Metal4 inside the ring band ------------
set _vs_margin [expr {int(1.0 * $_vs_dbu)}]   ; # 1 um keepout to foreign Metal4
set _vs_blk {}
foreach n [$_vs_block getNets] {
    if {$n eq $_vs_net} continue
    foreach sw [$n getSWires] {
        foreach w [$sw getWires] {
            if {[$w isVia]} continue
            if {[[$w getTechLayer] getName] ne "Metal4"} continue
            if {[$w yMax] < $ry0 || [$w yMin] > $ry1} continue
            if {[$w xMax] < $px0 || [$w xMin] > $px1} continue
            lappend _vs_blk [list [expr {[$w xMin]-$_vs_margin}] [expr {[$w xMax]+$_vs_margin}]]
        }
    }
}
set _vs_lo [expr {$px0 + int(0.5*$_vs_dbu)}]
set _vs_hi [expr {$px1 - int(0.5*$_vs_dbu)}]
set _vs_cuts [list [list $_vs_lo $_vs_hi]]
foreach b [lsort -integer -index 0 $_vs_blk] {
    set nxt {}
    foreach seg $_vs_cuts {
        lassign $seg a z
        lassign $b ba bz
        if {$bz <= $a || $ba >= $z} { lappend nxt $seg; continue }
        if {$ba > $a} { lappend nxt [list $a $ba] }
        if {$bz < $z} { lappend nxt [list $bz $z] }
    }
    set _vs_cuts $nxt
}
set _vs_win {}
set _vs_best 0
foreach seg $_vs_cuts {
    set w [expr {[lindex $seg 1] - [lindex $seg 0]}]
    if {$w > $_vs_best} { set _vs_best $w; set _vs_win $seg }
}
if {$_vs_best < [expr {int(3.0 * $_vs_dbu)}]} { _vs_log "free Metal4 window too narrow ([expr {$_vs_best/double($_vs_dbu)}] um)"; return }
lassign $_vs_win wx0 wx1
_vs_log "strap x window [expr {$wx0/double($_vs_dbu)}]..[expr {$wx1/double($_vs_dbu)}] um"

# --- 4. shapes -------------------------------------------------------------------
set _vs_sw [odb::dbSWire_create $_vs_net ROUTED]
if {$_vs_up} { set sy0 $py0; set sy1 $ry1 } else { set sy0 $ry0; set sy1 $py1 }
odb::dbSBox_create $_vs_sw $_vs_m3 $wx0 $sy0 $wx1 $sy1 STRIPE
odb::dbSBox_create $_vs_sw $_vs_m4 $wx0 $ry0 $wx1 $ry1 STRIPE

proc _vs_findvia {bot top} {
    upvar _vs_tech t
    foreach v [$t getVias] {
        if {[$v getBottomLayer] eq "NULL" || [$v getTopLayer] eq "NULL"} continue
        if {[[$v getBottomLayer] getName] eq $bot && [[$v getTopLayer] getName] eq $top} { return $v }
    }
    return ""
}
set _vs_v3 [_vs_findvia Metal3 Metal4]
set _vs_v4 [_vs_findvia Metal4 TopMetal1]
if {$_vs_v3 eq "" || $_vs_v4 eq ""} { _vs_log "tech via Metal3->Metal4 or Metal4->TopMetal1 not found"; return }

proc _vs_array {via x0 y0 x1 y1 pitch_um} {
    upvar _vs_sw sw _vs_dbu dbu
    # keep cuts + enclosures 1 um inside the overlap (covers TopVia enclosure)
    set hw [expr {int(1.0*$dbu)}]
    set hh $hw
    set p [expr {int($pitch_um * $dbu)}]
    set n 0
    for {set x [expr {$x0 + $hw}]} {$x <= $x1 - $hw} {incr x $p} {
        for {set y [expr {$y0 + $hh}]} {$y <= $y1 - $hh} {incr y $p} {
            odb::dbSBox_create $sw $via $x $y STRIPE
            incr n
        }
    }
    return $n
}
set n3 [_vs_array $_vs_v3 $wx0 $ry0 $wx1 $ry1 1.0]
set n4 [_vs_array $_vs_v4 $wx0 $ry0 $wx1 $ry1 2.0]
_vs_log "placed Metal3 strap, Metal4 landing, $n3 x [$_vs_v3 getName], $n4 x [$_vs_v4 getName]"
