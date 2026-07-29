`timescale 1ns/1ps

module cic_decimator #(
    parameter DECIM = 4
)(
    input  wire clk,
    input  wire rst,        
    input  wire signed [24:0] phase_residual, 
    
    output reg  do_update,
    output reg  signed [24:0] current_phi_error,
    output reg  locked,
    output wire low_power_mode
);

    reg signed [28:0] acc1, acc2;
    reg signed [28:0] acc2_z1, diff1_z1;
    reg [1:0] decim_cnt;

    wire signed [28:0] diff1_now = acc2_next - acc2_z1;
    wire signed [28:0] diff2_now = diff1_now - diff1_z1;

    // 29-bit accumulator needs 4 bits of sign extension on the 25-bit input
    wire signed [28:0] acc1_next = acc1 + $signed({{4{phase_residual[24]}}, phase_residual});
    wire signed [28:0] acc2_next = acc2 + acc1_next;

    parameter LOCK_COUNT = 6'd32;
    parameter THRESHOLD  = 8'd100;
    
    reg [5:0] stable_counter;
    wire [24:0] abs_error = current_phi_error[24] ? -current_phi_error : current_phi_error; 
    reg toggle;

    assign low_power_mode = locked;

    always @(posedge clk or posedge rst) begin 
        if (rst) begin                         
            acc1              <= 29'sd0;
            acc2              <= 29'sd0;
            acc2_z1           <= 29'sd0;
            diff1_z1          <= 29'sd0;
            decim_cnt         <= 2'd0;
            do_update         <= 1'b0;
            current_phi_error <= 32'sd0;
            stable_counter    <= 6'd0;
            toggle            <= 1'd0;
            locked            <= 1'b0;
        end else begin
            acc1 <= acc1_next;
            acc2 <= acc2_next;

            do_update <= 1'b0;

            if (decim_cnt == (DECIM - 1)) begin
                decim_cnt <= 2'd0;
                
                if (low_power_mode) begin
                    toggle <= ~toggle;
                    if (toggle)
                        do_update <= 1'b1;
                end else begin
                    do_update <= 1'b1;
                    toggle <= 1'b0;
                end
                
                acc2_z1 <= acc2_next;
                diff1_z1 <= diff1_now;
                
                current_phi_error <= diff2_now >>> 4;
            end else begin
                decim_cnt <= decim_cnt + 2'd1;
            end

            if (abs_error <= THRESHOLD) begin
                if (stable_counter < LOCK_COUNT)
                    stable_counter <= stable_counter + 1;
            end else begin
                stable_counter <= 0;
            end

            locked <= (stable_counter >= LOCK_COUNT);
        end
    end
endmodule