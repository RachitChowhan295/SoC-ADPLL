`timescale 1ns / 1ps
// ─────────────────────────────────────────────────────────────
// dco_nco : Synthesizable Digitally Controlled Oscillator
// Implements the "fractional-N accumulator DCO" the problem
// statement asks for. This REPLACES the old dco_model, which used
// `real` signals and `#delay` timing controls and cannot synthesize.
//
// Principle: a phase accumulator increments every clk_fast edge by
// a frequency tuning word (FTW). The accumulator's MSB toggles at
//   f_out = (FTW / 2^ACC_WIDTH) * f_clk_fast
// ctrl_word (from the PI loop filter) perturbs FTW around a center
// value FTW_FREE, exactly the way KO_GAIN perturbed freq_dco in the
// Python model. clk_fast must come from a real hardware clock
// (MMCM/PLL primitive) -- digital logic cannot manufacture an
// absolute frequency reference from nothing.
//
// Default parameters below were computed for the S=64 scaled
// frequency plan (f_free' = 54.6875 MHz) at clk_fast = 200 MHz,
// ACC_WIDTH = 32:
//   FTW_FREE = round((f_free'/clk_fast) * 2^32) = 1174405120 (0x46000000)
//   KO_SCALE = round((KO_GAIN'/clk_fast) * 2^32) = 16777216
// Recompute both if you change S, clk_fast, or ACC_WIDTH.
// ─────────────────────────────────────────────────────────────

module dco_nco #(
    parameter integer ACC_WIDTH          = 32,
    parameter [ACC_WIDTH-1:0] FTW_FREE   = 32'd1174405120,  // 0x46000000
    parameter signed [31:0]   KO_SCALE   = 32'sd16777216
)(
    input  wire                clk_fast,   // fixed physical clock, e.g. 200 MHz from MMCM
    input  wire                rst,
    input  wire signed [15:0]  ctrl_word,
    output reg                 dco_clk
);

    // Full-scale bound for the accumulator's tuning word, as a wide
    // signed value so comparisons below never truncate/overflow.
    localparam signed [63:0] FTW_MAX = (64'sd1 <<< ACC_WIDTH) - 64'sd1;

    reg [ACC_WIDTH-1:0] phase_acc;

    // Sign-extend ctrl_word and multiply in full 64-bit precision.
    // (KO_SCALE is up to 32 bits, ctrl_word extended to 32 bits ->
    // product needs up to 64 bits; a 33-bit intermediate, as in an
    // earlier draft, silently overflows at large ctrl_word values.)
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

    // Clamp into [0, FTW_MAX] -- this only ever engages under fault
    // conditions (e.g. sim startup transient or a runaway loop), not
    // during normal lock-in with the computed KO_SCALE above.
    wire [ACC_WIDTH-1:0] ftw_word;
    assign ftw_word = (ftw_signed < 64'sd0)     ? {ACC_WIDTH{1'b0}} :
                       (ftw_signed > FTW_MAX)    ? {ACC_WIDTH{1'b1}} :
                                                    ftw_signed[ACC_WIDTH-1:0];

    always @(posedge clk_fast or posedge rst) begin
        if (rst) begin
            phase_acc <= {ACC_WIDTH{1'b0}};
            dco_clk   <= 1'b0;
        end else begin
            phase_acc <= phase_acc + ftw_word;
            dco_clk   <= phase_acc[ACC_WIDTH-1];   // MSB toggle = output clock
        end
    end

endmodule
