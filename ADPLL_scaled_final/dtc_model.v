`timescale 1ns/1ps

module dtc_model #(
    parameter MAX_CODE = 31,
    parameter PHASE_FULL_SCALE = 128 
)(
    input clk,
    input rst,
    input en,

    input signed [24:0] phase_error,
    input [6:0] m1_reg,
    input c2_prev,

    output reg signed [24:0] phase_residual,
    output reg [4:0] dtc_code
);

localparam [6:0] F_mod = 7'd100;

localparam integer DIV100_SHIFT = 17;
localparam integer DIV100_MAGIC = 1311;  // for /F_mod  (F_mod = 100)
localparam integer DIV31_SHIFT  = 17;
localparam integer DIV31_MAGIC  = 4229;  // for /MAX_CODE (MAX_CODE = 31)

reg [7:0]  phase_fract;          // true range is 0..128 -> 8 bits (was signed [24:0])
reg signed [24:0] phase_residual_next;
reg [4:0] dtc_code_next;

reg [11:0] temp_code;             // true range is 0..~3987 -> 12 bits (was 32-bit integer)

always @(*) begin
    temp_code = 12'd0;
    phase_fract = 8'd0;
    phase_residual_next = phase_error;
    dtc_code_next = 5'd0;

    if(en) begin
        if (F_mod != 0) begin
            temp_code = (((m1_reg * MAX_CODE) + (F_mod >> 1)) * DIV100_MAGIC) >> DIV100_SHIFT;

            if (c2_prev && temp_code > 0)
                temp_code = temp_code - 1;

            // temp_code is built entirely from unsigned, non-negative operands,
            // so it can never go below 0 -- the original "< 0" clamp was dead code.
            if (temp_code > MAX_CODE)
                temp_code = MAX_CODE;

            dtc_code_next = temp_code[4:0];
            phase_fract = (((dtc_code_next * PHASE_FULL_SCALE) + (MAX_CODE >> 1)) * DIV31_MAGIC) >> DIV31_SHIFT;
            phase_residual_next = phase_error - $signed({17'b0, phase_fract});
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        phase_residual <= 25'sd0;
        dtc_code <= 5'd0;
    end
    else if(en) begin
        phase_residual <= phase_residual_next;
        dtc_code <= dtc_code_next;
    end
end

endmodule