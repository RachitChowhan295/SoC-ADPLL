`timescale 1ns/1ps

module pi_loop_filter #(
    parameter ERR_W      = 25,  
    parameter SHIFT_W    = 5,   
    parameter ACCUM_W    = 20,  // Stays reduced to 20 bits
    parameter FRAC_BITS  = 16,
    parameter OUT_W      = 16,
    parameter signed [OUT_W-1:0] MAX_STEP = 16'sd4096,

    parameter signed [ACCUM_W-1:0] INTEG_MAX = 20'sd32767,
    parameter signed [ACCUM_W-1:0] INTEG_MIN = -20'sd32768
)(
    input  wire clk,
    input  wire rst,       
    input  wire enable,

    input  wire signed [ERR_W-1:0] error,

    input  wire [SHIFT_W-1:0] kp_shift,
    input  wire [SHIFT_W-1:0] ki_shift,

    output reg signed [OUT_W-1:0] ctrl_word
);

    reg signed [ACCUM_W+FRAC_BITS-1:0] integrator;
    reg signed [ACCUM_W-1:0] ctrl_word_q;

   // Sign-extend error
    wire signed [ACCUM_W+FRAC_BITS-1:0] error_ext;
    assign error_ext = $signed({{(ACCUM_W+FRAC_BITS-ERR_W){error[ERR_W-1]}}, error});

    // 1. Define combinational wires for the shifted values
    wire signed [ACCUM_W-1:0]           p_term_comb;
    wire signed [ACCUM_W+FRAC_BITS-1:0] i_term_comb;
    
    assign p_term_comb = $signed(error_ext[ACCUM_W-1:0]) >>> kp_shift;
    assign i_term_comb = $signed(error_ext <<< FRAC_BITS) >>> ki_shift;

    // 2. Define pipeline registers
    reg signed [ACCUM_W-1:0]           p_term;
    reg signed [ACCUM_W+FRAC_BITS-1:0] i_term;

    // 3. Clock the shifted values into the pipeline registers
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            p_term <= 0;
            i_term <= 0;
        end 
        else if (enable) begin 
            p_term <= p_term_comb;
            i_term <= i_term_comb;
        end
    end

    // 4. Use the pipelined terms for integration and output
    wire signed [ACCUM_W+FRAC_BITS-1:0] integrator_next;
    wire signed [ACCUM_W-1:0]           pi_out;

    assign integrator_next = integrator - i_term;
    assign pi_out = (integrator_next >>> FRAC_BITS) - p_term;

    wire signed [ACCUM_W-1:0] ctrl_next;
    assign ctrl_next = pi_out;
    
    // Slew-rate limiter logic
    wire signed [ACCUM_W-1:0] ctrl_delta = ctrl_next - ctrl_word_q;
    wire signed [ACCUM_W-1:0] ctrl_next_limited =
    (ctrl_delta >  $signed({{(ACCUM_W-OUT_W){1'b0}}, MAX_STEP}))  ? ctrl_word_q + MAX_STEP :
    (ctrl_delta < -$signed({{(ACCUM_W-OUT_W){1'b0}}, MAX_STEP}))  ? ctrl_word_q - MAX_STEP :
                                                                     ctrl_next;

    always @(posedge clk or posedge rst) begin 
        if (rst) begin                         
            integrator  <= $signed({{FRAC_BITS{1'b0}}});
            ctrl_word_q <= 0;
            ctrl_word   <= 0;
        end
        else if (enable) begin
        if (!((ctrl_word_q >= INTEG_MAX) && (i_term < 0)) &&
            !((ctrl_word_q <= INTEG_MIN) && (i_term > 0))) begin
            if (integrator_next > $signed({INTEG_MAX, {FRAC_BITS{1'b0}}}))
                integrator <= $signed({INTEG_MAX, {FRAC_BITS{1'b0}}});
            else if (integrator_next < $signed({INTEG_MIN, {FRAC_BITS{1'b0}}}))
                integrator <= $signed({INTEG_MIN, {FRAC_BITS{1'b0}}});
            else
                integrator <= integrator_next;
        end
            ctrl_word_q <= ctrl_next_limited;

            if (ctrl_next_limited > 32767)
                ctrl_word <= 16'sd32767;
            else if (ctrl_next_limited < -32768)
                ctrl_word <= -16'sd32768;
            else
                ctrl_word <= ctrl_next_limited[OUT_W-1:0];
        end
    end
endmodule