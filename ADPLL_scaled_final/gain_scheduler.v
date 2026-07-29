`timescale 1ns/1ps

module gain_scheduler #(
    parameter ERR_W   = 25,   
    parameter SHIFT_W = 5,    

    // ---- Phase Thresholds ----
    parameter [ERR_W-1:0] TH_LARGE  = 32'd2500,  
    parameter [ERR_W-1:0] TH_MED    = 32'd1200,   
    parameter [ERR_W-1:0] TH_FREQ   = 32'd1000, 

   // ---- Gain sets ----
    // FLL GAINS: Max integral gain
    parameter [SHIFT_W-1:0] KP_SHIFT_FLL   = 5'd31, 
    parameter [SHIFT_W-1:0] KI_SHIFT_FLL   = 5'd0,  

    // LARGE GAINS: Wide bandwidth (811 rad/s) for fast pull-in
    parameter [SHIFT_W-1:0] KP_SHIFT_LARGE = 5'd0,  
    parameter [SHIFT_W-1:0] KI_SHIFT_LARGE = 5'd10,  

    // MEDIUM GAINS: Mid bandwidth (405 rad/s) for transition smoothing
    parameter [SHIFT_W-1:0] KP_SHIFT_MED   = 5'd1,  
    parameter [SHIFT_W-1:0] KI_SHIFT_MED   = 5'd12,  

    // FINE GAINS: Narrow bandwidth (202 rad/s) for max jitter rejection
    parameter [SHIFT_W-1:0] KP_SHIFT_FINE  = 5'd2,  
    parameter [SHIFT_W-1:0] KI_SHIFT_FINE  = 5'd14,

    parameter [ERR_W-1:0] HYST = 32'd50
)(
    input  wire clk,
    input  wire rst,
    input  wire enable, 
    input  wire signed [ERR_W-1:0] phase_error,
    
    output reg [SHIFT_W-1:0] kp_shift_sel,
    output reg [SHIFT_W-1:0] ki_shift_sel,
    
    output wire is_fll_mode,
    output wire signed [ERR_W-1:0] freq_error_out
);

    reg signed [ERR_W-1:0] phase_error_z1;
    always @(posedge clk or posedge rst) begin
        if (rst) phase_error_z1 <= 0;
        else if (enable) phase_error_z1 <= phase_error; 
    end
    
    wire signed [ERR_W-1:0] freq_error = phase_error - phase_error_z1;
    assign freq_error_out = freq_error;

    wire [ERR_W-1:0] err_abs = phase_error[ERR_W-1] ? (~phase_error + 1'b1) : phase_error;
    wire [ERR_W-1:0] freq_err_abs = freq_error[ERR_W-1] ? (~freq_error + 1'b1) : freq_error;

    reg [1:0] state, state_next;

    localparam FINE   = 2'd0;
    localparam MEDIUM = 2'd1;
    localparam LARGE  = 2'd2;
    localparam FLL    = 2'd3;

    assign is_fll_mode = (state == FLL);

    always @(*) begin
        state_next = state;
        
        if (freq_err_abs > TH_FREQ) begin
            state_next = FLL;
        end else begin
            case (state)
                FLL: begin
                    if (freq_err_abs < (TH_FREQ - HYST)) 
                        state_next = LARGE; 
                end
                FINE: begin
                    if (err_abs > TH_LARGE) state_next = LARGE;
                    else if (err_abs > TH_MED) state_next = MEDIUM;
                end
                MEDIUM: begin
                    if (err_abs > TH_LARGE) state_next = LARGE;
                    else if (err_abs < (TH_MED - HYST)) state_next = FINE;
                end
                LARGE: begin
                    if (err_abs < (TH_LARGE - HYST)) begin
                        if (err_abs > TH_MED) state_next = MEDIUM;
                        else state_next = FINE;
                    end
                end
                default: state_next = FINE;
            endcase
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) state <= FINE;
        else if (enable) state <= state_next; 
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            kp_shift_sel <= KP_SHIFT_FINE;
            ki_shift_sel <= KI_SHIFT_FINE;
        end else if (enable) begin 
            case (state_next)
                FLL:     begin kp_shift_sel <= KP_SHIFT_FLL;   ki_shift_sel <= KI_SHIFT_FLL;   end
                LARGE:   begin kp_shift_sel <= KP_SHIFT_LARGE; ki_shift_sel <= KI_SHIFT_LARGE; end
                MEDIUM:  begin kp_shift_sel <= KP_SHIFT_MED;   ki_shift_sel <= KI_SHIFT_MED;   end
                default: begin kp_shift_sel <= KP_SHIFT_FINE;  ki_shift_sel <= KI_SHIFT_FINE;  end
            endcase
        end
    end
endmodule