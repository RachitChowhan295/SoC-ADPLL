`timescale 1ns/1ps

module pi_loop_filter #(
    parameter ERR_W      = 32,
    parameter GAIN_W     = 32,
    parameter ACCUM_W    = 32,
    parameter FRAC_BITS  = 16,
    parameter OUT_W      = 16,

    parameter signed [ACCUM_W-1:0] PRELOAD   = 32'sd0,

    parameter signed [ACCUM_W-1:0] INTEG_MAX = 32'sd2147483647,
    parameter signed [ACCUM_W-1:0] INTEG_MIN = -32'sd2147483647
)(
    input  wire clk,
    input  wire rst,       
    input  wire enable,

    input  wire signed [ERR_W-1:0] error,

    input  wire signed [GAIN_W-1:0] kp,
    input  wire signed [GAIN_W-1:0] ki,

    output reg signed [OUT_W-1:0] ctrl_word
);

    reg signed [ACCUM_W-1:0] integrator;
    reg signed [ACCUM_W-1:0] ctrl_word_q;

    wire signed [ERR_W+GAIN_W-1:0] p_mult;
    wire signed [ERR_W+GAIN_W-1:0] i_mult;

    assign p_mult = $signed(error) * $signed(kp);
    assign i_mult = $signed(error) * $signed(ki);

    wire signed [ACCUM_W-1:0] p_term;
    wire signed [ACCUM_W-1:0] integrator_next;
    wire signed [ACCUM_W-1:0] pi_out;

    assign p_term = p_mult >>> FRAC_BITS;
    assign integrator_next = integrator - i_mult;
    assign pi_out = (integrator_next >>> FRAC_BITS) - p_term;

    wire signed [ACCUM_W-1:0] alpha_term;
    wire signed [ACCUM_W-1:0] beta_term;
    wire signed [ACCUM_W-1:0] ctrl_next;

    assign alpha_term = ((pi_out <<< 2) + pi_out) >>> 3;
    assign beta_term  = ((ctrl_word_q <<< 1) + ctrl_word_q) >>> 3;
    assign ctrl_next = alpha_term + beta_term;

    always @(posedge clk or posedge rst) begin 
        if (rst) begin                         
            integrator  <= PRELOAD;
            ctrl_word_q <= PRELOAD;
            ctrl_word   <= PRELOAD[OUT_W-1:0];
        end
        else if (enable) begin              
            if (integrator_next > INTEG_MAX)
                integrator <= INTEG_MAX;
            else if (integrator_next < INTEG_MIN)
                integrator <= INTEG_MIN;
            else
                integrator <= integrator_next;

            ctrl_word_q <= ctrl_next;

            if (ctrl_next > 32767)
                ctrl_word <= 16'sd32767;
            else if (ctrl_next < -32768)
                ctrl_word <= -16'sd32768;
            else
                ctrl_word <= ctrl_next[OUT_W-1:0];
        end
    end

endmodule
