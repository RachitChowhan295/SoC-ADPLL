`timescale 1ns/1ps

module tb_adpll_top();

    reg  ref_clk;
    reg  rst;

    reg  [4:0] N_int;
    reg  [6:0] m1_reg;
    reg  [6:0] F_mod;
    reg  [6:0] K_mod;
    reg        c2_prev;

    wire signed [24:0] phase_residual;
    wire signed [15:0] ctrl_word_out;
    wire fb_clk;  

    // DUT
    adpll_top dut (
        .ref_clk(ref_clk),
        .fb_clk(fb_clk),
        .rst(rst),
        .N_int(N_int),
        .m1_reg(m1_reg),
        .F_mod(F_mod),
        .K_mod(K_mod),
        .c2_prev(c2_prev),
        .phase_residual(phase_residual),
        .ctrl_word_out(ctrl_word_out)
    );

    // 100 MHz reference clock equals 10 ns period
    initial ref_clk = 1'b0;
    always #5 ref_clk = ~ref_clk;

    initial begin
        $dumpfile("adpll_top.vcd");
        $dumpvars(0, tb_adpll_top);

        // Initial values
        rst     = 1'b1;
        N_int   = 5'd8;
        m1_reg  = 7'd0;
        F_mod   = 7'd64;
        K_mod   = 7'd8;
        c2_prev = 1'b0;

        // Hold reset for 20 cycles
        #20;
        rst = 1'b0;

        // Loop running
        #5000;

        $finish;
    end

    initial begin
        $display(" time | rst ref_clk fb_clk | phase_residual | ctrl_word_out");
        $monitor("%5t |  %b      %b      %b   | %12d   | %d",
                 $time, rst, ref_clk, fb_clk, phase_residual, ctrl_word_out);
    end

endmodule