`timescale 1ps/1ps

module dco_model(
    input rst,
    input signed [15:0] ctrl_word,
    output reg dco_clk
);

parameter integer F_FREE_MHZ = 3500;
parameter integer KDCO_MHZ   = 50;

integer freq_mhz;
integer period_ps;
integer half_period_ps;

initial begin
    dco_clk = 1'b0;
end

always @(*) begin

    freq_mhz = F_FREE_MHZ + (ctrl_word * KDCO_MHZ);

    if(freq_mhz < 100)
        freq_mhz = 100;

    period_ps = 1000000 / freq_mhz;
    half_period_ps = period_ps / 2;

end

always begin

    if(rst) begin
        dco_clk = 1'b0;
        #100;
    end
    else begin
        #(half_period_ps)
        dco_clk = ~dco_clk;
    end

end

endmodule
