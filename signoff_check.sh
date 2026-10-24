#!/bin/bash
# Signoff gate for a finished LibreLane run. Fails (exit 1) on any DRC, LVS,
# density, antenna or route error; reports timing per corner.
# usage: ./signoff_check.sh [run_tag]   (default: newest run under runs/)
cd "$(dirname "$0")"
RUN=runs/${1:-$(ls -t runs | head -1)}
M=$RUN/final/metrics.json
[ -f "$M" ] || { echo "SIGNOFF FAIL: $M not found (flow did not finish)"; exit 1; }
python3 - "$M" "$RUN" <<'PY'
import json, sys, glob
m, run = json.load(open(sys.argv[1])), sys.argv[2]
fail = []
for k in ["klayout__drc_error__count", "design__lvs_error__count", "route__drc_errors"]:
    v = m.get(k)
    print(f"{k:40s} {v}")
    if v is None or float(v) != 0: fail.append(k)
for f in sorted(glob.glob(f"{run}/*klayout*/reports/*.lyrdb")):
    n = open(f).read().count("<item>")
    print(f"{f.split('/')[2]:40s} {n}")
    if n: fail.append(f)
for c in ["nom_fast_1p32V_m40C", "nom_typ_1p20V_25C", "nom_slow_1p08V_125C"]:
    print(f"setup WNS {c:28s} {m.get('timing__setup__ws__corner:'+c)}")
h = m.get("timing__hold__ws")
print(f"{'hold WNS (all corners)':40s} {h}")
if h is None or float(h) < 0: fail.append("hold")
t = m.get("timing__setup__ws__corner:nom_typ_1p20V_25C")
if t is None or float(t) < 0: fail.append("typical-corner setup")
print("SIGNOFF PASS" if not fail else "SIGNOFF FAIL: " + ", ".join(fail))
sys.exit(1 if fail else 0)
PY
