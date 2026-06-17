`timescale 1ns/1ps

module cic_decimator(
    input clk,
    input reset,
    input signed [31:0] pd_out,
    input [15:0] counter,

    output reg do_update,
    output reg signed [31:0] current_phi_error
);

parameter DECIM = 4;

reg signed [63:0] acc1_reg;
reg signed [63:0] acc2_reg;

reg signed [63:0] acc2_z1;
reg signed [63:0] diff1_z1;

reg signed [63:0] diff1;
reg signed [63:0] diff2;

always @(posedge clk) begin

    if(reset) begin
        acc1_reg <= 0;
        acc2_reg <= 0;

        acc2_z1 <= 0;
        diff1_z1 <= 0;

        diff1 <= 0;
        diff2 <= 0;

        current_phi_error <= 0;
        do_update <= 0;
    end
    else begin

        acc1_reg <= acc1_reg + pd_out;
        acc2_reg <= acc2_reg + acc1_reg;

        do_update <= 0;

        if ((counter % DECIM) == (DECIM-1)) begin

            diff1 <= acc2_reg - acc2_z1;
            acc2_z1 <= acc2_reg;

            diff2 <= diff1 - diff1_z1;
            diff1_z1 <= diff1;

            current_phi_error <= diff2 >>> 4; // divide by 16

            do_update <= 1;
        end
    end
end

endmodule