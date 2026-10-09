// =============================================================================
// uart_tx.sv — Minimal 8N1 UART transmitter
// Parameters : CLK_FREQ (Hz), BAUD_RATE (bps)
// Interface  : AXI-stream-like (valid/ready handshake)
// Usage      : Write byte to 0x2000_0000; poll bit[0] of same addr for ready
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module uart_tx #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 115_200
) (
    input  wire       clk,
    input  wire       rst_n,

    // Input handshake
    input  wire       tx_valid,    // CPU: byte ready to send
    input  wire [7:0] tx_data,     // byte to transmit
    output reg        tx_ready,    // module: ready to accept new byte

    // UART line
    output reg        tx           // serial output (idle = 1)
);

// ---------------------------------------------------------------------------
// Baud rate generator
// ---------------------------------------------------------------------------
localparam int BAUD_DIV = CLK_FREQ / BAUD_RATE;  // clocks per bit

reg [$clog2(BAUD_DIV)-1:0] baud_cnt;
wire baud_tick = (baud_cnt == BAUD_DIV - 1);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        baud_cnt <= '0;
    else if (baud_tick || tx_ready)   // reset counter when idle or on tick
        baud_cnt <= '0;
    else
        baud_cnt <= baud_cnt + 1;
end

// ---------------------------------------------------------------------------
// Shift register and bit counter
// ---------------------------------------------------------------------------
// Frame: [start=0] [d0..d7] [stop=1]  — 10 bits total
// ---------------------------------------------------------------------------
reg [9:0] shift_reg;    // {stop, d7..d0, start}
reg [3:0] bit_cnt;      // counts 0..9

localparam IDLE = 2'b00;
localparam DATA = 2'b10;
reg [1:0] state;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state     <= IDLE;
        tx_ready  <= 1'b1;
        tx        <= 1'b1;    // idle high
        bit_cnt   <= '0;
        shift_reg <= '1;
    end else begin
        case (state)
            IDLE: begin
                tx       <= 1'b1;
                tx_ready <= 1'b1;
                if (tx_valid && tx_ready) begin
                    // Latch frame: start bit (0), 8 data bits, stop bit (1)
                    shift_reg <= {1'b1, tx_data, 1'b0};
                    bit_cnt   <= 4'd0;
                    tx_ready  <= 1'b0;
                    state     <= DATA;
                end
            end

            DATA: begin
                if (baud_tick) begin
                    tx        <= shift_reg[0];
                    shift_reg <= {1'b1, shift_reg[9:1]};  // shift right
                    if (bit_cnt == 4'd9) begin
                        state <= IDLE;
                    end else begin
                        bit_cnt <= bit_cnt + 1;
                    end
                end
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
`default_nettype wire
