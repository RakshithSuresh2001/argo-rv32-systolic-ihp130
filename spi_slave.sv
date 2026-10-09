// =============================================================================
// spi_slave.sv — SPI Slave Controller for 8x8 Systolic Array
// Author: Rakshith Suresh
// Mode 0: CPOL=0, CPHA=0
// Commands:
//   0x01 = Load weights  → [0x01][row][w0..w7]
//   0x02 = Load acts     → [0x02][a0..a7]
//   0x03 = Read psums    → returns 32 bytes (8 cols x 4 bytes)
//   0x04 = Reset array
//   0x05 = Write ISRAM   → [0x05][addr_hi][addr_lo][d3][d2][d1][d0] (ignored while CPU runs)
//   0x06 = Run CPU       → release CPU reset
//   0x07 = Halt CPU      → hold CPU in reset (for reload)
// =============================================================================
module spi_slave #(
    parameter ROWS   = 8,
    parameter COLS   = 8,
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         spi_clk,
    input  wire                         spi_cs_n,
    input  wire                         spi_mosi,
    output wire                          spi_miso,
    output reg                          weight_load,
    output reg  [2:0]                   weight_row,
    output reg  [COLS*DATA_W-1:0]       weight_data_flat,
    output reg  [ROWS*DATA_W-1:0]       act_in_flat,
    output reg                          array_rst_n,
    input  wire [COLS*ACC_W-1:0]        psum_out_flat,
    output reg                          busy,
    // Boot loader
    output reg                          boot_we,
    output reg  [9:0]                   boot_addr,
    output reg  [31:0]                  boot_wdata,
    output reg                          cpu_run
);

// -------------------------------------------------------------------------
// Synchronizers
// -------------------------------------------------------------------------
reg [2:0] sclk_sync;
reg [1:0] cs_sync;
reg [1:0] mosi_sync;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sclk_sync <= 3'b0;
        cs_sync   <= 2'b11;
        mosi_sync <= 2'b0;
    end else begin
        sclk_sync <= {sclk_sync[1:0], spi_clk};
        cs_sync   <= {cs_sync[0],     spi_cs_n};
        mosi_sync <= {mosi_sync[0],   spi_mosi};
    end
end

