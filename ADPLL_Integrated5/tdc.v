`timescale 1ps/1ps

module snapshot_tdc(
    input  wire clk_ref,
    input  wire rst,
    input  wire [15:0] dco_phases,    // Wired directly from the Ring DCO
    output reg signed [5:0] tdc_fine_out // 6-bit output: 0 to 31
);

    reg [15:0] captured_phases;

    // 1. The Camera Shutter (Triggered by Ref Clock)
    always @(posedge clk_ref or posedge rst) begin
        if (rst) 
            captured_phases <= 16'd0;
        else 
            captured_phases <= dco_phases; // Take the snapshot!
    end

    // 2. The Decoder
    integer i;
    always @(*) begin
        tdc_fine_out = 6'sd0;
        
        // Edge cases (Ring is exactly full or empty)
        if (captured_phases == 16'h0000) begin
            tdc_fine_out = 6'sd0;
        end else if (captured_phases == 16'hFFFF) begin
            tdc_fine_out = 6'sd16;
        end else begin
            // Search the array to find where the 1s transition to 0s
            for (i = 0; i < 15; i = i + 1) begin
                if (captured_phases[i] != captured_phases[i+1]) begin
                    // Determine if we are in the first or second half of the clock cycle
                    if (captured_phases[0] == 1'b1) 
                        tdc_fine_out = i + 1;      // Bins 1 to 15
                    else 
                        tdc_fine_out = i + 17;     // Bins 17 to 31
                end
            end
        end
    end
endmodule
