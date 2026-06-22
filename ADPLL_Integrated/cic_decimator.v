`timescale 1ns/1ps

// CIC Decimator including a counter and is used to send the do_update signal and current_phi error signal

module cic_decimator #(
    parameter DECIM = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire signed [24:0] phase_residual, 
    
    output reg  [15:0] counter,
    output reg  do_update,
    output reg  signed [31:0] current_phi_error
);

    // Accumulators and Differentiators
    reg signed [31:0] acc1, acc2;
    reg signed [31:0] acc2_z1, diff1_z1;
    reg [2:0] decim_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc1 <= 0;
            acc2 <= 0;
            acc2_z1 <= 0;
            diff1_z1 <= 0;
            decim_cnt <= 0;
            counter <= 0;       
            do_update <= 0;
            current_phi_error <= 0;
        end else begin
            acc1 <= acc1 + phase_residual;
            acc2 <= acc2 + acc1;

            if (decim_cnt == (DECIM - 1)) begin
                decim_cnt <= 0;
                do_update <= 1'b1; 
              
                counter <= counter + 1; 

                acc2_z1 <= acc2;
                diff1_z1 <= (acc2 - acc2_z1);
                
                current_phi_error <= ((acc2 - acc2_z1) - diff1_z1) >>> 4;
            end else begin
                decim_cnt <= decim_cnt + 1;
                do_update <= 1'b0;
            end
        end
    end
endmodule
