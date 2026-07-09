`timescale 1ns/1ps

module adpll_top(
    input wire ref_clk,
    input wire board_clk,      // NEW: raw board oscillator feeding the MMCM (e.g. 100 MHz)
    input wire rst,

    input wire[5:0]N_int,
    input wire [6:0] F_mod,
    input wire[6:0]K_mod,

    output wire signed [24:0] phase_residual,
    output wire signed [15:0] ctrl_word_out,
    output wire fb_clk,
    output wire [5:0]N_div
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

    // NOTE: sim_vernier_tdc below still uses simulation-only #delay
    // controls and is not synthesizable -- your adpll_tdc (CARRY4-based)
    // is the synthesizable replacement, not swapped in here since that's
    // a separate, self-contained change from the DCO work.
    sim_vernier_tdc tdc_inst (
        .clk_ref(ref_clk),
        .clk_dco(fb_clk),
        .rst(rst),
        .tdc_fine_out(fine_error)
    );

    wire signed [24:0] scaled_coarse = coarse_error <<< 7;
    wire signed [24:0] total_combined_error = scaled_coarse;
    
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

    // ── Clock source for the DCO ──────────────────────────────────
    // clk_fast MUST come from a hard clocking primitive: fabric logic
    // cannot manufacture an absolute frequency reference. Values below
    // (MULT=8.0, DIV0=4.0) turn a 100 MHz board_clk into 200 MHz, the
    // clk_fast used to derive FTW_FREE/KO_SCALE in dco_nco. Adjust
    // CLKIN1_PERIOD and the MULT/DIV pair to match your actual board
    // oscillator frequency.
    wire clk_fast, clkfb, mmcm_locked;

    MMCME2_BASE #(
        .CLKIN1_PERIOD    (10.0),   // 100 MHz board oscillator -> 10 ns period
        .CLKFBOUT_MULT_F  (8.0),
        .CLKOUT0_DIVIDE_F (4.0),    // 100 MHz * 8 / 4 = 200 MHz = clk_fast
        .DIVCLK_DIVIDE    (1)
    ) mmcm_dco_inst (
        .CLKIN1   (board_clk),
        .CLKFBIN  (clkfb),
        .CLKFBOUT (clkfb),
        .CLKOUT0  (clk_fast),
        .LOCKED   (mmcm_locked),
        .PWRDWN   (1'b0),
        .RST      (rst)
    );

    // ── DCO: synthesizable NCO, replaces the old behavioral dco_model ──
    dco_nco #(
        .ACC_WIDTH (32),
        .FTW_FREE  (32'd1174405120),   // f_free' = 54.6875 MHz @ clk_fast=200MHz
        .KO_SCALE  (32'sd16777216)     // KO_GAIN' scaled into FTW LSBs
    ) dco_inst (
        .clk_fast  (clk_fast),
        .rst       (rst || !mmcm_locked),
        .ctrl_word (inverted_ctrl_word),
        .dco_clk   (dco_clk)
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


module phase_detector(
    input ref_clk,
    input fb_clk,
    input rst,
    output reg signed [24:0]phase_error
);

reg [23:0] phase_ref;

always@(posedge ref_clk or posedge rst) begin
    if(rst)
        phase_ref <= 24'd0;
    else 
        phase_ref <= phase_ref + 24'd1;
end

reg[23:0] phase_fb_bin;
always@(posedge fb_clk or posedge rst) begin
    if(rst)
        phase_fb_bin <= 24'd0;
    else 
        phase_fb_bin <= phase_fb_bin + 24'd1;
end

wire [23:0]phase_fb_gray;
assign phase_fb_gray = (phase_fb_bin) ^ (phase_fb_bin >> 1);

reg [23:0]gray_sync1;
reg [23:0]gray_sync2;

always@(posedge ref_clk or posedge rst) begin
    if(rst) begin
        gray_sync1 <= 24'd0;
        gray_sync2 <= 24'd0;
    end
    else begin
        gray_sync1 <= phase_fb_gray;
        gray_sync2 <= gray_sync1;
    end
end

wire [23:0]phase_fb_bin_sync;
genvar i;
generate 
    assign phase_fb_bin_sync[23] = gray_sync2[23];
    for(i = 22; i>=0; i=i-1)
        assign phase_fb_bin_sync[i] = phase_fb_bin_sync[i+1] ^ gray_sync2[i];
endgenerate

always@(posedge ref_clk or posedge rst) begin
    if(rst)
        phase_error <= 25'sd0;
    else
        phase_error <= $signed({1'b0,phase_ref}) - $signed({1'b0,phase_fb_bin_sync});
end

endmodule
