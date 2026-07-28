`timescale 1ns/1ps

module adpll_top #(
    parameter integer REF_HZ    = 2_000_000,     
    parameter integer BOARD_HZ  = 400_000_000,   
    parameter [31:0]  FTW_FREE  = 32'd751619277, 
    parameter signed [31:0] KO_SCALE = 32'sd4295 
)(
    input wire ref_clk,
    input wire rst,
    input wire board_clk,
    input wire[5:0]N_int,
    input wire[6:0]K_mod,
    
    output wire signed [24:0] phase_residual,
    output wire signed [15:0] ctrl_word_out,
    output wire fb_clk,
    output wire [5:0]N_div
);

    wire signed [24:0] coarse_error;
    wire signed [7:0] fine_error;
    wire dco_clk;
    wire [6:0] dco_frac_gray; 
    
    wire int_mode = (K_mod == 0)? 1'd1 : 1'd0;
    wire [6:0] F_mod;
    assign F_mod = 7'd100;

    // ==========================================
    // 1. True Counter-Based FLL (Fast Acquisition)
    // ==========================================
    wire fll_locked;
    wire signed [15:0] fll_ctrl;
    
    direct_fll fast_fll_inst (
        .ref_clk(ref_clk),
        .dco_clk(dco_clk),
        .rst(rst),
        .N_int(N_int),     
        .K_mod(K_mod),     
        .F_mod(F_mod),     
        .fll_ctrl(fll_ctrl),
        .fll_locked(fll_locked)
    );

    // ==========================================
    // 2. Standard Phase Tracking (Runs after FLL)
    // ==========================================
    phase_detector pd_inst (
        .ref_clk(ref_clk), 
        .fb_clk(fb_clk), 
        .rst(rst), 
        .phase_error(coarse_error)
    );

    digital_tdc tdc_inst (
        .clk_ref(ref_clk),
        .rst(rst),
        .dco_frac_gray(dco_frac_gray), 
        .tdc_fine_out(fine_error)      
    );

    wire signed [24:0] scaled_coarse = coarse_error <<< 7;
    wire signed [24:0] total_combined_error = scaled_coarse + fine_error;
    
    wire [4:0] dtc_code; 
    wire signed [24:0]phase_residual_dtc;
    wire [6:0] m1_reg;
    wire c2_prev;

    dtc_model dtc_inst_mod (
        .clk(ref_clk),
        .rst(rst),
        .en(~int_mode),
        .phase_error(total_combined_error), 
        .m1_reg(m1_reg),
        .F_mod(F_mod),
        .c2_prev(c2_prev),
        .phase_residual(phase_residual_dtc),    
        .dtc_code(dtc_code)
    );

    assign phase_residual = (int_mode)? total_combined_error : phase_residual_dtc;
    
    wire [15:0] counter; 
    wire do_update;
    wire signed [31:0] current_phi_error; 

    cic_decimator cic_inst(
        .clk(ref_clk),              
        .rst(rst),               
        .phase_residual(phase_residual), 
        .counter(counter),
        .do_update(do_update),      
        .current_phi_error(current_phi_error) 
    );
    
    wire [4:0] current_kp_shift;
    wire [4:0] current_ki_shift;

    gain_scheduler #(
        .ERR_W(25),
        .SHIFT_W(5)
    ) scheduler_inst (
        .clk(ref_clk),                   
        .rst(rst),
        .phase_error(current_phi_error[24:0]),    
        .kp_shift_sel(current_kp_shift),
        .ki_shift_sel(current_ki_shift)
    );

    wire signed [15:0] pll_ctrl;
    
    // Hold PLL Integrator at 0 until the FLL is completely locked
    wire pll_enable = do_update & fll_locked;

    pi_loop_filter #(
        .ERR_W(25),
        .SHIFT_W(5)
    ) filter_inst (
        .clk(ref_clk),                   
        .rst(rst),
        .enable(pll_enable),              
        .error(current_phi_error[24:0]),       
        .kp_shift(current_kp_shift),
        .ki_shift(current_ki_shift),
        .ctrl_word(pll_ctrl)
    );
    
    // ==========================================
    // 3. Final Summation & DCO
    // ==========================================
    // The FLL provides the baseline coarse word. The PLL adds fine adjustments.
    wire signed [15:0] final_ctrl_word = fll_locked ? (fll_ctrl + pll_ctrl) : fll_ctrl;
    
    assign ctrl_word_out = final_ctrl_word;
    wire signed [15:0] inverted_ctrl_word = -final_ctrl_word;

    dco_nco #(
        .FTW_FREE(FTW_FREE),
        .KO_SCALE(KO_SCALE)
    ) inst(
        .clk_fast(board_clk),
        .rst(rst),
        .ctrl_word(inverted_ctrl_word),
        .dco_clk(dco_clk),
        .dco_frac_gray(dco_frac_gray) 
    );
    
    wire [5:0]N_div_mash;
    
    mash_modulator mash_inst(
        .F_mod(F_mod), 
        .K_mod(K_mod), 
        .N_int(N_int), 
        .clk(ref_clk), 
        .rst(rst), 
        .en(~int_mode),
        .N_div(N_div_mash), 
        .m1_reg(m1_reg),
        .c2_prev(c2_prev)
    );

    assign N_div = (int_mode)? N_int: N_div_mash;

    clock_devider clkd_inst(
        .N_div(N_div),
        .dco_clk(dco_clk),
        .rst(rst),
        .fb_clk(fb_clk)
    );

endmodule