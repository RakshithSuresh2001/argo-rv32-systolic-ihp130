// =============================================================================
// soc_top.sv - PicoRV32 SoC top-level: CPU, systolic array accelerator,
// SPI slave, UART, and real IHP SRAM macros for instruction/data memory.
// Target : IHP SG13G2, via LibreLane
// Clock  : 100 MHz (10 ns period)
// Author : Rakshith Suresh
// =============================================================================
//
// Memory map
//   0x0000_0000 - 0x0000_0FFF  Instruction SRAM (4 KB, real IHP macro)
//   0x0001_0000 - 0x0001_0FFF  Data SRAM        (4 KB, real IHP macro)
//   0x1000_0000 - 0x1000_0FFF  Systolic array regs (AXI-Lite)
//   0x2000_0000 - 0x2000_0FFF  UART (TX only; RX unused)
//   SPI slave is NOT memory-mapped: it drives the array directly and
//   loads ISRAM / releases CPU reset (cmds 0x05/0x06/0x07).
//
// Unmapped accesses stall the CPU (mem_ready stays low), intentional.
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module soc_top (
    input  wire clk,
    input  wire rst_n,          // active-low async reset

    // UART (Phase 1 debug output)
    output wire uart_tx,
    input  wire uart_rx,
    // SPI (Phase 3)
    input  wire spi_clk,
    input  wire spi_cs_n,
    input  wire spi_mosi,
    output wire spi_miso
);

