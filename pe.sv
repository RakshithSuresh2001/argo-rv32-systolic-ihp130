// =============================================================================
// pe.sv — Processing Element (Yosys-compatible)
// Author: Rakshith Suresh
// =============================================================================
module pe #(
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 weight_load,
    input  wire [DATA_W-1:0]    weight_in,
    input  wire [DATA_W-1:0]    act_in,
    output reg  [DATA_W-1:0]    act_out,
    input  wire [ACC_W-1:0]     psum_in,
    output reg  [ACC_W-1:0]     psum_out
);
    reg [DATA_W-1:0] weight_reg;
    // Signed int8 x int8. Product computed separately and sign-extended
    // explicitly: mixing it with the unsigned psum_in in one expression
    // would silently make the whole add unsigned (Verilog signedness rule).
    wire signed [2*DATA_W-1:0] prod = $signed(weight_reg) * $signed(act_in);
    always @(posedge clk) begin
        if (!rst_n) begin
            weight_reg <= {DATA_W{1'b0}};
            act_out    <= {DATA_W{1'b0}};
            psum_out   <= {ACC_W{1'b0}};
        end else begin
            if (weight_load)
                weight_reg <= weight_in;
            act_out  <= act_in;
            psum_out <= psum_in + {{(ACC_W-2*DATA_W){prod[2*DATA_W-1]}}, prod};
        end
    end
endmodule
