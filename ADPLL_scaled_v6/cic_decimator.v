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

    parameter LOCK_COUNT = 12'd2000;
    reg [11:0]stable_counter;
    wire [31:0] abs_error = current_phi_error[31] ? -current_phi_error : current_phi_error; 
    parameter [31:0] THRESHOLD  = 32'd1000;
    reg low_power_mode;
    reg toggle;

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
            low_power_mode    <= 1'd0;
            stable_counter    <= 12'd0;
            toggle             <= 1'd0;
        end else begin
            acc1 <= acc1_next;
            acc2 <= acc2_next;

            do_update <= 1'b0;

            if (decim_cnt == (DECIM - 1)) begin
                decim_cnt <= 2'd0;
                if(low_power_mode) begin
                    toggle <= ~toggle;
                    if(toggle)
                        do_update <= 1'b1;
                end else 
                    do_update <= 1'b1;

                
                counter <= counter + 16'd1; 

                acc2_z1 <= acc2_next;
                diff1_z1 <= diff1_now;
                
                current_phi_error <= diff2_now >>> 4;
            end else begin
                decim_cnt <= decim_cnt + 2'd1;
            end

            if(abs_error <= THRESHOLD) begin
                if(stable_counter < LOCK_COUNT)
                    stable_counter <= stable_counter + 1;
            end
            else begin
                stable_counter <= 0;
                low_power_mode <= 0;
                toggle<= 0;
            end

            if(stable_counter >= LOCK_COUNT-1)
                low_power_mode <= 1;

        end
    end
endmodule
