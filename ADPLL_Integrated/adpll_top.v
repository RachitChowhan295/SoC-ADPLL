module adpll_top(
    input ref_clk,
    input fb_clk,
    input rst,
    output signed [24:0]phase_error
);

wire [6:0] m1_reg;
wire [6:0] F_mod;
wire c2_prev;

wire signed [24:0] phase_residual;
wire [4:0] dtc_code;

phase_detector pd_inst(.ref_clk(ref_clk), .fb_clk(fb_clk), .rst(rst), .phase_error(phase_error));

dtc_model dtc_inst(
    .clk(ref_clk),
    .rst(rst),
    .phase_error(phase_error),
    .m1_reg(m1_reg),
    .F_mod(F_mod),
    .c2_prev(c2_prev),
    .phase_residual(phase_residual),
    .dtc_code(dtc_code)
);
// phase_residual will be connected to TDC input
// m1_reg, F_mod and c2_prev will be connected from MASH module
endmodule
