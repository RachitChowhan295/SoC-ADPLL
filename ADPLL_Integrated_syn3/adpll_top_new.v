`timescale 1ns/1ps

module adpll_top(
    input wire ref_clk,
    input wire board_clk, // <--- ADD THIS LINE
    input wire rst,

    input wire[5:0]N_int,
    input wire [6:0] F_mod,
    input wire[6:0]K_mod,
    
    output wire signed [24:0] phase_residual,
    output wire signed [15:0] ctrl_word_out,
    output wire fb_clk,
    output wire [5:0]N_div,
    output wire dco_clk_probe   // DEBUG PORT: exposes internal dco_clk for
                                // post-implementation timing sim measurement.
                                // Internal wires can be renamed/optimized away
                                // by synthesis; a real port cannot.
);

    wire signed [24:0] coarse_error;
    wire signed [7:0] fine_error;
    wire signed [15:0] ctrl_word;
    (* dont_touch = "true" *) wire dco_clk;
    assign dco_clk_probe = dco_clk;
    

    phase_detector pd_inst (
        .ref_clk(ref_clk), 
        .fb_clk(fb_clk), 
        .rst(rst), 
        .phase_error(coarse_error)
    );

    
//tdc
//====================================================
// Synthesizable FPGA TDC (CARRY4 Based)
//====================================================
wire                 tdc_valid;
wire [63:0]          therm_out;

    
wire [6:0] m1_reg;
wire c2_prev;
    
adpll_tdc #(
    .NUM_TAPS(64)
) tdc_inst (
    .dtc_out    (ref_clk),      // TODO: Later connect to DTC delayed output
    .fb_clk     (fb_clk),
    .ref_clk    (ref_clk),
    .rst_n      (~rst),
    .tdc_error  (fine_error),
    .valid      (tdc_valid),
    .therm_out  (therm_out)
);

    

    // Scale coarse error (x128) to align with 7-bit TDC bins
    wire signed [24:0] scaled_coarse = coarse_error <<< 7;
    //wire signed [24:0] scaled_coarse;
    //assign scaled_coarse = $signed(coarse_error) * $signed(25'd1000);

    //wire signed [24:0] total_combined_error = scaled_coarse + fine_error;
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
    
    //====================================================
// FPGA Synthesizable DCO (NCO Based)
//====================================================

wire clk_fast;      // Fast FPGA clock from MMCM (parameter to be finalized)
wire signed [15:0] inverted_ctrl_word;
assign inverted_ctrl_word = -ctrl_word;
dco_nco #(
    .ACC_WIDTH (32),
    .FTW_FREE(2019976806),
    .KO_SCALE(42950)
    
) dco_inst(
        .clk_fast(board_clk), // <--- Connect the new fast clock here
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
