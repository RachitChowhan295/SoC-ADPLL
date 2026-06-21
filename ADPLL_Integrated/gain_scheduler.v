`timescale 1ns/1ps
module gain_scheduler #(

    // Fast acquisition mode (bw_scale = 10)
    parameter signed [31:0] KP_FAST = 32'd2957967,
    parameter signed [31:0] KI_FAST = 32'd49197,

    // Medium bandwidth mode (bw_scale = 3)
    parameter signed [31:0] KP_MED  = 32'd887390,
    parameter signed [31:0] KI_MED  = 32'd4428,

    // Tracking mode (bw_scale = 1)
    parameter signed [31:0] KP_SLOW = 32'd295797,
    parameter signed [31:0] KI_SLOW = 32'd492,

    // ── CORRECTED COUNTER END POINTS (Feedback Cycles) ──
    // Python threshold 2500 / DECIM 4 = 625
    parameter FAST_END = 16'd625,  
    
    // Python threshold 3500 / DECIM 4 = 875
    parameter MED_END  = 16'd875   

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
