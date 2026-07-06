module dco_model(
    input               clk,
    input               rst,
    input signed [15:0] ctrl_word,

    output reg [31:0]   freq_khz
);

parameter integer F_FREE_KHZ = 3500000;   // 3500 MHz
parameter integer KDCO_KHZ   = 20;        // 20 kHz per control word

reg signed [31:0] freq_calc;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        freq_khz <= F_FREE_KHZ;
    end
    else begin

        freq_calc = F_FREE_KHZ + (ctrl_word * KDCO_KHZ);

        // Frequency limit
        if (freq_calc < 100000)
            freq_khz <= 100000;
        else
            freq_khz <= freq_calc;

    end
end

endmodule
