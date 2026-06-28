`timescale 1ns/1ps

module sim_vernier_tdc #(
    parameter STAGES = 32
)(
    input wire clk_ref,   
    input wire clk_dco,   
    input wire rst,
    output reg signed [5:0] tdc_fine_out 
);

    wire [STAGES:0] ref_delayed;
    wire [STAGES:0] dco_delayed;
    reg [STAGES-1:0] therm_code;

    assign ref_delayed[0] = clk_ref;
    assign dco_delayed[0] = clk_dco;

    genvar i;
    generate
        for (i = 0; i < STAGES; i = i + 1) begin : delay_chain
            assign #0.020 ref_delayed[i+1] = ref_delayed[i]; 
            assign #0.010 dco_delayed[i+1] = dco_delayed[i]; 

            always @(posedge ref_delayed[i+1] or posedge rst) begin
                if (rst) therm_code[i] <= 1'b0;
                else therm_code[i] <= dco_delayed[i+1];
            end
        end
    endgenerate

    // FIXED: Priority Encoder looping backwards to find the first '1'
    integer j;
    always @(*) begin
        tdc_fine_out = 6'sd0; 
        for (j = STAGES - 1; j >= 0; j = j - 1) begin
            if (therm_code[j] == 1'b1) begin
                tdc_fine_out = j; 
            end
        end
    end
endmodule
