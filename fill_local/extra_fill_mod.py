# Density top-up for Metal2/Metal3: shaped fill (not fixed squares) in 800x800 um windows below TARGET.
# DRC deck checks on fill: MFil.c (>= 0.42 um to same-layer metal) and MFil.a2 (bbox <= 5.0 um).
try:
    import klayout.db as db
except ImportError:
    import pya as db
WIN = 800.0
LAYERS = {"Metal2": 10, "Metal3": 30}
SP = 0.42      # fill to metal and fill to fill
MINW = 1.0     # min fill width
CELL = 5.0     # max fill bbox

def top_up(ly, top, TARGET=0.29, STEP=200.0):
    dbu = ly.dbu
    U = lambda v: int(round(v / dbu))
    def reg(layer, dt):
        li = ly.find_layer(layer, dt)
        return db.Region(top.begin_shapes_rec(li)) if li is not None else db.Region()
    def windows(cb, step):
        out = []; x = cb.left
        while x + U(WIN) <= cb.right + 1:
            y = cb.bottom
            while y + U(WIN) <= cb.top + 1:
                out.append(db.Box(x, y, x + U(WIN), y + U(WIN))); y += U(step)
            x += U(step)
        return out
    def dens(r, w):
        t = r & db.Region(w); t.merge()
        return t.area() / float(w.area())

    seal = reg(39, 0); nometf = reg(160, 0)
    chip = seal.holes() if not seal.is_empty() else db.Region(top.bbox())
    chip.merge()
    if chip.is_empty(): chip = db.Region(top.bbox())
    cb = chip.bbox()
    wins = windows(cb, STEP); deck = windows(cb, 400.0)
    print("chip bbox um:", cb.left*dbu, cb.bottom*dbu, cb.right*dbu, cb.top*dbu, " windows:", len(wins), "deck windows:", len(deck))

    for name, ln in LAYERS.items():
        m = reg(ln, 0) + reg(ln, 22); m.merge()
        d0 = [dens(m, w) for w in wins]
        todo = [w for w, d in zip(wins, d0) if d < TARGET]
        print(f"{name}: before min {min(d0)*100:.2f}% (deck grid min {min(dens(m, w) for w in deck)*100:.2f}%), windows below {TARGET*100:.0f}%: {len(todo)}")
        if not todo: continue
        aoi = db.Region()
        for w in todo: aoi.insert(w)
        aoi.merge(); aoi &= chip
        near = m & aoi.sized(U(SP))
        free = aoi - (near.sized(U(SP)) + reg(ln, 23) + reg(ln, 24) + nometf)
        free.merge()
        ab = aoi.bbox(); p = U(CELL + SP); c = U(CELL)
        cells = db.Region()
        for xi in range((ab.left // p) * p, ab.right, p):
            for yi in range((ab.bottom // p) * p, ab.top, p):
                cells.insert(db.Box(xi, yi, xi + c, yi + c))
        cand = free & cells
        h = U(MINW / 2.0)
        cand = cand.sized(-h, -h, 2).sized(h, h, 2)     # opening: drops everything narrower than MINW
        cand.merge()
        bad = cand.interacting(cand.space_check(U(SP)).polygons() + cand.width_check(U(MINW)).polygons())
        cand = cand - bad
        keep = db.Region()
        for pg in cand.each():
            b = pg.bbox()
            if b.width() > c or b.height() > c: continue
            if any(pt.x % 5 or pt.y % 5 for pt in pg.each_point_hull()): continue
            keep.insert(pg)
        cand = keep
        print(f"   candidate fill: {cand.count()} shapes, {cand.area()*dbu*dbu:.0f} um2")
        added = db.Region()
        for w in todo:
            wr = db.Region(w)
            d = dens(m + added, w)
            if d >= TARGET: continue
            need = (TARGET - d) * w.area()
            pool = sorted((cand.inside(wr) - added).each(), key=lambda q: -q.area())
            got = 0.0
            for pg in pool:
                if got >= need: break
                added.insert(pg); got += pg.area()
        added.merge()
        top.shapes(ly.layer(ln, 22)).insert(added)
        fin = m + added; fin.merge()
        d1 = [dens(fin, w) for w in wins]; d2 = [dens(fin, w) for w in deck]
        print(f"   added {added.count()} shapes ({added.area()*dbu*dbu:.0f} um2): min {min(d1)*100:.2f}% max {max(d1)*100:.2f}%, deck grid min {min(d2)*100:.2f}% max {max(d2)*100:.2f}%, deck windows below 25%: {sum(1 for v in d2 if v < 0.25)}")
        c_viol = m.separation_check(added, U(SP)).count()
        a2 = sum(1 for pg in added.each() if pg.bbox().width() > c or pg.bbox().height() > c)
        offg = sum(1 for pg in added.each() for pt in pg.each_point_hull() if pt.x % 5 or pt.y % 5)
        print(f"   checks: MFil.c (<{SP} to metal) {c_viol}  MFil.a2 (bbox>{CELL}) {a2}  fill-fill<{SP} {added.space_check(U(SP)).count()}  width<{MINW} {added.width_check(U(MINW)).count()}  off-grid points {offg}")
