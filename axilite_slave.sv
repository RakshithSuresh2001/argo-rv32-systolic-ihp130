`default_nettype none
`timescale 1ns/1ps

// =============================================================================
// axilite_slave.sv — AXI-Lite slave for 8x8 weight-stationary systolic array
// Matches real systolic_array.sv port interface (flattened, pipeline style)
// Base address : 0x1000_0000
// =============================================================================
// Register map
//   0x00  WEIGHT_ROW      bits[2:0] = row index (0-7)
//   0x04  WEIGHT_DATA_LO  bits[31:0] = weight_data_flat[31:0]
//   0x08  WEIGHT_DATA_HI  bits[31:0] = weight_data_flat[63:32]
//   0x0C  WEIGHT_LOAD     write any value = pulse weight_load for 1 cycle
//   0x10  ACT_LO          bits[31:0] = act_in_flat[31:0]
//   0x14  ACT_HI          bits[31:0] = act_in_flat[63:32]
//   0x18  PSUM_SEL        bits[2:0] = output column to read (0-7)
//   0x1C  PSUM_DATA       bits[31:0] = psum_out_flat[col*32 +: 32] (read-only)
// =============================================================================

module axilite_slave (
    input  wire        clk,
    input  wire        rst_n,

    // PicoRV32 memory bus
    input  wire        mem_valid,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [ 3:0] mem_wstrb,
    output reg         mem_ready,
    output reg  [31:0] mem_rdata,

    // Systolic array interface
    output reg         weight_load,
    output reg  [ 2:0] weight_row,
    output reg  [63:0] weight_data_flat,
    output reg  [63:0] act_in_flat,
    input  wire [255:0] psum_out_flat
);

// ---------------------------------------------------------------------------
// Address decode
// ---------------------------------------------------------------------------
wire sel = mem_valid && (mem_addr[31:8] == 24'h100000);
wire we  = sel && (mem_wstrb != 4'b0);

wire [2:0] reg_sel = mem_addr[4:2];

localparam REG_WEIGHT_ROW     = 3'd0;
localparam REG_WEIGHT_DATA_LO = 3'd1;
localparam REG_WEIGHT_DATA_HI = 3'd2;
localparam REG_WEIGHT_LOAD    = 3'd3;
localparam REG_ACT_LO         = 3'd4;
localparam REG_ACT_HI         = 3'd5;
localparam REG_PSUM_SEL       = 3'd6;
localparam REG_PSUM_DATA      = 3'd7;

// ---------------------------------------------------------------------------
// Internal registers
// ---------------------------------------------------------------------------
reg [2:0] r_psum_sel;

// ---------------------------------------------------------------------------
// Write path
// ---------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        weight_load      <= 1'b0;
        weight_row       <= 3'b0;
        weight_data_flat <= 64'b0;
        act_in_flat      <= 64'b0;
        r_psum_sel       <= 3'b0;
    end else begin
        weight_load <= 1'b0; // default: clear pulse

        // !mem_ready: requester still holds valid in the ready cycle; without
        // this every write lands twice (WEIGHT_LOAD pulsed twice)
        if (we && !mem_ready) begin
            case (reg_sel)
                REG_WEIGHT_ROW:     weight_row              <= mem_wdata[2:0];
                REG_WEIGHT_DATA_LO: weight_data_flat[31:0]  <= mem_wdata;
                REG_WEIGHT_DATA_HI: weight_data_flat[63:32] <= mem_wdata;
                REG_WEIGHT_LOAD:    weight_load             <= 1'b1;
                REG_ACT_LO:         act_in_flat[31:0]       <= mem_wdata;
                REG_ACT_HI:         act_in_flat[63:32]      <= mem_wdata;
                REG_PSUM_SEL:       r_psum_sel              <= mem_wdata[2:0];
                default: ;
            endcase
        end
    end
end

// ---------------------------------------------------------------------------
// Read path
// ---------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_rdata <= 32'b0;
    end else if (sel) begin
        case (reg_sel)
            REG_WEIGHT_ROW:     mem_rdata <= {29'b0, weight_row};
            REG_WEIGHT_DATA_LO: mem_rdata <= weight_data_flat[31:0];
            REG_WEIGHT_DATA_HI: mem_rdata <= weight_data_flat[63:32];
            REG_WEIGHT_LOAD:    mem_rdata <= 32'b0;
            REG_ACT_LO:         mem_rdata <= act_in_flat[31:0];
            REG_ACT_HI:         mem_rdata <= act_in_flat[63:32];
            REG_PSUM_SEL:       mem_rdata <= {29'b0, r_psum_sel};
            REG_PSUM_DATA:      mem_rdata <= psum_out_flat[r_psum_sel*32 +: 32];
            default:            mem_rdata <= 32'b0;
        endcase
    end
end

// ---------------------------------------------------------------------------
// mem_ready — 1 cycle after valid select
// ---------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) mem_ready <= 1'b0;
    else        mem_ready <= sel && !mem_ready;   // 1-cycle pulse
end

endmodule
`default_nettype wire
