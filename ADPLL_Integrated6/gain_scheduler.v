`timescale 1ns/1ps
module gain_scheduler #(
    // 1. Mathematically Derived Acquisition Targets (500 kHz BW, Z = 1.0)
    parameter signed [31:0] KP_START = 32'd160845,
    parameter signed [31:0] KI_START = 32'd10105,

    // 2. Mathematically Derived Tracking Targets (50 kHz BW, Z = 0.707)
    parameter signed [31:0] KP_MIN = 32'd11372,
    parameter signed [31:0] KI_MIN = 32'd101,

    // 3. Precise Decay Steps (Calculated for a 2000 loop-tick transition)
    parameter signed [31:0] KP_STEP = 32'd75,
    parameter signed [31:0] KI_STEP = 32'd5,

    // 4. Hold Timer (Give it 2000 loop ticks / 8000 ref cycles to hit 0 error)
    parameter HOLD_CYCLES = 16'd2000
)(
    input  wire clk,
    input  wire reset,
    input  wire loop_tick,      
    input  wire [15:0] counter, 
    output reg signed [31:0] kp,
    output reg signed [31:0] ki
);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            kp <= KP_START;
            ki <= KI_START;
        end 
        else if (loop_tick) begin
            
            if (counter > HOLD_CYCLES) begin
                
                // Sequentially step down KP
                if (kp > (KP_MIN + KP_STEP)) begin
                    kp <= kp - KP_STEP;
                end else begin
                    kp <= KP_MIN;
                end

                // Sequentially step down KI
                if (ki > (KI_MIN + KI_STEP)) begin
                    ki <= ki - KI_STEP;
                end else begin
                    ki <= KI_MIN;
                end
                
            end
        end
    end

endmodule
