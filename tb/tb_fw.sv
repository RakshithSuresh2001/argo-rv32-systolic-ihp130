`timescale 1ns/1ps
module tb_fw;
  reg clk = 0, rst_n = 0;
  reg spi_clk = 0, spi_cs_n = 1, spi_mosi = 0, uart_rx = 1;
  wire spi_miso, uart_tx;
  always #5 clk = ~clk;
  soc_top dut (.clk(clk), .rst_n(rst_n), .uart_tx(uart_tx), .uart_rx(uart_rx),
               .spi_clk(spi_clk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi), .spi_miso(spi_miso));

  localparam SPI_HALF = 50;                    // 10 MHz SCK
  localparam real BIT_NS = 1.0e9/115200.0;

  task spi_byte(input [7:0] b); integer i; begin
    for (i = 7; i >= 0; i = i - 1) begin spi_mosi = b[i]; #SPI_HALF spi_clk = 1; #SPI_HALF spi_clk = 0; end
  end endtask
  task spi_frame_begin; begin spi_cs_n = 0; #(SPI_HALF*2); end endtask
  task spi_frame_end;   begin #(SPI_HALF*2); spi_cs_n = 1; #(SPI_HALF*4); end endtask
  task isram_write(input [9:0] a, input [31:0] d); begin
    spi_frame_begin;
    spi_byte(8'h05); spi_byte({6'b0, a[9:8]}); spi_byte(a[7:0]);
    spi_byte(d[31:24]); spi_byte(d[23:16]); spi_byte(d[15:8]); spi_byte(d[7:0]);
    spi_frame_end;
  end endtask

  reg [31:0] prog [0:1023];
  reg [8*256-1:0] hexfile;
  reg [8*64-1:0] expect_s = 0, line = 0;
  integer nwords = 0, k, tmo;

  reg [7:0] rx; integer b;
  initial forever begin
    @(negedge uart_tx);
    #(BIT_NS*1.5);
    for (b = 0; b < 8; b = b + 1) begin rx[b] = uart_tx; #(BIT_NS); end
    if (rx == 8'h0A) begin
      $display("[%0t] UART line: \"%0s\"", $time, line);
      if (line == expect_s) $display("PASS"); else $display("FAIL: expected \"%0s\"", expect_s);
      $finish;
    end else line = {line[8*63-1:0], rx};
  end

  initial begin
    if (!$value$plusargs("hex=%s", hexfile) || !$value$plusargs("words=%d", nwords)) begin
      $display("usage: +hex=<file> +words=<N> +expect=<line>"); $finish;
    end
    void'($value$plusargs("expect=%s", expect_s));
    $readmemh(hexfile, prog);
    #200 rst_n = 1;
    #500;
    for (k = 0; k < nwords; k = k + 1) isram_write(k[9:0], prog[k]);
    $display("[%0t] %0d words loaded over SPI, RUN", $time, nwords);
    spi_frame_begin; spi_byte(8'h06); spi_frame_end;
  end

  initial begin
    if (!$value$plusargs("timeout_us=%d", tmo)) tmo = 20000;
    #(tmo * 1000.0); $display("FAIL: timeout, partial line \"%0s\"", line); $finish;
  end
endmodule
