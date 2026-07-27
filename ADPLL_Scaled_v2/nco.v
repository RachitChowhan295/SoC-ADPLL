`timescale 1ns / 1ps

module dco_nco #(
    parameter integer ACC_WIDTH          = 32,
    parameter [ACC_WIDTH-1:0] FTW_FREE   = 32'd751619277,  // 70MHz
    parameter signed [31:0]   KO_SCALE   = 32'sd4295       // Assuming Kdco = 20kHz in original model
)(
    input  wire                clk_fast,   // fixed physical clock
    input  wire                rst,
    input  wire signed [15:0]  ctrl_word,
    
    output reg                 dco_clk,
    output reg [6:0]           dco_frac_gray // NEW: Feeds the Digital TDC
);

    // Full-scale bound for the accumulator's tuning word, as a wide
    // signed value so comparisons below never truncate/overflow.
    localparam signed [63:0] FTW_MAX = (64'sd1 <<< ACC_WIDTH) - 64'sd1;

    reg [ACC_WIDTH-1:0] phase_acc;

    // Sign-extend ctrl_word and multiply in full 64-bit precision.
    // 1. Synchronize the control word into the fast clock domain FIRST
    (* ASYNC_REG = "TRUE" *) reg signed [15:0] ctrl_sync1, ctrl_sync2;
    always @(posedge clk_fast or posedge rst) begin
        if (rst) begin
            ctrl_sync1 <= 16'd0;
            ctrl_sync2 <= 16'd0;
        end else begin
            ctrl_sync1 <= ctrl_word;
            ctrl_sync2 <= ctrl_sync1;
        end
    end

    // 2. Do the 64-bit math using the synchronized signal!
    wire signed [31:0] ctrl_word_ext = {{16{ctrl_sync2[15]}}, ctrl_sync2};
    wire signed [63:0] ftw_delta     = $signed(KO_SCALE) * ctrl_word_ext;
    
    // FTW_FREE is unsigned; zero-extend to 64 bits before signed add.
    wire signed [63:0] ftw_free_ext  = {32'sd0, FTW_FREE};
    wire signed [63:0] ftw_signed    = ftw_free_ext + ftw_delta;

    // Clamp into [0, FTW_MAX]
    wire [ACC_WIDTH-1:0] ftw_word;
    assign ftw_word = (ftw_signed < 64'sd0)      ? {ACC_WIDTH{1'b0}} :
                       (ftw_signed > FTW_MAX)    ? {ACC_WIDTH{1'b1}} :
                                                    ftw_signed[ACC_WIDTH-1:0];

    always @(posedge clk_fast or posedge rst) begin
        if (rst) begin
            phase_acc     <= {ACC_WIDTH{1'b0}};
            dco_clk       <= 1'b0;
            dco_frac_gray <= 7'd0;
        end else begin
            phase_acc     <= phase_acc + ftw_word;
            dco_clk       <= phase_acc[ACC_WIDTH-1];   // MSB toggle = output clock
            
            // NEW: Extract fractional bits [30:24] and convert to Gray code
            dco_frac_gray <= phase_acc[ACC_WIDTH-2 : ACC_WIDTH-8] ^ (phase_acc[ACC_WIDTH-2 : ACC_WIDTH-8] >> 1);
        end
    end

endmodule