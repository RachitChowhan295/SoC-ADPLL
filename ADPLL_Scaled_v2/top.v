`timescale 1ns/1ps

module adpll_top(
    input wire ref_clk,
    input wire rst,
    input wire board_clk,

    input wire [5:0] N_int,
    input wire [6:0] F_mod,
    input wire [6:0] K_mod,
    
    output wire signed [24:0] phase_residual,
    output wire signed [15:0] ctrl_word_out,
    output wire fb_clk,
    output wire [5:0] N_div
);

    wire signed [24:0] coarse_error;
    wire signed [7:0] fine_error;
    wire signed [15:0] ctrl_word;
    wire dco_clk;
    
    // NEW: Wire to carry the math-based fractional phase from NCO to TDC
    wire [6:0] dco_frac_gray; 

    phase_detector pd_inst (
        .ref_clk(ref_clk), 
        .fb_clk(fb_clk), 
        .rst(rst), 
        .phase_error(coarse_error)
    );

    // ==========================================
    // UPDATED: The New Digital TDC
    // ==========================================
    digital_tdc tdc_inst (
        .clk_ref(ref_clk),
        .rst(rst),
        .dco_frac_gray(dco_frac_gray), // Receives Gray code from NCO
        .tdc_fine_out(fine_error)      // Outputs safe binary fractional error
    );

    // Scale coarse error (x128) to align with 7-bit TDC bins
    wire signed [24:0] scaled_coarse = coarse_error <<< 7;

    // FIX: Re-enabled the addition of fine_error so the TDC is actually used!
    wire signed [24:0] total_combined_error = scaled_coarse + fine_error;
    
    wire [4:0] dtc_code; 

    dtc_model dtc_inst (
        .clk(ref_clk),
        .rst(rst),
        .phase_error(total_combined_error), 
        .m1_reg(m1_reg),
        .F_mod(F_mod),
        .c2_prev(c2_prev),
        .phase_residual(phase_residual),    
        .dtc_code(dtc_code)
    );

    assign ctrl_word_out = ctrl_word;
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
    
    wire signed [31:0] kp;
    wire signed [31:0] ki;

    gain_scheduler scheduler(
        .clk(ref_clk),
        .rst(rst),
        .phase_error(phase_residual),
        .kp_sel(kp),
        .ki_sel(ki)
    );
    
    pi_loop_filter filter (
        .clk(ref_clk),              
        .rst(rst),               
        .enable(do_update),         
        .error(current_phi_error),
        .kp(kp),
        .ki(ki),
        .ctrl_word(ctrl_word)       
    );
    
    wire signed [15:0] inverted_ctrl_word = -ctrl_word;

    // ==========================================
    // UPDATED: NCO with Gray Code Output
    // ==========================================
    dco_nco dco_inst(
        .clk_fast(board_clk),
        .rst(rst),
        .ctrl_word(inverted_ctrl_word),
        .dco_clk(dco_clk),
        .dco_frac_gray(dco_frac_gray) // NEW: Sends mathematical fraction to TDC
    );
    
    wire lock;                    
    lock_detector detector(
        .clk(ref_clk),              
        .rst(rst),              
        .error(current_phi_error),
        .lock(lock)        
    );
    
    wire [6:0] m1_reg;
    wire c2_prev;
    
    mash_modulator mash_inst(
        .F_mod(F_mod), 
        .K_mod(K_mod), 
        .N_int(N_int), 
        .clk(ref_clk), 
        .rst(rst), 
        .N_div(N_div), 
        .m1_reg(m1_reg),
        .c2_prev(c2_prev)
    );

    clock_devider clkd_inst(
        .N_div(N_div),
        .dco_clk(dco_clk),
        .rst(rst),
        .fb_clk(fb_clk)
    );

endmodule