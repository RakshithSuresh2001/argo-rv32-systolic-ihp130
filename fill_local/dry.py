import pya, time
exec(open(mod).read())
ly = pya.Layout(); ly.read(gds); t = time.time()
top_up(ly, max(ly.top_cells(), key=lambda c: c.bbox().area()))
print("dry run time %.0fs (nothing written)" % (time.time() - t))
