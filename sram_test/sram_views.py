#!/usr/bin/env python3
"""Generate LEF, Liberty and a standalone GDS for a Chips4Makers SRAM block.

usage: python3 sram_views.py <in.gds> <cell> <outdir> [pins_from.lef]

With pins_from.lef (e.g. the LEF arra-mem writes) pin shapes are taken from that
LEF instead of GDS labels; OBS, origin shift and power-rail pins are still ours.
"""
import sys, os, re
import klayout.db as db

GDS_IN, CELL, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
PIN_LEF = sys.argv[4] if len(sys.argv) > 4 else None
os.makedirs(OUT, exist_ok=True)

# GDS layer -> (LEF name, drawing datatype, pin datatype)
METALS = {8: "Metal1", 10: "Metal2", 30: "Metal3", 50: "Metal4"}
OBS_LAYERS = [8, 10, 30]          # macro uses Metal1..Metal3 only
ABOVE = {8: 10, 10: 30, 30: 50}
PIN_DT = 2
KEEPOUT_UM = 0.30                 # opening around pins in OBS

# Verilog port directions
INPUTS = re.compile(r"^(a|d|we)\[\d+\]$|^clk$")
OUTPUTS = re.compile(r"^q\[\d+\]$")
POWER, GROUND = "vdd", "vss"

ly = db.Layout()
ly.read(GDS_IN)
c = ly.cell(CELL)
if c is None:
    sys.exit(f"cell {CELL} not found")
dbu = ly.dbu
um = lambda v: round(v * dbu, 4)

# 1. move bbox lower-left to (0,0) so LEF ORIGIN/FOREIGN are 0 0
bb = c.bbox()
SHIFT = (-bb.left, -bb.bottom)          # dbu, applied to GDS and to LEF-sourced pins
c.transform(db.Trans(*SHIFT))
# drop prBoundary (189/0): the CMOS5L density deck takes it as the chip area
_pb = ly.find_layer(189, 0)
if _pb is not None and _pb >= 0:
    for _c in ly.each_cell(): _c.shapes(_pb).clear()
# local fix, Cnt.g2 in SP6TBulkConn: pSD must enclose p-tap Cont by 0.09 um (arra-mem draws 0.075)
_bc, _psd, _ct = ly.cell("SP6TBulkConn"), ly.find_layer(14, 0), ly.find_layer(6, 0)
if _bc is not None and _psd is not None and _ct is not None:
    _pr = db.Region(_bc.shapes(_psd))
    _g = int(round(0.09 / dbu))
    _n = 0
    for _s in list(_bc.shapes(_ct).each()):
        if not (_pr & db.Region(_s.bbox())).is_empty():
            _bc.shapes(_psd).insert(_s.bbox().enlarged(_g, _g)); _n += 1
    print(f"Cnt.g2 patch: grew pSD around {_n} p-tap contacts in SP6TBulkConn")
bb = c.bbox()
W, H = um(bb.width()), um(bb.height())

def li(layer, dt):
    return ly.find_layer(layer, dt)

# 2. pins: from a LEF if given, else top-level texts on pin layers -> containing pin shape
pins = {}   # name -> list of (gdslayer, Box)
LEFLAYER = {v: k for k, v in METALS.items()}
if PIN_LEF:
    cur = lay = None
    for line in open(PIN_LEF):
        t = line.split()
        if not t: continue
        if t[0] == "PIN": cur = t[1]
        elif t[0] == "END" and len(t) > 1 and t[1] == cur: cur = None
        elif t[0] == "OBS": cur = None
        elif cur and t[0] == "LAYER": lay = LEFLAYER.get(t[1])
        elif cur and t[0] == "RECT" and lay is not None:
            x1, y1, x2, y2 = (int(round(float(v) / dbu)) for v in t[1:5])
            pins.setdefault(cur, []).append((lay, db.Box(x1 + SHIFT[0], y1 + SHIFT[1], x2 + SHIFT[0], y2 + SHIFT[1])))
for g in (() if PIN_LEF else METALS):
    pl = li(g, PIN_DT)
    if pl is None:
        continue
    shapes = [s.bbox() for s in c.shapes(pl).each() if not s.is_text() and s.bbox().area() > 0]
    for s in c.shapes(pl).each():
        if not s.is_text():
            continue
        p = db.Point(s.text.x, s.text.y)
        hits = [b for b in shapes if b.contains(p)]
        if not hits:
            print(f"WARN label {s.text.string} on {g}/{PIN_DT} has no pin shape")
            continue
        for b in hits:
            pins.setdefault(s.text.string, []).append((g, b))

# dedupe
for k in pins:
    seen, out = set(), []
    for g, b in pins[k]:
        key = (g, b.left, b.bottom, b.right, b.top)
        if key not in seen:
            seen.add(key); out.append((g, b))
    pins[k] = out

