`timescale 1ns/1ps

module cic_decimator #(
    parameter DECIM = 4
)(
    input  wire clk,
    input  wire rst,        
    input  wire signed [24:0] phase_residual, 
    
    output reg  [15:0] counter,
    output reg  do_update,
    output reg  signed [31:0] current_phi_error
);

    reg signed [31:0] acc1, acc2;
    reg signed [31:0] acc2_z1, diff1_z1;
    reg [1:0] decim_cnt;

    wire signed [31:0] diff1_now = acc2_next - acc2_z1;
    wire signed [31:0] diff2_now = diff1_now - diff1_z1;

    wire signed [31:0] acc1_next = acc1 + $signed({{7{phase_residual[24]}}, phase_residual});
    wire signed [31:0] acc2_next = acc2 + acc1_next;

    always @(posedge clk or posedge rst) begin 
        if (rst) begin                         
            acc1              <= 32'sd0;
            acc2              <= 32'sd0;
            acc2_z1           <= 32'sd0;
            diff1_z1          <= 32'sd0;
            decim_cnt         <= 2'd0;
            counter           <= 16'd0;
            do_update         <= 1'b0;
            current_phi_error <= 32'sd0;
        end else begin
            acc1 <= acc1_next;
            acc2 <= acc2_next;

            do_update <= 1'b0;

            if (decim_cnt == (DECIM - 1)) begin
                decim_cnt <= 2'd0;
                do_update <= 1'b1; 
              
                counter <= counter + 16'd1; 

                acc2_z1 <= acc2_next;
                diff1_z1 <= diff1_now;
                
                current_phi_error <= diff2_now >>> 4;
            end else begin
                decim_cnt <= decim_cnt + 2'd1;
            end
        end
    end
endmodule
