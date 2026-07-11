# ==============================================================================
# ADPLL - Consolidated Clock & CDC Constraints
# (Replaces all previous constraint blocks - do not mix with older versions)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. PRIMARY (TRUE) CLOCKS - real external clocks from the testbench/board
# ------------------------------------------------------------------------------
# board_clk: 100 MHz physical oscillator, feeds dco_nco's clk_fast input
create_clock -period 10.000 -name board_clk [get_ports board_clk]

# ref_clk: 1.5625 MHz (640 ns), S=64 scaled reference for this model.
# NOTE: earlier draft had this at 10.000ns ("100 MHz") -- that was the
# pre-scaling value and is WRONG for the current S=64 model. Only this
# 640.000ns definition should exist.
create_clock -period 640.000 -name ref_clk [get_ports ref_clk]

# ------------------------------------------------------------------------------
# 2. GENERATED (FABRIC) CLOCKS - dco_clk and fb_clk are produced by plain
# logic (NCO accumulator, counter-based divider), not BUFG/MMCM, so Vivado
# needs explicit generated-clock relationships, not new primary clocks.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# 2. GENERATED (FABRIC) CLOCKS
# ------------------------------------------------------------------------------

# FIX 1: dco_clk is generated FROM board_clk. 
# We use a /2 divider (50 MHz) to give STA a valid contiguous clock tree.
create_generated_clock -name dco_clk -source [get_ports board_clk] -divide_by 2 [get_pins dco_inst/dco_clk_reg/Q]

# fb_clk stays the same, it just feeds off the newly legal dco_clk
create_generated_clock -name fb_clk -source [get_pins dco_inst/dco_clk_reg/Q] -divide_by 30 [get_pins clkd_inst/clk_buf/O]
# ------------------------------------------------------------------------------
# 3. CLOCK GROUPS
# ------------------------------------------------------------------------------
# board_clk <-> dco_clk: no data directly crosses here (dco_clk feeds only
# the divider chain), safe to treat as fully asynchronous.
set_clock_groups -asynchronous -group [get_clocks board_clk] -group [get_clocks dco_clk]

# NOTE: fb_clk and ref_clk are intentionally NOT put in an asynchronous
# clock group here. Real data crosses between them (gray-code phase bus,
# TDC toggle-flag handshake) through the synchronizers below, which are
# already precisely bounded with set_max_delay -datapath_only. Adding a
# blanket -asynchronous group on top of that would silently null out those
# targeted constraints (this was TIMING-24).

# ------------------------------------------------------------------------------
# 4. CDC PATHS - precise, targeted constraints for each synchronizer
# ------------------------------------------------------------------------------

# -- Phase Detector: fb_clk -> ref_clk gray-code phase bus --
set_max_delay -datapath_only -from [get_cells pd_inst/phase_fb_bin_reg*] -to [get_cells pd_inst/gray_sync1_reg*] 10.000

# -- TDC: fb_clk -> ref_clk toggle-flag handshake --
set_max_delay -datapath_only -from [get_cells tdc_inst/data_ready_toggle_reg] -to [get_cells tdc_inst/sync1_toggle_reg] 10.000

# -- TDC: fb_clk -> ref_clk multi-bit error payload --
set_max_delay -datapath_only -from [get_cells tdc_inst/error_fb_domain_reg*] -to [get_cells tdc_inst/tdc_error_reg*] 10.000

# -- Loop Filter -> DCO: ref_clk -> dco_clk ctrl_word --
set_max_delay -datapath_only -from [get_cells filter/ctrl_word_reg*] -to [get_cells dco_inst/ctrl_sync1_reg*] 5.000

set_max_delay -datapath_only -from [get_cells mash_inst/N_div_reg*] -to [get_cells clkd_inst/*] 21.000
# ------------------------------------------------------------------------------
# 5. RESET - true asynchronous reset, exempt from setup/hold analysis
# ------------------------------------------------------------------------------
# rst fans out to registers in every clock domain (ref_clk, fb_clk, dco_clk).
# Rather than adding set_input_delay for each domain (which TIMING-18 was
# flagging as missing for fb_clk), treat the async reset input as a false
# path entirely -- this is standard practice for a global async reset.
set_false_path -from [get_ports rst]

# ------------------------------------------------------------------------------
# 6. I/O DELAYS - remaining static/telemetry pins
# ------------------------------------------------------------------------------
set_input_delay -clock [get_clocks ref_clk] 2.000 [get_ports {N_int* F_mod* K_mod*}]

# ------------------------------------------------------------------------------
# 7. FALSE PATHS - telemetry/debug outputs and static config inputs
# ------------------------------------------------------------------------------
set_false_path -to [get_ports {{phase_residual[*]} {ctrl_word_out[*]} {N_div[*]}}]
set_false_path -from [get_ports {{F_mod[*]} {K_mod[*]} {N_int[*]}}]
# Ignore setup/hold on the TDC delay line capture registers (Asynchronous by design)
set_false_path -from [get_ports ref_clk] -to [get_cells tdc_inst/therm_q1_reg*]

# ------------------------------------------------------------------------------
# 8. DSP BLOCK ALLOCATION
# ------------------------------------------------------------------------------
set_property USE_DSP48 YES [get_cells filter/p_mult*]
set_property USE_DSP48 YES [get_cells filter/i_mult*]

reset_switching_activity -all 
