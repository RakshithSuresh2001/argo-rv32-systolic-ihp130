`timescale 1ns/1ps
module tb_spi;
  reg clk = 0, rst_n = 0;
  reg spi_clk = 0, spi_cs_n = 1, spi_mosi = 0, uart_rx = 1;
  wire spi_miso, uart_tx;
  always #5 clk = ~clk;
  soc_top dut (.clk(clk), .rst_n(rst_n), .uart_tx(uart_tx), .uart_rx(uart_rx),
               .spi_clk(spi_clk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi), .spi_miso(spi_miso));

  localparam SPI_HALF = 50;   // 10 MHz SCK, clk/10
  task spi_xfer(input [7:0] tx, output [7:0] rx); integer i; begin
    for (i = 7; i >= 0; i = i - 1) begin
      spi_mosi = tx[i]; #SPI_HALF spi_clk = 1; rx[i] = spi_miso; #SPI_HALF spi_clk = 0;
    end
  end endtask
  task cs_lo; begin spi_cs_n = 0; #(SPI_HALF*2); end endtask
  task cs_hi; begin #(SPI_HALF*2); spi_cs_n = 1; #(SPI_HALF*4); end endtask

  reg signed [7:0] W [0:7][0:7];
  reg signed [7:0] A [0:7];
  reg [7:0] dmy, b;
  reg [255:0] got;
  integer r, c, i, errs = 0, expv, gotv;

  task load_weights; begin
    for (r = 0; r < 8; r = r + 1) begin
      cs_lo; spi_xfer(8'h01, dmy); spi_xfer(r[7:0], dmy);
      for (c = 0; c < 8; c = c + 1) spi_xfer(W[r][c], dmy);
      cs_hi;
    end
  end endtask

  task run_check(input integer tag); begin
    cs_lo;                                          // acts + readback in ONE frame
    spi_xfer(8'h02, dmy);
    for (r = 0; r < 8; r = r + 1) spi_xfer(A[r], dmy);
    spi_xfer(8'h03, dmy);
    got = 0;
    for (i = 0; i < 32; i = i + 1) begin spi_xfer(8'h00, b); got = {got[247:0], b}; end
    cs_hi;
    for (c = 0; c < 8; c = c + 1) begin
      expv = 0;
      for (r = 0; r < 8; r = r + 1) expv = expv + W[r][c] * A[r];
      gotv = got[c*32 +: 32];
      if (gotv !== expv) begin
        errs = errs + 1;
        $display("t%0d c%0d got %08h exp %08h", tag, c, got[c*32 +: 32], expv);
      end
    end
  end endtask

  initial begin
    #200 rst_n = 1; #500;
    for (r = 0; r < 8; r = r + 1) for (c = 0; c < 8; c = c + 1) W[r][c] = (r*37 + c*11 + 5) & 8'hFF;
    load_weights;
    for (r = 0; r < 8; r = r + 1) A[r] = (r*53 + 17) & 8'hFF;   run_check(1);
    for (r = 0; r < 8; r = r + 1) A[r] = -128;                  run_check(2);
    for (r = 0; r < 8; r = r + 1) for (c = 0; c < 8; c = c + 1) W[r][c] = -128;
    load_weights;
    for (r = 0; r < 8; r = r + 1) A[r] = 127;                   run_check(3);
    cs_lo; spi_xfer(8'h04, dmy); cs_hi;                         // array reset clears weights
    for (r = 0; r < 8; r = r + 1) for (c = 0; c < 8; c = c + 1) W[r][c] = 0;
    for (r = 0; r < 8; r = r + 1) A[r] = (r*91 + 3) & 8'hFF;    run_check(4);
    if (errs == 0) $display("PASS"); else $display("FAIL: %0d mismatches", errs);
    $finish;
  end
  initial begin #20_000_000; $display("FAIL: timeout"); $finish; end
endmodule
