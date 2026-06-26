`timescale 1ps/1ps

module tb_dco_model;

reg rst;
reg signed [15:0] ctrl_word;

wire dco_clk;

dco_model dut(
    .rst(rst),
    .ctrl_word(ctrl_word),
    .dco_clk(dco_clk)
);

initial begin

    $dumpfile("dco_model.vcd");
    $dumpvars(0,tb_dco_model);

    rst = 1'b1;
    ctrl_word = 0;

    #1000;
    rst = 1'b0;

    #50000;
    ctrl_word = 2;

    #50000;
    ctrl_word = 5;

    #50000;
    ctrl_word = 10;

    #50000;
    ctrl_word = -2;

    #50000;

    $finish;

end

initial begin
    $monitor("time=%0t ctrl_word=%0d",
             $time, ctrl_word);
end

endmodule
