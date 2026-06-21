// Behavioral DCO model implemented as per ADPLL Python model

module dco_model(
    input clk,
    input rst,
    input signed [31:0] ctrl_word,
    output reg [31:0] freq_dco
);

parameter F_FREE_HZ  = 2500000000;
parameter KO_GAIN_HZ = 50000000;

always @(posedge clk or posedge rst) begin
    if(rst)
        freq_dco <= F_FREE_HZ;
    else
        freq_dco <= F_FREE_HZ + ctrl_word * KO_GAIN_HZ;
end

endmodule