# 2b. power pins: use the full drawn rail (merged same-layer metal touching the
#     pin marker), not the small pin marker. Different nets never touch, so the
#     merged polygon is all vdd (or all vss).
drawn = {}
for g in METALS:
    dl = li(g, 0)
    drawn[g] = db.Region(c.begin_shapes_rec(dl)).merged() if dl is not None else db.Region()
for name in (POWER, GROUND):
    full_shapes = []
    for g, b in pins.get(name, []):
        geom = drawn[g].interacting(db.Region(b))
        for p in geom.decompose_trapezoids_to_region(db.Polygon.TD_htrapezoids).each():
            full_shapes.append((g, p.bbox()))
    if full_shapes:
        seen = set(); out = []
        for g, b in full_shapes:
            k = (g, b.left, b.bottom, b.right, b.top)
            if k not in seen: seen.add(k); out.append((g, b))
        pins[name] = out

# 3. OBS: full block minus openings around pins (and the layer above them),
#    with real geometry of other shapes inside the openings added back
full = db.Region(bb)
keep = int(round(KEEPOUT_UM / dbu))
edge = int(round(1.0 / dbu))     # pins within 1 um of the boundary get an opening to the edge
open_on = {g: db.Region() for g in OBS_LAYERS}
pin_on = {g: db.Region() for g in OBS_LAYERS}

def opening(b):
    o = b.enlarged(keep, keep)
    l, bo, r, t = o.left, o.bottom, o.right, o.top
    if b.left - bb.left <= edge: l = bb.left
    if bb.right - b.right <= edge: r = bb.right
    if b.bottom - bb.bottom <= edge: bo = bb.bottom
    if bb.top - b.top <= edge: t = bb.top
    return db.Box(l, bo, r, t) & bb

pwr_on = {g: db.Region() for g in OBS_LAYERS}   # exact power rails, cut from OBS
for name, lst in pins.items():
    for g, b in lst:
        if name in (POWER, GROUND):
            if g in pwr_on: pwr_on[g].insert(b)
            continue
        if g in open_on:
            open_on[g].insert(opening(b)); pin_on[g].insert(b)
        up = ABOVE.get(g)
        if up in open_on:
            open_on[up].insert(opening(b))

obs = {}
for g in OBS_LAYERS:
    geom = drawn[g]
    holes = open_on[g].merged()
    r = (full - holes) + ((geom & holes) - pin_on[g])
    r = (r.merged() - pwr_on[g].merged()).merged()
    obs[g] = r.decompose_trapezoids_to_region(db.Polygon.TD_htrapezoids) if hasattr(r, "decompose_trapezoids_to_region") else r

# 4. LEF
def rect(b):
    return f"RECT {um(b.left)} {um(b.bottom)} {um(b.right)} {um(b.top)} ;"

L = [f"VERSION 5.8 ;", "BUSBITCHARS \"[]\" ;", "DIVIDERCHAR \"/\" ;", "",
     f"MACRO {CELL}", "  CLASS BLOCK ;", f"  FOREIGN {CELL} 0 0 ;", "  ORIGIN 0 0 ;",
     f"  SIZE {W} BY {H} ;", "  SYMMETRY X Y ;"]

def sortkey(n):
    m = re.match(r"(\w+)(?:\[(\d+)\])?", n)
    return (m.group(1), int(m.group(2) or 0))

for name in sorted(pins, key=sortkey):
    if name in (POWER, GROUND):
        d, use = "INOUT", "POWER" if name == POWER else "GROUND"
    elif OUTPUTS.match(name):
        d, use = "OUTPUT", "SIGNAL"
    elif INPUTS.match(name):
        d, use = "INPUT", "CLOCK" if name == "clk" else "SIGNAL"
    else:
        print(f"WARN unknown pin {name}, skipped"); continue
    L += [f"  PIN {name}", f"    DIRECTION {d} ;", f"    USE {use} ;"]
    if use in ("POWER", "GROUND"):
        L.append("    SHAPE ABUTMENT ;")
    L.append("    PORT")
    for g, b in pins[name]:
        L += [f"      LAYER {METALS[g]} ;", f"        {rect(b)}"]
    L += ["    END", f"  END {name}"]

L.append("  OBS")
for g in OBS_LAYERS:
    L.append(f"    LAYER {METALS[g]} ;")
    for p in obs[g].each():
        b = p.bbox()
        if p.is_box():
            L.append(f"      {rect(b)}")
        else:
            pts = " ".join(f"{um(q.x)} {um(q.y)}" for q in p.each_point_hull())
            L.append(f"      POLYGON {pts} ;")
L += ["  END", f"END {CELL}", "", "END LIBRARY", ""]
open(os.path.join(OUT, f"{CELL}.lef"), "w").write("\n".join(L))

# 5. standalone GDS (cell + children, shifted)
opt = db.SaveLayoutOptions(); opt.select_cell(c.cell_index())
ly.write(os.path.join(OUT, f"{CELL}.gds"), opt)

