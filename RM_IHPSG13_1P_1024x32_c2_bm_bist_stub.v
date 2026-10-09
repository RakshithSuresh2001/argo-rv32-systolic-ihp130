// =============================================================================
// RM_IHPSG13_1P_1024x32_c2_bm_bist_stub.v
// -----------------------------------------------------------------------------
// Minimal blackbox port declaration for the real IHP SRAM macro
// RM_IHPSG13_1P_1024x32_c2_bm_bist. Used only to satisfy Verilator's lint
// step and Yosys's port-visibility requirements; contains no behavioral
// logic. The actual timing/behavior for synthesis, PnR, and STA come from
// the macro's real LEF/LIB/GDS views (see MACROS config in config.yaml),
// not from this file.
//
// Port list and widths taken directly from the vendor's own
// RM_IHPSG13_1P_1024x32_c2_bm_bist.v (IHP-Open-PDK, Apache 2.0).
// =============================================================================
module RM_IHPSG13_1P_1024x32_c2_bm_bist (
    A_CLK,
    A_MEN,
    A_WEN,
    A_REN,
    A_ADDR,
    A_DIN,
    A_DLY,
    A_DOUT,
    A_BM,
    A_BIST_CLK,
    A_BIST_EN,
    A_BIST_MEN,
    A_BIST_WEN,
    A_BIST_REN,
    A_BIST_ADDR,
    A_BIST_DIN,
    A_BIST_BM
);
    input  A_CLK;
    input  A_MEN;
    input  A_WEN;
    input  A_REN;
    input  [9:0]  A_ADDR;
    input  [31:0] A_DIN;
    input  A_DLY;
    output [31:0] A_DOUT;
    input  [31:0] A_BM;
    input  A_BIST_CLK;
    input  A_BIST_EN;
    input  A_BIST_MEN;
    input  A_BIST_WEN;
    input  A_BIST_REN;
    input  [9:0]  A_BIST_ADDR;
    input  [31:0] A_BIST_DIN;
    input  [31:0] A_BIST_BM;
endmodule
