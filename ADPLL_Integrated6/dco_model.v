`timescale 1ns/1fs

module dco_model(
    input rst,
    input signed [15:0] ctrl_word,
    output reg dco_clk
);

parameter integer F_FREE_MHZ = 3500;
parameter integer KDCO_kHZ   = 20;

real freq_mhz;
integer period_ps;
real half_period_ps;

initial begin
    dco_clk = 1'b0;
end

always @(*) begin

    freq_mhz = F_FREE_MHZ + (ctrl_word * KDCO_kHZ *0.001);

    if(freq_mhz < 100)
        freq_mhz = 100;

    half_period_ps = 500.0 / freq_mhz;

end

always begin

    if(rst) begin
        dco_clk = 1'b0;
        #1;
    end
    else begin
        #(half_period_ps)
        dco_clk = ~dco_clk;
    end

end

// Behavioral DCO model for ADPLL integration.
// Frequency is controlled by ctrl_word and follows the
// same concept used in the Python system model.

endmodule
