module dtc_model #(
    parameter STEP_FS       = 5000,
    parameter BASE_DELAY_FS = 5000,
    parameter MAX_CODE      = 31
)(
    input clk_in,
    input rst_n,
    input [4:0] dtc_code,
    output reg clk_out
);

//Delay calculation
time delay_fs;

//Total delay
always @(*) begin
    delay_fs = BASE_DELAY_FS + (dtc_code * STEP_FS);
end

//Delayed clock output
always @(posedge clk_in or negedge clk_in or negedge rst_n) begin
    if(!rst_n)
        clk_out <= 1'b0;
    else
        clk_out <= #(delay_fs) clk_in;
end

endmodule
