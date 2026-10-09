`timescale 1ns/1ps
module tb_boot;
  reg clk = 0, rst_n = 0;
  reg spi_clk = 0, spi_cs_n = 1, spi_mosi = 0, uart_rx = 1;
  wire spi_miso, uart_tx;
  always #5 clk = ~clk;                       // 100 MHz

  soc_top dut (.clk(clk), .rst_n(rst_n), .uart_tx(uart_tx), .uart_rx(uart_rx),
               .spi_clk(spi_clk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi), .spi_miso(spi_miso));

  localparam SPI_HALF = 100;                  // 5 MHz SCK (20x oversampled)
  localparam real BIT_NS = 1.0e9/115200.0;

  task spi_byte(input [7:0] b); integer i; begin
    for (i = 7; i >= 0; i = i - 1) begin
      spi_mosi = b[i]; #SPI_HALF spi_clk = 1; #SPI_HALF spi_clk = 0;
    end
  end endtask
  task spi_frame_begin; begin spi_cs_n = 0; #(SPI_HALF*2); end endtask
  task spi_frame_end;   begin #(SPI_HALF*2); spi_cs_n = 1; #(SPI_HALF*4); end endtask

  task isram_write(input [9:0] a, input [31:0] d); begin
    spi_frame_begin;
    spi_byte(8'h05); spi_byte({6'b0, a[9:8]}); spi_byte(a[7:0]);
    spi_byte(d[31:24]); spi_byte(d[23:16]); spi_byte(d[15:8]); spi_byte(d[7:0]);
    spi_frame_end;
  end endtask

  reg [31:0] prog [0:16];
  integer k;
  initial begin
    prog[0]  = 32'h200002B7;                                   // lui  t0,0x20000
    prog[1]  = 32'h0002A383; prog[2]  = 32'h0013F393; prog[3]  = 32'hFE038CE3;
    prog[4]  = 32'h04F00313; prog[5]  = 32'h0062A023;          // 'O'
    prog[6]  = 32'h0002A383; prog[7]  = 32'h0013F393; prog[8]  = 32'hFE038CE3;
    prog[9]  = 32'h04B00313; prog[10] = 32'h0062A023;          // 'K'
    prog[11] = 32'h0002A383; prog[12] = 32'h0013F393; prog[13] = 32'hFE038CE3;
    prog[14] = 32'h00A00313; prog[15] = 32'h0062A023;          // '\n'
    prog[16] = 32'h0000006F;                                   // jal x0,0
  end

  // UART receiver
  reg [7:0] rx; reg [8*8-1:0] got = 0; integer nrx = 0, b;
  initial forever begin
    @(negedge uart_tx);
    #(BIT_NS*1.5);
    for (b = 0; b < 8; b = b + 1) begin rx[b] = uart_tx; #(BIT_NS); end
    got = {got[8*7-1:0], rx}; nrx = nrx + 1;
    $display("[%0t ns] UART rx: 0x%02h '%s'", $time, rx, (rx == 8'h0A) ? "\\n" : rx);
  end

  initial begin
    if ($test$plusargs("vcd")) begin $dumpfile("tb_boot.vcd"); $dumpvars(0, tb_boot); end
    #200 rst_n = 1;
    #500;
    if (dut.spi_cpu_run !== 1'b0) begin $display("FAIL: CPU not held in reset at power-up"); $finish; end
    for (k = 0; k < 17; k = k + 1) isram_write(k[9:0], prog[k]);
    $display("[%0t ns] program loaded over SPI, sending RUN", $time);
    spi_frame_begin; spi_byte(8'h06); spi_frame_end;
    #1_500_000;
    if (nrx == 3 && got[23:0] == {8'h4F, 8'h4B, 8'h0A})
      $display("PASS: booted over SPI, CPU printed \"OK\\n\"");
    else
      $display("FAIL: got %0d bytes, last three = %h", nrx, got[23:0]);
    $finish;
  end

  // bus trace: run vvp with +trace
  integer ntr = 0;
  always @(posedge clk)
    if ($test$plusargs("trace") && dut.mem_valid && dut.mem_ready && ntr < 60) begin
      ntr = ntr + 1;
      $display("[%0t] %s addr=%08h wstrb=%b wdata=%08h rdata=%08h", $time,
               dut.mem_instr ? "FETCH" : "DATA ", dut.mem_addr, dut.mem_wstrb, dut.mem_wdata, dut.mem_rdata);
    end
endmodule
