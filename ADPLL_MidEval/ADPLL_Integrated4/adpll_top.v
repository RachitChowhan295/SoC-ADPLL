`timescale 1ns/1ps

module adpll_top(
    input wire ref_clk,
    input wire rst,

    input wire[4:0]N_int,
    
    //input wire [6:0] m1_reg,
    input wire [6:0] F_mod,
    input wire[6:0]K_mod,
    //input wire c2_prev,
    
    output wire signed [24:0] phase_residual,
    output wire signed [15:0] ctrl_word_out,
    output wire fb_clk
);

    wire signed [24:0] coarse_error;
    wire signed [7:0] fine_error;
    wire signed [15:0] ctrl_word;
    wire dco_clk;
    

    phase_detector pd_inst (
        .ref_clk(ref_clk), 
        .fb_clk(fb_clk), 
        .rst(rst), 
        .phase_error(coarse_error)
    );
//tdc
    sim_vernier_tdc tdc_inst (
        .clk_ref(ref_clk),
        .clk_dco(fb_clk),
        .rst(rst),
        .tdc_fine_out(fine_error)
    );

    // Scale coarse error (x128) to align with 7-bit TDC bins
    wire signed [24:0] scaled_coarse = coarse_error <<< 7;
    //wire signed [24:0] scaled_coarse;
    //assign scaled_coarse = $signed(coarse_error) * $signed(25'd1000);

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
// m1_reg, F_mod and c2_prev will be connected from MASH module

   

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
        .counter(counter),
        .kp(kp),
        .ki(ki)
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
    dco_model dco_inst(
        .rst(rst),
        .ctrl_word(inverted_ctrl_word),
        .dco_clk(dco_clk)
    );
    
    wire lock;                    
    lock_detector detector(
        .clk(ref_clk),              
        .rst(rst),              
        .error(current_phi_error),
        .lock(lock)        
    );

    wire [4:0]N_div;
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
