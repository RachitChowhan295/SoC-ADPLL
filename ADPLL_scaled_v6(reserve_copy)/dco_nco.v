`timescale 1ns / 1ps

module dco_nco #(
    parameter integer ACC_WIDTH          = 32,
    parameter [ACC_WIDTH-1:0] FTW_FREE   = 32'd751619277,  // 70MHz
    parameter signed [31:0]   KO_SCALE   = 32'sd4295       // Assuming Kdco = 20kHz
)(
    input  wire                clk_fast,   // fixed physical clock
    input  wire                rst,
    input  wire signed [15:0]  ctrl_word,
    output reg                 dco_clk,
    output reg [6:0]           dco_frac_gray
);

    localparam signed [63:0] FTW_MAX = (64'sd1 <<< ACC_WIDTH) - 64'sd1;
    wire signed [63:0] ftw_free_ext  = {32'sd0, FTW_FREE};

    // 1. Synchronize the control word into the fast clock domain
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

    // ==============================================================================
    // PIPELINE STAGES (Fully folded into a single DSP48E1 MAC)
    // ==============================================================================

    reg signed [24:0] dsp_a_reg;
    reg signed [17:0] dsp_b_reg;
    reg signed [47:0] dsp_c_reg; 
    
    reg signed [42:0] dsp_m_reg; 

    // Force the multiplier/adder into a DSP block
    (* use_dsp = "yes" *) reg signed [47:0] ftw_signed_pipe; 

    always @(posedge clk_fast) begin
        // 1. Input Registers 
        dsp_a_reg <= $signed(KO_SCALE[24:0]);
        dsp_b_reg <= $signed({{2{ctrl_sync2[15]}}, ctrl_sync2}); 
        dsp_c_reg <= $signed({16'd0, FTW_FREE});                 
        
        // 2. MREG Pipeline
        dsp_m_reg <= dsp_a_reg * dsp_b_reg;
        
        // 3. PREG MAC Output 
        ftw_signed_pipe <= dsp_m_reg + dsp_c_reg;
    end

    // ==============================================================================
    // PHASE ACCUMULATOR - Carry-Save (redundant) recurrence @ full clk_fast rate
    // ==============================================================================
    // A single 32-bit ripple-carry add (phase_acc <= phase_acc + ftw) measured
    // ~2.76 ns in 7-series fabric (9 logic levels) - too slow for a 2.5 ns
    // (400 MHz) period. A carry-save accumulator removes the carry chain from
    // the recurrence entirely: acc_sum/acc_carry update via a per-bit 3:2
    // compressor (bitwise XOR / majority), with NO inter-bit dependency, so it
    // is ~1 logic level regardless of width and trivially meets 400 MHz.
    //
    // The true binary value (acc_sum + acc_carry, mod 2^ACC_WIDTH) is only
    // needed to drive dco_clk / dco_frac_gray, so it's resolved separately by
    // a freely-pipelined carry-propagate adder below. That resolver adds a
    // fixed 2-cycle (~5 ns) latency to those two outputs only - a constant
    // delay, not jitter, and negligible next to ref_clk's 500 ns period. The
    // accumulator itself never stalls, skips a cycle, or loses precision.
    localparam integer HALF = ACC_WIDTH/2; // low/high split for the resolver (16 for ACC_WIDTH=32)

    reg [ACC_WIDTH-1:0] acc_sum;
    reg [ACC_WIDTH-1:0] acc_carry;

    wire [ACC_WIDTH-1:0] ftw_val = ftw_signed_pipe[ACC_WIDTH-1:0];

    // 3:2 compressor: new_sum = XOR3, new_carry = majority shifted up by 1 bit
    // (a carry-out past bit ACC_WIDTH-1 is simply dropped, matching the
    // accumulator's intended mod-2^ACC_WIDTH wraparound).
    wire [ACC_WIDTH-1:0] csa_sum   = acc_sum ^ acc_carry ^ ftw_val;
    wire [ACC_WIDTH-1:0] csa_carry = ((acc_sum & acc_carry) | (acc_sum & ftw_val) | (acc_carry & ftw_val)) << 1;

    always @(posedge clk_fast or posedge rst) begin
        if (rst) begin
            acc_sum   <= {ACC_WIDTH{1'b0}};
            acc_carry <= {ACC_WIDTH{1'b0}};
        end else begin
            acc_sum   <= csa_sum;
            acc_carry <= csa_carry;
        end
    end

    // ==============================================================================
    // OUTPUT RESOLVER - 2-stage pipelined carry-propagate add (acc_sum + acc_carry)
    // ==============================================================================
    // Only the high half [ACC_WIDTH-1:HALF] is ever needed: dco_clk uses bit
    // ACC_WIDTH-1 and dco_frac_gray uses bits [ACC_WIDTH-2:ACC_WIDTH-8], both
    // of which live entirely inside the high half whenever ACC_WIDTH/2 >= 8
    // (true for the ACC_WIDTH=32 default). So only the low half's carry-out is
    // needed, never its resolved sum bits.
    reg              resolve_carry_in;
    reg [HALF-1:0]   resolve_hi_sum_operand;
    reg [HALF-1:0]   resolve_hi_carry_operand;

    // Stage 2 registers: hold the raw (non-Gray) resolved bits for one cycle
    // so the 16-bit carry-propagate add and the Gray XOR never share a
    // clk_fast period. This was the failing path in timing closure: with
    // both combined, resolve_hi_*_operand_reg -> dco_frac_gray_reg measured
    // ~2.8-3.0 ns of total delay against a 2.5 ns (400 MHz) requirement
    // (setup slack as bad as -0.541 ns). Splitting them removes the extra
    // XOR logic level from the adder's path, at the cost of one more fixed
    // clk_fast cycle (~2.5 ns) of constant latency on dco_clk/dco_frac_gray -
    // still negligible next to ref_clk's 500 ns period.
    reg              hi_bit_resolved;   // hi_add[HALF-1]      -> dco_clk
    reg [6:0]        hi_frac_resolved;  // hi_add[HALF-2 -: 7] -> dco_frac_gray

    wire [HALF:0] lo_add = {1'b0, acc_sum[HALF-1:0]}   + {1'b0, acc_carry[HALF-1:0]};
    wire [HALF:0] hi_add = {1'b0, resolve_hi_sum_operand} + {1'b0, resolve_hi_carry_operand} + resolve_carry_in;

    always @(posedge clk_fast or posedge rst) begin
        if (rst) begin
            resolve_carry_in         <= 1'b0;
            resolve_hi_sum_operand   <= {HALF{1'b0}};
            resolve_hi_carry_operand <= {HALF{1'b0}};
            hi_bit_resolved          <= 1'b0;
            hi_frac_resolved         <= 7'd0;
            dco_clk                  <= 1'b0;
            dco_frac_gray            <= 7'd0;
        end else begin
            // Stage 1: capture this cycle's acc_sum/acc_carry pair to resolve
            resolve_carry_in         <= lo_add[HALF];
            resolve_hi_sum_operand   <= acc_sum[ACC_WIDTH-1:HALF];
            resolve_hi_carry_operand <= acc_carry[ACC_WIDTH-1:HALF];

            // Stage 2: register the raw 16-bit add result only - no Gray
            // encoding here, so this stage's combinational path is just the
            // carry-propagate add.
            hi_bit_resolved  <= hi_add[HALF-1];
            hi_frac_resolved <= hi_add[HALF-2 -: 7];

            // Stage 3: Gray-encode from the already-registered bits and
            // drive the outputs. dco_clk is delayed here too (one extra
            // flop) purely to stay time-aligned with dco_frac_gray.
            dco_clk       <= hi_bit_resolved;
            dco_frac_gray <= hi_frac_resolved ^ (hi_frac_resolved >> 1);
        end
    end
endmodule