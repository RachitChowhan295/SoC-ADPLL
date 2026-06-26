`timescale 1ns/1ps

module adpll_top(
    input wire ref_clk,
    input wire rst,

    input wire [4:0] N_int,
    
    input wire [6:0] F_mod,
    input wire [6:0] K_mod,
    
    output wire signed [24:0] phase_residual,
    output wire signed [15:0] ctrl_word_out,
    output wire fb_clk
);

    
    wire signed [24:0] coarse_error;
    wire signed [5:0] fine_error; // 6-bit for Snapshot TDC (0 to 31)
    wire [15:0] dco_phases;       // 16-wire bus from the Ring DCO
    wire signed [15:0] ctrl_word;
    
    wire [4:0] N_div;
    wire [6:0] m1_reg;
    wire c2_prev;
    
    wire [15:0] counter; 
    wire do_update;
    wire signed [31:0] current_phi_error; 
    
    wire signed [31:0] kp;
    wire signed [31:0] ki;
    
    wire lock; 
    wire [4:0] dtc_code; 

    
    
    phase_detector pd_inst (
        .ref_clk(ref_clk), 
        .fb_clk(fb_clk), 
        .rst(rst), 
        .phase_error(coarse_error)
    );

    // New Snapshot TDC takes an instant picture of all 16 DCO phases
    snapshot_tdc tdc_inst (
        .clk_ref(ref_clk),
        .rst(rst),
        .dco_phases(dco_phases),
        .tdc_fine_out(fine_error)
    );

    // Scale coarse error (x32) to align with 5-bit TDC bins (16 stages = 32 edges)
    wire signed [24:0] scaled_coarse = coarse_error <<< 5;
    
    // The physical phase error based on the 32-edge Ring DCO
    wire signed [24:0] physical_error = scaled_coarse - fine_error;

    // ? RESTORE TO <<< 2! We must maintain exactly 128 virtual bins 
    // for the MASH fractional cancellation to work correctly.
    wire signed [24:0] total_combined_error = physical_error <<< 2;

    

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

    

    cic_decimator cic_inst(
        .clk(ref_clk),              
        .rst(rst),               
        .phase_residual(phase_residual), 
        .counter(counter),
        .do_update(do_update),      
        .current_phi_error(current_phi_error) 
    );
    
    gain_scheduler scheduler(
        .counter(counter),
        .kp(kp),
        .ki(ki)
    );
    
   
    pi_loop_filter #(
        .FRAC_BITS(15)
    ) filter (
        .clk(ref_clk),              
        .rst(rst),               
        .enable(do_update),         
        .error(current_phi_error),
        .kp(kp),
        .ki(ki),
        .ctrl_word(ctrl_word)       
    );
    
    assign ctrl_word_out = ctrl_word;
    
    
    wire signed [15:0] inverted_ctrl_word = -ctrl_word;

   
    // New 16-Stage Ring DCO
    wire ignored_fb_clk;
    ring_dco_model dco_inst(
        .rst(rst),
        .ctrl_word(inverted_ctrl_word), // Back to the inverted word
        .phases(dco_phases), 
        .fb_clk(ignored_fb_clk)     
    );

   
    wire dco_clk = dco_phases[0]; // Renamed from aligned_dco_clk back to dco_clk

    clock_devider clkd_inst(
        .N_div(N_div),
        .dco_clk(dco_clk),
        .rst(rst),
        .fb_clk(fb_clk)
    );
    
    lock_detector detector(
        .clk(ref_clk),              
        .rst(rst),              
        .error(current_phi_error),
        .lock(lock)        
    );

endmodule
