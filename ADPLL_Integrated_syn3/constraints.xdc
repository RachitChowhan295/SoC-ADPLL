# ==============================================================================
# ADPLL - Consolidated Clock & CDC Constraints
# (Updated for S = 50)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. PRIMARY (TRUE) CLOCKS
# ------------------------------------------------------------------------------

# board_clk: 100 MHz physical oscillator
create_clock -period 10.000 -name board_clk [get_ports board_clk]

# ref_clk: 2 MHz (500 ns), S = 50 scaled reference
create_clock -period 500.000 -name ref_clk [get_ports ref_clk]

# ------------------------------------------------------------------------------
# 2. GENERATED (FABRIC) CLOCKS
# ------------------------------------------------------------------------------

# dco_clk generated from board_clk
create_generated_clock \
    -name dco_clk \
    -source [get_ports board_clk] \
    -divide_by 2 \
    [get_pins dco_inst/dco_clk_reg/Q]

# fb_clk generated from dco_clk
create_generated_clock \
    -name fb_clk \
    -source [get_pins dco_inst/dco_clk_reg/Q] \
    -divide_by 30 \
    [get_pins clkd_inst/clk_buf/O]

# ------------------------------------------------------------------------------
# 3. CLOCK GROUPS
# ------------------------------------------------------------------------------

set_clock_groups -asynchronous \
    -group [get_clocks board_clk] \
    -group [get_clocks dco_clk]

# ------------------------------------------------------------------------------
# 4. CDC PATHS
# ------------------------------------------------------------------------------

# Phase Detector: fb_clk -> ref_clk
set_max_delay -datapath_only \
    -from [get_cells pd_inst/phase_fb_bin_reg*] \
    -to   [get_cells pd_inst/gray_sync1_reg*] \
    10.000

# TDC toggle handshake
set_max_delay -datapath_only \
    -from [get_cells tdc_inst/data_ready_toggle_reg] \
    -to   [get_cells tdc_inst/sync1_toggle_reg] \
    10.000

# TDC payload crossing
set_max_delay -datapath_only \
    -from [get_cells tdc_inst/error_fb_domain_reg*] \
    -to   [get_cells tdc_inst/tdc_error_reg*] \
    10.000

# Loop Filter -> DCO
set_max_delay -datapath_only \
    -from [get_cells filter/ctrl_word_reg*] \
    -to   [get_cells dco_inst/ctrl_sync1_reg*] \
    5.000

# MASH -> Clock Divider
set_max_delay -datapath_only \
    -from [get_cells mash_inst/N_div_reg*] \
    -to   [get_cells clkd_inst/*] \
    21.000

# ------------------------------------------------------------------------------
# 5. RESET
# ------------------------------------------------------------------------------

set_false_path -from [get_ports rst]

# ------------------------------------------------------------------------------
# 6. I/O DELAYS
# ------------------------------------------------------------------------------

set_input_delay \
    -clock [get_clocks ref_clk] \
    2.000 \
    [get_ports {N_int* F_mod* K_mod*}]

# ------------------------------------------------------------------------------
# 7. FALSE PATHS
# ------------------------------------------------------------------------------

set_false_path \
    -to [get_ports {{phase_residual[*]} {ctrl_word_out[*]} {N_div[*]}}]

set_false_path \
    -from [get_ports {{F_mod[*]} {K_mod[*]} {N_int[*]}}]

set_false_path \
    -from [get_ports ref_clk] \
    -to [get_cells tdc_inst/therm_q1_reg*]

# ------------------------------------------------------------------------------
# 8. DSP BLOCK ALLOCATION
# ------------------------------------------------------------------------------

set_property USE_DSP48 YES [get_cells filter/p_mult*]
set_property USE_DSP48 YES [get_cells filter/i_mult*]

reset_switching_activity -all
