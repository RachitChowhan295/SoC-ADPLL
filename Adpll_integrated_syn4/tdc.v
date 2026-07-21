`timescale 1ns/1ps

module digital_tdc(
    input  wire        clk_ref,
    input  wire        rst,
    input  wire [6:0]  dco_frac_gray,
    output reg signed [7:0] tdc_fine_out
);

    // 2-FF Synchronizer to safely capture the NCO's fractional phase
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

    // Gray to Binary Decoder
    wire [6:0] bin_val;
    genvar i;
    generate
        assign bin_val[6] = sync2[6];
        for (i = 5; i >= 0; i = i - 1) begin : gray_decode
            assign bin_val[i] = bin_val[i+1] ^ sync2[i];
        end
    endgenerate

    // Output as a signed fractional value (matching your old TDC scale)
    always @(posedge clk_ref or posedge rst) begin
        if (rst) 
            tdc_fine_out <= 8'sd0;
        else     
            tdc_fine_out <= $signed({1'b0, bin_val});
    end

endmodule