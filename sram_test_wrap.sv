// sram_test_wrap.sv
// Detachable test port for the Chips4Makers SP6TBlock_512x32we4 macro.
//
// Map (CPU sees it at 0x3000_0000, decoded in soc_top):
//   +0x0000 .. +0x07FC  512 x 32-bit SRAM words, byte writes via wstrb
//   +0x1000             STATUS (RO): bit0 = SRAM enabled (strap), bits 31:8 = 0x5A4D00 id
//
// Isolation, so a dead SRAM can't take Argo down:
//   * sram_en comes from a strap pad, synchronized, default off when the pad is low
//   * disabled: macro clock gated off, all macro inputs forced to 0
//     (no switching, no back-powering an unpowered VDD_SRAM domain)
//   * disabled: SRAM reads return 0, writes are dropped, ready still comes back,
//     so the CPU never hangs on this region
//   * macro q is ANDed with sram_en before it reaches the bus, so X or floating
//     outputs from an unpowered macro can't leak into Argo
//
// Access timing: the C4M model latches the address on one edge and writes
// using the previously latched address. The wrapper holds the address for two
// macro clock edges on every access, so it is correct whether silicon writes
// with the old or the new latched address.
//   S_ADDR : a = addr, we = 0            (edge latches address)
//   S_DATA : a = addr, we = wstrb, d     (edge performs write; q valid for reads)
//   S_DONE : ready = 1, rdata from q captured at end of S_DATA

module sram_test_wrap (
    input  wire        clk,
    input  wire        rst_n,        // synchronized reset from soc_top
    input  wire        sram_en_pad,  // strap pad, async

    // PicoRV32 native slave port (sel = mem_valid && region hit)
    input  wire        sel,
    input  wire [12:0] addr,         // byte offset within the region
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output reg         ready,
    output reg  [31:0] rdata,

    // to the macro
    output wire        m_clk,
    output wire [8:0]  m_a,
    output wire [31:0] m_d,
    output wire [3:0]  m_we,
    input  wire [31:0] m_q
);
    // strap synchronizer
    reg en_s1, en_s2;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) {en_s2, en_s1} <= 2'b00;
        else        {en_s2, en_s1} <= {en_s1, sram_en_pad};
    wire sram_en = en_s2;

    localparam S_IDLE = 2'd0, S_ADDR = 2'd1, S_DATA = 2'd2, S_DONE = 2'd3;
    reg [1:0]  state;
    reg [8:0]  a_r;
    reg [31:0] d_r;
    reg [3:0]  we_r;
    reg        is_status;

    // isolation: macro outputs never reach the bus when disabled
    wire [31:0] m_q_iso = m_q & {32{sram_en}};

    wire start = sel && !ready && state == S_IDLE;
    wire hit_status = addr[12];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; ready <= 1'b0; rdata <= 32'd0;
            a_r <= 9'd0; d_r <= 32'd0; we_r <= 4'd0; is_status <= 1'b0;
        end else begin
            ready <= 1'b0;
            case (state)
                S_IDLE: if (start) begin
                    is_status <= hit_status;
                    if (hit_status || !sram_en) begin
                        // status read, or SRAM disabled: answer right away
                        rdata <= hit_status ? {24'h5A4D00, 7'd0, sram_en} : 32'd0;
                        state <= S_DONE;
                    end else begin
                        a_r  <= addr[10:2];
                        d_r  <= wdata;
                        we_r <= 4'd0;                // first edge: address only
                        state <= S_ADDR;
                    end
                end
                S_ADDR: begin
                    we_r  <= wstrb;                  // second edge: write strobes
                    state <= S_DATA;
                end
                S_DATA: begin
                    rdata <= m_q_iso;                // q valid after the address edge
                    we_r  <= 4'd0;
                    state <= S_DONE;
                end
                S_DONE: begin
                    ready <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // isolation: everything into the macro is 0 when disabled
    assign m_a  = a_r  & {9{sram_en}};
    assign m_d  = d_r  & {32{sram_en}};
    assign m_we = we_r & {4{sram_en}};

    // clock gate: macro clock only runs while enabled and an access is in flight
    wire clk_req = sram_en && (state == S_ADDR || state == S_DATA);
    sram_clk_gate u_cg (.clk(clk), .en(clk_req), .gclk(m_clk));
endmodule

// Latch-based clock gate. In synthesis, map to the PDK ICG cell.
module sram_clk_gate (
    input  wire clk,
    input  wire en,
    output wire gclk
);
`ifdef SRAM_USE_ICG_CELL
    sg13cmos5l_lgcp_1 u_icg (.CLK(clk), .GATE(en), .GCLK(gclk));
`else
    reg en_l;
    always @(*) if (!clk) en_l = en;
    assign gclk = clk & en_l;
`endif
endmodule
