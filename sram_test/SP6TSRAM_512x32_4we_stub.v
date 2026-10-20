/// sta-blackbox
// Ports-only blackbox for the flow. Simulation model: SP6TSRAM_512x32_4we.v (Chips4Makers arra-mem).
(* blackbox *)
module SP6TSRAM_512x32_4we (a, d, we, clk, q);
  input  [8:0]  a;
  input  [31:0] d;
  input  [3:0]  we;
  input         clk;
  output [31:0] q;
endmodule
