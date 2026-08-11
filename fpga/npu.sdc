create_clock -name clk -period 10.05 [get_ports clk]
derive_pll_clocks
derive_clock_uncertainty