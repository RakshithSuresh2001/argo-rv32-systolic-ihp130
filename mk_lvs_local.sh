#!/bin/bash
set -e
rm -rf "$2"; mkdir -p "$2"; cp -rL "$1"/. "$2"/
python3 - "$2/sg13cmos5l.lvs" <<'EOF'
import sys
p=sys.argv[1]; s=open(p).read()
add='''  align

  # LOCAL: -rd blackbox=a,b,* removes those circuits (and all calls) from BOTH netlists
  if $blackbox && !$blackbox.to_s.empty?
    [netlist, schematic].each do |nl|
      $blackbox.to_s.split(',').each do |bb|
        rx = Regexp.new('\\\\A' + Regexp.escape(bb).gsub('\\\\*', '.*') + '\\\\z', Regexp::IGNORECASE)
        victims = []
        nl.each_circuit { |cc| victims << cc.name if rx.match(cc.name) }
        victims.each do |vn|
          c = nl.circuit_by_name(vn)
          next unless c
          refs = []
          c.each_ref { |sc| refs << sc }
          refs.each { |sc| sc.circuit.remove_subcircuit(sc) }
          nl.remove(c)
          logger.info("Black box removed: #{vn} (#{refs.size} calls)")
        end
      end
    end
  end
'''
assert s.count('\n  align\n')==1, "align anchor not found"
open(p,'w').write(s.replace('\n  align\n','\n'+add,1))
EOF
grep -c "Black box removed" "$2/sg13cmos5l.lvs"
