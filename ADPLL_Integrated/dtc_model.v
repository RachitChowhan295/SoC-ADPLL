`timescale 1fs/1fs

module dtc_model #(
    parameter int STEP_FS       = 5000,
    parameter int BASE_DELAY_FS = 5000,
    parameter int MAX_CODE      = 31
)(
    input  logic clk_in,
    input  logic rst_n,
    input  logic [$clog2(MAX_CODE+1)-1:0] dtc_code,
    output logic clk_out
);

//Delay calculation
time delay_fs;

//Total delay
always_comb begin
    delay_fs = BASE_DELAY_FS + (time'(dtc_code) * STEP_FS);
end

//Delayed clock output
always @(posedge clk_in or negedge clk_in or negedge rst_n) begin
    if(!rst_n)
        clk_out <= 1'b0;
    else
        clk_out <= #(delay_fs) clk_in;
end

endmodule
