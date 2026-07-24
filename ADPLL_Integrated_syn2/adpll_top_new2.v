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
    
    // FRAC_BITS must be 16 here: gain_scheduler's KP_*/KI_* constants are
    // documented and derived as Q16.16 fixed point. Leaving this at the
    // module default (FRAC_BITS=24) silently adds an extra >>>8 to every
    // P and I term, shrinking the effective loop gain by 256x and
    // crippling lock/tracking performance.
    pi_loop_filter #(
        .FRAC_BITS(16)
    ) filter (
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

// ── clk_fast generation ─────────────────────────────────────────
// board_clk is the raw 100 MHz board oscillator. The DCO's phase
// accumulator toggles its MSB at f_out = (FTW/2^32)*clk_fast, so
// clk_fast must be well above 2x the highest frequency you ever need
// the DCO to produce, or the output *aliases* (folds back to a bogus
// lower frequency) instead of tracking the target. At S=50 the DCO
// must reach 60.2 MHz; with clk_fast = 100 MHz (Nyquist = 50 MHz) this
// is mathematically impossible and is exactly what was breaking lock.
// clk_fast = 300 MHz gives a max FTW fraction of ~0.34 even at full
// ctrl_word deflection -- comfortably clear of the 0.5 Nyquist wall.
`ifdef SYNTHESIS
    // Real hardware: MMCME2_BASE multiplies 100MHz board_clk -> 300MHz.
    // VCO = 100MHz * 9.0 / 1 = 900MHz (valid Artix-7 VCO range),
    // CLKOUT0 = 900MHz / 3.0 = 300MHz exactly.
    wire clk_fast_unbuf, clkfb, mmcm_locked;
    MMCME2_BASE #(
        .CLKIN1_PERIOD     (10.0),
        .CLKFBOUT_MULT_F   (9.0),
        .CLKOUT0_DIVIDE_F  (3.0),
        .DIVCLK_DIVIDE     (1),
        .STARTUP_WAIT      ("FALSE")
    ) mmcm_inst (
        .CLKIN1   (board_clk),
        .CLKFBIN  (clkfb),
        .CLKFBOUT (clkfb),
        .CLKOUT0  (clk_fast_unbuf),
        .PWRDWN   (1'b0),
        .RST      (rst),
        .LOCKED   (mmcm_locked)
    );
    BUFG clk_fast_bufg (.I(clk_fast_unbuf), .O(clk_fast));
`else
    // Simulation: idealized behavioral 300 MHz clk_fast. Icarus/generic
    // simulators don't carry the Xilinx UNISIM MMCME2_BASE model, so this
    // stands in for it -- functionally equivalent for RTL-level loop
    // verification, just without real MMCM lock-time/jitter behavior.
    reg clk_fast_behav = 1'b0;
    always #1.6667 clk_fast_behav = ~clk_fast_behav;  // 3.3333ns period = 300 MHz
    wire clk_fast = clk_fast_behav;
`endif

wire signed [15:0] inverted_ctrl_word;
assign inverted_ctrl_word = -ctrl_word;
// ── S=50 migration, clk_fast = 300 MHz ──────────────────────────
// target_new  = target_orig/S = 3010MHz/50 = 60.2 MHz
// KO_GAIN_new = KO_GAIN_orig/S = 64kHz/50 = 1.28 kHz/LSB
//   (KO_GAIN_orig = 64 kHz/LSB back-derived from the previously
//    verified S=64 top-level values; confirm against the golden
//    Python model if available)
// FTW_FREE = round((60.2e6  / 300e6) * 2^32) = 861856771
// KO_SCALE = round((1280.0  / 300e6) * 2^32) = 18325
dco_nco #(
    .ACC_WIDTH (32),
    .FTW_FREE(861856771),
    .KO_SCALE(18325)

) dco_inst(
        .clk_fast(clk_fast), // now the generated/behavioral 300MHz clock,
                              // NOT the raw 100MHz board_clk
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
