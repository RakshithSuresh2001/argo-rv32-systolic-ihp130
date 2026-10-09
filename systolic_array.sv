// =============================================================================
// systolic_array.sv — 8x8 Weight-Stationary Systolic Array (Yosys-compatible)
// Author: Rakshith Suresh
// -----------------------------------------------------------------------------
// Flattened port declarations for Yosys compatibility.
// Activations flow left->right, partial sums accumulate top->bottom.
// 12 pipeline stages: 2 input regs + 8 PE rows + 2 output regs
// col[k] peaks at cycle 20+k due to 1-cycle horizontal skew
// =============================================================================

module systolic_array #(
    parameter ROWS   = 8,
    parameter COLS   = 8,
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  wire                          clk,
    input  wire                          rst_n,

    // Weight load interface
    input  wire                          weight_load,
    input  wire [2:0]                    weight_row,

    // Flattened weight data: COLS * DATA_W bits
    input  wire [COLS*DATA_W-1:0]        weight_data_flat,

    // Flattened activation inputs: ROWS * DATA_W bits
    input  wire [ROWS*DATA_W-1:0]        act_in_flat,

    // Flattened partial sum outputs: COLS * ACC_W bits
    output reg  [COLS*ACC_W-1:0]         psum_out_flat,
    // Done pulse — fires 12 cycles after last activation
    output reg                           done
);

    // Unpack weight_data and act_in from flat ports
    wire [DATA_W-1:0] weight_data [0:COLS-1];
    wire [DATA_W-1:0] act_in      [0:ROWS-1];

    genvar unpack_i;
    generate
        for (unpack_i = 0; unpack_i < COLS; unpack_i = unpack_i + 1) begin : unpack_w
            assign weight_data[unpack_i] = weight_data_flat[(unpack_i+1)*DATA_W-1 : unpack_i*DATA_W];
        end
        for (unpack_i = 0; unpack_i < ROWS; unpack_i = unpack_i + 1) begin : unpack_a
            assign act_in[unpack_i] = act_in_flat[(unpack_i+1)*DATA_W-1 : unpack_i*DATA_W];
        end
    endgenerate

    // ── Stages 1 & 2: Input pipeline registers ──────────────────────────────
    reg [DATA_W-1:0] act_s1 [0:ROWS-1];
    reg [DATA_W-1:0] act_s2 [0:ROWS-1];

    genvar s;
    generate
        for (s = 0; s < ROWS; s = s + 1) begin : stage_reg
            always @(posedge clk) begin
                if (!rst_n) begin
                    act_s1[s] <= {DATA_W{1'b0}};
                    act_s2[s] <= {DATA_W{1'b0}};
                end else begin
                    act_s1[s] <= act_in[s];
                    act_s2[s] <= act_s1[s];
                end
            end
        end
    endgenerate

    // ── PE array internal wiring ─────────────────────────────────────────────
    wire [DATA_W-1:0] act_h  [0:ROWS-1][0:COLS];
    wire [ACC_W-1:0]  psum_v [0:ROWS]  [0:COLS-1];

    genvar r;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : act_feed
            assign act_h[r][0] = act_s2[r];
        end
    endgenerate

    genvar c;
    generate
        for (c = 0; c < COLS; c = c + 1) begin : psum_top
            assign psum_v[0][c] = {ACC_W{1'b0}};
        end
    endgenerate

    // ── 8x8 PE grid ──────────────────────────────────────────────────────────
    genvar row, col;
    generate
        for (row = 0; row < ROWS; row = row + 1) begin : gen_row
            for (col = 0; col < COLS; col = col + 1) begin : gen_col
                pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_pe (
                    .clk         (clk),
                    .rst_n       (rst_n),
                    .weight_load (weight_load && (weight_row == row)),
                    .weight_in   (weight_data[col]),
                    .act_in      (act_h[row][col]),
                    .act_out     (act_h[row][col+1]),
                    .psum_in     (psum_v[row][col]),
                    .psum_out    (psum_v[row+1][col])
                );
            end
        end
    endgenerate

    // ── Stages 11 & 12: Output pipeline registers ────────────────────────────
    reg [ACC_W-1:0] psum_s11 [0:COLS-1];
    reg [ACC_W-1:0] psum_out [0:COLS-1];

    genvar o;
    generate
        for (o = 0; o < COLS; o = o + 1) begin : out_reg
            always @(posedge clk) begin
                if (!rst_n) begin
                    psum_s11[o] <= {ACC_W{1'b0}};
                    psum_out[o] <= {ACC_W{1'b0}};
                end else begin
                    psum_s11[o] <= psum_v[ROWS][o];
                    psum_out[o] <= psum_s11[o];
                end
            end
            // Pack output
            assign psum_out_flat[(o+1)*ACC_W-1 : o*ACC_W] = psum_out[o];
        end
    endgenerate

// ---------------------------------------------------------------------------
// Done signal — shift register tracks activation valid through pipeline
// ---------------------------------------------------------------------------
reg [11:0] act_valid_sr;
wire       act_valid = |act_in_flat;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        act_valid_sr <= 12'b0;
        done         <= 1'b0;
    end else begin
        act_valid_sr <= {act_valid_sr[10:0], act_valid};
        done         <= act_valid_sr[11] & ~act_valid_sr[10];
    end
end


endmodule
