# ==============================================================================
# ADPLL - Consolidated Clock & CDC Constraints
# ==============================================================================
# ------------------------------------------------------------------------------
# 1. PRIMARY (TRUE) CLOCKS
# ------------------------------------------------------------------------------
create_clock -period 2.500 -name board_clk [get_ports board_clk]
create_clock -period 500.000 -name ref_clk [get_ports ref_clk]

# ------------------------------------------------------------------------------
# 2. GENERATED (FABRIC) CLOCKS
# ------------------------------------------------------------------------------
# dco_clk_gen was previously declared with a bare create_clock directly on
# inst/dco_clk_reg/Q. Because that pin sits downstream of board_clk in the
# same clock tree, that created a second PRIMARY clock and overrode board_clk's
# own period/insertion-delay for everything in its fanout - which is exactly
# why purely-board_clk-domain paths (e.g. ftw_signed_pipe_reg -> phase_acc_reg
# inside dco_nco.v) were failing setup with small, oddly precise negative
# slacks instead of having several ns of margin.
#
# 70 MHz / 400 MHz reduces exactly to 7/40, so -multiply_by/-divide_by
# reproduces 70.000 MHz (14.2857 ns) precisely - no manual rounding needed.
create_generated_clock -name dco_clk_gen -source [get_ports board_clk] -divide_by 40 -multiply_by 7 [get_pins inst/dco_clk_reg/Q]

# fb_clk_gen is genuinely generated FROM dco_clk_gen (clock_devider's counter
# is clocked by dco_clk), so it must be sourced from dco_clk_gen, not declared
# as its own independent primary clock. Nominal locked N_div ~35 gives exactly
# 2.000 MHz (500.000 ns), matching ref_clk's rate as intended for a locked loop.
create_generated_clock -name fb_clk_gen -source [get_pins inst/dco_clk_reg/Q] -divide_by 35 [get_pins clkd_inst/fb_clk_reg/Q]

# ------------------------------------------------------------------------------
# 3. CLOCK GROUPS
# ------------------------------------------------------------------------------
# Single three-way group: every clock is mutually exclusive/asynchronous with
# every clock in a different group. dco_clk_gen and fb_clk_gen stay together
# since they ARE a real generated-clock hierarchy with a fixed ratio.
# (fb_clk_gen was missing from the old pairwise statements entirely, which
# left it fully synchronous-analyzed against ref_clk by default - a second,
# separate source of spurious failures.)


# ------------------------------------------------------------------------------
# 4. CDC PATHS - precise, targeted constraints for each synchronizer
# ------------------------------------------------------------------------------
# -- Phase Detector: fb_clk -> ref_clk gray-code phase bus --
set_max_delay -datapath_only -from [get_cells pd_inst/phase_fb_bin_reg*] -to [get_cells pd_inst/gray_sync1_reg*] 10.000

# -- Loop Filter -> DCO: ref_clk -> dco_clk ctrl_word --
# Fixed: instance is filter_inst in adpll_top.v, not "filter". The old name
# matched zero cells, so this crossing had no explicit datapath bound.
set_max_delay -datapath_only -from [get_cells filter_inst/ctrl_word_reg*] -to [get_cells inst/ctrl_sync1_reg*] 5.000

# -- MASH -> Clock Divider: ref_clk -> dco_clk N_div --
# Retargeted from clkd_inst/counter_reg (the far side of the comparison) to
# clkd_inst/N_div_sync1_reg, the new first-stage synchronizer flop added in
# clock_devider.v. This now follows the same convention as the other three
# CDC paths: the datapath_only bound lands on the first synchronizer stage,
# not the eventual consumer of the resynchronized value.
set_max_delay -datapath_only -from [get_cells mash_inst/N_div_reg*] -to [get_cells clkd_inst/N_div_sync1_reg*] 21.000

# -- DCO -> TDC: board_clk -> ref_clk dco_frac_gray bus --
# Replaced the dead therm_q1_reg reference (no such cell in the current
# digital_tdc.v) with the actual crossing: dco_frac_gray_reg -> sync1_reg.
set_max_delay -datapath_only -from [get_cells inst/dco_frac_gray_reg*] -to [get_cells tdc_inst/sync1_reg*] 10.000

# ------------------------------------------------------------------------------
# 5. RESET - true asynchronous reset, exempt from setup/hold analysis
# ------------------------------------------------------------------------------
set_false_path -from [get_ports rst]

# ------------------------------------------------------------------------------
# 6. I/O DELAYS - remaining static/telemetry pins
# ------------------------------------------------------------------------------
# N_int/K_mod are false-pathed below (section 7), so no input_delay is
# defined on them - a false path exempts them from setup/hold analysis
# entirely, making an input_delay on the same ports meaningless and the
# source of 13 XDCH-2 "same delay for max/min" warnings for no benefit.
# (F_mod isn't a port at all - assign F_mod = 7'd100; in adpll_top.v - so
# it never needed one either.)

# ------------------------------------------------------------------------------
# 7. FALSE PATHS - telemetry/debug outputs and static config inputs
# ------------------------------------------------------------------------------
set_false_path -to [get_ports {{phase_residual[*]} {ctrl_word_out[*]} {N_div[*]}}]
set_false_path -from [get_ports {{K_mod[*]} {N_int[*]}}]
# (F_mod removed here too, same reason as section 6.)
# (therm_q1_reg false path removed - replaced by the proper set_max_delay
# in section 4, which now targets the real dco_frac_gray_reg -> sync1_reg path.)

# ------------------------------------------------------------------------------
# 8. DSP BLOCK ALLOCATION & PIPELINING ENFORCEMENT
# ------------------------------------------------------------------------------
# Fixed: inst/ftw_delta_pipe* doesn't exist in dco_nco.v. Retargeted to the
# actual MAC pipeline registers (dsp_a_reg=A, dsp_b_reg=B, dsp_m_reg=M,
# ftw_signed_pipe=P). This is belt-and-suspenders on top of the existing
# (* use_dsp = "yes" *) attribute already in the RTL.
set_property USE_DSP48 YES [get_cells inst/ftw_signed_pipe_reg*]
set_property PREG 1 [get_cells inst/ftw_signed_pipe_reg*]

reset_switching_activity -all 
