#!/bin/bash
# Gate-level simulation of the final routed netlist.
# usage: ./run_gls.sh [prog] [zero|sdf|sdfnoic] [timeout_us] [sram_en]
#   prog     hello | sa_test | sram_test | post   (default hello)
#   sram_en  0 = SRAM test block detached, 1 = enabled (default 1)
#   RUN=runs/<tag>/final overrides the run (default runs/sram_full6/final)
cd "$(dirname "$0")"
PROG=${1:-hello}; MODE=${2:-zero}; TMO=${3:-40000}; EN=${4:-1}
RUN=${RUN:-runs/sram_full6/final}
P=${CMOS5L_PDK_ROOT:-$HOME/ihp-open-pdk-dev}/ihp-sg13cmos5l/libs.ref
NL=$RUN/nl/soc_padframe.nl.v
[ -f "$NL" ] || { echo "netlist not found: $NL"; exit 1; }
SC=$P/sg13cmos5l_stdcell/verilog
STEST_MODEL=sram_test/SP6TSRAM_512x32_4we.v          # arra-mem behavioral model
[ -f "$STEST_MODEL" ] || { echo "missing $STEST_MODEL (SRAM test macro sim model)"; exit 1; }
MODELS="$SC/sg13cmos5l_stdcell.v $P/sg13cmos5l_io/verilog/sg13cmos5l_io.v bondpad/bondpad_70x70.v $STEST_MODEL $(ls $P/sg13cmos5l_sram/verilog/*.v | tr '\n' ' ')"
grep -q '`include' $SC/sg13cmos5l_stdcell.v || MODELS="$SC/sg13cmos5l_udp.v $MODELS"

# tb_gls.sv = tb_fw.sv with the pad frame as DUT instead of soc_top
python3 - "tb/tb_gls_$$.sv" <<'PY'
import re, sys
s = open("tb/tb_fw.sv").read()
new = '''wire clk_w = clk, rst_w = rst_n, sram_en_w = sram_en;
  wire [3:0] in_pad = {spi_mosi, spi_cs_n, spi_clk, uart_rx};
  wire [1:0] out_pad;
  assign uart_tx = out_pad[0];
  assign spi_miso = out_pad[1];
  soc_padframe dut (.clk_PAD(clk_w), .rst_n_PAD(rst_w), .input_PAD(in_pad), .output_PAD(out_pad), .sram_en_PAD(sram_en_w));
  initial forever begin #50000; $display("[%0t] alive", $time); end
`ifdef SDF_FILE
  initial $sdf_annotate(`SDF_FILE, dut);
`endif'''
s2, n = re.subn(r"soc_top dut \(.*?\);", lambda m: new, s, flags=re.S)
assert n == 1, "soc_top instantiation not found in tb/tb_fw.sv"
# the macro_x hook forces an RTL-only net; the gate-level hierarchy has no dut.stest_m_q
s2, k = re.subn(r"^\s*initial if \(\$test\$plusargs\(\"macro_x\"\)\).*\n", "", s2, flags=re.M)
open(sys.argv[1], "w").write(s2.replace("module tb_fw;", "module tb_gls;"))
PY
[ -z "$PROBE" ] || sed -i "/^endmodule/e cat $PROBE" tb/tb_gls_$$.sv

IV=$(command -v iverilog || echo ~/oss-cad-suite/bin/iverilog); VVP=$(command -v vvp || echo ~/oss-cad-suite/bin/vvp)
OPTS=(-g2012)
if [ "$MODE" != zero ]; then
  SDF=$(find $RUN/sdf -name "*typ*.sdf" | head -1); echo "SDF: $SDF"
  if [ "$MODE" = sdfnoic ]; then grep -v "(INTERCONNECT" $SDF > gls_noic.sdf; SDF=$PWD/gls_noic.sdf; else OPTS+=(-ginterconnect); fi
  OPTS+=(-gspecify -Ttyp "-DSDF_FILE=\"$SDF\"")
fi
echo "compiling $NL ($MODE) ..."
$IV "${OPTS[@]}" -o /tmp/tb_gls_${MODE}_$$.vvp -s tb_gls tb/tb_gls_$$.sv $NL $MODELS > gls_compile_${PROG}_en${EN}_$MODE.log 2>&1; rc=$?
echo "compile rc=$rc, error lines: $(grep -ci error gls_compile_${PROG}_en${EN}_$MODE.log)"; grep -i -m 15 error gls_compile_${PROG}_en${EN}_$MODE.log
[ $rc -ne 0 ] && exit 1

make -s -C firmware PROG=$PROG >/dev/null || { echo "firmware build failed"; exit 1; }
case $PROG in
  hello)     EXP=HI ;;
  memw)      EXP=DONE ;;
  sa_test)   EXP=PASS ;;
  sram_test) [ "$EN" = 1 ] && EXP=PASS || EXP=OFF ;;
  post)      [ "$EN" = 1 ] && EXP=POST:I+D+A+S+ || EXP=POST:I+D+A+S0 ;;
  *) echo "unknown prog $PROG"; exit 1 ;;
esac
echo "running $PROG (sram_en=$EN), expecting \"$EXP\", timeout ${TMO} us ..."
time stdbuf -oL $VVP -n /tmp/tb_gls_${MODE}_$$.vvp +hex=firmware/$PROG.hex +words=$(wc -l < firmware/$PROG.hex) +expect=$EXP +sram_en=$EN +timeout_us=$TMO 2>&1 \
  | grep --line-buffered -vE "^(WARNING|SDF|.*sdf)" | tee gls_${PROG}_en${EN}_$MODE.log
grep -q "^PASS" gls_${PROG}_en${EN}_$MODE.log
