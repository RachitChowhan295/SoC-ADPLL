# 1. Define the Reference Clock (100 MHz -> 10.000 ns period)
create_clock -period 10.000 -name ref_clk -waveform {0.000 5.000} [get_ports ref_clk]

# 2. Define the Feedback Clock (100 MHz in steady-state)
create_clock -period 10.000 -name fb_clk -waveform {0.000 5.000} [get_ports fb_clk]

# 3. TDC Asynchronous Sampling Exception
# We are intentionally using fb_clk to sample the asynchronous dtc_out wave. 
# We must tell Vivado to ignore setup/hold times here, otherwise it will fail timing.
set_false_path -from [get_ports dtc_out] -to [get_cells -hierarchical *therm_q1_reg*]

# 4. Clock Domain Crossing (CDC) Exception
# We built a safe 3-stage synchronizer to cross from fb_clk to ref_clk. 
# We tell Vivado to ignore the asynchronous boundary between these two clock domains.
set_false_path -from [get_clocks fb_clk] -to [get_clocks ref_clk]
