#!/bin/bash
# CI entry point: lint, firmware build and RTL regression
set -e
cd "$(dirname "$0")"
export CMOS5L_PDK_ROOT=${CMOS5L_PDK_ROOT:-/usr/local/share/OpenPDKs/IHP-Open-PDK}
CROSS=${CROSS:-riscv64-unknown-elf-}
./lint.sh
( cd firmware && for p in hello sa_test sram_test post; do make -B -s PROG=$p CROSS=$CROSS; done )
./run_regress.sh 2>&1 | tee regress.log
! grep -q "^FAIL" regress.log
