# soc_padframe.sdc - PicoRV32 + 8x8 systolic array SoC, IHP SG13G2
set clk_period 10.0
create_clock -name clk -period $clk_period [get_ports clk_PAD]
set_clock_uncertainty -setup 0.25 [get_clocks clk]
set_clock_uncertainty -hold 0.10 [get_clocks clk]
set_clock_transition  0.15 [get_clocks clk]

# rst_n: asynchronous assert. SPI inputs (sclk/cs_n/mosi): 2-3 FF synchronizers,
# oversampled in the clk domain; SCK must be <= clk/10 (10 MHz at 100 MHz clk).
# uart_rx: unused. None of these are timed as synchronous inputs.
set_false_path -from [get_ports rst_n_PAD]
set_false_path -from [get_ports {input_PAD[*]}]

# Outputs are driven from flops (uart_tx, spi_miso); external sampling is slow
# (115200 baud / <=10 MHz SPI), 2 ns output budget is conservative.
set_output_delay 2.0 -clock clk [get_ports {output_PAD[*]}]
