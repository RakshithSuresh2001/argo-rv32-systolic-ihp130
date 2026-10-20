#!/bin/bash
# RTL regression: all SoC-level tests on the real IHP SRAM models,
# run with the SRAM test strap low (detached) and high (enabled)
set -e
cd "$(dirname "$0")"
for p in hello sa_test sram_test; do make -s -C firmware PROG=$p >/dev/null; done
SRAMV=$(ls ${CMOS5L_PDK_ROOT:-$HOME/ihp-open-pdk-dev}/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/verilog/*.v | tr '\n' ' ')
RTL="soc_top.sv picorv32/picorv32.v systolic_array.sv pe.sv spi_slave.sv uart_tx.sv axilite_slave.sv sram_word_ctrl.sv sram_test_wrap.sv sram_test/SP6TSRAM_512x32_4we.v $SRAMV"
IV=$(command -v iverilog || echo ~/oss-cad-suite/bin/iverilog); VVP=$(command -v vvp || echo ~/oss-cad-suite/bin/vvp)
for t in tb_boot tb_spi tb_fw; do $IV -g2012 -o /tmp/$t.vvp -s $t tb/$t.sv $RTL; done
set +e
fail=0
chk() { if echo "$2" | grep -q "^PASS"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }
fw() { $VVP /tmp/tb_fw.vvp +hex=firmware/$1.hex +words=$(wc -l < firmware/$1.hex) +expect=$2 ${@:3} | grep -oE '^(PASS|FAIL).*'; }
for en in 0 1; do
  chk "tb_boot   sram_en=$en" "$($VVP /tmp/tb_boot.vvp +sram_en=$en | grep -oE '^(PASS|FAIL).*')"
  chk "tb_spi    sram_en=$en" "$($VVP /tmp/tb_spi.vvp  +sram_en=$en | grep -oE '^(PASS|FAIL).*')"
  chk "hello     sram_en=$en" "$(fw hello   HI   +sram_en=$en)"
  chk "sa_test   sram_en=$en" "$(fw sa_test PASS +sram_en=$en)"
done
chk "sram_test sram_en=1 (march C-, addr, byte lanes)" "$(fw sram_test PASS +sram_en=1)"
chk "sram_test sram_en=0 (detached, reads 0)"          "$(fw sram_test OFF  +sram_en=0)"
chk "sram_test sram_en=0 + macro q forced X"           "$(fw sram_test OFF  +sram_en=0 +macro_x)"
chk "sa_test   sram_en=0 + macro q forced X"           "$(fw sa_test  PASS +sram_en=0 +macro_x)"
exit $fail
