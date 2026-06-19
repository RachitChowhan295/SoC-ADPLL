`timescale 1ns/1ps

module tb_mash_modulator;
    reg clk;
    reg rst;
    reg [6:0]F_mod;
    reg [6:0]K_mod;
    reg [4:0]N_int;

    wire [4:0]N_div;
    wire [6:0]m1_reg;

    mash_modulator dut(.clk(clk), .rst(rst), .F_mod(F_mod), .K_mod(K_mod), .N_int(N_int), .N_div(N_div), .m1_reg(m1_reg));

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin 
        rst = 1'b1;
        F_mod = 7'd10;
        K_mod = 7'd1;
        N_int = 5'd8;

        #20
        rst = 1'b0;

        #3000

        $finish;
    end

    initial begin
        $monitor("t=%0t rst=%b F_mod=%0d K_mod=%0d N_int=%0d | N_div=%0d m1_reg=%0d",
                 $time, rst, F_mod, K_mod, N_int, N_div, m1_reg);
    end

    initial begin 
        $dumpfile("test.vcd");
        $dumpvars(0,dut);
    end

endmodule