#!/bin/bash
# Gate-level simulation of the final netlist.  usage: ./run_gls.sh [hello|sa_test] [zero|sdf] [timeout_us]
cd "$(dirname "$0")"
PROG=${1:-hello}; MODE=${2:-zero}; TMO=${3:-20000}
RUN=${RUN:-runs/c5l_v3/final}
P=${CMOS5L_PDK_ROOT:-$HOME/ihp-open-pdk-dev}/ihp-sg13cmos5l/libs.ref
NL=$RUN/nl/soc_padframe.nl.v
SC=$P/sg13cmos5l_stdcell/verilog
MODELS="$SC/sg13cmos5l_stdcell.v $P/sg13cmos5l_io/verilog/sg13cmos5l_io.v bondpad/bondpad_70x70.v $(ls $P/sg13cmos5l_sram/verilog/*.v | tr '\n' ' ')"
grep -q '`include' $SC/sg13cmos5l_stdcell.v || MODELS="$SC/sg13cmos5l_udp.v $MODELS"
python3 - <<'EOF'
import re
s = open("tb/tb_fw.sv").read()
new = '''wire clk_w = clk, rst_w = rst_n;
  wire [3:0] in_pad = {spi_mosi, spi_cs_n, spi_clk, uart_rx};
  wire [1:0] out_pad;
  assign uart_tx = out_pad[0];
  assign spi_miso = out_pad[1];
  soc_padframe dut (.clk_PAD(clk_w), .rst_n_PAD(rst_w), .input_PAD(in_pad), .output_PAD(out_pad));
  initial forever begin #50000; $display("[%0t] alive", $time); end
`ifdef SDF_FILE
  initial $sdf_annotate(`SDF_FILE, dut);
`endif'''
s2, n = re.subn(r"soc_top dut \(.*?\);", lambda m: new, s, flags=re.S)
assert n == 1, "soc_top instantiation not found in tb/tb_fw.sv"
open("tb/tb_gls.sv", "w").write(s2.replace("module tb_fw;", "module tb_gls;"))
EOF
IV=~/oss-cad-suite/bin/iverilog; VVP=~/oss-cad-suite/bin/vvp
OPTS=(-g2012)
if [ "$MODE" != zero ]; then
  SDF=$(find $RUN/sdf -name "*typ*.sdf" | head -1); echo "SDF: $SDF"
  if [ "$MODE" = sdfnoic ]; then grep -v "(INTERCONNECT" $SDF > gls_noic.sdf; SDF=$PWD/gls_noic.sdf; else OPTS+=(-ginterconnect); fi
  OPTS+=(-gspecify -Ttyp "-DSDF_FILE=\"$SDF\"")
fi
echo "compiling ($MODE) ..."
$IV "${OPTS[@]}" -o /tmp/tb_gls_$MODE.vvp -s tb_gls tb/tb_gls.sv $NL $MODELS > gls_compile_$MODE.log 2>&1; rc=$?
echo "compile rc=$rc, error lines: $(grep -ci error gls_compile_$MODE.log)"; grep -i -m 15 error gls_compile_$MODE.log
[ $rc -ne 0 ] && exit 1
EXP=HI; [ "$PROG" = sa_test ] && EXP=PASS
echo "running $PROG, expecting \"$EXP\", timeout ${TMO} us ..."
time $VVP -n /tmp/tb_gls_$MODE.vvp +hex=firmware/$PROG.hex +words=$(wc -l < firmware/$PROG.hex) +expect=$EXP +timeout_us=$TMO 2>&1 | grep --line-buffered -vE "^(WARNING|SDF|.*sdf)"
