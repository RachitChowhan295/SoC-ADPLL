`timescale 1ns/1fs

module dtc_model #(
    parameter MAX_CODE = 31,
    parameter PHASE_BITS = 7,
    parameter PHASE_FULL_SCALE = (1 << PHASE_BITS) // 128 = 128
)(
    input clk,
    input rst,

    input signed [24:0] phase_error,
    input [6:0] m1_reg,
    input [6:0] F_mod,
    input c2_prev,

    output reg signed [24:0] phase_residual,
    output reg [4:0] dtc_code
);
// =========================================================
// 1. INVERSE ROM FOR F_MOD (The Division Killer)
// Pre-calculate (65536 / F_mod) to multiply instead of divide.
// =========================================================
reg [16:0] inv_f_rom [0:127];
integer i;
initial begin
    inv_f_rom[0] = 0; // Prevent divide by zero
    for (i = 1; i < 128; i = i + 1) begin
        // The (+ i>>1) ensures perfectly rounded math
        inv_f_rom[i] = (65536 + (i >> 1)) / i;
    end
end

// Pre-calculate the inverse for MAX_CODE
localparam [16:0] INV_MAX_CODE = (65536 + (MAX_CODE >> 1)) / MAX_CODE;

// --- PIPELINE REGISTERS ---
reg signed [24:0] phase_error_q1;
reg [23:0] dividend_q1;
reg [16:0] inv_F_q1;
reg        c2_prev_q1;

reg signed [24:0] phase_error_q2;
reg [4:0]  dtc_code_q2;

reg [31:0] math_temp;
reg [31:0] math_temp2; // FIX: Added dedicated register for Stage 3
integer temp_code;     // Safe 32-bit bucket for large DSP products

always @(posedge clk or posedge rst) begin
    if (rst) begin
        phase_error_q1 <= 25'sd0;
        dividend_q1    <= 24'd0;
        inv_F_q1       <= 17'd0;
        c2_prev_q1     <= 1'b0;

        phase_error_q2 <= 25'sd0;
        dtc_code_q2    <= 5'd0;

        phase_residual <= 25'sd0;
        dtc_code       <= 5'd0;
        
        // FIX: Explicitly clear scratch registers to prevent transient X values
        math_temp      <= 32'd0;
        math_temp2     <= 32'd0;
        temp_code      <= 0;
    end else begin
        // ==========================================
        // STAGE 1: Multiplication and ROM Read
        // ==========================================
        phase_error_q1 <= phase_error;
        c2_prev_q1     <= c2_prev;
        
        dividend_q1    <= m1_reg * MAX_CODE;
        inv_F_q1       <= inv_f_rom[F_mod]; // Instant ROM Lookup

        // ==========================================
        // STAGE 2: "Division" via Q16 Multiplication
        // ==========================================
        phase_error_q2 <= phase_error_q1;
        
        math_temp <= (dividend_q1 * inv_F_q1) + 32768;
        temp_code <= math_temp >> 16; 
        
        if (c2_prev_q1 && temp_code > 0)
            temp_code <= temp_code - 1;
            
        if (temp_code < 0)
            temp_code <= 0;
        else if (temp_code > MAX_CODE)
            temp_code <= MAX_CODE;
            
        dtc_code_q2 <= temp_code[4:0];

        // ==========================================
        // STAGE 3: Second "Division" and Subtraction
        // ==========================================
        dtc_code <= dtc_code_q2;
        
        // FIX: Use math_temp2 to avoid colliding with Stage 2's math_temp
        math_temp2 <= (dtc_code_q2 * PHASE_FULL_SCALE * INV_MAX_CODE) + 32768;
        phase_residual <= phase_error_q2 - (math_temp2 >> 16);
    end
end

endmodule
