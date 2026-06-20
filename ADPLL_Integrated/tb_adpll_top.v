`timescale 1ns/1ps

module tb_adpll_top();

    reg ref_clk;
    reg fb_clk;
    reg rst;

    wire signed [24:0]phase_error;

    adpll_top dut(.ref_clk(ref_clk), .fb_clk(fb_clk), .rst(rst), .phase_error(phase_error));

    initial begin 
        ref_clk = 1'b0;
        fb_clk = 1'b0;
    end

    always #5 ref_clk = ~ref_clk;

    always #4 fb_clk = ~fb_clk;

    initial begin 
        $monitor("t=%0t rst=%b phase_error=%0d", $time, rst, phase_error);
    end

    initial begin 

        $dumpfile("test.vcd");
        $dumpvars(0,dut);

        rst = 1'b1;
        #20
        rst = 1'b0;

        #2000

        $finish;
    end

endmodule