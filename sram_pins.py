import pya
ly = pya.Layout(); ly.read(gds)
top = max(ly.top_cells(), key=lambda c: c.bbox().area())
mc = ly.cell("RM_IHPSG13_1P_1024x32_c2_bm_bist")
dbu = ly.dbu
# pin shapes (Metal4.pin 50/2) grouped by the label (Metal4.text 50/25) that sits on them
pins = pya.Region(mc.begin_shapes_rec(ly.find_layer(50, 2))); pins.merge()
groups = {}
it = mc.begin_shapes_rec(ly.find_layer(50, 25))
while not it.at_end():
    s = it.shape()
    if s.is_text():
        p = it.trans() * pya.Point(s.text.x, s.text.y)
        groups.setdefault(s.text.string, pya.Region()).insert(pya.Box(p.x - 5, p.y - 5, p.x + 5, p.y + 5))
    it.next()
pinreg = {k: pins.interacting(v) for k, v in groups.items() if k.upper().startswith(("VDD", "VSS"))}
print("macro pin shapes per supply:", {k: v.count() for k, v in sorted(pinreg.items())})
tv = ly.find_layer(125, 0)
n = 0
for inst in top.each_inst():
    if inst.cell.name != mc.name: continue
    n += 1; b = inst.bbox(); t = inst.cplx_trans
    it = top.begin_shapes_rec_overlapping(tv, b); it.unselect_cells([mc.cell_index()])
    vias = pya.Region(it)
    print("SRAM #%d at (%.0f,%.0f) um, orientation %s, chip-level TopVia1 cuts over it: %d" % (n, b.left*dbu, b.bottom*dbu, str(inst.trans).split()[0], vias.count()))
    tot = 0
    for k in sorted(pinreg):
        pr = pinreg[k].transformed(t)
        hit = pr.interacting(vias).count(); cuts = vias.interacting(pr).count(); tot += cuts
        print("   %-10s pin stripes %3d, stripes with vias %3d, via cuts on them %5d" % (k, pr.count(), hit, cuts))
    print("   via cuts not on any supply pin: %d" % (vias.count() - tot))
if n == 0: print("no SRAM instance found directly under the top cell")
