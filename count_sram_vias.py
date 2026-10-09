import odb, glob
db = odb.dbDatabase.create()
odb.read_db(db, glob.glob("runs/c5l_full/*-openroad-generatepdn/*.odb")[0])
blk = db.getChip().getBlock()
for inst in blk.getInsts():
    if not inst.getMaster().getName().startswith("RM_IHPSG13"): continue
    bb = inst.getBBox(); x0, y0, x1, y1 = bb.xMin(), bb.yMin(), bb.xMax(), bb.yMax()
    flip = inst.getOrient() in ("MX", "R180")
    c = {"VSS!": 0, "VDD!": 0, "VDDARRAY!": 0}
    for net in ("VPWR", "VGND"):
        for sw in blk.findNet(net).getSWires():
            for sb in sw.getWires():
                if not sb.isVia(): continue
                if not (x0 <= sb.xMin() and sb.xMax() <= x1 and y0 <= sb.yMin() and sb.yMax() <= y1): continue
                lo, hi = (y1 - sb.yMax(), y1 - sb.yMin()) if flip else (sb.yMin() - y0, sb.yMax() - y0)
                if net == "VGND": c["VSS!"] += 1
                elif hi <= 38825: c["VDD!"] += 1
                elif lo >= 45465: c["VDDARRAY!"] += 1
    print(inst.getName(), inst.getOrient(), c)