# 6. Liberty: conservative scalar timing, to be replaced by characterized numbers
T_CLK2Q, T_SETUP, T_HOLD = 3.0, 1.0, 1.0      # ns
C_IN, C_CLK, C_MAXLOAD = 0.010, 0.050, 0.5     # pF
area = round(W * H, 3)

BUSES = (("a", 9, "input"), ("d", 32, "input"), ("we", 4, "input"), ("q", 32, "output"))

def bus_types():
    return "\n".join(
        f"  type (bus_{n}) {{ base_type : array ; data_type : bit ; bit_width : {n} ;"
        f" bit_from : {n-1} ; bit_to : 0 ; downto : true ; }}"
        for n in sorted({w for _, w, _ in BUSES}))

def bus_group(prefix, n, direction):
    s = [f"    bus ({prefix}) {{", f"      bus_type : bus_{n} ;", f"      direction : {direction} ;",
         '      related_power_pin : "vdd" ;', '      related_ground_pin : "vss" ;']
    if direction == "input":
        s.append(f"      capacitance : {C_IN} ;")
        for kind, val in (("setup_rising", T_SETUP), ("hold_rising", T_HOLD)):
            s.append(f'      timing () {{\n        related_pin : "clk" ;\n        timing_type : {kind} ;\n'
                     f'        rise_constraint (scalar) {{ values ("{val}") ; }}\n'
                     f'        fall_constraint (scalar) {{ values ("{val}") ; }}\n      }}')
    else:
        s.append(f"      max_capacitance : {C_MAXLOAD} ;")
        s.append(f'      timing () {{\n        related_pin : "clk" ;\n        timing_type : rising_edge ;\n'
                 f'        cell_rise (scalar) {{ values ("{T_CLK2Q}") ; }}\n'
                 f'        cell_fall (scalar) {{ values ("{T_CLK2Q}") ; }}\n'
                 f'        rise_transition (scalar) {{ values ("0.5") ; }}\n'
                 f'        fall_transition (scalar) {{ values ("0.5") ; }}\n      }}')
    s.append("    }")
    return "\n".join(s)

lib = f"""/* {CELL}: placeholder timing model, NOT characterized.
   clk->q {T_CLK2Q} ns, setup {T_SETUP} ns, hold {T_HOLD} ns, typ 1.2 V 25C */
library ({CELL}_typ) {{
  delay_model : table_lookup ;
  time_unit : "1ns" ;
  voltage_unit : "1V" ;
  current_unit : "1mA" ;
  capacitive_load_unit (1, pf) ;
  pulling_resistance_unit : "1kohm" ;
  leakage_power_unit : "1nW" ;
  nom_process : 1 ;
  nom_voltage : 1.2 ;
  nom_temperature : 25 ;
  operating_conditions (typ) {{ process : 1 ; voltage : 1.2 ; temperature : 25 ; }}
  default_operating_conditions : typ ;
  voltage_map (vdd, 1.2) ;
  voltage_map (vss, 0.0) ;
  input_threshold_pct_rise : 50 ; input_threshold_pct_fall : 50 ;
  output_threshold_pct_rise : 50 ; output_threshold_pct_fall : 50 ;
  slew_lower_threshold_pct_rise : 20 ; slew_upper_threshold_pct_rise : 80 ;
  slew_lower_threshold_pct_fall : 20 ; slew_upper_threshold_pct_fall : 80 ;
  default_max_transition : 2.0 ;
{bus_types()}

  cell ({CELL}) {{
    area : {area} ;
    is_macro_cell : true ;
    dont_use : true ;
    dont_touch : true ;
    pg_pin (vdd) {{ voltage_name : vdd ; pg_type : primary_power ; }}
    pg_pin (vss) {{ voltage_name : vss ; pg_type : primary_ground ; }}
    pin (clk) {{
      direction : input ;
      clock : true ;
      capacitance : {C_CLK} ;
      related_power_pin : "vdd" ;
      related_ground_pin : "vss" ;
      min_pulse_width_high : 2.0 ;
      min_pulse_width_low : 2.0 ;
    }}
{chr(10).join(bus_group(*b) for b in BUSES)}
  }}
}}
"""
open(os.path.join(OUT, f"{CELL}_typ.lib"), "w").write(lib)

# 7. report
print(f"SIZE {W} x {H} um")
want = {"clk"} | {f"a[{i}]" for i in range(9)} | {f"d[{i}]" for i in range(32)} | \
       {f"q[{i}]" for i in range(32)} | {f"we[{i}]" for i in range(4)} | {POWER, GROUND}
missing, extra = sorted(want - set(pins)), sorted(set(pins) - want)
print(f"pins found {len(pins)}/{len(want)}  missing={missing}  extra={extra}")
for g in OBS_LAYERS:
    print(f"OBS {METALS[g]}: {obs[g].count()} shapes")
print("wrote", *[os.path.join(OUT, f) for f in (f"{CELL}.lef", f"{CELL}_typ.lib", f"{CELL}.gds")])
