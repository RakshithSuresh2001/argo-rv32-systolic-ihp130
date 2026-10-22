#!/bin/bash
# Verilator lint of Argo's RTL. Reviewed waivers live in lint.vlt; any new
# warning in Argo's own files fails (exit 1).
cd "$(dirname "$0")"
command -v verilator >/dev/null || { echo "lint: verilator not found"; exit 1; }
verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL --top-module soc_top lint.vlt \
  soc_top.sv picorv32/picorv32.v systolic_array.sv pe.sv spi_slave.sv uart_tx.sv axilite_slave.sv \
  sram_word_ctrl.sv sram_test_wrap.sv sram_test/SP6TSRAM_512x32_4we_stub.v RM_IHPSG13_1P_1024x32_c2_bm_bist_stub.v \
  && echo "LINT PASS"