wire sclk_rise = (sclk_sync[2:1] == 2'b01);
wire sclk_fall = (sclk_sync[2:1] == 2'b10);
wire cs_active = ~cs_sync[1];
wire mosi_d    = mosi_sync[1];

// -------------------------------------------------------------------------
// RX — shift in 8 bits per byte on rising edge
// -------------------------------------------------------------------------
reg [7:0] shift_rx;
reg [2:0] bit_cnt;
reg       byte_ready;
reg [7:0] rx_byte;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        shift_rx   <= 8'h0;
        bit_cnt    <= 3'd0;
        byte_ready <= 1'b0;
        rx_byte    <= 8'h0;
    end else if (!cs_active) begin
        shift_rx   <= 8'h0;
        bit_cnt    <= 3'd0;
        byte_ready <= 1'b0;
    end else begin
        byte_ready <= 1'b0;
        if (sclk_rise) begin
            shift_rx <= {shift_rx[6:0], mosi_d};
            if (bit_cnt == 3'd7) begin
                rx_byte    <= {shift_rx[6:0], mosi_d};
                byte_ready <= 1'b1;
                bit_cnt    <= 3'd0;
            end else begin
                bit_cnt <= bit_cnt + 3'd1;
            end
        end
    end
end

// -------------------------------------------------------------------------
// TX — output on falling edge (Mode 0: data changes on falling, sampled on rising)
// -------------------------------------------------------------------------
reg [7:0]   shift_tx;
reg [7:0]   tx_byte_idx;
reg [255:0] psum_latch;
reg         tx_active;
reg         tx_skip;   // swallow the falling edge that ends the byte during which TX was loaded

assign spi_miso = (cs_active && tx_active) ? shift_tx[7] : 1'b0;


// -------------------------------------------------------------------------
// FSM
// -------------------------------------------------------------------------
localparam S_IDLE   = 3'd0;
localparam S_WEIGHT = 3'd1;
localparam S_ACT    = 3'd2;
localparam S_PSUM   = 3'd3;
localparam S_BOOTW  = 3'd4;

reg [2:0] fsm_state;
reg [3:0] byte_idx;
reg [2:0] w_row_latch;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fsm_state        <= S_IDLE;
        byte_idx         <= 4'd0;
        weight_load      <= 1'b0;
        weight_row       <= 3'd0;
        weight_data_flat <= {(COLS*DATA_W){1'b0}};
        act_in_flat      <= {(ROWS*DATA_W){1'b0}};
        array_rst_n      <= 1'b1;
        busy             <= 1'b0;
        w_row_latch      <= 3'd0;
        tx_byte_idx      <= 8'd0;
        tx_active        <= 1'b0;
        shift_tx         <= 8'h0;
        tx_skip          <= 1'b0;
        boot_we          <= 1'b0;
        boot_addr        <= 10'd0;
        boot_wdata       <= 32'd0;
        cpu_run          <= 1'b0;
    end else begin
        weight_load <= 1'b0;
        array_rst_n <= 1'b1;
        boot_we     <= 1'b0;

        // Shift TX register on falling edge
        if (tx_active && sclk_fall) begin
            if (tx_skip) tx_skip  <= 1'b0;
            else         shift_tx <= {shift_tx[6:0], 1'b0};
        end

        if (!cs_active) begin
            fsm_state <= S_IDLE;
            byte_idx  <= 4'd0;
            busy      <= 1'b0;
            tx_active <= 1'b0;
        end else if (byte_ready) begin
            case (fsm_state)
                S_IDLE: begin
                    busy <= 1'b1;
                    case (rx_byte)
                        8'h01: begin fsm_state <= S_WEIGHT; byte_idx <= 4'd0; end
                        8'h02: begin fsm_state <= S_ACT;    byte_idx <= 4'd0; end
                        8'h03: begin
                            // Latch psums, load first byte into TX
                            psum_latch  <= psum_out_flat;
                            tx_byte_idx <= 8'd1;
                            shift_tx    <= psum_out_flat[255:248];
                            tx_skip     <= 1'b1;
                            tx_active   <= 1'b1;
                            fsm_state   <= S_PSUM;
                            byte_idx    <= 4'd0;
                        end
                        8'h04: begin
                            array_rst_n <= 1'b0;
                            fsm_state   <= S_IDLE;
                        end
                        8'h05: begin fsm_state <= S_BOOTW; byte_idx <= 4'd0; end
                        8'h06: begin cpu_run <= 1'b1; fsm_state <= S_IDLE; end
                        8'h07: begin cpu_run <= 1'b0; fsm_state <= S_IDLE; end
                        default: fsm_state <= S_IDLE;
                    endcase
                end

                S_WEIGHT: begin
                    if (byte_idx == 4'd0) begin
                        w_row_latch <= rx_byte[2:0];
                        byte_idx    <= byte_idx + 4'd1;
                    end else begin
                        weight_data_flat[(byte_idx-1)*DATA_W +: DATA_W] <= rx_byte;
                        if (byte_idx == 4'd8) begin
                            weight_load <= 1'b1;
                            weight_row  <= w_row_latch;
                            fsm_state   <= S_IDLE;
                            byte_idx    <= 4'd0;
                        end else begin
                            byte_idx <= byte_idx + 4'd1;
                        end
                    end
                end

                S_ACT: begin
                    act_in_flat[byte_idx*DATA_W +: DATA_W] <= rx_byte;
                    if (byte_idx == 4'd7) begin
                        fsm_state <= S_IDLE;
                        byte_idx  <= 4'd0;
                    end else begin
                        byte_idx <= byte_idx + 4'd1;
                    end
                end

                S_PSUM: begin
                    // Each incoming dummy byte → load next TX byte
                    if (tx_byte_idx <= 8'd31) begin
                        shift_tx    <= psum_latch[(255 - tx_byte_idx*8) -: 8];
                        tx_skip     <= 1'b1;
                        tx_byte_idx <= tx_byte_idx + 8'd1;
                    end else begin
                        fsm_state <= S_IDLE;
                        tx_active <= 1'b0;
                    end
                end

                S_BOOTW: begin
                    case (byte_idx)
                        4'd0:    boot_addr[9:8] <= rx_byte[1:0];
                        4'd1:    boot_addr[7:0] <= rx_byte;
                        default: boot_wdata     <= {boot_wdata[23:0], rx_byte};
                    endcase
                    if (byte_idx == 4'd5) begin
                        boot_we   <= ~cpu_run;
                        fsm_state <= S_IDLE;
                        byte_idx  <= 4'd0;
                    end else begin
                        byte_idx <= byte_idx + 4'd1;
                    end
                end

                default: fsm_state <= S_IDLE;
            endcase
        end
    end
end

endmodule
