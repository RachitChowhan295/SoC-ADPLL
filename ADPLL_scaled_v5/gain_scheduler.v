`timescale 1ns/1ps

module gain_scheduler #(
    parameter ERR_W   = 25,   
    parameter SHIFT_W = 5,    // width of kp/ki shift outputs

    // ---- Threshold table ----
    parameter [ERR_W-1:0] TH_LARGE  = 32'd2500,  
    parameter [ERR_W-1:0] TH_MED    = 32'd500,   

    // ---- Gain sets (Right-Shift amounts) ----
    // LARGE: Aggressive pull-in. 
    parameter [SHIFT_W-1:0] KP_SHIFT_LARGE = 5'd1,  // Gain ~ 0.5
    parameter [SHIFT_W-1:0] KI_SHIFT_LARGE = 5'd7,  // Gain ~ 0.007

    // MEDIUM: Strong proportional braking, weak integral to prevent overshoot.
    parameter [SHIFT_W-1:0] KP_SHIFT_MED   = 5'd3,  // Gain ~ 0.125
    parameter [SHIFT_W-1:0] KI_SHIFT_MED   = 5'd13, // Gain ~ 0.00012

    // FINE: Very strong proportional tracking, extremely slow integral.
    // The I-term will only hold the center frequency, preventing ringing.
    parameter [SHIFT_W-1:0] KP_SHIFT_FINE  = 5'd4,  // Gain ~ 0.0625
    parameter [SHIFT_W-1:0] KI_SHIFT_FINE  = 5'd16, // Gain ~ 0.000015

    // Hysteresis margin
    parameter [ERR_W-1:0] HYST = 32'd50
    
)(
    input  wire clk,
    input  wire rst,

    input  wire signed [ERR_W-1:0] phase_error,

    output reg [SHIFT_W-1:0] kp_shift_sel,
    output reg [SHIFT_W-1:0] ki_shift_sel
);

    wire [ERR_W-1:0] err_abs;
    assign err_abs = phase_error[ERR_W-1] ? (~phase_error + 1'b1) : phase_error;

    reg [1:0] state, state_next;

    localparam FINE   = 2'd0;
    localparam MEDIUM = 2'd1;
    localparam LARGE  = 2'd2;

    always @(*) begin
        state_next = state;
        case (state)
            FINE: begin
                if (err_abs > TH_LARGE)
                    state_next = LARGE;
                else if (err_abs > TH_MED)
                    state_next = MEDIUM;
            end
            MEDIUM: begin
                if (err_abs > TH_LARGE)
                    state_next = LARGE;
                else if (err_abs < (TH_MED - HYST))
                    state_next = FINE;
            end
            LARGE: begin
                if (err_abs < (TH_LARGE - HYST)) begin
                    if (err_abs > TH_MED)
                        state_next = MEDIUM;
                    else
                        state_next = FINE;
                end
            end
            default: state_next = FINE;
        endcase
    end

   always @(posedge clk or posedge rst) begin
    if (rst) begin
            state  <= FINE;
        end else begin
            state <= state_next;
        end
    end

    // Registered shift outputs
    always @(posedge clk or posedge rst) begin
    if (rst) begin
            kp_shift_sel <= KP_SHIFT_FINE;
            ki_shift_sel <= KI_SHIFT_FINE;
        end else begin
            case (state_next)
                LARGE:   begin kp_shift_sel <= KP_SHIFT_LARGE; ki_shift_sel <= KI_SHIFT_LARGE; end
                MEDIUM:  begin kp_shift_sel <= KP_SHIFT_MED;   ki_shift_sel <= KI_SHIFT_MED;   end
                default: begin kp_shift_sel <= KP_SHIFT_FINE;  ki_shift_sel <= KI_SHIFT_FINE;  end
            endcase
        end
    end

endmodule