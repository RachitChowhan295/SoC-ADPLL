`timescale 1ns/1ps
module gain_scheduler #(

    // Fast acquisition mode
    parameter signed [31:0] KP_FAST = 32'd2957967,
    parameter signed [31:0] KI_FAST = 32'd49197,

    // Medium bandwidth mode
    parameter signed [31:0] KP_MED  = 32'd887390,
    parameter signed [31:0] KI_MED  = 32'd4428,

    // Tracking mode
    parameter signed [31:0] KP_SLOW = 32'd295797,
    parameter signed [31:0] KI_SLOW = 32'd492,

    // counter end points
    parameter FAST_END = 50,
    parameter MED_END  = 100

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

/** IN PI FILTER
wire signed [31:0] kp;
wire signed [31:0] ki;

gain_scheduler gs (
    .counter(counter),
    .kp(kp),
    .ki(ki)
);

integrator <= integrator - ((ki * current_phi_error) >>> 16);

pi_out <= integrator - ((kp * current_phi_error) >>> 16);

**/