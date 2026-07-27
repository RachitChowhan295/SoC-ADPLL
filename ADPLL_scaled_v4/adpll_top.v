`timescale 1ns/1fs

module adpll_top #(
    parameter integer REF_HZ    = 2_000_000,     // ref_clk frequency
    parameter integer BOARD_HZ  = 400_000_000,   // board_clk frequency (dco_nco's clk_fast)
    parameter [31:0]  FTW_FREE  = 32'd751619277, // must match dco_inst
    parameter signed [31:0] KO_SCALE = 32'sd4295 // must match dco_inst
)(
    input wire ref_clk,
    input wire rst,
    input wire board_clk,

    input wire[5:0]N_int,
    
    //input wire [6:0] m1_reg,
    
    input wire[6:0]K_mod,
    //input wire c2_prev,
    
    output wire signed [24:0] phase_residual,
    output wire signed [15:0] ctrl_word_out,
    output wire fb_clk,
    output wire [5:0]N_div
);

    wire signed [24:0] coarse_error;
    wire signed [7:0] fine_error;
    wire signed [15:0] ctrl_word;
    wire dco_clk;
    
    // NEW: Wire to route the mathematical fractional phase from NCO to Digital TDC
    wire [6:0] dco_frac_gray; 
    
    wire int_mode = (K_mod == 0)? 1'd1 : 1'd0;
    wire [6:0] F_mod;
    assign F_mod = 7'd100;
    
    // N_avg = N_int + K_mod/F_mod, in Q16.16
    wire signed [31:0] n_avg_q16 = (F_mod != 0)
        ? (($signed({1'b0,N_int}) <<< 16) + (($signed({1'b0,K_mod}) <<< 16) / $signed({1'b0,F_mod})))
        : ($signed({1'b0,N_int}) <<< 16);

    localparam signed [63:0] REF_SCALED = REF_HZ * 64'sd65536;   // elaboration-time constant

    wire signed [63:0] target_ftw   = (n_avg_q16 * REF_SCALED) / BOARD_HZ;
    wire signed [63:0] preload_calc = ($signed({32'd0, FTW_FREE}) - target_ftw) / KO_SCALE;
    wire signed [31:0] dyn_preload  =  32'd0;  //preload_calc[31:0];

    phase_detector pd_inst (
        .ref_clk(ref_clk), 
        .fb_clk(fb_clk), 
        .rst(rst), 
        .phase_error(coarse_error)
    );

    // ==========================================
    // UPDATED: Digital TDC Integration
    // ==========================================
    digital_tdc tdc_inst (
        .clk_ref(ref_clk),
        .rst(rst),
        .dco_frac_gray(dco_frac_gray), // Receives safe Gray code from NCO
        .tdc_fine_out(fine_error)      // Outputs binary fractional error
    );

    // Scale coarse error (x128) to align with 7-bit TDC bins
    wire signed [24:0] scaled_coarse = coarse_error <<< 7;

    // The digital fine_error is successfully added here to feed the DTC
    wire signed [24:0] total_combined_error = scaled_coarse + fine_error;
    
    wire [4:0] dtc_code; 
    wire signed [24:0]phase_residual_dtc;

    // ==========================================
    // DTC Model (Unchanged, accurately receiving total_combined_error)
    // ==========================================
    dtc_model dtc_inst (
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
    // m1_reg, F_mod and c2_prev will be connected from MASH module

    assign phase_residual = (int_mode)? total_combined_error : phase_residual_dtc;

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
    
    wire [4:0] current_kp_shift;
    wire [4:0] current_ki_shift;

    gain_scheduler #(
        .ERR_W(25),
        .SHIFT_W(5)
    ) scheduler_inst (
        .clk(ref_clk),                   
        .rst(rst),
        .phase_error(phase_residual),    
        .kp_shift_sel(current_kp_shift),
        .ki_shift_sel(current_ki_shift)
    );

    pi_loop_filter #(
        .ERR_W(25),
        .SHIFT_W(5)
    ) filter_inst (
        .clk(ref_clk),                   
        .rst(rst),
        .enable(do_update),              
        .error(phase_residual),
        .preload(dyn_preload),          
        .kp_shift(current_kp_shift),
        .ki_shift(current_ki_shift),
        .ctrl_word(ctrl_word)
    );
    
    wire signed [15:0] inverted_ctrl_word = -ctrl_word;

    // ==========================================
    // UPDATED: DCO NCO Integration
    // ==========================================
    dco_nco #(
    .FTW_FREE(FTW_FREE),
    .KO_SCALE(KO_SCALE)
    ) inst(
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