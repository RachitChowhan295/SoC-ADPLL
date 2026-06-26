`timescale 1ns/1ps

module tb_dtc_model;

reg clk;
reg rst;

reg signed [24:0] phase_error;
reg [6:0] m1_reg;
reg [6:0] F_mod;
reg c2_prev;

wire signed [24:0] phase_residual;
wire [4:0] dtc_code;

dtc_model dut (
    .clk(clk),
    .rst(rst),
    .phase_error(phase_error),
    .m1_reg(m1_reg),
    .F_mod(F_mod),
    .c2_prev(c2_prev),
    .phase_residual(phase_residual),
    .dtc_code(dtc_code)
);

always #5 clk = ~clk;

initial begin
    $dumpfile("dtc_model.vcd");
    $dumpvars(0, tb_dtc_model);

    clk = 0;
    rst = 1;

    phase_error = 25'sd0;
    m1_reg = 7'd0;
    F_mod = 7'd0;
    c2_prev = 1'b0;

    #12;
    rst = 0;

    phase_error = 25'sd100;
    m1_reg = 7'd0;
    F_mod = 7'd10;
    c2_prev = 1'b0;
    #10;
    $display("time=%0t phase_error=%0d dtc_code=%0d phase_residual=%0d",
             $time, phase_error, dtc_code, phase_residual);

    phase_error = 25'sd100;
    m1_reg = 7'd3;
    F_mod = 7'd10;
    c2_prev = 1'b0;
    #10;
    $display("time=%0t phase_error=%0d dtc_code=%0d phase_residual=%0d",
             $time, phase_error, dtc_code, phase_residual);

    phase_error = 25'sd100;
    m1_reg = 7'd7;
    F_mod = 7'd10;
    c2_prev = 1'b1;
    #10;
    $display("time=%0t phase_error=%0d dtc_code=%0d phase_residual=%0d",
             $time, phase_error, dtc_code, phase_residual);

    phase_error = -25'sd60;
    m1_reg = 7'd9;
    F_mod = 7'd10;
    c2_prev = 1'b0;
    #10;
    $display("time=%0t phase_error=%0d dtc_code=%0d phase_residual=%0d",
             $time, phase_error, dtc_code, phase_residual);

    #20;
    $finish;
end

endmodule
