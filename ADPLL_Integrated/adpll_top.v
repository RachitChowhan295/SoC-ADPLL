module adpll_top(
    input ref_clk,
    input fb_clk,
    input rst,
    output signed [24:0]phase_error
);

phase_detector pd_inst(.ref_clk(ref_clk), .fb_clk(fb_clk), .rst(rst), .phase_error(phase_error));


endmodule