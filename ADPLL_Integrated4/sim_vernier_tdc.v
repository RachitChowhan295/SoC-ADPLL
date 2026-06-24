`timescale 1ns/1ps

module sim_vernier_tdc #(
    parameter STAGES = 64
)(
    input wire clk_ref,
    input wire clk_dco,
    input wire rst,
    output reg signed [7:0] tdc_fine_out  // 7-bit to hold 0..32
);

    wire [STAGES:0] ref_delayed;
    wire [STAGES:0] dco_delayed;
    reg  [STAGES-1:0] therm_code;

    assign ref_delayed[0] = clk_ref;
    assign dco_delayed[0] = clk_dco;

    genvar i;
    generate
        for (i = 0; i < STAGES; i = i + 1) begin : delay_chain
            assign #0.020 ref_delayed[i+1] = ref_delayed[i];
            assign #0.010 dco_delayed[i+1] = dco_delayed[i];

            // DCO edge samples REF — correct Vernier structure
            always @(posedge dco_delayed[i+1] or posedge rst) begin
                if (rst) therm_code[i] <= 1'b0;
                else     therm_code[i] <= ref_delayed[i+1];
            end
        end
    endgenerate

    integer j;

    // Count ones = number of stages where dco hasn't caught ref yet
    always @(*) begin
        tdc_fine_out = 8'sd0;
        for (j = 0; j < STAGES; j = j + 1)
            tdc_fine_out = tdc_fine_out + $signed({1'b0, therm_code[j]});
    end

endmodule