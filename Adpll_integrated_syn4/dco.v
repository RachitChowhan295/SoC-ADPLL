module dco_nco #(
    parameter integer ACC_WIDTH          = 32,
    parameter [ACC_WIDTH-1:0] FTW_FREE   = 32'd1503238605,  
    parameter signed [31:0]   KO_SCALE   = 32'sd8590
)(
    input  wire                clk_fast,
    input  wire                rst,
    input  wire signed [15:0]  ctrl_word,
    output reg                 dco_clk,
    
    // NEW: Export the mathematically perfect fractional phase
    output reg [6:0]           dco_frac_gray 
);

    localparam signed [63:0] FTW_MAX = (64'sd1 <<< ACC_WIDTH) - 64'sd1;
    reg [ACC_WIDTH-1:0] phase_acc;

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

    wire signed [31:0] ctrl_word_ext = {{16{ctrl_sync2[15]}}, ctrl_sync2};
    wire signed [63:0] ftw_delta     = $signed(KO_SCALE) * ctrl_word_ext;
    wire signed [63:0] ftw_free_ext  = {32'sd0, FTW_FREE};
    wire signed [63:0] ftw_signed    = ftw_free_ext + ftw_delta;

    wire [ACC_WIDTH-1:0] ftw_word;
    assign ftw_word = (ftw_signed < 64'sd0)  ? {ACC_WIDTH{1'b0}} :
                      (ftw_signed > FTW_MAX) ? {ACC_WIDTH{1'b1}} :
                                               ftw_signed[ACC_WIDTH-1:0];

    // Extract the 7 fractional bits just below the MSB (Bit 30 down to 24)
    wire [6:0] frac_bin = phase_acc[ACC_WIDTH-2 : ACC_WIDTH-8];

    always @(posedge clk_fast or posedge rst) begin
        if (rst) begin
            phase_acc <= {ACC_WIDTH{1'b0}};
            dco_clk   <= 1'b0;
            dco_frac_gray <= 7'd0;
        end else begin
            phase_acc <= phase_acc + ftw_word;
            dco_clk   <= phase_acc[ACC_WIDTH-1]; 
            
            // Safely Gray code the fraction before it leaves the fast domain
            dco_frac_gray <= frac_bin ^ (frac_bin >> 1);
        end
    end
endmodule