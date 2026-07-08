`timescale 1ns / 1ps

module dco_nco #(
    parameter integer ACC_WIDTH = 32,          // phase accumulator width
    parameter [ACC_WIDTH-1:0] FTW_FREE = 32'd0, // FTW that yields f_free at clk_fast
    parameter signed [31:0]   KO_SCALE = 32'sd0 // FTW counts per LSB of ctrl_word
)(
    input  wire                clk_fast,  // fixed physical clock (from MMCM), e.g. 200 MHz
    input  wire                rst,
    input  wire signed [15:0]  ctrl_word,
    output reg                 dco_clk
);

    reg  [ACC_WIDTH-1:0]      phase_acc;
    wire signed [ACC_WIDTH:0] ftw_signed;
    wire [ACC_WIDTH-1:0]      ftw_word;

    // FTW = FTW_FREE + KO_SCALE * ctrl_word, clamped so it can't go negative or overflow
    assign ftw_signed = $signed({1'b0, FTW_FREE}) + (KO_SCALE * ctrl_word);

    assign ftw_word = ftw_signed[ACC_WIDTH] ? {ACC_WIDTH{1'b0}}      // negative -> clamp to 0
                                             : ftw_signed[ACC_WIDTH-1:0];

    always @(posedge clk_fast or posedge rst) begin
        if (rst) begin
            phase_acc <= {ACC_WIDTH{1'b0}};
            dco_clk   <= 1'b0;
        end else begin
            phase_acc <= phase_acc + ftw_word;
            dco_clk   <= phase_acc[ACC_WIDTH-1];   // MSB toggling = the output "clock"
        end
    end

endmodule
