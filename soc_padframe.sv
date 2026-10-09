`default_nettype none

module soc_padframe (
    `ifdef USE_POWER_PINS
    inout wire IOVDD,
    inout wire IOVSS,
    inout wire VPWR,
    inout wire VGND,
    `endif
    inout wire       clk_PAD,
    inout wire       rst_n_PAD,
    inout wire [3:0] input_PAD,   // 0=uart_rx 1=spi_clk 2=spi_cs_n 3=spi_mosi
    inout wire [1:0] output_PAD   // 0=uart_tx 1=spi_miso
);

    logic       clk_PAD2CORE;
    logic       rst_n_PAD2CORE;
    logic [3:0] input_PAD2CORE;
    logic [1:0] output_CORE2PAD;

    (* keep *) sg13cmos5l_IOPadVdd   vdd_pad   (`ifdef USE_POWER_PINS .iovdd(IOVDD), .iovss(IOVSS), .vdd(VPWR), .vss(VGND) `endif );
    (* keep *) sg13cmos5l_IOPadVss   vss_pad   (`ifdef USE_POWER_PINS .iovdd(IOVDD), .iovss(IOVSS), .vdd(VPWR), .vss(VGND) `endif );
    (* keep *) sg13cmos5l_IOPadIOVdd iovdd_pad (`ifdef USE_POWER_PINS .iovdd(IOVDD), .iovss(IOVSS), .vdd(VPWR), .vss(VGND) `endif );
    (* keep *) sg13cmos5l_IOPadIOVss iovss_pad (`ifdef USE_POWER_PINS .iovdd(IOVDD), .iovss(IOVSS), .vdd(VPWR), .vss(VGND) `endif );

    sg13cmos5l_IOPadIn clk_pad (
        `ifdef USE_POWER_PINS .iovdd(IOVDD), .iovss(IOVSS), .vdd(VPWR), .vss(VGND), `endif
        .p2c(clk_PAD2CORE), .pad(clk_PAD)
    );

    sg13cmos5l_IOPadIn rst_n_pad (
        `ifdef USE_POWER_PINS .iovdd(IOVDD), .iovss(IOVSS), .vdd(VPWR), .vss(VGND), `endif
        .p2c(rst_n_PAD2CORE), .pad(rst_n_PAD)
    );

    generate
        for (genvar i = 0; i < 4; i++) begin : g_inputs
            sg13cmos5l_IOPadIn input_pad (
                `ifdef USE_POWER_PINS .iovdd(IOVDD), .iovss(IOVSS), .vdd(VPWR), .vss(VGND), `endif
                .p2c(input_PAD2CORE[i]), .pad(input_PAD[i])
            );
        end
    endgenerate

    generate
        for (genvar i = 0; i < 2; i++) begin : g_outputs
            sg13cmos5l_IOPadOut16mA output_pad (
                `ifdef USE_POWER_PINS .iovdd(IOVDD), .iovss(IOVSS), .vdd(VPWR), .vss(VGND), `endif
                .c2p(output_CORE2PAD[i]), .pad(output_PAD[i])
            );
        end
    endgenerate

    soc_top i_soc_top (
        .clk      (clk_PAD2CORE),
        .rst_n    (rst_n_PAD2CORE),
        .uart_rx  (input_PAD2CORE[0]),
        .spi_clk  (input_PAD2CORE[1]),
        .spi_cs_n (input_PAD2CORE[2]),
        .spi_mosi (input_PAD2CORE[3]),
        .uart_tx  (output_CORE2PAD[0]),
        .spi_miso (output_CORE2PAD[1])
    );

endmodule

`default_nettype wire
