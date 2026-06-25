module dtc_model #(
    parameter MAX_CODE = 31
)(
    input clk,
    input rst,

    input signed [24:0] phase_error,
    input [6:0] m1_reg,
    input [6:0] F_mod,
    input c2_prev,

    output reg signed [24:0] phase_residual,
    output reg [4:0] dtc_code
);

reg signed [24:0] phase_fract;
reg signed [24:0] phase_residual_next;
reg [4:0] dtc_code_next;

integer temp_code;

always @(*) begin
    temp_code = 0;
    phase_fract = 25'sd0;
    phase_residual_next = phase_error;
    dtc_code_next = 5'd0;

    if (F_mod != 0) begin
        temp_code = (m1_reg * MAX_CODE) / F_mod;

        if (c2_prev && temp_code > 0)
            temp_code = temp_code - 1;

        if (temp_code < 0)
            temp_code = 0;
        else if (temp_code > MAX_CODE)
            temp_code = MAX_CODE;

        dtc_code_next = temp_code[4:0];
        phase_fract = $signed({20'd0, dtc_code_next});
        phase_residual_next = phase_error - phase_fract;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        phase_residual <= 25'sd0;
        dtc_code <= 5'd0;
    end
    else begin
        phase_residual <= phase_residual_next;
        dtc_code <= dtc_code_next;
    end
end

endmodule
