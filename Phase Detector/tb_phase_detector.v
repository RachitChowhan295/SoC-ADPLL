`timescale 1ns/1ps

module tb_phase_detector();

reg ref_clk;
reg fb_clk;
reg rst;

wire signed [24:0]phase_error;

phase_detector dut(.ref_clk(ref_clk), .fb_clk(fb_clk), .rst(rst), .phase_error(phase_error));

initial ref_clk = 1'b0;
always #5 ref_clk = ~ref_clk;

initial fb_clk = 1'b0;
always #3.5 fb_clk = ~fb_clk;

initial begin
    rst = 1'b1;
    #20
    rst = 1'b0;

    #2000

    $finish;
end

initial begin
    $monitor("t=%0t rst=%b phase_error=%0d", $time, rst, phase_error);
end

initial begin
    $dumpfile("test.vcd");
    $dumpvars(0,dut);
end


endmodule