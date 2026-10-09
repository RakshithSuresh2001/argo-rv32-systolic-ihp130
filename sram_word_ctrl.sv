// =============================================================================
// sram_word_ctrl.sv - Memory controller wrapping a real IHP SRAM macro
// -----------------------------------------------------------------------------
// Wraps RM_IHPSG13_1P_1024x32_c2_bm_bist (1024 x 32-bit, single-port, with
// per-bit write masking via A_BM).
//
// A_BM[i]=1'b1 writes bit i; A_BM[i]=1'b0 preserves the existing value
// (confirmed from RM_IHPSG13_1P_core_behavioral_bm_bist.v line 44). This lets
// byte-strobe writes commit in a single cycle with no read-modify-write.
//
// Macro timing (per datasheet): A_REN/A_ADDR are sampled on the clock edge
// that ends the cycle they're held stable. A_DOUT becomes valid on the
// FOLLOWING cycle (registered output, one-cycle access latency). Writes
// (A_WEN/A_DIN/A_BM) commit at the same sampling edge.
//
// Timing contract (cycles from `valid` asserted to `ready` pulsing):
//   - Read:  2 cycles (1 to present REN/ADDR, 1 for DOUT to register)
//   - Write: 2 cycles (1 to present WEN/ADDR/DIN/BM, 1 for commit to complete)
//     (any byte combination, via A_BM, single-pass, no RMW)
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module sram_word_ctrl #(
    parameter ADDR_W = 10   // 1024 words = 10-bit address
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // CPU-facing interface
    input  wire                  valid,
    input  wire [ADDR_W-1:0]     addr,        // word address (not byte address)
    input  wire [31:0]           wdata,
    input  wire [3:0]            wstrb,       // 0 = read, nonzero = write (per-byte)
    output reg                   ready,
    output reg  [31:0]           rdata
);

    // -------------------------------------------------------------------------
    // Macro instantiation
    // -------------------------------------------------------------------------
    reg  [ADDR_W-1:0] mem_addr_r;
    reg                mem_wen_r;
    reg                mem_ren_r;
    reg  [31:0]        mem_din_r;
    reg  [31:0]        mem_bm_r;
    wire [31:0]        mem_dout;

    RM_IHPSG13_1P_1024x32_c2_bm_bist u_mem (
        .A_CLK        (clk),
        .A_MEN        (mem_wen_r | mem_ren_r),
        .A_WEN        (mem_wen_r),
        .A_REN        (mem_ren_r),
        .A_ADDR       (mem_addr_r),
        .A_DIN        (mem_din_r),
        .A_BM         (mem_bm_r),
        .A_DLY        (1'b1),        // mandatory tie-off per macro datasheet
        .A_DOUT       (mem_dout),
        // BIST disabled for normal operation
        .A_BIST_CLK   (1'b0),
        .A_BIST_EN    (1'b0),
        .A_BIST_MEN   (1'b0),
        .A_BIST_WEN   (1'b0),
        .A_BIST_REN   (1'b0),
        .A_BIST_ADDR  ({ADDR_W{1'b0}}),
        .A_BIST_DIN   (32'b0),
        .A_BIST_BM    (32'b0)
    );

    // -------------------------------------------------------------------------
    // Control FSM
    // -------------------------------------------------------------------------
    localparam ST_IDLE   = 2'd0;
    localparam ST_ACCESS = 2'd1;   // REN or WEN presented, stable this cycle
    localparam ST_DONE   = 2'd2;   // for reads: DOUT now valid; for writes: commit done

    reg [1:0] state;
    reg       req_is_write;

    wire is_write = (wstrb != 4'b0000);

    // Expand byte strobes to a 32-bit per-bit mask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            ready        <= 1'b0;
            rdata        <= 32'b0;
            mem_wen_r    <= 1'b0;
            mem_ren_r    <= 1'b0;
            mem_addr_r   <= '0;
            mem_din_r    <= 32'b0;
            mem_bm_r     <= 32'b0;
            req_is_write <= 1'b0;
        end else begin
            ready <= 1'b0;  // default; pulsed high only in DONE

            case (state)
                ST_IDLE: begin
                    // !ready: in the cycle ready is visible the requester still holds
                    // valid; accepting it would start a ghost access whose ready lands
                    // on the NEXT transaction with stale data.
                    if (valid && !ready) begin
                        mem_addr_r   <= addr;
                        req_is_write <= is_write;
                        if (is_write) begin
                            mem_din_r <= wdata;
                            mem_bm_r  <= {{8{wstrb[3]}}, {8{wstrb[2]}}, {8{wstrb[1]}}, {8{wstrb[0]}}};
                            mem_wen_r <= 1'b1;
                            mem_ren_r <= 1'b0;
                        end else begin
                            mem_wen_r <= 1'b0;
                            mem_ren_r <= 1'b1;
                        end
                        state <= ST_ACCESS;
                    end
                end

                // REN/WEN + ADDR (+DIN/BM for writes) are stable THIS cycle;
                // sampled by the macro at the edge ending this state.
                ST_ACCESS: begin
                    mem_wen_r <= 1'b0;
                    mem_ren_r <= 1'b0;
                    state     <= ST_DONE;
                end

                ST_DONE: begin
                    // For reads, DOUT is valid now (one cycle after sampling).
                    // For writes, the commit already happened at the edge that
                    // brought us here; nothing further to do but signal ready.
                    if (!req_is_write) rdata <= mem_dout;
                    ready <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
