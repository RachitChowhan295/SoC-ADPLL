`timescale 1ns/1ps

module digital_tdc (
    input  wire        clk_ref,
    input  wire        rst,
    
    input  wire [6:0]  dco_frac_gray, // Pure math input directly from NCO
    output reg signed [7:0] tdc_fine_out   // Output fractional error
);

    // ==========================================
    // 1. Clock Domain Crossing (CDC) Synchronizer
    // ==========================================
    // Safely brings the fast Gray-coded phase into the slow ref_clk domain.
    (* ASYNC_REG = "TRUE" *) reg [6:0] sync1, sync2;
    
    always @(posedge clk_ref or posedge rst) begin
        if (rst) begin
            sync1 <= 7'd0;
            sync2 <= 7'd0;
        end else begin
            sync1 <= dco_frac_gray;
            sync2 <= sync1;
        end
    end

    // ==========================================
    // 2. Gray to Binary Decoder
    // ==========================================
    reg [6:0] bin_val;
    integer i;
    
    always @(*) begin
        bin_val[6] = sync2[6];
        for (i = 5; i >= 0; i = i - 1) begin
            bin_val[i] = bin_val[i+1] ^ sync2[i];
        end
    end

    // ==========================================
    // 3. Output Register
    // ==========================================
    always @(posedge clk_ref or posedge rst) begin
        if (rst) begin
            tdc_fine_out <= 8'sd0;
        end else begin
            // Pad with a leading zero to explicitly make it a positive signed number (0 to 127)
            tdc_fine_out <= $signed({1'b0, bin_val});
        end
    end

endmodule