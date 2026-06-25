`timescale 1ns/1ps
module gain_scheduler #(

    // Fast acquisition mode (500 kHz BW)
    parameter signed [31:0] KP_FAST = 32'd6000,
    parameter signed [31:0] KI_FAST = 32'd200,

    // Medium bandwidth mode (100 kHz BW)
    parameter signed [31:0] KP_MED  = 32'd800,
    parameter signed [31:0] KI_MED  = 32'd5,

    // Tracking mode (30 kHz BW)
    parameter signed [31:0] KP_SLOW = 32'd50,
    parameter signed [31:0] KI_SLOW = 32'd1,

    // Feedback Cycle Thresholds
    parameter FAST_END = 16'd75,  
    parameter MED_END  = 16'd150   

)(
    input  wire [15:0] counter,
    output reg signed [31:0] kp,
    output reg signed [31:0] ki
);

always @(*) begin

    if(counter < FAST_END) begin
        kp = KP_FAST;
        ki = KI_FAST;
    end
    else if(counter < MED_END) begin
        kp = KP_MED;
        ki = KI_MED;
    end
    else begin
        kp = KP_SLOW;
        ki = KI_SLOW;
    end

end
endmodule
