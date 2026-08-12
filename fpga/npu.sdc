create_clock -name clk -period 9.5 [get_ports clk]
derive_pll_clocks
derive_clock_uncertainty