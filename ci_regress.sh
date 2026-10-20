#!/bin/bash
# CI entry point for the Symbiotic EDA bouquet [202610] IHP ASIC accelerator
set -e
cd "$(dirname "$0")"
export CMOS5L_PDK_ROOT=${CMOS5L_PDK_ROOT:-/usr/local/share/OpenPDKs/IHP-Open-PDK}
CROSS=${CROSS:-riscv64-unknown-elf-}
( cd firmware && for p in hello sa_test sram_test; do make -B -s PROG=$p CROSS=$CROSS; done )
./run_regress.sh 2>&1 | tee regress.log
! grep -q "^FAIL" regress.log