// reset synchronizer: assert asynchronously, release on a clock edge
reg [1:0] rst_sync;
always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) rst_sync <= 2'b00;
    else        rst_sync <= {rst_sync[0], 1'b1};
wire rst_ns = rst_sync[1];

// ---------------------------------------------------------------------------
// 1. PicoRV32 memory bus signals
// ---------------------------------------------------------------------------
wire        mem_valid;          // CPU: transaction pending
wire        mem_instr;          // CPU: 1=fetch, 0=load/store
reg         mem_ready;          // Slave: transaction accepted
wire [31:0] mem_addr;           // byte address
wire [31:0] mem_wdata;          // write data
wire [ 3:0] mem_wstrb;          // byte enables (0000 = read)
reg  [31:0] mem_rdata;          // read data back to CPU

// SPI boot loader: CPU held in reset until SPI cmd 0x06
wire        spi_boot_we;
wire [ 9:0] spi_boot_addr;
wire [31:0] spi_boot_wdata;
wire        spi_cpu_run;
wire        cpu_resetn = rst_ns & spi_cpu_run;

// Array / SPI nets (declared early: used by muxes before instances)
wire        sa_weight_load;
wire [ 2:0] sa_weight_row;
wire [63:0] sa_weight_data_flat;
wire [63:0] sa_act_in_flat;
wire [255:0] sa_psum_out_flat;
wire [31:0] sa_rdata;
wire        spi_weight_load;
wire [2:0]  spi_weight_row;
wire [63:0] spi_weight_data_flat;
wire [63:0] spi_act_in_flat;
wire        spi_array_rst_n;
wire        spi_busy;

// IRQ (16-bit, tied off in Phase 1)
wire sa_done;
wire [31:0] irq = {31'b0, sa_done};

// ---------------------------------------------------------------------------
// 2. PicoRV32 instantiation
// ---------------------------------------------------------------------------
picorv32 #(
    .ENABLE_MUL         (1),   // hardware multiply (M extension)
    .ENABLE_DIV         (0),   // skip divide — saves area, use SW div if needed
    .ENABLE_FAST_MUL    (0),   // multi-cycle multiply: the fast one misses 100 MHz in the slow corner
    .COMPRESSED_ISA  (0),   // RVC 16-bit instructions (C extension)
    .ENABLE_IRQ         (0),   // IRQ unused by firmware; removed for timing
    .ENABLE_IRQ_QREGS   (0),   // disable IRQ registers in regfile (saves 4 regs)
    .ENABLE_COUNTERS    (1),   // mcycle / minstret CSRs for profiling
    .TWO_STAGE_SHIFT    (1),   // 2-cycle shift instead of barrel shifter (saves area)
    .BARREL_SHIFTER     (0),   // disabled — consistent with TWO_STAGE_SHIFT
    .REGS_INIT_ZERO     (1),   // initialise all registers to 0 at reset
    .STACKADDR          (32'h0001_7FFC), // sp = top of data SRAM
    .PROGADDR_RESET     (32'h0000_0000), // PC starts at base of instruction SRAM
    .PROGADDR_IRQ       (32'h0000_0010)  // IRQ handler at offset 0x10
) u_cpu (
    .clk        (clk),
    .resetn     (cpu_resetn),
    .mem_valid  (mem_valid),
    .mem_instr  (mem_instr),
    .mem_ready  (mem_ready),
    .mem_addr   (mem_addr),
    .mem_wdata  (mem_wdata),
    .mem_wstrb  (mem_wstrb),
    .mem_rdata  (mem_rdata),
    .mem_la_read  (),          // look-ahead signals — unused
    .mem_la_write (),
    .mem_la_addr  (),
    .mem_la_wdata (),
    .irq        (irq),
    .eoi        ()             // end-of-interrupt — unused in Phase 1
);

// ---------------------------------------------------------------------------
// 3. Address decoder
// ---------------------------------------------------------------------------
// Combinational: asserts the correct chip-select based on mem_addr[31:16]
// and mem_instr. mem_ready is registered (1-cycle SRAM latency).
// ---------------------------------------------------------------------------
wire sel_isram;   // instruction SRAM
wire sel_dsram;   // data SRAM
wire sel_uart;    // UART peripheral
wire sel_sa;

assign sel_sa = mem_valid && !mem_instr && (mem_addr[31:8] == 24'h100000);
assign sel_isram = mem_valid && (mem_addr[31:16] == 16'h0000);
assign sel_dsram = mem_valid && ~mem_instr && (mem_addr[31:16] == 16'h0001);
assign sel_uart  = mem_valid && !mem_instr && (mem_addr[31:16] == 16'h2000);

// ---------------------------------------------------------------------------
// 4. Instruction SRAM (64 KB = 16K × 32-bit words)
// ---------------------------------------------------------------------------
// Modelled as a synchronous single-port SRAM.
// In OpenROAD flow, replace this with the ASAP7 SRAM macro.
// mem_instr=1 implies read-only — mem_wstrb will always be 4'b0000 here,
// so the write path is present but never exercised during correct operation.
// ---------------------------------------------------------------------------
localparam ISRAM_DEPTH   = 1024;  // 4 KB / 4 bytes per word (real IHP SRAM macro)
localparam ISRAM_ADDR_W  = 10;

wire        isram_ready;
wire [31:0] isram_rdata;

wire                    isram_valid = spi_cpu_run ? sel_isram                   : spi_boot_we;
wire [ISRAM_ADDR_W-1:0] isram_addr  = spi_cpu_run ? mem_addr[ISRAM_ADDR_W+1:2] : spi_boot_addr;
wire [31:0]             isram_wdata = spi_cpu_run ? mem_wdata                   : spi_boot_wdata;
wire [ 3:0]             isram_wstrb = spi_cpu_run ? mem_wstrb                   : 4'b1111;

sram_word_ctrl #(.ADDR_W(ISRAM_ADDR_W)) u_isram (
    .clk   (clk),
    .rst_n (rst_ns),
    .valid (isram_valid),
    .addr  (isram_addr),
    .wdata (isram_wdata),
    .wstrb (isram_wstrb),
    .ready (isram_ready),
    .rdata (isram_rdata)
);

// ---------------------------------------------------------------------------
// 5. Data SRAM (32 KB = 8K × 32-bit words)
// ---------------------------------------------------------------------------
localparam DSRAM_DEPTH   = 1024;  // 4 KB / 4 bytes per word (real IHP SRAM macro)
localparam DSRAM_ADDR_W  = 10;

wire        dsram_ready;
wire [31:0] dsram_rdata;

sram_word_ctrl #(.ADDR_W(DSRAM_ADDR_W)) u_dsram (
    .clk   (clk),
    .rst_n (rst_ns),
    .valid (sel_dsram),
    .addr  (mem_addr[DSRAM_ADDR_W+1:2]),
    .wdata (mem_wdata),
    .wstrb (mem_wstrb),
    .ready (dsram_ready),
    .rdata (dsram_rdata)
);

// ---------------------------------------------------------------------------
// 6. UART (Phase 1 stub — enough to emit bytes, full driver in Phase 2)
// ---------------------------------------------------------------------------
wire        uart_tx_valid;
wire [7:0]  uart_tx_data;
wire        uart_tx_ready;
reg  [31:0] uart_rdata;

uart_tx #(
    .CLK_FREQ   (100_000_000),  // matches actual 100MHz (10ns) IHP clock target
    .BAUD_RATE  (115_200)
) u_uart (
    .clk        (clk),
    .rst_n      (rst_ns),
    .tx_valid   (uart_tx_valid),
    .tx_data    (uart_tx_data),
    .tx_ready   (uart_tx_ready),
    .tx         (uart_tx)
);

// CPU writes byte to 0x2000_0000 → UART TX
// CPU reads  0x2000_0000 → bit[0] = tx_ready (not full)
// Registered write pulse — one cycle wide, aligned with SRAM ready timing
reg sel_uart_r, sel_sa_r;
reg uart_tx_valid_r;
reg [7:0] uart_tx_data_r;

always_ff @(posedge clk or negedge rst_ns) begin
    if (!rst_ns) begin
        uart_tx_valid_r <= 1'b0;
        uart_tx_data_r  <= 8'b0;
    end else begin
        uart_tx_valid_r <= sel_uart && (mem_wstrb != 4'b0) && !sel_uart_r;
        uart_tx_data_r  <= mem_wdata[7:0];
    end
end

assign uart_tx_valid = uart_tx_valid_r;
assign uart_tx_data  = uart_tx_data_r;

always_ff @(posedge clk)
    uart_rdata <= {31'b0, uart_tx_ready};

// ---------------------------------------------------------------------------
// 7. mem_ready and mem_rdata mux
// ---------------------------------------------------------------------------
// All SRAMs have 1-cycle latency — ready comes one cycle after select.
// UART also responds in 1 cycle (TX fires immediately, read returns status).
// ---------------------------------------------------------------------------

always_ff @(posedge clk or negedge rst_ns) begin
    if (!rst_ns) begin
        sel_uart_r  <= 1'b0;
        sel_sa_r <= 1'b0;
    end else begin
        // one-cycle ready pulse: mem_valid is still high in the ready cycle,
        // so re-registering sel_* would fire a 2nd ready into the next xfer
        sel_uart_r  <= sel_uart && !sel_uart_r;
        sel_sa_r    <= sel_sa   && !sel_sa_r;
    end
end

// mem_ready: isram/dsram use sram_word_ctrl's real ready (multi-cycle, real
// macro access). uart/systolic-array keep the original 1-cycle-registered
// assumption (unchanged, out of scope for this integration).
always_comb begin
    mem_ready = isram_ready | dsram_ready | sel_uart_r | sel_sa_r;
end

// mem_rdata mux: output whichever slave responded
always_comb begin
    mem_rdata = 32'b0;
    if (isram_ready)      mem_rdata = isram_rdata;
    else if (dsram_ready) mem_rdata = dsram_rdata;
    else if (sel_uart_r)  mem_rdata = uart_rdata;
    else if (sel_sa_r)    mem_rdata = sa_rdata;
end

// ---------------------------------------------------------------------------
// 8. Unused output tie-off
wire _unused_uart_rx = uart_rx; // RX unused in Phase 1, referenced to avoid unused-input lint

// ---------------------------------------------------------------------------
// Systolic array + AXI-Lite wrapper
// ---------------------------------------------------------------------------
wire        sa_start, sa_soft_reset, sa_weight_we, sa_input_we;
wire [ 5:0] sa_weight_addr;
wire [ 7:0] sa_weight_data, sa_input_data;
wire [ 2:0] sa_input_addr, sa_output_addr;

// ---------------------------------------------------------------------------
// Systolic array + AXI-Lite wrapper
// ---------------------------------------------------------------------------

axilite_slave u_axilite (
    .clk              (clk),
    .rst_n            (rst_ns),
    .mem_valid        (mem_valid),
    .mem_addr         (mem_addr),
    .mem_wdata        (mem_wdata),
    .mem_wstrb        (mem_wstrb),
    .mem_ready        (),
    .mem_rdata        (sa_rdata),
    .weight_load      (sa_weight_load),
    .weight_row       (sa_weight_row),
    .weight_data_flat (sa_weight_data_flat),
    .act_in_flat      (sa_act_in_flat),
    .psum_out_flat    (sa_psum_out_flat)
);

// ---------------------------------------------------------------------------
// Mux: SPI takes priority while spi_busy (CS synchronized to clk) is high
// ---------------------------------------------------------------------------
wire        mux_weight_load      = !spi_busy ? sa_weight_load       : spi_weight_load;
wire [2:0]  mux_weight_row       = !spi_busy ? sa_weight_row        : spi_weight_row;
wire [63:0] mux_weight_data_flat = !spi_busy ? sa_weight_data_flat  : spi_weight_data_flat;
wire [63:0] mux_act_in_flat      = !spi_busy ? sa_act_in_flat       : spi_act_in_flat;
// systolic array reset, registered so the mux output cannot glitch the async reset
reg         mux_rst_n;
always_ff @(posedge clk or negedge rst_ns)
    if (!rst_ns) mux_rst_n <= 1'b0;
    else         mux_rst_n <= !spi_busy ? 1'b1 : spi_array_rst_n;

systolic_array u_sa (
    .clk              (clk),
    .rst_n            (mux_rst_n),
    .weight_load      (mux_weight_load),
    .weight_row       (mux_weight_row),
    .weight_data_flat (mux_weight_data_flat),
    .act_in_flat      (mux_act_in_flat),
    .psum_out_flat    (sa_psum_out_flat),
    .done             (sa_done)
);

// ---------------------------------------------------------------------------
// 9. SPI Slave (Phase 3) — direct access to systolic array
// ---------------------------------------------------------------------------

spi_slave #(
    .ROWS   (8),
    .COLS   (8),
    .DATA_W (8),
    .ACC_W  (32)
) u_spi (
    .clk             (clk),
    .rst_n           (rst_ns),
    .spi_clk         (spi_clk),
    .spi_cs_n        (spi_cs_n),
    .spi_mosi        (spi_mosi),
    .spi_miso        (spi_miso),
    .weight_load     (spi_weight_load),
    .weight_row      (spi_weight_row),
    .weight_data_flat(spi_weight_data_flat),
    .act_in_flat     (spi_act_in_flat),
    .array_rst_n     (spi_array_rst_n),
    .psum_out_flat   (sa_psum_out_flat),
    .busy            (spi_busy),
    .boot_we         (spi_boot_we),
    .boot_addr       (spi_boot_addr),
    .boot_wdata      (spi_boot_wdata),
    .cpu_run         (spi_cpu_run)
);

endmodule
`default_nettype wire
