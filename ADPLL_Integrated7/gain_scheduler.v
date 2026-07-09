`timescale 1ns/1ps

module gain_scheduler #(
    parameter ERR_W   = 25,   // width of phase_error input
    parameter GAIN_W  = 32,   // width of kp/ki outputs (must match pi_loop_filter's GAIN_W)

    // ---- Threshold table (magnitude of phase_error) ----
    // Adjust these based on your phase detector's error units/scale
    parameter [ERR_W-1:0] TH_LARGE  = 32'd2000,   // above this -> "acquisition" gains
    parameter [ERR_W-1:0] TH_MED    = 32'd500,    // above this -> "medium" gains
    // below TH_MED -> "fine tracking" gains

    // ---- Gain sets (Q16.16 fixed point, matching FRAC_BITS=16) ----
    parameter signed [GAIN_W-1:0] KP_LARGE = 32'sd7140618,
    parameter signed [GAIN_W-1:0] KI_LARGE = 32'sd158649,

    parameter signed [GAIN_W-1:0] KP_MED   = 32'sd1428124,
    parameter signed [GAIN_W-1:0] KI_MED   = 32'sd6346,

    parameter signed [GAIN_W-1:0] KP_FINE  = 32'sd142812,
    parameter signed [GAIN_W-1:0] KI_FINE  = 32'sd63,

    // Hysteresis margin to prevent chattering near thresholds
    parameter [ERR_W-1:0] HYST = 32'd50
)(
    input  wire clk,
    input  wire rst,

    input  wire signed [ERR_W-1:0] phase_error,

    output reg signed [GAIN_W-1:0] kp_sel,
    output reg signed [GAIN_W-1:0] ki_sel
    // 0=fine, 1=medium, 2=large (for debug/monitoring)
);

    // Unsigned magnitude of phase_error
    wire [ERR_W-1:0] err_abs;
    assign err_abs = phase_error[ERR_W-1] ? (~phase_error + 1'b1) : phase_error;

    // State-holding registers for hysteresis (avoid rapid toggling at boundaries)
    reg [1:0] state, state_next;

    localparam FINE   = 2'd0;
    localparam MEDIUM = 2'd1;
    localparam LARGE  = 2'd2;

    // Next-state logic with hysteresis:
    // Moving "up" (to higher gain) uses the plain threshold.
    // Moving "down" (to lower gain) requires err_abs to drop below (threshold - HYST).
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

    always @(posedge clk) begin
        if (rst) begin
            state  <= FINE;
        end else begin
            state <= state_next;
        end
    end

    // Registered gain outputs (avoids combinational glitches feeding into PI filter)
    always @(posedge clk) begin
        if (rst) begin
            kp_sel     <= KP_FINE;
            ki_sel     <= KI_FINE;
        end else begin
            case (state_next)
                LARGE:   begin kp_sel <= KP_LARGE; ki_sel <= KI_LARGE; end
                MEDIUM:  begin kp_sel <= KP_MED;   ki_sel <= KI_MED;   end
                default: begin kp_sel <= KP_FINE;  ki_sel <= KI_FINE;  end
            endcase
        end
    end

endmodule
