#!/bin/bash
# RTL regression: all SoC-level tests on the real IHP SRAM models
set -e
cd "$(dirname "$0")"
make -s -C firmware PROG=hello >/dev/null && make -s -C firmware PROG=sa_test >/dev/null
SRAMV=$(ls ${CMOS5L_PDK_ROOT:-$HOME/ihp-open-pdk-dev}/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/verilog/*.v | tr '\n' ' ')
RTL="soc_top.sv picorv32/picorv32.v systolic_array.sv pe.sv spi_slave.sv uart_tx.sv axilite_slave.sv sram_word_ctrl.sv $SRAMV"
IV=~/oss-cad-suite/bin/iverilog; VVP=~/oss-cad-suite/bin/vvp
for t in tb_boot tb_spi tb_fw; do $IV -g2012 -o /tmp/$t.vvp -s $t tb/$t.sv $RTL; done
fail=0
chk() { if echo "$2" | grep -q "^PASS"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }
chk tb_boot "$($VVP /tmp/tb_boot.vvp | grep -oE '^(PASS|FAIL).*')"
chk tb_spi  "$($VVP /tmp/tb_spi.vvp  | grep -oE '^(PASS|FAIL).*')"
chk hello   "$($VVP /tmp/tb_fw.vvp +hex=firmware/hello.hex   +words=$(wc -l < firmware/hello.hex)   +expect=HI   | grep -oE '^(PASS|FAIL).*')"
chk sa_test "$($VVP /tmp/tb_fw.vvp +hex=firmware/sa_test.hex +words=$(wc -l < firmware/sa_test.hex) +expect=PASS | grep -oE '^(PASS|FAIL).*')"
exit $fail
