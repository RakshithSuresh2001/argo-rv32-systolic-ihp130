  // Debug probe used to root-cause the GLS multiply hang (WAIVERS.md W5).
  // Net names (_005099_, net1070, net2985) are specific to run sram_full6.
  // GLS probe: PCPI multiplier handshake, printed every cycle while pcpi_valid != 0
  wire       pm_v   = dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.pcpi_valid ;
  wire       pm_any = dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.instr_any_mul ;
  wire       pm_w   = dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.pcpi_wait ;
  wire       pm_wq  = dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.pcpi_wait_q ;
  wire       pm_mw  = dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.mul_waiting ;
  wire [6:0] pm_cnt = {dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.mul_counter[6] , dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.mul_counter[5] , dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.mul_counter[4] , dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.mul_counter[3] , dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.mul_counter[2] , dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.mul_counter[1] , dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.mul_counter[0] };
  wire pm_mulh = dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.instr_mulh ;
  wire       pm_fin = dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.mul_finish ;
  wire       pm_rdy = dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.pcpi_ready ;
  wire       pm_to  = dut.\i_soc_top.u_cpu.pcpi_timeout ;
  integer pn = 0;
  always @(posedge clk) if (pn < 120 && pm_v !== 1'b0) begin
    pn = pn + 1;
    $display("[%0t] PCPI v=%b any=%b wait=%b wq=%b mwait=%b cnt=%b fin=%b rdy=%b tmo=%b mulh=%b",
             $time, pm_v, pm_any, pm_w, pm_wq, pm_mw, pm_cnt, pm_fin, pm_rdy, pm_to, pm_mulh);
  end
  initial begin #1000; force dut._005099_ = 1'b0; #699000000; release dut._005099_; end
  always @(posedge clk) if (pn < 120 && pm_v !== 1'b0)
    $display("      n1070=%b a2=%b q0=%b d0=%b", dut.net1070, dut.net2985, dut.\i_soc_top.u_cpu.genblk1.genblk1.pcpi_mul.mul_counter[0] , dut._005099_);
