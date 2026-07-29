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
    localparam integer HALF = ACC_WIDTH/2;

    reg [ACC_WIDTH-1:0] acc_sum;
    reg [ACC_WIDTH-1:0] acc_carry;

    wire [ACC_WIDTH-1:0] ftw_val = ftw_signed_pipe[ACC_WIDTH-1:0];

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
    reg              resolve_carry_in;
    reg [HALF-1:0]   resolve_hi_sum_operand;
    reg [HALF-1:0]   resolve_hi_carry_operand;

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
            resolve_carry_in         <= lo_add[HALF];
            resolve_hi_sum_operand   <= acc_sum[ACC_WIDTH-1:HALF];
            resolve_hi_carry_operand <= acc_carry[ACC_WIDTH-1:HALF];

            hi_bit_resolved  <= hi_add[HALF-1];
            hi_frac_resolved <= hi_add[HALF-2 -: 7];

            dco_clk       <= hi_bit_resolved;
            dco_frac_gray <= hi_frac_resolved ^ (hi_frac_resolved >> 1);
        end
    end
endmodule